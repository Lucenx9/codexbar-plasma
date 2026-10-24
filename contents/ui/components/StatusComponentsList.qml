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

    signal openRequested()

    spacing: 0

    function indicatorText(indicator) {
        switch (indicator) {
        case "none":
            return i18n("Operational")
        case "minor":
            return i18n("Degraded performance")
        case "major":
            return i18n("Partial outage")
        case "critical":
            return i18n("Major outage")
        case "maintenance":
            return i18n("Maintenance")
        default:
            return i18n("Status unknown")
        }
    }

    function indicatorColor(indicator) {
        return indicator === "none" ? Kirigami.Theme.positiveTextColor : statusList.applet.statusBadgeColor(indicator)
    }

    component ComponentRow: RowLayout {
        id: componentRow

        required property var row
        property int depth: 0
        property bool expanded: false

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

        DisclosureButton {
            objectName: "statusGroupToggle"
            visible: componentRow.row.children.length > 0
            plainText: componentRow.row.name
            expanded: componentRow.expanded
            onClicked: componentRow.expanded = !componentRow.expanded
        }

        PlainPlasmaLabel {
            visible: componentRow.row.children.length === 0
            text: componentRow.row.name
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        Item {
            visible: componentRow.row.children.length > 0
            Layout.fillWidth: true
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
        Layout.rightMargin: Kirigami.Units.smallSpacing
        leftPadding: Kirigami.Units.smallSpacing
        rightPadding: Kirigami.Units.smallSpacing
        text: i18n("Open Status Page")
        icon.name: "internet-web-browser"
        onClicked: statusList.openRequested()
    }
}
