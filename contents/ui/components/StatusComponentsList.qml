import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Service components of a supported status page, below its "Status Page" row.
// Component names come from the remote page, so they stay plain text.
ColumnLayout {
    id: statusList

    required property var applet
    required property var statusState
    property var expandedGroups: []

    signal groupToggled(string name)
    signal openRequested()

    spacing: 0

    // Component states follow the page's own scale, which differs from the
    // provider status pill, so they carry their own translation context.
    function indicatorText(indicator) {
        switch (indicator) {
        case "none":
            return i18nc("Status of one service component", "Operational")
        case "minor":
            return i18nc("Status of one service component", "Degraded performance")
        case "major":
            return i18nc("Status of one service component", "Partial outage")
        case "critical":
            return i18nc("Status of one service component", "Major outage")
        case "maintenance":
            return i18nc("Status of one service component", "Under maintenance")
        default:
            return i18nc("Status of one service component", "Unknown")
        }
    }

    function indicatorColor(indicator) {
        return indicator === "none" ? Kirigami.Theme.positiveTextColor : statusList.applet.statusBadgeColor(indicator)
    }

    component ComponentRow: RowLayout {
        id: componentRow

        required property var row
        property int depth: 0
        readonly property bool expanded: depth === 0 && statusList.expandedGroups.indexOf(row.name) >= 0

        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing + depth * Kirigami.Units.gridUnit * 2
        Layout.rightMargin: Kirigami.Units.largeSpacing
        Layout.minimumHeight: Kirigami.Units.gridUnit + Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Rectangle {
            Layout.preferredWidth: Kirigami.Units.smallSpacing * 2
            Layout.preferredHeight: Kirigami.Units.smallSpacing * 2
            radius: width / 2
            color: statusList.indicatorColor(componentRow.row.indicator)
        }

        // The arrow alone is the control, so a long remote name elides in
        // the label instead of widening the popup past its status column.
        DisclosureButton {
            id: groupToggle

            objectName: "statusGroupToggle"
            visible: componentRow.row.children.length > 0
            expanded: componentRow.expanded
            Accessible.name: componentRow.row.name + ", " + statusList.indicatorText(componentRow.row.indicator)
            onClicked: statusList.groupToggled(componentRow.row.name)
        }

        PlainPlasmaLabel {
            id: componentName

            text: componentRow.row.name
            elide: Text.ElideRight
            Layout.fillWidth: true

            HoverHandler {
                id: componentNameHover
            }

            // Like other disclosures, the group title toggles too.
            TapHandler {
                enabled: groupToggle.visible
                onTapped: statusList.groupToggled(componentRow.row.name)
            }

            PlainToolTip {
                visible: componentName.truncated && (componentNameHover.hovered || groupToggle.visualFocus)
                plainText: componentName.text
            }
        }

        PlainPlasmaLabel {
            text: statusList.indicatorText(componentRow.row.indicator)
            opacity: statusList.applet.secondaryTextOpacity
        }
    }

    PlainPlasmaLabel {
        visible: statusList.statusState.loading || statusList.statusState.failed
        text: statusList.statusState.loading ? i18n("Loading service status…")
            : i18n("Service status is unavailable.")
        opacity: statusList.applet.secondaryTextOpacity
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing * 2
        Layout.rightMargin: Kirigami.Units.largeSpacing
        Layout.topMargin: Kirigami.Units.smallSpacing
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        wrapMode: Text.Wrap
    }

    Repeater {
        model: statusList.statusState.rows

        delegate: ColumnLayout {
            required property var modelData

            Layout.fillWidth: true
            spacing: 0

            ComponentRow {
                id: groupRow
                row: modelData
            }

            Repeater {
                model: groupRow.expanded ? modelData.children : []

                delegate: ComponentRow {
                    required property var modelData
                    row: modelData
                    depth: 1
                }
            }
        }
    }

    Controls.ItemDelegate {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        // Match the parent action highlights' right edge, not the text rows.
        Layout.rightMargin: Kirigami.Units.smallSpacing
        leftPadding: Kirigami.Units.smallSpacing
        rightPadding: Kirigami.Units.smallSpacing
        text: i18n("Open Status Page")
        icon.name: "internet-web-browser"
        onClicked: statusList.openRequested()
    }
}
