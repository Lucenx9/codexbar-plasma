import QtQuick
import "../CostResponse.mjs" as CostResponse
import "../CostRefreshPolicy.js" as CostRefreshPolicy
import "../Guards.js" as Guards
import "../ProviderIdentity.mjs" as ProviderIdentity
import "../ProviderNormalizer.mjs" as Normalizer

Item {
    id: controller

    property string commandPath: ""
    property string provider: ""
    property int historyDays: 30
    // "month-to-date" or "all" asks the CLI for that calendar period instead.
    property string historyPeriod: ""
    property bool costUsageEnabled: true
    property bool active: false

    readonly property var costs: lifecycle.snapshotContext === lifecycle.commandSource ? lifecycle.snapshot : ({})
    readonly property alias loading: lifecycle.running
    readonly property string errorText: lifecycle.errorText

    function refresh(force) {
        return lifecycle.initialized && lifecycle.requestRefresh(force === true);
    }

    onActiveChanged: {
        if (lifecycle.initialized && active) {
            Qt.callLater(lifecycle.refreshVisible);
        }
    }
    Component.onCompleted: {
        lifecycle.initialized = true;
        Qt.callLater(lifecycle.refreshIfStale);
    }

    Component.onDestruction: {
        lifecycle.initialized = false;
        lifecycle.cancel();
    }

    Item {
        id: lifecycle

        property bool initialized: false
        property var snapshot: ({})
        property string snapshotContext: ""
        property string errorText: ""
        property double lastAttemptAtMs: -1
        property int serial: 0
        property var currentRun: null
        property bool running: false
        // Imperative notification lets a loading observer start another run
        // without changing a dependency during evaluation of a binding.
        onCurrentRunChanged: running = currentRun !== null
        property var queuedReply: null
        property bool workerBusy: false
        readonly property int commandTimeoutMs: 120000
        readonly property string commandSource: {
            if (!controller.costUsageEnabled || controller.commandPath.length === 0) {
                return "";
            }
            var range = controller.historyPeriod.length > 0 ? ["--period", Guards.shellQuote(controller.historyPeriod)] : ["--days", String(controller.historyDays)];
            var parts = [Guards.shellQuote(controller.commandPath), "cost", "--format", "json", "--json-only"].concat(range);
            if (controller.provider.length > 0) {
                parts.push("--provider", Guards.shellQuote(ProviderIdentity.providerCliArgument(controller.provider)));
            }
            return parts.join(" ");
        }

        onCommandSourceChanged: {
            if (initialized) {
                // Invalidate live sources synchronously; coalesce setting changes
                // before starting a scan. Keep the old snapshot private so a
                // return to its context can reuse it until the next reply.
                cancel();
                Qt.callLater(refreshChangedSource);
            }
        }

        function refreshChangedSource() {
            requestRefresh(true);
        }

        function refreshIfStale() {
            requestRefresh(false);
        }

        function refreshVisible() {
            if (controller.active) {
                refreshIfStale();
            }
        }

        function cancel() {
            var cancelledSerial = ++serial;
            queuedReply = null;
            request.cancel();
            currentRun = null;
            return cancelledSerial;
        }

        function isCurrent(run) {
            return currentRun !== null && currentRun.serial === run.serial
                && run.commandSource === commandSource;
        }

        function requestRefresh(force) {
            var nowMs = Date.now();
            var action = CostRefreshPolicy.refreshAction(commandSource.length > 0, controller.loading, force === true, lastAttemptAtMs, nowMs);
            if (action === CostRefreshPolicy.keepAction) {
                return false;
            }
            var nextSerial = cancel();
            if (serial !== nextSerial) return false;
            errorText = "";
            if (serial !== nextSerial) return false;
            if (action === CostRefreshPolicy.clearAction) {
                snapshot = ({});
                snapshotContext = "";
                return false;
            }
            lastAttemptAtMs = nowMs;
            var run = {
                serial: serial,
                historyDays: controller.historyDays,
                historyPeriod: controller.historyPeriod,
                commandSource: commandSource,
                deadlineMs: nowMs + commandTimeoutMs
            };
            currentRun = run;
            if (!isCurrent(run)) return false;
            var started = request.start(commandSource, run, commandTimeoutMs);
            if (!started && isCurrent(run)) currentRun = null;
            return started;
        }

        function acceptReply(run, stdoutText, stderrText, exitCode) {
            if (!isCurrent(run)) return;
            // One running normalization and at most one replacement reply. Forced
            // refreshes cannot fill the worker's unbounded internal message queue.
            queuedReply = CostResponse.workerRequest(run, stdoutText, stderrText, exitCode);
            dispatchReply();
        }

        function dispatchReply() {
            if (workerBusy || !normalizer.ready || queuedReply === null) return;
            var reply = queuedReply;
            queuedReply = null;
            workerBusy = true;
            normalizer.sendMessage(reply);
        }

        function acceptResult(message) {
            workerBusy = false;
            var run = currentRun;
            if (run !== null && message.serial === run.serial && isCurrent(run)) {
                if (Date.now() >= run.deadlineMs) {
                    expire();
                } else {
                    applyResult(run, message.result);
                    if (isCurrent(run)) currentRun = null;
                }
            }
            dispatchReply();
        }

        function expire() {
            var expiredSerial = cancel();
            if (serial === expiredSerial)
                errorText = i18n("Loading cost data timed out. Try again.");
        }

        function applyResult(run, result) {
            switch (result.outcome) {
            case "success":
            case "partial":
                var previous = snapshotContext === run.commandSource ? snapshot : ({});
                snapshot = Normalizer.mergeCostSnapshotsAfterPartialFailure(previous, result.costs, result.failedProviders);
                if (!isCurrent(run)) return;
                snapshotContext = run.commandSource;
                if (!isCurrent(run)) return;
                errorText = result.outcome === "success" ? "" : (result.message.length > 0 ? result.message : i18n("Some cost data could not be refreshed."));
                break;
            case "commandFailed":
                errorText = result.message || i18n("codexbar command failed.");
                if (result.argumentsRejected && run.historyPeriod.length > 0) {
                    errorText = i18n("Month to date and All history need codexbar 0.67.0 or later.");
                }
                break;
            case "tooLarge":
                errorText = i18n("codexbar response exceeded the supported size.");
                break;
            case "empty":
                errorText = result.message.length > 0 ? result.message : i18n("codexbar cost did not return JSON.");
                break;
            case "invalidJson":
                errorText = i18n("Could not parse codexbar cost JSON: %1", result.message);
                break;
            case "unsupported":
                errorText = i18n("codexbar cost returned an unsupported JSON payload.");
                break;
            }
        }
    }

    CliProcess {
        id: request

        onCompleted: function (context, stdoutText, stderrText, exitCode) {
            lifecycle.acceptReply(context, stdoutText, stderrText, exitCode);
        }
        onTimedOut: function(context) {
            if (lifecycle.isCurrent(context)) lifecycle.expire();
        }
    }

    WorkerScript {
        id: normalizer
        source: "../CostWorker.mjs"
        onReadyChanged: if (ready) lifecycle.dispatchReply()
        onMessage: function(messageObject) { lifecycle.acceptResult(messageObject); }
    }

    Timer {
        interval: 1000
        repeat: true
        running: controller.loading
        onTriggered: {
            if (lifecycle.currentRun !== null && Date.now() >= lifecycle.currentRun.deadlineMs)
                lifecycle.expire();
        }
    }

    Timer {
        interval: CostRefreshPolicy.automaticRefreshCheckIntervalMs
        repeat: true
        running: lifecycle.commandSource.length > 0
        onTriggered: lifecycle.refreshIfStale()
    }

    Timer {
        interval: 60000
        repeat: true
        running: controller.active
        onTriggered: {
            if (CostRefreshPolicy.isNewBucketDay(lifecycle.lastAttemptAtMs, Date.now())) {
                lifecycle.refreshVisible();
            }
        }
    }
}
