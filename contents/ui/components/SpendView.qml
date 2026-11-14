import QtQuick
import QtQuick.Window
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "." as Components
import "../UsageAnalysis.js" as Analysis
import "../AnalysisAmounts.mjs" as AnalysisAmounts
import "../CostAmounts.mjs" as CostAmounts
import "../CostChart.mjs" as CostChart
import "../CostCurrency.mjs" as CostCurrency
import "../CostTrust.mjs" as CostTrust
import "../HeatmapNavigation.js" as HeatmapNavigation

ColumnLayout {
    id: view

    required property var applet
    property string selectedProvider: ""
    property bool expandedView: false
    readonly property bool historyAvailable: applet.costUsageEnabled !== false || applet.identifiedTokensEnabled === true
    property bool activityExpanded: false
    property var expandedModelProviders: []
    property var providersShowingAllModels: []
    property string modelFocusRestoreProvider: ""
    property bool modelFocusRestoreAction: false
    property int modelFocusRestoreReason: Qt.OtherFocusReason
    signal restoreModelsFocus(string provider, bool modelAction, int focusReason)
    readonly property var allProviderCosts: applet.spendProviderCosts()
    readonly property var filterProviderCosts: selectedProvider
        && !allProviderCosts.some(function(item) { return item.provider === selectedProvider })
        ? allProviderCosts.concat([{provider: selectedProvider}]) : allProviderCosts
    readonly property var dailyPoints: Analysis.dailyPoints(
        applet.costNumberFormat, providerCosts, applet.costHistoryShowsTokens)
    readonly property string selectedDay: historyChart.selectedIndex >= 0
        && historyChart.selectedIndex < dailyPoints.length ? dailyPoints[historyChart.selectedIndex].label : ""
    readonly property var providerOptions: [{value: "", text: i18n("All providers")}].concat(
        applet.presentedSpendProviderCosts(filterProviderCosts).map(function(item) {
            return {value: item.provider, text: view.applet.providerDisplayTitle(item.provider)}
        }))
    property var daySelectionMemo: ({ points: [], index: -1 })
    readonly property string selectionScope: JSON.stringify([
        applet.costHistoryDays, applet.costHistoryPeriod, applet.costHistoryMetric, selectedProvider])
    readonly property var providerCosts: Analysis.filterCosts(allProviderCosts, selectedProvider)
    readonly property var presentedProviderCosts: applet.presentedSpendProviderCosts(Analysis.dayCosts(providerCosts, selectedDay))
    readonly property var costTrustSummary: CostTrust.costTrustSummary(providerCosts)
    readonly property string spendCurrency: applet.spendCurrency(providerCosts)
    readonly property bool hasMixedCostCurrencies: CostCurrency.spendHasMixedCostCurrencies(providerCosts)
    readonly property real heatmapMaximum: chartMaximum(dailyPoints)
    readonly property var heatmapDays: CostChart.spendHeatmapDays(
        dailyPoints.filter(function(point) { return point.value !== null }), providerCosts)
    readonly property int heatmapFirstWeekday: Qt.locale().firstDayOfWeek
    readonly property var heatmapRowWeekdays: CostChart.spendHeatmapRowWeekdays(
        heatmapDays, heatmapFirstWeekday)
    readonly property int heatmapTrailingSlots: CostChart.spendHeatmapTrailingSlots(
        heatmapDays, heatmapFirstWeekday)

    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Kirigami.Units.largeSpacing

    Timer {
        id: modelFocusRestore
        interval: 0
        onTriggered: {
            var provider = view.modelFocusRestoreProvider
            var modelAction = view.modelFocusRestoreAction
            var focusReason = view.modelFocusRestoreReason
            view.modelFocusRestoreProvider = ""
            view.modelFocusRestoreAction = false
            view.modelFocusRestoreReason = Qt.OtherFocusReason
            if (!view.visible || !provider) return
            if (view.presentedProviderCosts.some(function(item) { return item.provider === provider }))
                view.restoreModelsFocus(provider, modelAction, focusReason)
            else
                providerFilter.forceActiveFocus(Qt.OtherFocusReason)
        }
    }

    Connections {
        target: spendProviderRepeater
        function onItemRemoved(index: int, item: var) {
            if (item && (item.modelsActionFocused || item.providerHeaderFocused)) {
                view.modelFocusRestoreProvider = item.modelData.provider
                view.modelFocusRestoreAction = item.modelsActionFocused
                view.modelFocusRestoreReason = item.providerHeaderFocusReason
                modelFocusRestore.restart()
            }
        }
    }

    onSelectionScopeChanged: {
        if (!historyChart)
            return
        heatmapFocus.selectedDay = ""
        heatmapFocus.hoveredDay = ""
        daySelectionMemo = { points: historyChart.points, index: -1 }
        historyChart.selectedIndex = -1
        historyChart.hoveredIndex = -1
    }

    function chartMaximum(points) {
        var maximum = 0
        for (var i = 0; i < points.length; i++) {
            maximum = Math.max(maximum, Number(points[i].value) || 0)
        }
        return maximum
    }

    function revealHistoryItem(item, lastItem) {
        var flick = spendHistoryScroll.contentItem as Flickable
        if (!visible || !flick || !item || !item.visible) return
        item.ensurePolished()
        historyContent.ensurePolished()
        var ancestor = item
        while (ancestor && ancestor !== flick.contentItem) ancestor = ancestor.parent
        if (!ancestor) return
        var top = item.mapToItem(flick.contentItem, 0, 0).y
        var end = lastItem || item
        var bottom = end.mapToItem(flick.contentItem, 0, end.height).y
        var target = flick.contentY
        if (top < target) target = top
        else if (bottom > target + flick.height) target = Math.min(top, bottom - flick.height)
        flick.contentY = Math.max(0, Math.min(target, Math.max(0, flick.contentHeight - flick.height)))
    }

    Connections {
        target: view.Window.window
        function onActiveFocusItemChanged() {
            var item = view.Window.window.activeFocusItem
            if (item && item.focusReason !== Qt.MouseFocusReason)
                Qt.callLater(function() { if (item && item.activeFocus) view.revealHistoryItem(item) })
        }
    }

    // Shared by the grid and its legend, so the key matches the cells exactly.
    function heatmapTint(fraction) {
        return applet.withAlpha(Kirigami.Theme.highlightColor, 0.1 + fraction * 0.8)
    }

    // Day counts are numbers; the calendar periods are the CLI's names.
    function rangeOptions(days) {
        var values = [7, 30, 90]
        var options = [
            { text: i18n("7 days"), value: 7 },
            { text: i18n("30 days"), value: 30 },
            { text: i18n("90 days"), value: 90 },
            { text: i18n("Month to date"), value: "month-to-date" },
            { text: i18n("All history"), value: "all" }
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

    function rangeIndex(options, days, period) {
        for (var i = 0; i < options.length; i++) {
            if (period ? options[i].value === period : options[i].value === Number(days)) {
                return i
            }
        }
        return 0
    }

    Kirigami.Action {
        id: showAllProvidersAction
        text: i18n("Show all providers")
        visible: view.selectedProvider.length > 0 && view.allProviderCosts.length > 0
        onTriggered: {
            providerFilter.forceActiveFocus(Qt.TabFocusReason)
            view.selectedProvider = ""
        }
    }

    RowLayout {
        id: spendHeaderRow

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
                id: spendMetaLabel

                visible: view.applet.costUsageEnabled !== false
                text: i18n("Local history and optional AI analysis")
                font: Kirigami.Theme.smallFont
                opacity: view.applet.secondaryTextOpacity
                Layout.fillWidth: true
                elide: Text.ElideRight

                HoverHandler {
                    id: spendMetaLabelHover
                }

                PlainToolTip {
                    parent: spendMetaLabel
                    visible: spendMetaLabel.truncated && spendMetaLabelHover.hovered
                    plainText: spendMetaLabel.text
                }
            }
        }

        PlasmaComponents.ToolButton {
            id: expandButton
            Layout.alignment: Qt.AlignTop
            visible: view.applet.costUsageEnabled !== false
            objectName: "analysisExpandButton"
            icon.name: view.expandedView ? "view-restore" : "view-fullscreen"
            Accessible.name: view.expandedView ? i18n("Compact analysis") : i18n("Expand analysis")
            onClicked: view.expandedView = !view.expandedView
            PlainToolTip { visible: expandButton.hovered || expandButton.visualFocus; plainText: expandButton.Accessible.name }
        }

        PlasmaComponents.ToolButton {
            id: shareButton
            visible: view.applet.costUsageEnabled !== false
            objectName: "shareUsageButton"
            Layout.alignment: Qt.AlignTop
            icon.name: "document-share"
            Accessible.name: i18n("Share AI usage")
            enabled: view.allProviderCosts.length > 0 && !view.applet.costLoading
            onClicked: view.applet.openShareUsage()
            PlainToolTip {
                parent: shareButton
                visible: shareButton.hovered || shareButton.visualFocus
                plainText: i18n("Share AI usage")
            }
        }

        Components.RefreshButton {
            objectName: "analysisRefreshButton"
            visible: view.applet.costUsageEnabled !== false
            Layout.alignment: Qt.AlignTop
            busy: view.applet.costLoading
            label: i18n("Refresh local history")
            onRequested: view.applet.refreshCost(true)
        }
    }

    GridLayout {
        id: historyControlsRow
        columns: view.width >= metricToggle.implicitWidth + rangeCombo.implicitWidth + Kirigami.Units.gridUnit * 11
            ? 4 : view.width >= metricToggle.implicitWidth + rangeCombo.implicitWidth + Kirigami.Units.smallSpacing ? 2 : 1
        visible: view.applet.costUsageEnabled !== false

        Layout.fillWidth: true
        Layout.rightMargin: Kirigami.Units.smallSpacing
        columnSpacing: Kirigami.Units.smallSpacing
        rowSpacing: Kirigami.Units.smallSpacing

        Components.PlainComboBox {
            id: providerFilter
            objectName: "analysisProviderFilter"
            Layout.columnSpan: historyControlsRow.columns === 4 ? 1 : historyControlsRow.columns
            visible: view.applet.costUsageEnabled !== false
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.maximumWidth: historyControlsRow.columns === 4 ? Kirigami.Units.gridUnit * 18 : Infinity
            textRole: "text"
            valueRole: "value"
            model: view.providerOptions
            currentIndex: Math.max(0, view.providerOptions.findIndex(function(item) {
                return item.value === view.selectedProvider
            }))
            Accessible.name: i18n("Provider filter")
            Accessible.description: currentText
            // The desktop style paints displayText in its background.
            displayText: ""
            RowLayout {
                readonly property real arrowSpace: Math.max(providerFilter.indicator.width,
                    Kirigami.Units.iconSizes.small) + Kirigami.Units.smallSpacing
                x: providerFilter.leftPadding + (providerFilter.mirrored ? arrowSpace : 0)
                y: providerFilter.topPadding
                width: Math.max(0, providerFilter.availableWidth - arrowSpace)
                height: providerFilter.availableHeight
                spacing: Kirigami.Units.smallSpacing
                LayoutMirroring.enabled: providerFilter.mirrored
                Kirigami.Icon {
                    objectName: "analysisSelectedProviderIcon"
                    readonly property string provider: providerFilter.currentValue || ""
                    source: provider ? view.applet.providerIconSource(provider) : "view-list-symbolic"
                    fallback: "view-statistics"
                    isMask: !provider || view.applet.providerIconIsMask(provider)
                    color: provider ? view.applet.providerReadableColor(provider,
                        Kirigami.Theme.backgroundColor) : Kirigami.Theme.textColor
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    Accessible.ignored: true
                }
                PlainPlasmaLabel {
                    id: selectedProviderLabel
                    text: providerFilter.currentText
                    font: providerFilter.font
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    Accessible.ignored: true
                }
            }
            HoverHandler { id: providerFilterHover }
            PlainToolTip {
                objectName: "analysisProviderFilterToolTip"
                parent: providerFilter
                visible: selectedProviderLabel.truncated && !providerFilter.popup.visible
                    && (providerFilterHover.hovered || providerFilter.visualFocus)
                delay: providerFilter.visualFocus ? 0 : Kirigami.Units.toolTipDelay
                plainText: providerFilter.currentText
            }
            delegate: Controls.ItemDelegate {
                id: providerOption
                required property int index
                required property var modelData
                readonly property string provider: modelData.value
                width: providerFilter.width
                readonly property string plainText: providerFilter.textAt(index)
                Accessible.name: plainText
                highlighted: providerFilter.highlightedIndex === index
                PlainToolTip {
                    visible: providerOption.hovered && optionLabel.truncated
                    plainText: providerOption.plainText
                }
                contentItem: RowLayout {
                    LayoutMirroring.enabled: providerOption.mirrored
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Icon {
                        source: providerOption.provider ? view.applet.providerIconSource(providerOption.provider) : "view-list-symbolic"
                        fallback: "view-statistics"
                        isMask: !providerOption.provider || view.applet.providerIconIsMask(providerOption.provider)
                        color: providerOption.provider ? view.applet.providerReadableColor(providerOption.provider,
                            providerOption.highlighted || providerOption.down ? Kirigami.Theme.highlightColor : Kirigami.Theme.backgroundColor)
                            : optionLabel.color
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        Accessible.ignored: true
                    }
                    PlainPlasmaLabel {
                        id: optionLabel
                        text: providerOption.plainText
                        font: providerOption.font
                        color: providerOption.highlighted || providerOption.down
                            ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                    }
                }
            }
            onActivated: function(index) {
                view.selectedProvider = view.providerOptions[index].value
                currentIndex = Qt.binding(function() {
                    return Math.max(0, view.providerOptions.findIndex(function(item) {
                        return item.value === view.selectedProvider
                    }))
                })
            }
        }
        Item { visible: historyControlsRow.columns === 4; Layout.fillWidth: true }

        Components.CostMetricToggle {
            id: metricToggle
            objectName: "analysisMetricToggle"
            enabled: view.applet.costUsageEnabled !== false

            applet: view.applet
        }

        Components.PlainComboBox {
            id: rangeCombo
            Layout.alignment: Qt.AlignRight
            visible: view.applet.costUsageEnabled !== false

            Layout.minimumHeight: metricToggle.implicitHeight
            textRole: "text"
            valueRole: "value"
            model: view.rangeOptions(view.applet.costHistoryDays)
            currentIndex: view.rangeIndex(model, view.applet.costHistoryDays, view.applet.costHistoryPeriod)
            Accessible.name: i18n("%1: %2", i18n("History range"), displayText)
            onActivated: function(index) {
                var value = rangeCombo.valueAt(index)
                if (typeof value === "string") {
                    view.applet.setCostHistoryPeriod(value)
                } else {
                    view.applet.setCostHistoryDays(value)
                }
                // The pick severs currentIndex; restore the binding so the
                // combo keeps tracking settings changes made outside this view.
                rangeCombo.currentIndex = Qt.binding(function() {
                    return view.rangeIndex(rangeCombo.model, view.applet.costHistoryDays,
                        view.applet.costHistoryPeriod)
                })
            }
        }
    }

    PlasmaComponents.ScrollView {
        id: spendHistoryScroll
        objectName: "spendHistoryScroll"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        contentWidth: availableWidth
        clip: true
        PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff

        ColumnLayout {
            id: historyContent
            width: Math.max(0, parent.width - Kirigami.Units.smallSpacing)
            height: !view.historyAvailable || view.providerCosts.length > 0 || view.applet.identifiedTokensEnabled === true
                ? implicitHeight : Math.max(implicitHeight, spendHistoryScroll.availableHeight)
            spacing: Kirigami.Units.largeSpacing

            Loader {
                Layout.fillWidth: true
                active: view.applet.identifiedTokensEnabled === true
                visible: active
                sourceComponent: Components.IdentifiedTokensSection { applet: view.applet }
            }

            Components.PlainNote {
                visible: view.applet.costErrorText.length > 0
                plainText: view.providerCosts.length > 0
                    ? i18n("Some local history is unavailable: %1", view.applet.privateErrorText(view.applet.costErrorText))
                    : i18n("Local history is unavailable: %1", view.applet.privateErrorText(view.applet.costErrorText))
                type: Kirigami.MessageType.Warning
                Layout.fillWidth: true
            }

            Components.AnalysisSummary {
                applet: view.applet
                costs: view.providerCosts
            }

            Components.CostTrustNotice {
                noticeScope: "spend"
                stateOwner: view.applet
                presentationVisible: view.visible
                summary: view.costTrustSummary
            }

            PlainPlasmaLabel {
                visible: view.hasMixedCostCurrencies
                text: i18n("Costs and charts use %1. Other currencies appear separately below. Tokens include all providers.", view.spendCurrency)
                font: Kirigami.Theme.smallFont
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }

            Item {
                visible: view.applet.costUsageEnabled !== false && !view.applet.costLoading
                    && view.providerCosts.length === 0
                    && view.applet.costErrorText.length === 0
                implicitHeight: emptySpendPlaceholder.implicitHeight
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Keep the native placeholder together while this item fills the view.
                PlainPlaceholderMessage {
                    id: emptySpendPlaceholder

                    anchors.centerIn: parent
                    width: parent.width
                    plainText: view.selectedProvider.length > 0 && view.allProviderCosts.length > 0
                        ? i18n("No history for this provider") : i18n("No local token or cost history")
                    plainExplanation: view.selectedProvider.length > 0 && view.allProviderCosts.length > 0
                        ? i18n("Choose another provider or show all providers.")
                        : i18n("History appears for providers supported by the codexbar cost command.")
                    helpfulAction: showAllProvidersAction
                    icon.name: "view-statistics-symbolic"
                    type: Kirigami.PlaceholderMessage.Type.Informational
                }
            }

            Item {
                visible: view.applet.costLoading && view.providerCosts.length === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: spendBusyIndicator.implicitHeight

                Controls.BusyIndicator {
                    id: spendBusyIndicator
                    anchors.centerIn: parent
                    Accessible.name: i18n("Refresh local history")
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

            GridLayout {
                objectName: "analysisChartProviders"
                columns: view.expandedView && view.width >= Kirigami.Units.gridUnit * 38 ? 2 : 1
                columnSpacing: Kirigami.Units.largeSpacing * 2
                rowSpacing: Kirigami.Units.largeSpacing
                Layout.fillWidth: true

                ColumnLayout {
                    objectName: "analysisChartEmptyState"
                    visible: view.providerCosts.length > 0 && view.dailyPoints.length === 0
                    Layout.fillWidth: true
                    Layout.preferredWidth: 3
                    Layout.alignment: Qt.AlignTop
                    spacing: Kirigami.Units.smallSpacing

                    PlainPlasmaLabel {
                        text: view.applet.costHistoryShowsTokens
                            ? i18n("No daily token history is available for this range.")
                            : i18n("No daily cost history for this range. Try Tokens for token history.")
                        font: Kirigami.Theme.smallFont
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                    }

                    PlainButton {
                        id: showTokensButton
                        objectName: "analysisShowTokensButton"
                        visible: !view.applet.costHistoryShowsTokens
                        plainText: i18n("Tokens")
                        onClicked: {
                            var reason = showTokensButton.focusReason
                            view.applet.setCostHistoryMetric("tokens")
                            metricToggle.focusCurrentChoice(reason)
                        }
                    }
                }
            InteractiveChart {
                id: historyChart
                Layout.alignment: Qt.AlignTop
                objectName: "analysisHistoryChart"
                Layout.preferredWidth: 3
                seriesColors: {
                    var colors = ({})
                    view.providerCosts.forEach(function(item) {
                        colors[item.provider] = view.applet.providerReadableColor(item.provider,
                            Kirigami.Theme.backgroundColor)
                    })
                    return colors
                }

                onPointsChanged: {
                    var index = CostChart.costDayIndexAfterRefresh(
                        view.daySelectionMemo.points, view.daySelectionMemo.index, points)
                    if (index >= 0 && points[index].value === null) index = -1
                    view.daySelectionMemo = { points: points, index: index }
                    selectedIndex = index
                    hoveredIndex = -1
                }
                onSelectedIndexChanged: {
                    // Ignore the chart's index clamp until new points are reconciled.
                    if (view.daySelectionMemo.points === points)
                        view.daySelectionMemo = { points: points, index: selectedIndex }
                }
                visible: view.dailyPoints.length > 0
                applet: view.applet
                points: view.dailyPoints
                accent: view.applet.readableAccentColor(
                    Kirigami.Theme.highlightColor,
                    Kirigami.Theme.backgroundColor)
                kind: Analysis.hasCalendarHistory(view.dailyPoints) ? "line" : "bar"
                lineSeries: kind !== "line" ? null : view.applet.presentedSpendProviderCosts(
                    Analysis.providerLines(view.applet.costNumberFormat, view.providerCosts,
                        view.dailyPoints, view.applet.costHistoryShowsTokens)).map(function(series) {
                        return Object.assign({}, series, {
                            label: view.applet.providerDisplayTitle(series.provider),
                            iconSource: view.applet.providerIconSource(series.provider),
                            iconIsMask: view.applet.providerIconIsMask(series.provider)
                        })
                    })
                axisLabels: kind !== "line" ? [] : [historyChart.valueDomain.maximum, historyChart.valueDomain.maximum / 2, 0]
                    .map(function(value, index) {
                        return historyChart.valueDomain.maximum === 0 && index < 2 ? ""
                            : AnalysisAmounts.axisText(view.applet.costNumberFormat, value,
                                {step: historyChart.valueDomain.maximum / 2, currency: view.spendCurrency,
                                    showsTokens: view.applet.costHistoryShowsTokens})
                    })
                showPeak: true
                // This chart plots the whole selected range, up to 365 days, and
                // is the primary view here: it outranks the heatmap below it.
                plotHeight: Kirigami.Units.gridUnit * (view.expandedView ? 10 : 6)
                accessibleTitle: view.applet.costHistoryShowsTokens
                    ? i18n("Daily token history")
                    : i18n("Daily cost history")
            }

                ColumnLayout {
                    visible: view.providerCosts.length > 0
                    Layout.fillWidth: true
                    Layout.preferredWidth: 2
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignTop
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.minimumHeight: allDaysButton.implicitHeight
                        PlainPlasmaLabel {
                            text: view.selectedDay.length > 0 ? i18n("Providers on %1", historyChart.pointLabel({label: view.selectedDay})) : i18n("Providers")
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        PlainButton {
                            id: allDaysButton
                            objectName: "analysisAllDaysButton"
                            visible: view.selectedDay.length > 0
                            plainText: i18n("All days")
                            onClicked: {
                                historyChart.focusPlot(Qt.TabFocusReason)
                                historyChart.selectedIndex = -1
                            }
                        }
                    }

                    Repeater {
                        id: spendProviderRepeater

                        model: view.presentedProviderCosts

                        delegate: ColumnLayout {
                            id: providerGroup
                            required property var modelData
                            readonly property bool modelsActionFocused: modelList.actionFocused
                            readonly property bool providerHeaderFocused: spendProviderCard.activeFocus
                            readonly property int providerHeaderFocusReason: spendProviderCard.focusReason
                            Connections {
                                target: view
                                function onRestoreModelsFocus(provider: string, modelAction: bool, focusReason: int) {
                                    if (provider !== providerGroup.modelData.provider) return
                                    if (modelAction) modelList.restoreActionFocus()
                                    else spendProviderCard.forceActiveFocus(focusReason)
                                }
                            }
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: Kirigami.Units.smallSpacing
                            PlasmaComponents.AbstractButton {
                                id: spendProviderCard

                                readonly property var modelData: providerGroup.modelData
                                readonly property var totals: modelData.totals
                                readonly property string costText: CostAmounts.hasMetricValue(totals, false)
                                    ? view.applet.qualifiedCostValue(AnalysisAmounts.metricText(view.applet.costNumberFormat,
                                        totals.cost, totals.currency, false), modelData.valueMode)
                                    : i18n("Cost unavailable")
                                readonly property string tokensText: CostAmounts.hasMetricValue(totals, true)
                                    ? view.applet.usageCountText(totals.tokens, "tokens")
                                    : i18n("Tokens unavailable")

                                Layout.fillWidth: true
                                implicitHeight: spendProviderRow.implicitHeight + Kirigami.Units.smallSpacing * 2
                                padding: Kirigami.Units.smallSpacing
                                background: Rectangle {
                                    radius: view.applet.roundedSurfaceRadius
                                    color: spendProviderCard.down
                                        ? view.applet.withAlpha(Kirigami.Theme.highlightColor, 0.2)
                                        : spendProviderCard.hovered || spendProviderCard.checked
                                            ? view.applet.withAlpha(Kirigami.Theme.highlightColor, 0.12) : "transparent"
                                    border.width: spendProviderCard.visualFocus ? 2 : 0
                                    border.color: Kirigami.Theme.focusColor
                                }
                                checkable: true
                                checked: view.expandedModelProviders.indexOf(modelData.provider) >= 0
                                onClicked: {
                                    var provider = modelData.provider
                                    var opened = view.expandedModelProviders.indexOf(provider) >= 0
                                    view.expandedModelProviders = opened
                                        ? view.expandedModelProviders.filter(function(value) { return value !== provider })
                                        : view.expandedModelProviders.concat([provider])
                                    checked = Qt.binding(function() { return view.expandedModelProviders.indexOf(modelData.provider) >= 0 })
                                }
                                objectName: "analysisProviderToggle-" + modelData.provider
                                Accessible.checkable: true
                                Accessible.checked: checked

                                Accessible.role: Accessible.Button
                                Accessible.name: view.applet.providerDisplayTitle(spendProviderCard.modelData.provider)
                                Accessible.description: spendProviderPrimary.text + ". " + spendProviderSecondary.text

                                HoverHandler { id: spendProviderHover }

                                PlainToolTip {
                                    visible: (spendProviderHover.hovered || spendProviderCard.visualFocus)
                                        && (spendProviderTitle.truncated || spendProviderPrimary.truncated
                                            || spendProviderSecondary.truncated)
                                    delay: spendProviderCard.visualFocus ? 0 : Kirigami.Units.toolTipDelay
                                    plainText: spendProviderTitle.text + "\n" + spendProviderPrimary.text
                                        + "\n" + spendProviderSecondary.text
                                }

                                contentItem: RowLayout {
                                    id: spendProviderRow

                                    spacing: Kirigami.Units.largeSpacing

                                    Kirigami.Icon {
                                        source: spendProviderCard.checked ? "arrow-down" : (spendProviderCard.mirrored ? "arrow-left" : "arrow-right")
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                        Accessible.ignored: true
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                            + Kirigami.Units.smallSpacing * 2
                                        Layout.preferredHeight: Layout.preferredWidth
                                        // Same identity-tile treatment as the overview
                                        // and header tiles, scaled down for this row.
                                        radius: view.applet.nestedSurfaceRadius
                                        color: view.applet.withAlpha(view.applet.providerReadableColor(
                                            spendProviderCard.modelData.provider,
                                            Kirigami.Theme.backgroundColor), 0.12)
                                        border.width: 1
                                        border.color: view.applet.withAlpha(Kirigami.Theme.textColor, 0.1)

                                        Kirigami.Icon {
                                            anchors.centerIn: parent
                                            source: view.applet.providerIconSource(spendProviderCard.modelData.provider)
                                            fallback: "view-statistics"
                                            isMask: view.applet.providerIconIsMask(spendProviderCard.modelData.provider)
                                            color: view.applet.providerReadableColor(
                                                spendProviderCard.modelData.provider,
                                                Kirigami.Theme.backgroundColor)
                                            width: Kirigami.Units.iconSizes.smallMedium
                                            height: Kirigami.Units.iconSizes.smallMedium
                                        }
                                    }

                                    PlainPlasmaLabel {
                                        id: spendProviderTitle
                                        objectName: "spendProviderTitle"

                                        text: view.applet.providerDisplayTitle(spendProviderCard.modelData.provider)
                                        font.weight: Font.DemiBold
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        Layout.preferredWidth: 1
                                        elide: Text.ElideRight
                                    }

                                    ColumnLayout {
                                        // Equal flexible columns keep long amounts from
                                        // pushing the provider identity out of the row.
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        Layout.preferredWidth: 1
                                        spacing: Kirigami.Units.smallSpacing / 2

                                        PlainPlasmaLabel {
                                            id: spendProviderPrimary
                                            objectName: "spendProviderPrimary"
                                            font.features: { "tnum": 1 }

                                            text: view.applet.costHistoryShowsTokens
                                                ? spendProviderCard.tokensText : spendProviderCard.costText
                                            font.weight: Font.DemiBold
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            horizontalAlignment: Text.AlignRight
                                            elide: Text.ElideRight
                                        }

                                        PlainPlasmaLabel {
                                            id: spendProviderSecondary
                                            objectName: "spendProviderSecondary"

                                            text: view.applet.costHistoryShowsTokens
                                                ? spendProviderCard.costText : spendProviderCard.tokensText
                                            font: Qt.font(Object.assign({}, Kirigami.Theme.smallFont, { features: { "tnum": 1 } }))
                                            opacity: view.applet.secondaryTextOpacity
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            horizontalAlignment: Text.AlignRight
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                            Components.AnalysisModels {
                                id: modelList
                                applet: view.applet
                                costs: Analysis.filterCosts(view.providerCosts, providerGroup.modelData.provider)
                                selectedDay: view.selectedDay
                                expanded: spendProviderCard.checked
                                showAll: view.providersShowingAllModels.indexOf(providerGroup.modelData.provider) >= 0
                                onShowAllRequested: function(value) {
                                    var provider = providerGroup.modelData.provider
                                    var remaining = view.providersShowingAllModels.filter(function(item) { return item !== provider })
                                    view.providersShowingAllModels = value ? remaining.concat([provider]) : remaining
                                }
                                visible: expanded
                                Layout.leftMargin: Kirigami.Units.iconSizes.small + Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
                                Layout.rightMargin: Kirigami.Units.smallSpacing
                                onRestoreFocusRequested: spendProviderCard.forceActiveFocus(Qt.TabFocusReason)
                            }
                        }
                    }
                }
            }

            Components.DisclosureButton {
                id: activityToggle
                objectName: "analysisActivityToggle"
                plainText: i18n("Daily activity")
                visible: view.heatmapDays.length > 7
                expanded: view.activityExpanded
                onClicked: {
                    if (view.activityExpanded) forceActiveFocus(Qt.OtherFocusReason)
                    view.activityExpanded = !view.activityExpanded
                }
            }

            GridLayout {
                id: activitySummary
                visible: view.activityExpanded
                objectName: "spendActivitySummary"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 1
                // The viewport stays stable when the grid's implicit size or
                // scrollbar visibility changes at the layout breakpoint.
                columns: 1
                columnSpacing: Kirigami.Units.largeSpacing * 2
                rowSpacing: Kirigami.Units.largeSpacing

                ColumnLayout {
                    // One week column carries a single day per row, which repeats
                    // the chart above instead of showing a weekday pattern.
                    visible: view.heatmapDays.length > 7
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignTop
                    spacing: Kirigami.Units.smallSpacing / 2

                    // The grid follows the selected range instead of a fixed
                    // 42-day window, and derives the cell size from the available
                    // width so the cells stay large enough to hover.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        // Without weekday names the rows are an unlabelled stripe
                        // pattern; the labels are what make it a weekday read.
                        Column {
                            id: heatmapWeekdayLabels

                            visible: view.heatmapRowWeekdays.length === 7
                            spacing: heatmapGrid.rowSpacing
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: heatmapFocus.monthHeaderHeight
                            Accessible.ignored: true

                            Repeater {
                                model: view.heatmapRowWeekdays

                                delegate: PlainPlasmaLabel {
                                    required property var modelData

                                    height: heatmapGrid.cellHeight
                                    text: Qt.locale().dayName(modelData, Locale.ShortFormat)
                                    font: Kirigami.Theme.smallFont
                                    opacity: view.applet.secondaryTextOpacity
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }

                        Controls.Control {
                            id: heatmapFocus
                            objectName: "spendHeatmap"

                            property string selectedDay: ""
                            property string hoveredDay: ""
                            readonly property var cells: heatmapGrid.cells
                            readonly property var months: CostChart.spendHeatmapMonths(cells)
                            readonly property real monthHeaderHeight: months.length > 0
                                ? heatmapFontMetrics.height + Kirigami.Units.smallSpacing : 0
                            readonly property int inspectedIndex: HeatmapNavigation.indexForDay(cells,
                                hoveredDay.length > 0 ? hoveredDay : (activeFocus ? selectedDay : view.selectedDay))
                            readonly property var inspectedCell: inspectedIndex >= 0 ? cells[inspectedIndex] : null
                            readonly property string inspectedValue: !inspectedCell ? ""
                                : view.applet.costHistoryShowsTokens ? view.applet.usageCountText(inspectedCell.value, "tokens")
                                : inspectedCell.displayValue
                            readonly property string readout: inspectedCell
                                ? i18n("%1: %2", historyChart.pointLabel(inspectedCell), inspectedValue) : ""

                            activeFocusOnTab: HeatmapNavigation.nextDay(cells, "", "first", false).length > 0
                            background: null
                            Accessible.role: Accessible.Graphic
                            Accessible.name: readout.length > 0
                                ? i18n("%1: %2", i18n("Daily activity"), readout) : i18n("Daily activity")
                            Accessible.description: i18n("Arrow keys inspect days. Enter selects a day; Escape clears the selection.")

                            function selectDay(day, reason) {
                                var index = CostChart.uniqueCostDayIndex(historyChart.points, day)
                                if (index < 0 || historyChart.points[index].value === null) return
                                selectedDay = day
                                historyChart.selectedIndex = index
                                forceActiveFocus(reason)
                            }

                            onActiveFocusChanged: {
                                if (activeFocus) {
                                    hoveredDay = ""
                                    view.revealHistoryItem(heatmapFocus, heatmapReadout)
                                }
                                if (activeFocus && HeatmapNavigation.indexForDay(cells, selectedDay) < 0)
                                    selectedDay = HeatmapNavigation.indexForDay(cells, view.selectedDay) >= 0
                                        ? view.selectedDay : HeatmapNavigation.nextDay(cells, "", "last", false)
                            }
                            onCellsChanged: {
                                hoveredDay = ""
                                if (HeatmapNavigation.indexForDay(cells, selectedDay) < 0)
                                    selectedDay = ""
                            }
                            Keys.onPressed: function(event) {
                                var direction = ""
                                switch (event.key) {
                                case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space:
                                    selectDay(selectedDay, Qt.OtherFocusReason); event.accepted = true; return
                                case Qt.Key_Escape:
                                    if (view.selectedDay.length === 0) {
                                        event.accepted = false
                                        return
                                    }
                                    historyChart.selectedIndex = -1
                                    selectedDay = ""
                                    hoveredDay = ""
                                    event.accepted = true
                                    return
                                case Qt.Key_Left: direction = "left"; break
                                case Qt.Key_Right: direction = "right"; break
                                case Qt.Key_Up: direction = "up"; break
                                case Qt.Key_Down: direction = "down"; break
                                case Qt.Key_Home: direction = "first"; break
                                case Qt.Key_End: direction = "last"; break
                                default: event.accepted = false; return
                                }
                                selectedDay = HeatmapNavigation.nextDay(cells, selectedDay,
                                    direction, LayoutMirroring.enabled)
                                hoveredDay = ""
                                event.accepted = true
                            }

                            Layout.fillWidth: true
                            Layout.preferredHeight: 7 * heatmapGrid.cellHeight
                                + 6 * heatmapGrid.rowSpacing + monthHeaderHeight
                            clip: true

                            FontMetrics { id: heatmapFontMetrics; font: Kirigami.Theme.smallFont }

                            Repeater {
                                model: heatmapFocus.months
                                delegate: PlainPlasmaLabel {
                                    required property var modelData
                                    readonly property real start: modelData.column * (heatmapGrid.cellWidth + heatmapGrid.cellSpacing)
                                    width: modelData.columns * (heatmapGrid.cellWidth + heatmapGrid.cellSpacing) - heatmapGrid.cellSpacing
                                    x: LayoutMirroring.enabled ? heatmapFocus.width - start - width : start
                                    height: heatmapFontMetrics.height
                                    visible: implicitWidth <= width
                                    text: Qt.locale().standaloneMonthName(modelData.month, Locale.ShortFormat)
                                    font: Kirigami.Theme.smallFont
                                    opacity: view.applet.secondaryTextOpacity
                                    horizontalAlignment: Text.AlignLeft
                                    Accessible.ignored: true
                                }
                            }

                            Grid {
                                id: heatmapGrid
                                y: heatmapFocus.monthHeaderHeight

                                readonly property real cellSpacing: Math.max(1, Math.round(Kirigami.Units.smallSpacing / 2))
                                readonly property real minimumCellSize: Kirigami.Units.gridUnit * 0.6
                                // Kept below the chart's weight: this is the secondary
                                // read, a weekday pattern, not the magnitude over time.
                                readonly property real maximumCellSize: Kirigami.Units.gridUnit * 1.15
                                readonly property int fittingColumns: Math.max(1, Math.floor(
                                    (width + cellSpacing) / (minimumCellSize + cellSpacing)))
                                readonly property int columnCount: Math.max(1, Math.min(
                                    fittingColumns, Math.ceil(
                                        (view.heatmapDays.length + view.heatmapTrailingSlots) / 7)))
                                readonly property real availableCellWidth: Math.max(minimumCellSize,
                                    (width - cellSpacing * (columnCount - 1)) / columnCount)
                                readonly property real cellHeight: Math.max(minimumCellSize, Math.min(
                                    maximumCellSize, availableCellWidth))
                                readonly property real cellWidth: cellHeight
                                readonly property var cells: CostChart.spendHeatmapCells(
                                    view.heatmapDays, columnCount * 7, view.heatmapTrailingSlots)

                                width: parent.width
                                rows: 7
                                flow: Grid.TopToBottom
                                columnSpacing: cellSpacing
                                rowSpacing: cellSpacing

                                Repeater {
                                    model: heatmapGrid.cells

                                    delegate: Rectangle {
                                        id: heatmapCell

                                        required property var modelData
                                        required property int index
                                        objectName: measured ? "activityDay-" + modelData.label : ""

                                        // Padding slots carry no day: they fill the
                                        // oldest corner of the block and stay out of
                                        // hover, the readout, and the reading order.
                                        readonly property bool measured: !!heatmapCell.modelData
                                        readonly property real fraction: heatmapCell.measured && view.heatmapMaximum > 0
                                            ? Math.max(0, Math.min(1,
                                                Number(heatmapCell.modelData.value) / view.heatmapMaximum))
                                            : 0

                                        Accessible.role: Accessible.Button
                                        Accessible.ignored: !heatmapCell.measured
                                        Accessible.onPressAction: if (heatmapCell.measured)
                                            heatmapFocus.selectDay(heatmapCell.modelData.label, Qt.OtherFocusReason)
                                        readonly property bool pinned: measured && modelData.label === view.selectedDay
                                        Accessible.selectable: heatmapCell.measured
                                        Accessible.selected: pinned
                                        // Days read like the chart's, in the locale's date format.
                                        readonly property string dayLabel: heatmapCell.measured
                                            ? historyChart.pointLabel(heatmapCell.modelData) : ""

                                        Accessible.name: heatmapCell.dayLabel
                                        Accessible.description: !heatmapCell.measured ? ""
                                            : view.applet.costHistoryShowsTokens ? view.applet.usageCountText(heatmapCell.modelData.value, "tokens")
                                            : heatmapCell.modelData.displayValue

                                        width: heatmapGrid.cellWidth
                                        height: heatmapGrid.cellHeight
                                        radius: Kirigami.Units.cornerRadius / 2
                                        // Padding has no measurement and must stay distinct
                                        // from a measured zero. Its outline never receives tint.
                                        color: heatmapCell.measured
                                            ? view.applet.withAlpha(Kirigami.Theme.textColor, 0.05) : "transparent"
                                        border.width: heatmapCell.measured ? 0 : 1
                                        border.color: view.applet.withAlpha(Kirigami.Theme.textColor, 0.12)

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: parent.radius
                                            visible: heatmapCell.measured
                                            color: view.heatmapTint(heatmapCell.fraction)
                                        }

                                        // The cell carries no border of its own and the
                                        // hover outline is a separate overlay. Fading a
                                        // border's own alpha does not work: Qt treats a
                                        // zero-alpha pen as invalid and paints the
                                        // rectangle with a zero-width border, so the fill
                                        // snaps out to the cell edge the moment the
                                        // highlight leaves. Grabbing the rendered pixels
                                        // confirmed it: between alpha 0 and 0.01 an edge
                                        // pixel jumped straight from the fill colour to
                                        // the background. Fading this overlay's opacity
                                        // blends that pixel instead, leaving the cell's
                                        // painted geometry untouched.
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: parent.radius
                                            color: "transparent"
                                            border.width: heatmapCell.pinned ? 2 : 1
                                            border.color: heatmapCell.pinned || heatmapFocus.activeFocus && heatmapFocus.hoveredDay.length === 0
                                                ? Kirigami.Theme.textColor
                                                : view.applet.withAlpha(Kirigami.Theme.textColor, 0.4)
                                            visible: heatmapCell.measured
                                            opacity: heatmapCell.pinned || heatmapCell.index === heatmapFocus.inspectedIndex ? 1 : 0

                                            Rectangle {
                                                anchors.fill: parent
                                                anchors.margins: 1
                                                radius: Math.max(0, parent.radius - 1)
                                                color: "transparent"
                                                border.width: 1
                                                border.color: Kirigami.Theme.backgroundColor
                                                visible: heatmapCell.pinned || heatmapFocus.activeFocus && heatmapFocus.hoveredDay.length === 0
                                            }

                                            Behavior on opacity {
                                                enabled: !heatmapFocus.activeFocus
                                                NumberAnimation {
                                                    duration: Kirigami.Units.shortDuration
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: heatmapMouse

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            acceptedButtons: Qt.LeftButton
                                            cursorShape: heatmapCell.measured ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: if (heatmapCell.measured)
                                                heatmapFocus.selectDay(heatmapCell.modelData.label, Qt.MouseFocusReason)
                                            onEntered: if (heatmapCell.measured)
                                                heatmapFocus.hoveredDay = heatmapCell.modelData.label
                                            onPositionChanged: if (heatmapCell.measured)
                                                heatmapFocus.hoveredDay = heatmapCell.modelData.label
                                            onExited: if (heatmapCell.measured
                                                && heatmapFocus.hoveredDay === heatmapCell.modelData.label)
                                                heatmapFocus.hoveredDay = ""
                                        }
                                    }
                                }
                            }
                        }
                    }
                    PlainPlasmaLabel {
                        id: heatmapReadout
                        objectName: "heatmapReadout"
                        Layout.fillWidth: true
                        Layout.preferredHeight: heatmapFontMetrics.height
                        text: heatmapFocus.readout.length > 0 ? heatmapFocus.readout : " "
                        opacity: heatmapFocus.readout.length > 0 ? view.applet.secondaryTextOpacity : 0
                        font: Qt.font(Object.assign({}, Kirigami.Theme.smallFont, { features: { "tnum": 1 } }))
                        elide: Text.ElideRight
                        Accessible.ignored: true
                    }
                    // The tint is the only magnitude cue: without a key the
                    // shades read as decoration. Each cell keeps its own
                    // accessible value, so the key stays out of the tree.
                    RowLayout {
                        objectName: "heatmapLegend"

                        spacing: heatmapGrid.cellSpacing
                        Accessible.ignored: true

                        PlainPlasmaLabel {
                            text: i18nc("Activity heatmap legend, shade of the lowest daily value", "Less")
                            font: Kirigami.Theme.smallFont
                            opacity: view.applet.secondaryTextOpacity
                            Accessible.ignored: true
                            Layout.rightMargin: Kirigami.Units.smallSpacing - heatmapGrid.cellSpacing
                        }

                        Repeater {
                            model: [0, 0.25, 0.5, 0.75, 1]

                            delegate: Rectangle {
                                required property var modelData

                                implicitWidth: Math.round(Kirigami.Units.gridUnit * 0.6)
                                implicitHeight: implicitWidth
                                radius: Kirigami.Units.cornerRadius / 2
                                color: view.applet.withAlpha(Kirigami.Theme.textColor, 0.05)
                                Accessible.ignored: true

                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: view.heatmapTint(parent.modelData)
                                }
                            }
                        }

                        PlainPlasmaLabel {
                            text: i18nc("Activity heatmap legend, shade of the highest daily value", "More")
                            font: Kirigami.Theme.smallFont
                            opacity: view.applet.secondaryTextOpacity
                            Accessible.ignored: true
                            Layout.leftMargin: Kirigami.Units.smallSpacing - heatmapGrid.cellSpacing
                        }
                    }


                }


            }
            Components.AnalysisAssistant {
                id: analysisAssistant
                answerExpanded: !view.historyAvailable
                applet: view.applet
                onAnswerExpandedChanged: if (answerExpanded)
                    Qt.callLater(function() { view.revealHistoryItem(analysisAssistant) })
            }
        }
    }

}
