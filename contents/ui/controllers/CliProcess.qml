import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../CommandLedger.js" as CommandLedger

// One active request. Callers own command construction, immutable context,
// response interpretation and retry policy; this component owns execution.
Item {
    id: process

    readonly property alias busy: lifecycle.running

    signal completed(var context, var stdoutText, var stderrText, var exitCode)
    signal timedOut(var context)

    function start(command, context, timeoutMs) {
        if (lifecycle.destroyed || typeof command !== "string" || command.length === 0)
            return false;
        var revision = ++lifecycle.revision;
        lifecycle.retire();
        // Disconnect/busy callbacks may have cancelled or started newer work.
        if (lifecycle.destroyed || revision !== lifecycle.revision)
            return false;
        lifecycle.runSerial += 1;
        var source = CommandLedger.withRunNonce(command, lifecycle.runSerial, Date.now() + "-" + Math.random());
        var descriptor = CommandLedger.descriptor("process", "", Date.now(), timeoutMs);
        descriptor.context = context;
        lifecycle.commands = CommandLedger.opened(lifecycle.commands, source, descriptor);
        lifecycle.running = true;
        if (lifecycle.destroyed || revision !== lifecycle.revision)
            return false;
        commandSource.connectSource(source);
        return true;
    }

    function cancel() {
        lifecycle.revision += 1;
        lifecycle.retire();
    }

    Component.onDestruction: {
        lifecycle.destroyed = true;
        cancel();
    }

    Item {
        id: lifecycle

        property bool running: false
        property bool destroyed: false
        property int revision: 0
        property int runSerial: 0
        property var commands: ({})

        function retire() {
            var sources = CommandLedger.sourcesOfKind(commands, "process");
            commands = ({});
            running = false;
            for (var i = 0; i < sources.length; i++)
                commandSource.disconnectSource(sources[i]);
        }

        function accept(sourceName, data) {
            var descriptor = CommandLedger.find(commands, sourceName);
            if (!descriptor || destroyed)
                return;
            var acceptedRevision = revision;
            retire();
            if (!destroyed && acceptedRevision === revision)
                process.completed(descriptor.context, data ? data["stdout"] : "", data ? data["stderr"] : "", data ? data["exit code"] : null);
        }

        function expire(nowMs) {
            var expired = CommandLedger.expired(commands, nowMs);
            if (expired.length === 0 || destroyed)
                return;
            var acceptedRevision = revision;
            retire();
            if (!destroyed && acceptedRevision === revision)
                process.timedOut(expired[0].descriptor.context);
        }
    }

    Plasma5Support.DataSource {
        id: commandSource
        engine: "executable"
        interval: 0
        onNewData: function (sourceName, data) {
            lifecycle.accept(sourceName, data);
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: process.busy
        onTriggered: lifecycle.expire(Date.now())
    }
}
