import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

ColumnLayout {
    id: usageRow

    required property var applet
    required property var providerData
    required property var modelData
    readonly property var rowData: modelData

    readonly property color accent: applet.providerColor(providerData ? providerData.provider : "")
    readonly property real shownPercent: applet.displayPercent(rowData)
    readonly property real markerPercent: applet.paceMarkerPercent(rowData)

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing / 1.5

    PlasmaComponents.Label {
        text: usageRow.rowData.label
        font.weight: Font.DemiBold
        Layout.fillWidth: true
        elide: Text.ElideRight
    }

    Rectangle {
        id: usageBar

        visible: usageRow.rowData.hasPercent
        Layout.fillWidth: true
        Layout.preferredHeight: 6
        radius: height / 2
        color: usageRow.applet.withAlpha(Kirigami.Theme.textColor, 0.14)
        clip: true

        Rectangle {
            width: usageRow.shownPercent <= 0
                ? 0
                : Math.max(parent.height, parent.width * usageRow.shownPercent / 100)
            height: parent.height
            radius: parent.radius
            color: usageRow.accent
        }

        Rectangle {
            visible: usageRow.markerPercent > 0 && usageRow.markerPercent < 100
            x: Math.max(0, Math.min(parent.width - width, parent.width * usageRow.markerPercent / 100 - width / 2))
            y: 1
            width: 2
            height: parent.height - 2
            radius: width / 2
            color: usageRow.rowData.paceOnTop
                ? usageRow.applet.withAlpha(Kirigami.Theme.positiveTextColor, 0.9)
                : usageRow.applet.withAlpha(Kirigami.Theme.negativeTextColor, 0.9)
        }

        Repeater {
            id: quotaWarningMarkerRepeater

            model: usageRow.applet.quotaWarningMarkers(usageRow.rowData)

            delegate: Rectangle {
                readonly property real warningPercent: Number(modelData.percent) || 0

                visible: warningPercent > 0 && warningPercent < 100
                x: Math.max(0, Math.min(usageBar.width - width, usageBar.width * warningPercent / 100 - width / 2))
                y: 0
                width: 1
                height: usageBar.height
                radius: width / 2
                color: usageRow.applet.statusBadgeColor(modelData.severity)
                opacity: 0.72
            }
        }
    }

    RowLayout {
        visible: usageRow.rowData.hasPercent || usageRow.applet.resetLabel(usageRow.rowData.reset).length > 0
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            visible: usageRow.rowData.hasPercent
            text: i18n("%1% %2", Math.round(usageRow.shownPercent), usageRow.applet.percentSuffix())
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        PlasmaComponents.Label {
            visible: usageRow.applet.resetLabel(usageRow.rowData.reset).length > 0
            text: usageRow.applet.resetLabel(usageRow.rowData.reset)
            opacity: 0.66
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        }
    }

    PlasmaComponents.Label {
        visible: usageRow.rowData.pace.length > 0
        text: usageRow.rowData.pace
        opacity: 0.66
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }
}
