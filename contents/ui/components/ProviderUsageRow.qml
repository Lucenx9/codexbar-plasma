import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "../UsageRowLayout.js" as UsageRowLayout

ColumnLayout {
    id: usageRow

    required property var rowData
    required property bool showPace
    required property bool hideable
    required property string percentText
    required property string paceText
    required property string resetText
    required property string confidenceText
    property string dailyAllowanceText: ""
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
    readonly property bool hasPaceOrSummary: summaryText.length > 0
        || (showPace && rowData.pace.length > 0)
    readonly property bool inlineResetEligible: !hasPaceOrSummary && resetText.length > 0
    readonly property real inlineTitleSpacing: Kirigami.Units.smallSpacing * 1.5
    // TextMetrics stay independent of assigned label widths and visibility.
    readonly property real resetSpareWidth: width - Math.ceil(usageTitleMetrics.advanceWidth)
        - Math.ceil(usageResetMetrics.advanceWidth)
        - (rowData.hasPercent ? Math.ceil(usagePercentMetrics.advanceWidth) : 0)
        - (hideable ? actionSize : 0)
        - 1 - inlineTitleSpacing * (3 + (hideable ? 1 : 0) + (rowData.hasPercent ? 1 : 0))
    property bool resetInline: false
    readonly property string warningDescription: warningMarkers.filter(function(marker) {
        return marker.percent > 0 && marker.percent < 100 && typeof marker.description === "string"
    }).map(function(marker) { return marker.description }).join("\n")

    onResetSpareWidthChanged: updateResetPlacement()
    onInlineResetEligibleChanged: updateResetPlacement()
    Component.onCompleted: updateResetPlacement()

    function updateResetPlacement() {
        resetInline = UsageRowLayout.nextInlineReset(resetInline, inlineResetEligible,
            resetSpareWidth, Kirigami.Units.gridUnit)
    }

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    function withAlpha(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    HoverHandler {
        id: usageRowHover
    }

    TextMetrics {
        id: usageTitleMetrics
        font: usageTitleLabel.font
        text: usageRow.rowData.label
    }

    TextMetrics {
        id: usageResetMetrics
        font: usageInlineResetLabel.font
        text: usageRow.resetText
    }

    TextMetrics {
        id: usagePercentMetrics
        font: usagePercentLabel.font
        text: usageRow.percentText
    }

    GridLayout {
        id: usageTitleLayout

        readonly property bool stacked: usageRow.rowData.hasPercent
            && Math.ceil(usageTitleMetrics.advanceWidth) + Math.ceil(usagePercentMetrics.advanceWidth)
                + (usageRow.hideable ? usageRow.actionSize : 0)
                + Kirigami.Units.smallSpacing * (usageRow.hideable ? 2 : 1) > width

        Layout.fillWidth: true
        Layout.minimumWidth: 0
        columns: stacked ? 1 : 2
        columnSpacing: usageRow.resetInline ? usageRow.inlineTitleSpacing : Kirigami.Units.smallSpacing
        rowSpacing: Kirigami.Units.smallSpacing

        RowLayout {
            id: usageTitleRow

            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignBaseline
            baselineOffset: usageTitleLabel.y + usageTitleLabel.baselineOffset
            spacing: usageRow.resetInline ? usageRow.inlineTitleSpacing : Kirigami.Units.smallSpacing

            PlainPlasmaLabel {
                id: usageTitleLabel

                text: usageRow.rowData.label
                font.weight: Font.DemiBold
                Layout.alignment: Qt.AlignBaseline
                Layout.fillWidth: true
                Layout.maximumWidth: usageRow.resetInline ? Math.ceil(implicitWidth) : Infinity
                Layout.minimumWidth: usageRow.resetInline ? Math.ceil(implicitWidth) : 0
                elide: Text.ElideRight

                HoverHandler { id: usageTitleHover }

                PlainToolTip {
                    visible: usageTitleLabel.truncated && usageTitleHover.hovered
                    plainText: usageTitleLabel.text
                }
            }

            Rectangle {
                objectName: "usageResetSeparator"
                visible: usageRow.resetInline
                Layout.preferredWidth: 1
                Layout.preferredHeight: Math.round(usageInlineResetLabel.implicitHeight * 0.75)
                color: usageRow.withAlpha(Kirigami.Theme.textColor, 0.2)
                Accessible.ignored: true
            }

            PlainPlasmaLabel {
                id: usageInlineResetLabel
                objectName: "usageInlineResetLabel"

                visible: usageRow.resetInline
                text: usageRow.resetText
                font: Kirigami.Theme.smallFont
                opacity: usageRow.secondaryTextOpacity
                Layout.alignment: Qt.AlignBaseline
                elide: Text.ElideRight

                HoverHandler { id: usageInlineResetHover }

                PlainToolTip {
                    visible: usageInlineResetLabel.truncated && usageInlineResetHover.hovered
                    plainText: usageInlineResetLabel.text
                }
            }

            Item {
                visible: usageRow.resetInline
                Layout.fillWidth: true
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
                Accessible.description: usageRow.warningDescription

                PlainToolTip {
                    parent: hideUsageRowButton
                    visible: hideUsageRowButton.hovered || hideUsageRowButton.visualFocus
                    plainText: hideUsageRowButton.Accessible.name
                }

                onClicked: usageRow.hideRequested()
            }
        }

        PlainPlasmaLabel {
            id: usagePercentLabel
            objectName: "usagePercentLabel"

            visible: usageRow.rowData.hasPercent
            text: usageRow.percentText
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
            font.features: { "tnum": 1 }
            font.weight: Font.DemiBold
            Layout.alignment: Qt.AlignBaseline
            horizontalAlignment: Text.AlignRight
            Layout.fillWidth: usageTitleLayout.stacked
            Layout.minimumWidth: usageTitleLayout.stacked ? 0 : implicitWidth
            wrapMode: Text.Wrap
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
        Accessible.role: Accessible.ProgressBar
        Accessible.name: usageRow.rowData.label
        Accessible.description: [usageRow.percentText, usageRow.warningDescription]
            .filter(function(part) { return part.length > 0 }).join("\n")

        // Clip the paint separately: clipping the hover handler's parent also
        // clips its margin, making thin tracks unnecessarily hard to target.
        Item {
            anchors.fill: parent
            clip: true

            Rectangle {
                objectName: "usageBarFill"
                width: usageRow.shownPercent <= 0
                    ? 0
                    : Math.max(parent.height, parent.width * usageRow.shownPercent / 100)
                height: parent.height
                radius: usageBar.radius
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

        HoverHandler {
            id: usageBarHover
            margin: Kirigami.Units.smallSpacing
        }

        PlainToolTip {
            objectName: "usageThresholdToolTip"
            visible: usageRow.warningDescription.length > 0 && usageBarHover.hovered
            plainText: usageRow.warningDescription
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

        visible: usageRow.hasPaceOrSummary || (!usageRow.resetInline && usageRow.resetText.length > 0)
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
            objectName: "usageResetLabel"

            visible: !usageRow.resetInline && usageRow.resetText.length > 0
            text: usageRow.resetText
            font: Kirigami.Theme.smallFont
            opacity: usageRow.secondaryTextOpacity
            horizontalAlignment: usageMetadataLayout.stacked || !usagePaceLabel.visible
                ? Text.AlignLeft : Text.AlignRight
            elide: Text.ElideRight
            Layout.alignment: Qt.AlignBaseline
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            // Keep fractional glyph widths when the layout snaps to whole pixels.
            Layout.maximumWidth: usageMetadataLayout.stacked || !usagePaceLabel.visible
                ? Infinity : Math.ceil(implicitWidth)

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

    PlainPlasmaLabel {
        objectName: "usageDailyAllowanceLabel"
        visible: usageRow.dailyAllowanceText.length > 0
        text: usageRow.dailyAllowanceText
        font: Kirigami.Theme.smallFont
        opacity: usageRow.secondaryTextOpacity
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }
}
