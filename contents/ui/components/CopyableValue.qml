import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

RowLayout {
    id: valueRow

    required property string text
    property string copyAccessibleName: i18n("Copy value")
    property int fontWeight: Font.Normal
    property real textOpacity: 1
    property int pixelSize: 0
    property bool copied: false
    // Owners reveal the action on row hover; keyboard focus and the copied
    // confirmation still force it visible so it stays reachable without a mouse.
    property bool copyRevealed: true

    signal copyRequested(string text)

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing / 2

    PlasmaComponents.Label {
        text: valueRow.text
        font.weight: valueRow.fontWeight
        font.pixelSize: valueRow.pixelSize > 0 ? valueRow.pixelSize : Kirigami.Theme.defaultFont.pixelSize
        opacity: valueRow.textOpacity
        Layout.fillWidth: true
        elide: Text.ElideRight
    }

    PlasmaComponents.ToolButton {
        id: copyButton

        icon.name: "edit-copy"
        opacity: valueRow.copyRevealed || valueRow.copied || hovered || activeFocus ? 1 : 0
        Accessible.name: valueRow.copyAccessibleName
        Controls.ToolTip.visible: hovered || valueRow.copied
        Controls.ToolTip.text: valueRow.copied ? i18n("Copied") : valueRow.copyAccessibleName
        onClicked: valueRow.copyRequested(valueRow.text)

        Behavior on opacity {
            NumberAnimation {
                duration: Kirigami.Units.shortDuration
            }
        }
    }
}
