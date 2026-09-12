import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../CommandLedger.js" as CommandLedger
import "../Guards.js" as Guards
import "../SessionRefreshPolicy.js" as SessionRefreshPolicy
import "../SessionResponse.js" as SessionResponse

Item {
    id: controller

    property string commandPath: ""
    property int refreshIntervalSec: 300
    property bool active: false

    readonly property var sessions: lifecycle.snapshot
    readonly property bool loading: CommandLedger.hasKind(lifecycle.commands, "sessions")
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
    Component.onDestruction: lifecycle.retireRequests()

    Item {
        id: lifecycle

        property bool initialized: false
        property int runSerial: 0
        property var commands: ({})
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
            retireRequests();
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
            runSerial += 1;
            var source = CommandLedger.withRunNonce(commandSource, runSerial);
            var descriptor = CommandLedger.descriptor("sessions", "", Date.now(), sessionsCommandTimeoutMs);
            commands = CommandLedger.opened(commands, source, descriptor);
            sessionsSource.connectSource(source);
            return true;
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

        function finishRequest(sourceName) {
            commands = CommandLedger.closed(commands, sourceName);
            sessionsSource.disconnectSource(sourceName);
        }

        function retireRequests() {
            var sources = CommandLedger.sourcesOfKind(commands, "sessions");
            for (var i = 0; i < sources.length; i++) {
                finishRequest(sources[i]);
            }
        }

        function expireRequests(nowMs) {
            var expired = CommandLedger.expired(commands, nowMs);
            for (var i = 0; i < expired.length; i++) {
                finishRequest(expired[i].sourceName);
                lastFinishedAtMs = nowMs;
                errorText = i18n("Loading sessions timed out. Try again.");
            }
            if (expired.length > 0) {
                scheduleRefresh();
            }
        }

        function acceptReply(sourceName, stdoutText, stderrText) {
            if (!CommandLedger.find(commands, sourceName)) {
                return;
            }
            finishRequest(sourceName);
            lastFinishedAtMs = Date.now();
            var result = SessionResponse.response(stdoutText, stderrText);
            switch (result.outcome) {
            case "success":
                snapshot = result.sessions;
                errorText = "";
                lastCompletedAtMs = Date.now();
                loadedCommandSource = commandSource;
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

    Plasma5Support.DataSource {
        id: sessionsSource

        engine: "executable"
        interval: 0
        onNewData: function (sourceName, data) {
            lifecycle.acceptReply(sourceName, data ? data["stdout"] : "", data ? data["stderr"] : "");
        }
    }

    Timer {
        id: refreshTimer

        repeat: false
        onTriggered: lifecycle.refreshIfStale()
    }

    Timer {
        interval: 1000
        repeat: true
        running: controller.loading
        onTriggered: lifecycle.expireRequests(Date.now())
    }
}
