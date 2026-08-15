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
        icon.name: "edit-copy"
        Accessible.name: valueRow.copyAccessibleName
        Controls.ToolTip.visible: hovered || valueRow.copied
        Controls.ToolTip.text: valueRow.copied ? i18n("Copied") : valueRow.copyAccessibleName
        onClicked: valueRow.copyRequested(valueRow.text)
    }
}
