import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "." as Components
import "../CostPresentation.js" as CostPresentation

ColumnLayout {
    id: tokenCostSection
    objectName: "providerLocalCostSection"

    required property var applet
    required property var providerData
    property string accountSelectionKey: applet.accountKey(providerData)
    property bool presentationVisible: false
    property bool detailsExpanded: false
    property var daySelectionMemo: ({ points: [], index: -1 })
    readonly property bool costHistoryShowsTokens: applet.costHistoryShowsTokens
    readonly property string selectionScope: providerData ? JSON.stringify([providerData.provider, accountSelectionKey,
        tokenCost ? tokenCost.historyDays : 0]) : ""
    readonly property var selectedDay: CostPresentation.selectedCostDay(tokenCost ? tokenCost.daily : [], chartPoints, costChart.selectedIndex)
    readonly property bool hasVisibleDetails: detailsExpanded || selectedDay !== null

    onSelectionScopeChanged: {
        detailsExpanded = false;
        clearDaySelection();
    }
    onCostHistoryShowsTokensChanged: clearDaySelection()

    function amountText(amounts, mode) {
        return CostPresentation.hasMetricValue(amounts, false) ? applet.qualifiedCostValue(applet.amountString(amounts.cost, amounts.currency), mode) : i18n("Cost unavailable");
    }

    function tokensText(amounts) {
        return CostPresentation.hasMetricValue(amounts, true) ? applet.usageCountText(amounts.tokens, "tokens") : i18n("Tokens unavailable");
    }

    function daySummaryText() {
        return CostPresentation.amountSummary(applet.costNumberFormat, selectedDay, function (tokens) {
            return applet.usageCountText(tokens, "tokens");
        });
    }

    function clearDaySelection() {
        if (!costChart)
            return;
        daySelectionMemo = { points: costChart.points, index: -1 };
        costChart.selectedIndex = -1;
        costChart.hoveredIndex = -1;
    }

    function rememberDaySelection() {
        // Ignore the chart's index clamp while a new points array is awaiting reconciliation.
        if (daySelectionMemo.points === costChart.points)
            daySelectionMemo = { points: costChart.points, index: costChart.selectedIndex };
    }

    function reconcileDaySelection() {
        var points = costChart.points;
        var index = CostPresentation.costDayIndexAfterRefresh(daySelectionMemo.points, daySelectionMemo.index, points);
        daySelectionMemo = { points: points, index: index };
        costChart.selectedIndex = index;
        costChart.hoveredIndex = -1;
    }

    readonly property var tokenCost: tokenCostSection.providerData ? tokenCostSection.providerData.tokenCost : null
    readonly property var chartPoints: tokenCost ? applet.costChartPoints(tokenCost.daily) : []
    readonly property var costTrustSummary: CostPresentation.costTrustSummary(tokenCost ? [tokenCost] : [])
    readonly property string costErrorText: applet.privateErrorText(applet.costErrorText)
    readonly property bool supportsLocalCost: tokenCostSection.providerData && applet.tokenCostHint(tokenCostSection.providerData.provider).length > 0

    visible: tokenCostSection.tokenCost ? true : tokenCostSection.supportsLocalCost && tokenCostSection.costErrorText.length > 0
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing / 1.5

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    RowLayout {
        Layout.fillWidth: true

        PlainHeading {
            text: i18n("Cost")
            level: 4
            type: Kirigami.Heading.Type.Primary
            Layout.fillWidth: true
        }

        Components.PlainComboBox {
            objectName: "providerCostMetricCombo"
            visible: tokenCostSection.tokenCost !== null
            textRole: "text"
            valueRole: "value"
            model: [
                {
                    text: i18n("Cost"),
                    value: "cost"
                },
                {
                    text: i18n("Tokens"),
                    value: "tokens"
                }
            ]
            currentIndex: tokenCostSection.costHistoryShowsTokens ? 1 : 0
            Accessible.name: i18n("History metric")
            onActivated: function (index) {
                tokenCostSection.applet.setCostHistoryMetric(valueAt(index));
                // The interactive pick severs the currentIndex binding; restore
                // it so the combo keeps tracking settings changes made outside
                // this section.
                currentIndex = Qt.binding(function () {
                    return tokenCostSection.costHistoryShowsTokens ? 1 : 0;
                });
            }
        }
    }

    PlainPlasmaLabel {
        visible: !tokenCostSection.tokenCost && tokenCostSection.costErrorText.length > 0
        text: i18n("Cost unavailable: %1", tokenCostSection.costErrorText)
        color: Kirigami.Theme.negativeTextColor
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }

    GridLayout {
        id: costSummaryGrid
        objectName: "costSummaryGrid"
        visible: tokenCostSection.tokenCost !== null
        Layout.fillWidth: true
        columns: 2
        columnSpacing: Kirigami.Units.largeSpacing

        Repeater {
            model: tokenCostSection.tokenCost ? [
                {
                    label: i18n("Today"),
                    amounts: tokenCostSection.tokenCost.today,
                    valueMode: "plain"
                },
                {
                    label: tokenCostSection.tokenCost.windowLabel,
                    amounts: tokenCostSection.tokenCost.totals,
                    valueMode: tokenCostSection.tokenCost.valueMode
                }
            ] : []

            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: Kirigami.Units.smallSpacing / 2

                PlainPlasmaLabel {
                    text: modelData.label
                    font: Kirigami.Theme.smallFont
                    opacity: tokenCostSection.applet.secondaryTextOpacity
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
                PlainPlasmaLabel {
                    text: tokenCostSection.amountText(modelData.amounts, modelData.valueMode)
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
                PlainPlasmaLabel {
                    text: tokenCostSection.tokensText(modelData.amounts)
                    font: Kirigami.Theme.smallFont
                    opacity: tokenCostSection.applet.secondaryTextOpacity
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    Components.CostTrustNotice {
        noticeScope: "provider:" + (tokenCostSection.providerData ? tokenCostSection.providerData.provider : "")
        stateOwner: tokenCostSection.applet
        presentationVisible: tokenCostSection.presentationVisible
        summary: tokenCostSection.costTrustSummary
    }

    Components.InteractiveChart {
        id: costChart
        objectName: "providerCostChart"
        onPointsChanged: tokenCostSection.reconcileDaySelection()
        onSelectedIndexChanged: tokenCostSection.rememberDaySelection()
        visible: tokenCostSection.chartPoints.length > 0
        applet: tokenCostSection.applet
        points: tokenCostSection.chartPoints
        accent: applet.providerReadableColor(providerData ? providerData.provider : "")
        kind: "bar"
        accessibleTitle: tokenCostSection.costHistoryShowsTokens ? i18n("Daily token history") : i18n("Daily cost history")
        Layout.topMargin: Kirigami.Units.smallSpacing / 2
    }

    RowLayout {
        visible: tokenCostSection.chartPoints.length > 0
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlainPlasmaLabel {
            id: costSparklineSummaryLabel

            text: tokenCostSection.tokenCost ? applet.costSparklineSummary(tokenCostSection.tokenCost.daily) : ""
            font: Kirigami.Theme.smallFont
            opacity: applet.secondaryTextOpacity
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        PlainPlasmaLabel {
            id: costSparklineRangeLabel

            text: tokenCostSection.tokenCost ? i18np("%1 day", "%1 days", tokenCostSection.tokenCost.daily.length) : ""
            font: Kirigami.Theme.smallFont
            opacity: applet.secondaryTextOpacity
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }
    }

    Components.PlainButton {
        objectName: "costDetailsToggle"
        visible: tokenCostSection.tokenCost !== null
        plainText: tokenCostSection.hasVisibleDetails ? i18n("Hide details") : i18n("Show details")
        icon.name: tokenCostSection.hasVisibleDetails ? "arrow-up" : "arrow-down"
        onClicked: {
            if (tokenCostSection.hasVisibleDetails) {
                tokenCostSection.detailsExpanded = false;
                tokenCostSection.clearDaySelection();
            } else {
                tokenCostSection.detailsExpanded = true;
            }
        }
    }

    ColumnLayout {
        id: costDrillDownSection

        readonly property var detailData: tokenCostSection.selectedDay ? {
            totals: tokenCostSection.selectedDay,
            models: tokenCostSection.selectedDay.models,
            modelsTruncated: tokenCostSection.selectedDay.modelsTruncated
        } : tokenCostSection.tokenCost
        readonly property var breakdownRows: applet.costBreakdownRows(detailData)
        readonly property var modelRows: applet.costModelRows(detailData)
        readonly property real metricValueColumnWidth: Kirigami.Units.gridUnit * 9

        objectName: "costDrillDownSection"
        visible: tokenCostSection.tokenCost !== null && tokenCostSection.hasVisibleDetails
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true

            PlainPlasmaLabel {
                objectName: "costDetailsTitle"
                text: tokenCostSection.selectedDay ? i18n("Details for %1", tokenCostSection.selectedDay.label) : i18n("Cost details")
                font.weight: Font.DemiBold
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }

            Components.PlainButton {
                plainText: i18n("All days")
                visible: tokenCostSection.selectedDay !== null
                onClicked: {
                    tokenCostSection.detailsExpanded = true;
                    tokenCostSection.clearDaySelection();
                }
            }
        }

        PlainPlasmaLabel {
            visible: tokenCostSection.selectedDay !== null
            text: tokenCostSection.daySummaryText()
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }

        PlainPlasmaLabel {
            objectName: "costModelsEmptyNotice"
            visible: costDrillDownSection.modelRows.length === 0
            text: tokenCostSection.selectedDay !== null ? i18n("No model breakdown for this day.")
                : i18n("No model breakdown for this period.")
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }

        PlainPlasmaLabel {
            objectName: "costModelsPartialNotice"
            visible: costDrillDownSection.detailData !== null && costDrillDownSection.detailData.modelsTruncated === true
            text: i18n("Model breakdown is partial.")
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }

        PlainPlasmaLabel {
            visible: !tokenCostSection.selectedDay && tokenCostSection.tokenCost && applet.costPerMillionLine(tokenCostSection.tokenCost).length > 0
            text: tokenCostSection.tokenCost ? applet.costPerMillionLine(tokenCostSection.tokenCost) : ""
            font: Kirigami.Theme.smallFont
            opacity: applet.secondaryTextOpacity
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        ColumnLayout {
            visible: costDrillDownSection.breakdownRows.length > 0
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing / 2

            Repeater {
                model: costDrillDownSection.breakdownRows

                delegate: RowLayout {
                    required property var modelData

                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlainPlasmaLabel {
                        text: modelData.label
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        opacity: applet.secondaryTextOpacity
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    PlainPlasmaLabel {
                        id: costBreakdownValueLabel

                        text: modelData.value
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        opacity: applet.valueTextOpacity
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignRight
                        Layout.preferredWidth: costDrillDownSection.metricValueColumnWidth
                        Layout.maximumWidth: costDrillDownSection.metricValueColumnWidth
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Kirigami.Separator {
            visible: costDrillDownSection.modelRows.length > 0
            Layout.fillWidth: true
            opacity: 0.55
        }

        ColumnLayout {
            visible: costDrillDownSection.modelRows.length > 0
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing / 2

            PlainPlasmaLabel {
                id: costModelsHeading

                text: i18n("Models")
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.weight: Font.DemiBold
                opacity: applet.secondaryTextOpacity
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Repeater {
                model: costDrillDownSection.modelRows

                delegate: RowLayout {
                    required property var modelData

                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlainPlasmaLabel {
                        text: modelData.label
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        opacity: applet.secondaryTextOpacity
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    PlainPlasmaLabel {
                        id: costModelValueLabel

                        text: modelData.value
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        opacity: applet.valueTextOpacity
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignRight
                        Layout.preferredWidth: costDrillDownSection.metricValueColumnWidth
                        Layout.maximumWidth: costDrillDownSection.metricValueColumnWidth
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: costHistoryChartSection

        readonly property var rows: applet.costHistoryRows(tokenCostSection.tokenCost)
        readonly property string peakLine: tokenCostSection.tokenCost ? applet.costPeakLine(tokenCostSection.tokenCost.daily) : ""
        readonly property string averageLine: tokenCostSection.tokenCost ? applet.costAverageDailyLine(tokenCostSection.tokenCost.daily) : ""
        readonly property color accent: applet.providerReadableColor(tokenCostSection.providerData ? tokenCostSection.providerData.provider : "")

        visible: tokenCostSection.detailsExpanded && rows.length > 1
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing / 2

        RowLayout {
            id: costHistoryHeaderRow

            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlainPlasmaLabel {
                text: i18n("Cost history")
                font.weight: Font.DemiBold
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            PlainPlasmaLabel {
                visible: costHistoryChartSection.averageLine.length > 0
                text: costHistoryChartSection.averageLine
                font: Kirigami.Theme.smallFont
                opacity: applet.secondaryTextOpacity
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
        }

        PlainPlasmaLabel {
            visible: costHistoryChartSection.peakLine.length > 0
            text: costHistoryChartSection.peakLine
            font: Kirigami.Theme.smallFont
            opacity: applet.secondaryTextOpacity
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        Repeater {
            model: costHistoryChartSection.rows

            delegate: RowLayout {
                id: costHistoryMetricRow

                required property var modelData

                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlainPlasmaLabel {
                    id: costHistoryDateLabel

                    text: modelData.label
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    opacity: applet.secondaryTextOpacity
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                    elide: Text.ElideRight
                }

                Rectangle {
                    id: costHistoryBarTrack

                    Layout.fillWidth: true
                    Layout.preferredHeight: applet.compactMeterTrackHeight
                    radius: height / 2
                    color: applet.withAlpha(Kirigami.Theme.textColor, 0.055)
                    clip: true
                    antialiasing: true

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(100, modelData.percent)) / 100
                        height: parent.height
                        radius: parent.radius
                        antialiasing: true
                        gradient: Gradient {
                            orientation: Gradient.Horizontal

                            GradientStop {
                                position: 0
                                color: applet.withAlpha(costHistoryChartSection.accent, modelData.isPeak ? 0.72 : 0.46)
                            }

                            GradientStop {
                                position: 1
                                color: applet.withAlpha(costHistoryChartSection.accent, modelData.isPeak ? 1 : 0.8)
                            }
                        }

                        Behavior on width {
                            NumberAnimation {
                                duration: Kirigami.Units.longDuration
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }

                PlainPlasmaLabel {
                    id: costHistoryValueLabel

                    text: modelData.value
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    opacity: modelData.isPeak ? applet.valueTextOpacity : applet.secondaryTextOpacity
                    font.weight: modelData.isPeak ? Font.DemiBold : Font.Normal
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                    elide: Text.ElideRight
                }
            }
        }
    }

    ColumnLayout {
        visible: tokenCostSection.detailsExpanded
        Layout.fillWidth: true
        Components.ProjectCostSection {
            applet: tokenCostSection.applet
            providerCosts: tokenCostSection.tokenCost ? [tokenCostSection.tokenCost] : []
        }
    }

    PlainPlasmaLabel {
        visible: tokenCostSection.tokenCost && tokenCostSection.tokenCost.hintLine.length > 0 ? true : false
        text: tokenCostSection.tokenCost ? tokenCostSection.tokenCost.hintLine : ""
        opacity: applet.secondaryTextOpacity
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }
}
