import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "." as Components
import "../CostPresentation.js" as CostPresentation

ColumnLayout {
    id: view

    required property var applet
    readonly property var dailyPoints: applet.spendDailyPoints()
    readonly property var providerCosts: applet.spendProviderCosts()
    readonly property var costTrustSummary: CostPresentation.costTrustSummary(providerCosts)
    readonly property real heatmapMaximum: chartMaximum(dailyPoints)

    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Kirigami.Units.largeSpacing

    function chartMaximum(points) {
        var maximum = 0
        for (var i = 0; i < points.length; i++) {
            maximum = Math.max(maximum, Number(points[i].value) || 0)
        }
        return maximum
    }

    function rangeOptions(days) {
        var values = [7, 30, 90]
        var options = [
            { text: i18n("7 days"), value: 7 },
            { text: i18n("30 days"), value: 30 },
            { text: i18n("90 days"), value: 90 }
        ]
        var currentDays = Number(days)
        if (values.indexOf(currentDays) === -1) {
            options.unshift({
                text: i18np("%1 day", "%1 days", currentDays),
                value: currentDays
            })
        }
        return options
    }

    function rangeIndex(options, days) {
        for (var i = 0; i < options.length; i++) {
            if (Number(options[i].value) === Number(days)) {
                return i
            }
        }
        return 0
    }

    function metricOptions() {
        return [
            { text: i18n("Cost"), value: "cost" },
            { text: i18n("Tokens"), value: "tokens" }
        ]
    }

    function metricIndex(options, metric) {
        for (var i = 0; i < options.length; i++) {
            if (String(options[i].value) === String(metric)) {
                return i
            }
        }
        return 0
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing / 2

            PlainHeading {
                text: i18n("Usage & Spend")
                level: 2
                type: Kirigami.Heading.Type.Primary
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            PlainPlasmaLabel {
                text: view.applet.spendTotalLine()
                opacity: view.applet.secondaryTextOpacity
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }

        Controls.ComboBox {
            id: metricCombo

            textRole: "text"
            valueRole: "value"
            model: view.metricOptions()
            currentIndex: view.metricIndex(model, view.applet.costHistoryMetric)
            Accessible.name: i18n("Cost history metric")
            onActivated: function(index) {
                view.applet.setCostHistoryMetric(metricCombo.valueAt(index))
            }
        }

        Controls.ComboBox {
            id: rangeCombo

            textRole: "text"
            valueRole: "value"
            model: view.rangeOptions(view.applet.costHistoryDays)
            currentIndex: view.rangeIndex(model, view.applet.costHistoryDays)
            Accessible.name: i18n("Cost history range")
            onActivated: function(index) {
                view.applet.setCostHistoryDays(rangeCombo.valueAt(index))
            }
        }

        PlasmaComponents.ToolButton {
            icon.name: "view-refresh"
            enabled: !view.applet.costLoading
            Accessible.name: i18n("Refresh cost data")
            onClicked: view.applet.refreshCost(true)
        }
    }

    Components.PlainInlineMessage {
        visible: view.applet.costErrorText.length > 0
        plainText: i18n("Some cost data is unavailable: %1", view.applet.costErrorText)
        type: Kirigami.MessageType.Warning
        Layout.fillWidth: true
    }

    Components.PlainInlineMessage {
        // Distinguishes "you spent little" from "the local scan has not reached
        // that far back yet", which otherwise look identical on the chart.
        visible: view.providerCosts.length > 0 && view.applet.spendHistoryStillBuilding()
        plainText: i18n("Local history is still being collected, so early days may be incomplete.")
        type: Kirigami.MessageType.Information
        Layout.fillWidth: true
    }

    Components.CostTrustNotice {
        noticeScope: "spend"
        stateOwner: view.applet
        presentationVisible: view.visible
        summary: view.costTrustSummary
    }

    PlainPlaceholderMessage {
        visible: !view.applet.costLoading
            && view.providerCosts.length === 0
            && view.applet.costErrorText.length === 0
        plainText: i18n("No local cost data available.")
        plainExplanation: i18n("Cost history appears for providers supported by the codexbar cost command.")
        icon.name: "view-statistics-symbolic"
        type: Kirigami.PlaceholderMessage.Type.Informational
        Layout.fillWidth: true
        Layout.fillHeight: true
    }

    Item {
        visible: view.applet.costLoading && view.providerCosts.length === 0
        Layout.fillWidth: true
        Layout.fillHeight: true

        Controls.BusyIndicator {
            anchors.centerIn: parent
            running: parent.visible
        }
    }

    Item {
        visible: !view.applet.costLoading
            && view.providerCosts.length === 0
            && view.applet.costErrorText.length > 0
        Layout.fillWidth: true
        Layout.fillHeight: true
    }

    PlasmaComponents.ScrollView {
        visible: view.providerCosts.length > 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: availableWidth
        clip: true
        PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff

        ColumnLayout {
            width: Math.max(0, parent.width - Kirigami.Units.smallSpacing)
            spacing: Kirigami.Units.largeSpacing

            InteractiveChart {
                visible: view.dailyPoints.length > 1
                applet: view.applet
                points: view.dailyPoints
                accent: view.applet.readableAccentColor(
                    Kirigami.Theme.highlightColor,
                    Kirigami.Theme.backgroundColor)
                kind: "bar"
                // This chart plots the whole selected range, up to 90 bars, and
                // is the primary view here: it outranks the heatmap below it.
                plotHeight: Kirigami.Units.gridUnit * 6
                accessibleTitle: view.applet.costHistoryShowsTokens
                    ? i18n("Daily token history")
                    : i18n("Daily cost history")
            }

            ColumnLayout {
                visible: view.dailyPoints.length > 0
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing / 2

                PlainPlasmaLabel {
                    text: i18n("Activity heatmap")
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                // The grid follows the selected range instead of a fixed
                // 42-day window, and derives the cell size from the available
                // width so the cells stay large enough to hover.
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: heatmapGrid.implicitHeight
                    clip: true

                    Grid {
                        id: heatmapGrid

                        readonly property real cellSpacing: Math.max(1, Math.round(Kirigami.Units.smallSpacing / 2))
                        readonly property real minimumCellSize: Kirigami.Units.gridUnit * 0.6
                        // Kept below the chart's weight: this is the secondary
                        // read, a weekday pattern, not the magnitude over time.
                        readonly property real maximumCellSize: Kirigami.Units.gridUnit * 1.15
                        readonly property int fittingColumns: Math.max(1, Math.floor(
                            (width + cellSpacing) / (minimumCellSize + cellSpacing)))
                        readonly property int columnCount: Math.max(1, Math.min(
                            fittingColumns, Math.ceil(view.dailyPoints.length / rows)))
                        readonly property real cellSize: Math.max(minimumCellSize, Math.min(
                            maximumCellSize,
                            (width - cellSpacing * (columnCount - 1)) / columnCount))
                        readonly property var cells: view.dailyPoints.slice(
                            Math.max(0, view.dailyPoints.length - columnCount * rows))

                        width: parent.width
                        rows: 7
                        flow: Grid.TopToBottom
                        columnSpacing: cellSpacing
                        rowSpacing: cellSpacing

                        Repeater {
                            model: heatmapGrid.cells

                            delegate: Rectangle {
                                required property var modelData

                                readonly property real fraction: view.heatmapMaximum > 0
                                    ? Math.max(0, Math.min(1, Number(modelData.value) / view.heatmapMaximum))
                                    : 0

                                width: heatmapGrid.cellSize
                                height: heatmapGrid.cellSize
                                radius: Kirigami.Units.cornerRadius / 2
                                color: view.applet.withAlpha(
                                    Kirigami.Theme.highlightColor,
                                    0.1 + fraction * 0.8)
                                border.width: heatmapMouse.containsMouse ? 1 : 0
                                border.color: view.applet.withAlpha(Kirigami.Theme.textColor, 0.4)

                                Controls.ToolTip.visible: heatmapMouse.containsMouse
                                Controls.ToolTip.text: i18n("%1: %2", modelData.label, modelData.displayValue)

                                MouseArea {
                                    id: heatmapMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.NoButton
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlainPlasmaLabel {
                    text: i18n("Providers")
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                Repeater {
                    model: view.providerCosts

                    delegate: RowLayout {
                        required property var modelData

                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: view.applet.providerIconSource(modelData.provider)
                            fallback: "view-statistics"
                            isMask: view.applet.providerIconIsMask(modelData.provider)
                            color: view.applet.providerReadableColor(
                                modelData.provider,
                                Kirigami.Theme.backgroundColor)
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }

                        PlainPlasmaLabel {
                            text: view.applet.providerTitle(modelData.provider)
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        PlainPlasmaLabel {
                            // The range selector above states the window once,
                            // so each row carries only its own figures.
                            text: modelData.windowValueLine
                            opacity: view.applet.valueTextOpacity
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
