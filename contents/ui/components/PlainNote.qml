import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

// A quiet footnote for information and warnings that need no action. Errors
// with recovery actions keep PlainInlineMessage. The close button hides the
// note like Kirigami.InlineMessage does, so owners can observe visibility.
Rectangle {
    id: noteRoot

    property string plainText: ""
    property int type: Kirigami.MessageType.Information
    property bool showCloseButton: false
    readonly property alias text: noteLabel.text

    readonly property bool warning: type === Kirigami.MessageType.Warning
    readonly property color tone: warning ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
    readonly property real padding: Kirigami.Units.smallSpacing * 1.5

    implicitHeight: noteRow.implicitHeight + padding * 2
    radius: Kirigami.Units.cornerRadius * 2
    color: withAlpha(tone, warning ? 0.12 : 0.05)

    RowLayout {
        id: noteRow

        anchors.fill: parent
        anchors.margins: noteRoot.padding
        anchors.leftMargin: noteRoot.padding * 1.5
        spacing: Kirigami.Units.smallSpacing * 1.5

        Kirigami.Icon {
            // Breeze's warning keeps its own neutral color; the info glyph is
            // monochrome and follows the secondary text.
            source: noteRoot.warning ? "data-warning" : "help-about-symbolic"
            isMask: !noteRoot.warning
            color: Kirigami.Theme.textColor
            opacity: noteRoot.warning ? 1 : 0.6
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: Math.max(0, (noteMetrics.height - height) / 2)
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }

        FontMetrics {
            id: noteMetrics

            font: noteLabel.font
        }

        PlainPlasmaLabel {
            id: noteLabel
            objectName: "plainNoteLabel"

            text: noteRoot.plainText
            font: Kirigami.Theme.smallFont
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
        }

        PlasmaComponents.ToolButton {
            objectName: "plainNoteCloseButton"
            visible: noteRoot.showCloseButton
            icon.name: "window-close-symbolic"
            icon.width: Kirigami.Units.iconSizes.small
            icon.height: Kirigami.Units.iconSizes.small
            display: PlasmaComponents.AbstractButton.IconOnly
            text: i18n("Close")
            Accessible.name: text
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: -noteRoot.padding / 2
            Layout.bottomMargin: -noteRoot.padding / 2
            onClicked: noteRoot.visible = false
        }
    }

    function withAlpha(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }
}
