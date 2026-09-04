import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: refreshControl

    required property string label
    property bool busy: false

    signal requested

    // Keep the native button's footprint while the smaller spinner is shown,
    // so refreshing never changes the space available to the heading.
    implicitWidth: refreshButton.implicitWidth
    implicitHeight: refreshButton.implicitHeight

    PlasmaComponents.ToolButton {
        id: refreshButton

        anchors.fill: parent
        visible: !refreshControl.busy
        icon.name: "view-refresh"
        Accessible.name: refreshControl.label
        onClicked: refreshControl.requested()

        PlainToolTip {
            visible: refreshButton.hovered
            delay: Kirigami.Units.toolTipDelay
            plainText: refreshControl.label
        }
    }

    Controls.BusyIndicator {
        anchors.centerIn: parent
        width: Kirigami.Units.iconSizes.smallMedium
        height: width
        visible: refreshControl.busy
        running: visible
        Accessible.name: refreshControl.label
    }
}
