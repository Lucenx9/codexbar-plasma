import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../CommandLedger.js" as CommandLedger
import "../IdentifiedTokens.js" as IdentifiedTokens

Item {
    id: controller

    property string commandPath: ""
    property bool collectionEnabled: false
    property string sshHost: ""
    property int historyDays: 30
    readonly property bool loading: CommandLedger.hasKind(lifecycle.commands, "identified")
    readonly property var snapshot: lifecycle.snapshot
    readonly property string errorKind: lifecycle.errorKind
    readonly property bool sshAvailable: IdentifiedTokens.validHost(sshHost)

    function request(includeRemote) {
        if (!collectionEnabled) return false;
        if (includeRemote === true && !sshAvailable) return false;
        var plan = IdentifiedTokens.requestPlan(commandPath, historyDays, Date.now(), includeRemote === true ? sshHost : "");
        lifecycle.clear();
        if (plan.outcome !== "ready") {
            lifecycle.errorKind = plan.outcome;
            return false;
        }
        lifecycle.runSerial++;
        var source = CommandLedger.withRunNonce(plan.command, lifecycle.runSerial, Date.now() + "-" + Math.random());
        var descriptor = CommandLedger.descriptor("identified", "codex", Date.now(), IdentifiedTokens.requestDeadlineMs);
        descriptor.plan = plan;
        descriptor.context = lifecycle.context;
        lifecycle.commands = CommandLedger.opened(lifecycle.commands, source, descriptor);
        dataSource.connectSource(source);
        return true;
    }

    Component.onDestruction: lifecycle.retireRequests()

    Item {
        id: lifecycle
        objectName: "identifiedTokensLifecycle"
        property int runSerial: 0
        property var commands: ({})
        property var snapshot: null
        property string errorKind: ""
        readonly property string context: JSON.stringify([controller.commandPath, controller.collectionEnabled,
            controller.sshHost, controller.historyDays])
        onContextChanged: clear()

        function finishRequest(source) {
            commands = CommandLedger.closed(commands, source);
            dataSource.disconnectSource(source);
        }
        function retireRequests() {
            var sources = CommandLedger.sourcesOfKind(commands, "identified");
            for (var i = 0; i < sources.length; i++) finishRequest(sources[i]);
        }
        function clear() {
            retireRequests();
            snapshot = null;
            errorKind = "";
        }
        function expireRequests(nowMs) {
            var expired = CommandLedger.expired(commands, nowMs);
            for (var i = 0; i < expired.length; i++) {
                finishRequest(expired[i].sourceName);
                errorKind = "timeout";
            }
        }
        function acceptReply(source, stdoutText, exitCode) {
            var descriptor = CommandLedger.find(commands, source);
            if (!descriptor) return;
            finishRequest(source);
            if (!controller.collectionEnabled || descriptor.context !== context) return;
            var result = IdentifiedTokens.decode(stdoutText, exitCode, descriptor.plan);
            snapshot = result.outcome === "data" ? result.snapshot : null;
            errorKind = result.outcome === "data" ? "" : result.outcome;
        }
    }

    Plasma5Support.DataSource {
        id: dataSource
        engine: "executable"
        interval: 0
        onNewData: function(sourceName, data) {
            lifecycle.acceptReply(sourceName, data ? data["stdout"] : "", data ? data["exit code"] : null);
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: controller.loading
        onTriggered: lifecycle.expireRequests(Date.now())
    }
}
