import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../ProviderConfigWatch.js" as ProviderConfigWatch

Item {
    id: controller

    property bool active: true
    property string command: ProviderConfigWatch.watchCommand()
    readonly property int pollIntervalMs: 60000
    readonly property string stamp: lifecycle.stamp

    signal stampObserved(string stamp, bool initial)

    onActiveChanged: lifecycle.reconnect()
    onCommandChanged: lifecycle.reconnect()
    Component.onCompleted: {
        lifecycle.initialized = true;
        lifecycle.reconnect();
    }
    Component.onDestruction: lifecycle.disconnect()

    Item {
        id: lifecycle

        property bool initialized: false
        property string connectedCommand: ""
        property string stamp: ""

        function disconnect() {
            var previous = connectedCommand;
            connectedCommand = "";
            if (previous.length > 0) {
                watchSource.disconnectSource(previous);
            }
        }

        function reconnect() {
            if (!initialized) {
                return;
            }
            var nextCommand = controller.active ? controller.command : "";
            if (nextCommand === connectedCommand) {
                return;
            }
            disconnect();
            // A shared executable source can publish cached data synchronously.
            connectedCommand = nextCommand;
            if (nextCommand.length > 0) {
                watchSource.connectSource(nextCommand);
            }
        }

        function accept(sourceName, data) {
            if (!controller.active || connectedCommand.length === 0 || sourceName !== connectedCommand || sourceName !== controller.command) {
                watchSource.disconnectSource(sourceName);
                return;
            }
            var result = ProviderConfigWatch.observation(stamp, data ? data["stdout"] : undefined);
            if (result === null) {
                return;
            }
            stamp = result.stamp;
            controller.stampObserved(result.stamp, result.initial);
        }
    }

    Plasma5Support.DataSource {
        id: watchSource

        engine: "executable"
        interval: controller.pollIntervalMs
        onNewData: function (sourceName, data) {
            lifecycle.accept(sourceName, data);
        }
    }
}
