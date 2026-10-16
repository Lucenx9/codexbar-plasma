import QtQuick
import "../Guards.js" as Guards
import "../SessionRefreshPolicy.js" as SessionRefreshPolicy
import "../SessionResponse.js" as SessionResponse

Item {
    id: controller

    property string commandPath: ""
    property int refreshIntervalSec: 300
    property bool active: false

    readonly property var sessions: lifecycle.snapshot
    readonly property bool loading: request.busy
    readonly property string errorText: lifecycle.errorText
    readonly property double lastUpdatedAtMs: lifecycle.lastCompletedAtMs

    function refresh() {
        return lifecycle.initialized && lifecycle.requestRefresh(true);
    }

    onActiveChanged: {
        if (lifecycle.initialized) {
            if (active) {
                Qt.callLater(lifecycle.refreshIfStale);
            } else {
                refreshTimer.stop();
            }
        }
    }
    Component.onCompleted: {
        lifecycle.initialized = true;
        Qt.callLater(lifecycle.refreshIfStale);
    }

    Item {
        id: lifecycle

        property bool initialized: false
        property var snapshot: []
        property string errorText: ""
        property double lastFinishedAtMs: -1
        property double lastCompletedAtMs: -1
        property string loadedCommandSource: ""
        readonly property string commandSource: controller.commandPath.length > 0 ? [Guards.shellQuote(controller.commandPath), "sessions", "--json-v2"].join(" ") : ""
        readonly property int staleAfterMs: SessionRefreshPolicy.staleAfterMs(controller.refreshIntervalSec)
        readonly property int sessionsCommandTimeoutMs: 60000

        onCommandSourceChanged: {
            if (!initialized) {
                return;
            }
            // Retire the old source before clearing its snapshot. A queued
            // refresh rechecks visibility and uses the final command path.
            request.cancel();
            snapshot = [];
            errorText = "";
            lastFinishedAtMs = -1;
            lastCompletedAtMs = -1;
            loadedCommandSource = "";
            refreshTimer.stop();
            Qt.callLater(refreshIfStale);
        }
        onStaleAfterMsChanged: {
            if (initialized) {
                Qt.callLater(refreshIfStale);
            }
        }

        function observation(force) {
            return {
                commandSource: commandSource,
                loadedCommandSource: loadedCommandSource,
                loading: controller.loading,
                visible: controller.active,
                force: force === true,
                lastFinishedAtMs: lastFinishedAtMs,
                lastCompletedAtMs: lastCompletedAtMs,
                nowMs: Date.now(),
                staleAfterMs: staleAfterMs
            };
        }

        function requestRefresh(force) {
            var action = SessionRefreshPolicy.refreshAction(observation(force));
            if (action === SessionRefreshPolicy.keepAction) {
                return false;
            }
            if (action === SessionRefreshPolicy.missingCommandAction) {
                errorText = i18n("Set the codexbar command path in widget settings.");
                return false;
            }
            refreshTimer.stop();
            errorText = "";
            return request.start(commandSource, null, sessionsCommandTimeoutMs);
        }

        function refreshIfStale() {
            requestRefresh(false);
            scheduleRefresh();
        }

        function scheduleRefresh() {
            refreshTimer.stop();
            var delayMs = SessionRefreshPolicy.nextCheckDelay(observation(false));
            if (delayMs > 0) {
                refreshTimer.interval = delayMs;
                refreshTimer.start();
            }
        }

        function acceptReply(stdoutText, stderrText, exitCode) {
            lastFinishedAtMs = Date.now();
            var result = SessionResponse.response(stdoutText, stderrText, exitCode);
            switch (result.outcome) {
            case "success":
                snapshot = result.sessions;
                errorText = "";
                lastCompletedAtMs = Date.now();
                loadedCommandSource = commandSource;
                break;
            case "commandFailed":
                errorText = result.message || i18n("codexbar command failed.");
                break;
            case "tooLarge":
                errorText = i18n("codexbar response exceeded the supported size.");
                break;
            case "empty":
                errorText = result.message.length > 0 ? result.message : i18n("codexbar sessions did not return JSON.");
                break;
            case "invalidJson":
                errorText = i18n("Could not parse codexbar sessions JSON: %1", result.message);
                break;
            case "unsupported":
                errorText = i18n("codexbar sessions returned an unsupported JSON payload.");
                break;
            }
            scheduleRefresh();
        }
    }

    CliProcess {
        id: request

        onCompleted: function (context, stdoutText, stderrText, exitCode) {
            lifecycle.acceptReply(stdoutText, stderrText, exitCode);
        }
        onTimedOut: {
            lifecycle.lastFinishedAtMs = Date.now();
            lifecycle.errorText = i18n("Loading sessions timed out. Try again.");
            lifecycle.scheduleRefresh();
        }
    }

    Timer {
        id: refreshTimer

        repeat: false
        onTriggered: lifecycle.refreshIfStale()
    }
}
