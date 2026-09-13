import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../CommandLedger.js" as CommandLedger
import "../NotificationCommand.js" as NotificationCommand

Item {
    id: controller

    readonly property bool sending: CommandLedger.hasDeadlines(lifecycle.commands)

    function send(title, body, urgency) {
        return lifecycle.dispatch(title, body, urgency);
    }

    Component.onDestruction: lifecycle.retire()

    Item {
        id: lifecycle

        property var commands: ({})
        property int runSerial: 0
        property bool destroyed: false
        readonly property int notificationCommandTimeoutMs: 10000

        function dispatch(title, body, urgency) {
            if (destroyed)
                return false;
            var command = NotificationCommand.command(title, body, urgency);
            if (command.length === 0)
                return false;
            runSerial += 1;
            var sourceName = CommandLedger.withRunNonce(command, runSerial);
            var descriptor = CommandLedger.descriptor("notification", "", Date.now(), notificationCommandTimeoutMs);
            // Plasma may publish a cached result while connecting the source.
            commands = CommandLedger.opened(commands, sourceName, descriptor);
            notificationSource.connectSource(sourceName);
            return true;
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
            lifecycle.finish(sourceName);
        }
    }
}
