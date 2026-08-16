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

    readonly property color accent: applet.providerReadableColor(
        providerData ? providerData.provider : "",
        Kirigami.Theme.backgroundColor)
    readonly property real shownPercent: applet.displayPercent(rowData)
    readonly property real markerPercent: applet.paceMarkerPercent(rowData)
    readonly property string resetText: usageRow.applet.resetLabel(
        usageRow.applet.usageResetText(usageRow.rowData))
    // Every marker drawn on the meter shares one geometry so pace and quota
    // thresholds read as the same kind of annotation. The inset matters: a
    // marker that spans the track edge to edge looks like a gap in the accent
    // fill rather than a tick placed on top of it.
    readonly property real meterMarkerInset: Math.max(1, Math.round(applet.meterTrackHeight / 7))
    readonly property real meterMarkerWidth: Math.max(2, Math.round(applet.meterTrackHeight / 3.5))

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing / 1.5

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            text: usageRow.rowData.label
            font.weight: Font.DemiBold
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        PlasmaComponents.Label {
            id: usagePercentLabel

            visible: usageRow.rowData.hasPercent
            text: i18n("%1% %2", Math.round(usageRow.shownPercent), usageRow.applet.percentSuffix())
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }
    }

    Rectangle {
        id: usageBar

        visible: usageRow.rowData.hasPercent
        Layout.fillWidth: true
        Layout.preferredHeight: usageRow.applet.meterTrackHeight
        radius: height / 2
        color: usageRow.applet.withAlpha(Kirigami.Theme.textColor, 0.1)
        clip: true

        Rectangle {
            width: usageRow.shownPercent <= 0
                ? 0
                : Math.max(parent.height, parent.width * usageRow.shownPercent / 100)
            height: parent.height
            radius: parent.radius
            color: usageRow.applet.quotaMeterColor(usageRow.rowData, usageRow.accent)

            Behavior on color {
                ColorAnimation {
                    duration: Kirigami.Units.longDuration
                }
            }

            Behavior on width {
                NumberAnimation {
                    duration: Kirigami.Units.longDuration
                    easing.type: Easing.OutCubic
                }
            }
        }

        Rectangle {
            visible: usageRow.markerPercent > 0 && usageRow.markerPercent < 100
            x: Math.max(0, Math.min(parent.width - width, parent.width * usageRow.markerPercent / 100 - width / 2))
            y: usageRow.meterMarkerInset
            width: usageRow.meterMarkerWidth
            height: parent.height - usageRow.meterMarkerInset * 2
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
                y: usageRow.meterMarkerInset
                width: usageRow.meterMarkerWidth
                height: usageBar.height - usageRow.meterMarkerInset * 2
                radius: width / 2
                color: usageRow.applet.statusBadgeColor(modelData.severity)
                opacity: 0.72
            }
        }
    }

    RowLayout {
        visible: usageRow.rowData.pace.length > 0
            || usageRow.resetText.length > 0
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            id: usagePaceLabel

            visible: usageRow.rowData.pace.length > 0
            text: usageRow.rowData.pace
            font: Kirigami.Theme.smallFont
            opacity: usageRow.applet.secondaryTextOpacity
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        PlasmaComponents.Label {
            id: usageResetLabel

            visible: usageRow.resetText.length > 0
            text: usageRow.resetText
            font: Kirigami.Theme.smallFont
            opacity: usageRow.applet.secondaryTextOpacity
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        }
    }
}
