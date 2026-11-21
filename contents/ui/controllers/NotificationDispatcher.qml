import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../CommandLedger.js" as CommandLedger
import "../Guards.js" as Guards
import "../NotificationCommand.js" as NotificationCommand

Item {
    id: controller

    readonly property bool sending: CommandLedger.hasDeadlines(lifecycle.commands)

    signal activated(string sourceName)
    signal actionDiscarded(string sourceName)

    function send(title, body, urgency, actionLabel, onStarted) {
        return lifecycle.dispatch(title, body, urgency, actionLabel, onStarted);
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

        function dispatch(title, body, urgency, actionLabel, onStarted) {
            if (destroyed)
                return "";
            var command = NotificationCommand.command(title, body, urgency, actionLabel);
            if (command.length === 0)
                return "";
            runSerial += 1;
            var actionable = NotificationCommand.wantsAction(actionLabel);
            var timeout = actionable ? notificationActionCommandTimeoutMs : notificationCommandTimeoutMs;
            var descriptor = CommandLedger.descriptor(actionable ? "notificationAction" : "notification", "", Date.now(), timeout);
            var bounded = Guards.boundedShellCommand("sh -c " + Guards.shellQuote(command), timeout / 1000 + 2, 1, true);
            var sourceName = CommandLedger.withRunNonce(bounded, runSerial, Date.now() + "-" + Math.random());
            // Plasma may publish a cached result while connecting the source.
            commands = CommandLedger.opened(commands, sourceName, descriptor);
            if (onStarted)
                onStarted(sourceName);
            notificationSource.connectSource(sourceName);
            return sourceName;
        }

        function finish(sourceName, activated) {
            var descriptor = CommandLedger.find(commands, sourceName);
            if (!descriptor)
                return;
            commands = CommandLedger.closed(commands, sourceName);
            notificationSource.disconnectSource(sourceName);
            if (destroyed || descriptor.kind !== "notificationAction")
                return;
            if (activated)
                controller.activated(sourceName);
            else
                controller.actionDiscarded(sourceName);
        }

        function expire(nowMs) {
            var expired = CommandLedger.expired(commands, nowMs);
            for (var i = 0; i < expired.length; i++) {
                finish(expired[i].sourceName, false);
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
            var exitCode = Guards.exitCode(data ? data["exit code"] : undefined)
            if (exitCode !== 0)
                return false
            var stdoutText = data && typeof data["stdout"] === "string" ? data["stdout"] : ""
            return stdoutText.slice(0, 64).trim() === "default"
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
            var descriptor = CommandLedger.find(lifecycle.commands, sourceName);
            if (!descriptor) {
                notificationSource.disconnectSource(sourceName);
                return;
            }
            lifecycle.finish(sourceName, lifecycle.actionActivated(data));
        }
    }
}
