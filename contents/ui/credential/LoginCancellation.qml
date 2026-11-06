pragma Singleton
import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support

QtObject {
    id: cancellation

    // A singleton context outlives the settings page, including the request's
    // completion handler and cleanup timer. Only credential-free commands enter.
    function run(command) {
        return requestComponent.createObject(cancellation, {command: command})
    }

    property Component requestComponent: Component {
        Plasma5Support.DataSource {
            id: request
            property string command: ""
            engine: "executable"
            interval: 0
            connectedSources: command.length > 0 ? [command] : []
            onNewData: function(name) {
                disconnectSource(name)
                destroy()
            }
            property Timer deadline: Timer {
                interval: 7000
                running: true
                onTriggered: request.destroy()
            }
        }
    }
}
