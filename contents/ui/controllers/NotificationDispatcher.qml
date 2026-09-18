import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../CommandLedger.js" as CommandLedger
import "../NotificationCommand.js" as NotificationCommand

Item {
    id: controller

    readonly property bool sending: CommandLedger.hasDeadlines(lifecycle.commands)

    signal activated(string sourceName)

    function send(title, body, urgency, actionLabel) {
        return lifecycle.dispatch(title, body, urgency, actionLabel);
    }

    Component.onDestruction: lifecycle.retire()

    Item {
        id: lifecycle

        property var commands: ({})
        property int runSerial: 0
        property bool destroyed: false
        readonly property int notificationCommandTimeoutMs: 10000
        // A clickable notification blocks until it is activated or closed, so
        // its command needs a longer bounded lifetime than a fire-and-forget
        // send.
        readonly property int notificationActionCommandTimeoutMs: 120000

        function dispatch(title, body, urgency, actionLabel) {
            if (destroyed)
                return "";
            var command = NotificationCommand.command(title, body, urgency, actionLabel);
            if (command.length === 0)
                return "";
            runSerial += 1;
            var sourceName = CommandLedger.withRunNonce(command, runSerial);
            var timeout = command.indexOf("--action=") >= 0
                ? notificationActionCommandTimeoutMs
                : notificationCommandTimeoutMs;
            var descriptor = CommandLedger.descriptor("notification", "", Date.now(), timeout);
            // Plasma may publish a cached result while connecting the source.
            commands = CommandLedger.opened(commands, sourceName, descriptor);
            notificationSource.connectSource(sourceName);
            return sourceName;
        }

        function finish(sourceName) {
            commands = CommandLedger.closed(commands, sourceName);
            notificationSource.disconnectSource(sourceName);
        }

        function expire(nowMs) {
            var expired = CommandLedger.expired(commands, nowMs);
            for (var i = 0; i < expired.length; i++) {
                finish(expired[i].sourceName);
            }
        }

        function retire() {
            destroyed = true;
            var sources = Object.keys(commands);
            commands = ({});
            for (var i = 0; i < sources.length; i++) {
                notificationSource.disconnectSource(sources[i]);
            }
        }

        function actionActivated(data) {
            var stdoutText = data && typeof data["stdout"] === "string" ? data["stdout"] : "";
            return stdoutText.slice(0, 64).trim() === "default";
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: controller.sending
        onTriggered: lifecycle.expire(Date.now())
    }

    Plasma5Support.DataSource {
        id: notificationSource

        engine: "executable"
        onNewData: function (sourceName, data) {
            if (!CommandLedger.find(lifecycle.commands, sourceName)) {
                notificationSource.disconnectSource(sourceName);
                return;
            }
            var actionActivated = lifecycle.actionActivated(data);
            lifecycle.finish(sourceName);
            if (actionActivated) {
                controller.activated(sourceName);
            }
        }
    }
}
