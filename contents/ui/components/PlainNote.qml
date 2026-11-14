import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

// Contextual text without a message surface. Optional explanations can start
// collapsed; failures needing recovery actions keep PlainInlineMessage.
Item {
    id: noteRoot

    property string plainText: ""
    property int type: Kirigami.MessageType.Information
    property bool showCloseButton: false
    property string heading: ""
    property bool expanded: false
    readonly property alias text: noteLabel.text

    signal closed()

    onExpandedChanged: {
        if (!expanded && closeButton.activeFocus)
            detailsButton.forceActiveFocus(Qt.TabFocusReason)
    }

    readonly property bool warning: type === Kirigami.MessageType.Warning
    implicitHeight: noteRow.implicitHeight

    RowLayout {
        id: noteRow

        width: parent.width
        spacing: Kirigami.Units.smallSpacing * 1.5

        Kirigami.Icon {
            visible: noteRoot.warning && noteRoot.heading.length === 0
            source: "data-warning"
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: Math.max(0, (noteMetrics.height - height) / 2)
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }

        FontMetrics {
            id: noteMetrics

            font: noteLabel.font
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: Kirigami.Units.smallSpacing

            DisclosureButton {
                id: detailsButton
                objectName: "plainNoteDetailsButton"
                visible: noteRoot.heading.length > 0
                Layout.minimumWidth: 0
                Layout.maximumWidth: Math.max(0, noteRoot.width
                    - (closeButton.visible ? closeButton.implicitWidth + noteRow.spacing : 0))
                plainText: noteRoot.heading
                expanded: noteRoot.expanded
                onClicked: noteRoot.expanded = !noteRoot.expanded
            }

            PlainPlasmaLabel {
                id: noteLabel
                objectName: "plainNoteLabel"

                visible: noteRoot.heading.length === 0 || noteRoot.expanded
                text: noteRoot.plainText
                font: Kirigami.Theme.smallFont
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Layout.minimumWidth: 0
            }
        }

        PlasmaComponents.ToolButton {
            id: closeButton
            objectName: "plainNoteCloseButton"
            visible: noteRoot.showCloseButton && (noteRoot.heading.length === 0 || noteRoot.expanded)
            icon.name: "window-close-symbolic"
            icon.width: Kirigami.Units.iconSizes.small
            icon.height: Kirigami.Units.iconSizes.small
            display: PlasmaComponents.AbstractButton.IconOnly
            text: i18n("Close")
            Accessible.name: text
            Layout.alignment: Qt.AlignTop
            onClicked: {
                noteRoot.visible = false
                noteRoot.closed()
            }

            // Match every other icon-only ToolButton: Accessible.name covers
            // screen readers, and the tooltip covers pointer and keyboard focus.
            PlainToolTip {
                objectName: "plainNoteCloseToolTip"
                plainText: closeButton.text
                visible: closeButton.hovered || closeButton.visualFocus
            }
        }
    }
}
