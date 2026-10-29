import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

ColumnLayout {
    id: usageRow

    required property var rowData
    required property bool showPace
    required property bool hideable
    required property string percentText
    required property string paceText
    required property string resetText
    required property string confidenceText
    required property real shownPercent
    required property real markerPercent
    required property color meterColor
    required property var warningMarkers
    required property real meterTrackHeight
    required property real secondaryTextOpacity

    signal hideRequested()

    readonly property string summaryText: typeof rowData.summaryText === "string"
        ? rowData.summaryText : ""
    // Match the copy action's compact target so the header keeps its height.
    readonly property real actionSize: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing

    Layout.fillWidth: true
    spacing: Math.round(Kirigami.Units.smallSpacing / 1.5)

    function withAlpha(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    HoverHandler {
        id: usageRowHover
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlainPlasmaLabel {
            id: usageTitleLabel

            text: usageRow.rowData.label
            font.weight: Font.DemiBold
            Layout.fillWidth: true
            elide: Text.ElideRight

            HoverHandler { id: usageTitleHover }

            PlainToolTip {
                visible: usageTitleLabel.truncated && usageTitleHover.hovered
                plainText: usageTitleLabel.text
            }
        }

        // Revealed on row hover; keyboard focus keeps it visible and reachable.
        // It sits before the percentage so its reserved space falls in the
        // gap after the label, keeping the value flush with the meter's end.
        PlasmaComponents.ToolButton {
            id: hideUsageRowButton
            objectName: "hideUsageRowButton"

            visible: usageRow.hideable
            icon.name: "view-hidden"
            icon.width: Kirigami.Units.iconSizes.small
            icon.height: Kirigami.Units.iconSizes.small
            opacity: usageRowHover.hovered || hovered || activeFocus ? 1 : 0
            Layout.preferredWidth: usageRow.actionSize
            Layout.preferredHeight: usageRow.actionSize
            Accessible.name: i18n("Hide the %1 row", usageRow.rowData.label)

            PlainToolTip {
                parent: hideUsageRowButton
                visible: hideUsageRowButton.hovered || hideUsageRowButton.visualFocus
                plainText: hideUsageRowButton.Accessible.name
            }

            onClicked: usageRow.hideRequested()
        }

        PlainPlasmaLabel {
            id: usagePercentLabel
            objectName: "usagePercentLabel"

            visible: usageRow.rowData.hasPercent
            text: usageRow.percentText
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }
    }

    Rectangle {
        id: usageBar
        objectName: "usageBar"

        visible: usageRow.rowData.hasPercent
        Layout.fillWidth: true
        Layout.preferredHeight: usageRow.meterTrackHeight
        radius: height / 2
        color: usageRow.withAlpha(Kirigami.Theme.textColor, 0.1)
        clip: true

        Rectangle {
            width: usageRow.shownPercent <= 0
                ? 0
                : Math.max(parent.height, parent.width * usageRow.shownPercent / 100)
            height: parent.height
            radius: parent.radius
            color: usageRow.meterColor

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

        MeterMarker {
            objectName: "usagePaceMarker"
            visible: usageRow.showPace && percent > 0 && percent < 100
            percent: usageRow.markerPercent
            markerColor: usageRow.rowData.paceOnTop
                ? usageRow.withAlpha(Kirigami.Theme.positiveTextColor, 0.9)
                : usageRow.withAlpha(Kirigami.Theme.negativeTextColor, 0.9)
        }

        Repeater {
            id: quotaWarningMarkerRepeater

            model: usageRow.warningMarkers

            delegate: MeterMarker {
                required property var modelData

                percent: Number(modelData.percent) || 0
                markerColor: modelData.color
            }
        }
    }

    TextMetrics {
        id: usageMetadataMetrics

        font: usagePaceLabel.font
        text: usagePaceLabel.text + usageResetLabel.text
    }

    GridLayout {
        id: usageMetadataLayout

        // Measure the unwrapped text, so changing columns never feeds the
        // resulting label geometry back into the layout decision.
        readonly property bool stacked: usagePaceLabel.visible && usageResetLabel.visible
            && usageMetadataMetrics.advanceWidth + columnSpacing > width

        visible: usageRow.summaryText.length > 0
            || (usageRow.showPace && usageRow.rowData.pace.length > 0)
            || usageRow.resetText.length > 0
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        columns: stacked ? 1 : 2
        columnSpacing: Kirigami.Units.smallSpacing
        rowSpacing: Kirigami.Units.smallSpacing / 2

        PlainPlasmaLabel {
            id: usagePaceLabel
            objectName: "usagePaceLabel"

            visible: usageRow.summaryText.length > 0
                || (usageRow.showPace && usageRow.rowData.pace.length > 0)
            text: usageRow.summaryText.length > 0 ? usageRow.summaryText
                : usageRow.paceText
            font: Kirigami.Theme.smallFont
            opacity: usageRow.secondaryTextOpacity
            Layout.alignment: Qt.AlignBaseline
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            wrapMode: Text.Wrap
        }

        PlainPlasmaLabel {
            id: usageResetLabel

            visible: usageRow.resetText.length > 0
            text: usageRow.resetText
            font: Kirigami.Theme.smallFont
            opacity: usageRow.secondaryTextOpacity
            horizontalAlignment: usageMetadataLayout.stacked || !usagePaceLabel.visible
                ? Text.AlignLeft : Text.AlignRight
            elide: Text.ElideRight
            Layout.alignment: Qt.AlignBaseline
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.maximumWidth: usageMetadataLayout.stacked || !usagePaceLabel.visible
                ? Infinity : implicitWidth

            HoverHandler { id: usageResetHover }

            PlainToolTip {
                visible: usageResetLabel.truncated && usageResetHover.hovered
                plainText: usageResetLabel.text
            }
        }
    }

    PlainPlasmaLabel {
        objectName: "usageConfidenceLabel"
        visible: usageRow.confidenceText.length > 0
        text: usageRow.confidenceText
        font: Kirigami.Theme.smallFont
        opacity: usageRow.secondaryTextOpacity
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }
}
