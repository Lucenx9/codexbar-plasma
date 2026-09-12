import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../CommandLedger.js" as CommandLedger
import "../CostRefreshPolicy.js" as CostRefreshPolicy
import "../CostResponse.js" as CostResponse
import "../Guards.js" as Guards
import "../ProviderNormalizer.js" as Normalizer

Item {
    id: controller

    property string commandPath: ""
    property string provider: ""
    property int historyDays: 30
    property bool costUsageEnabled: true
    property bool active: false

    readonly property var costs: lifecycle.snapshotContext === lifecycle.commandSource ? lifecycle.snapshot : ({})
    readonly property bool loading: CommandLedger.hasKind(lifecycle.commands, "cost")
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
    Component.onDestruction: lifecycle.retireRequests()

    Item {
        id: lifecycle

        property bool initialized: false
        property int runSerial: 0
        property var commands: ({})
        property var snapshot: ({})
        property string snapshotContext: ""
        property string errorText: ""
        property double lastAttemptAtMs: -1
        readonly property int commandTimeoutMs: 120000
        readonly property string commandSource: {
            if (!controller.costUsageEnabled || controller.commandPath.length === 0) {
                return "";
            }
            var parts = [Guards.shellQuote(controller.commandPath), "cost", "--format", "json", "--json-only", "--days", String(controller.historyDays)];
            if (controller.provider.length > 0) {
                parts.push("--provider", Guards.shellQuote(controller.provider));
            }
            return parts.join(" ");
        }

        onCommandSourceChanged: {
            if (initialized) {
                // Invalidate live sources synchronously; coalesce setting changes
                // before starting a scan. Keep the old snapshot private so a
                // return to its context can reuse it until the next reply.
                retireRequests();
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

        function requestRefresh(force) {
            var nowMs = Date.now();
            var action = CostRefreshPolicy.refreshAction(commandSource.length > 0, controller.loading, force === true, lastAttemptAtMs, nowMs);
            if (action === CostRefreshPolicy.keepAction) {
                return false;
            }
            retireRequests();
            errorText = "";
            if (action === CostRefreshPolicy.clearAction) {
                snapshot = ({});
                snapshotContext = "";
                return false;
            }
            lastAttemptAtMs = nowMs;
            runSerial += 1;
            var source = CommandLedger.withRunNonce(commandSource, runSerial);
            var descriptor = CommandLedger.descriptor("cost", "", nowMs, commandTimeoutMs);
            descriptor.historyDays = controller.historyDays;
            descriptor.context = commandSource;
            commands = CommandLedger.opened(commands, source, descriptor);
            costSource.connectSource(source);
            return true;
        }

        function finishRequest(sourceName) {
            commands = CommandLedger.closed(commands, sourceName);
            costSource.disconnectSource(sourceName);
        }

        function retireRequests() {
            var sources = CommandLedger.sourcesOfKind(commands, "cost");
            for (var i = 0; i < sources.length; i++) {
                finishRequest(sources[i]);
            }
        }

        function expireRequests(nowMs) {
            var expired = CommandLedger.expired(commands, nowMs);
            for (var i = 0; i < expired.length; i++) {
                finishRequest(expired[i].sourceName);
                errorText = i18n("Loading cost data timed out. Try again.");
            }
        }

        function acceptReply(sourceName, stdoutText, stderrText) {
            var descriptor = CommandLedger.find(commands, sourceName);
            if (!descriptor) {
                return;
            }
            finishRequest(sourceName);
            var result = CostResponse.response(stdoutText, stderrText, descriptor.historyDays);
            switch (result.outcome) {
            case "success":
            case "partial":
                var previous = snapshotContext === descriptor.context ? snapshot : ({});
                snapshot = Normalizer.mergeCostSnapshotsAfterPartialFailure(previous, result.costs, result.failedProviders);
                snapshotContext = descriptor.context;
                errorText = result.outcome === "success" ? "" : (result.message.length > 0 ? result.message : i18n("Some cost data could not be refreshed."));
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

    Plasma5Support.DataSource {
        id: costSource
        engine: "executable"
        interval: 0
        onNewData: function (sourceName, data) {
            lifecycle.acceptReply(sourceName, data ? data["stdout"] : "", data ? data["stderr"] : "");
        }
    }

    Timer {
        interval: CostRefreshPolicy.automaticRefreshIntervalMs
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

    Timer {
        interval: 1000
        repeat: true
        running: controller.loading
        onTriggered: lifecycle.expireRequests(Date.now())
    }
}
