import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../UsageAnalysis.js" as Analysis
import "../AnalysisAmounts.mjs" as AnalysisAmounts
import "../CostPresentation.mjs" as Costs
import "../CostTrust.mjs" as Trust
import "../CostCurrency.mjs" as CostCurrency

GridLayout {
    id: summary
    required property var applet
    required property var costs
    readonly property var totals: Costs.spendTotals(costs)
    readonly property var trust: Trust.costTrustSummary(costs)
    readonly property int excludedTokenRequests: Trust.incompleteTokenRequests(costs)
    readonly property var comparison: Analysis.comparison(costs, applet.costHistoryShowsTokens, applet.panelClockMs)
    readonly property string changeText: !comparison ? i18n("Unavailable")
        : comparison.changeMultiple !== undefined ? i18n("%1×", comparison.changeMultiple.toLocaleString(Qt.locale(), 'f', 1))
        : comparison.changePercent !== undefined ? i18n("%1%", (comparison.changePercent > 0 ? "+" : "")
            + comparison.changePercent.toLocaleString(Qt.locale(), 'f', 0)) : i18n("No baseline")
    Layout.fillWidth: true
    columns: width >= Math.max(Kirigami.Units.gridUnit * 24, summaryFont.height * 24) ? 3 : 1
    columnSpacing: Kirigami.Units.largeSpacing
    rowSpacing: Kirigami.Units.smallSpacing
    visible: totals !== null

    readonly property string comparisonHelp: i18n("Requires 14 complete days and a refresh today. Today is excluded.")
    readonly property var metrics: [
        {label: CostCurrency.spendHasMixedCostCurrencies(costs)
            ? i18n("Cost (%1 subtotal)", summary.totals ? summary.totals.currency : "") : i18n("Cost"),
            value: summary.totals && summary.totals.cost !== null
            ? applet.qualifiedCostValue(AnalysisAmounts.metricText(applet.costNumberFormat, summary.totals.cost, summary.totals.currency, false),
                summary.trust ? summary.trust.valueMode : "plain") : i18n("Cost unavailable")},
        {label: summary.excludedTokenRequests > 0
            ? i18n("%1 (partial)", i18n("Tokens")) : i18n("Tokens"),
            value: summary.totals && summary.totals.tokens !== null
            ? applet.usageCountText(summary.totals.tokens, "tokens") : i18n("Tokens unavailable"),
            help: summary.excludedTokenRequests > 0 ? i18np("%1 incomplete request excluded",
                "%1 incomplete requests excluded", summary.excludedTokenRequests) : ""},
        {label: i18n("Last 7 days vs previous 7"), value: summary.comparison && summary.comparison.estimated
            ? applet.qualifiedCostValue(summary.changeText, "estimated") : summary.changeText,
            help: summary.comparisonHelp}
    ]

    FontMetrics { id: summaryFont; font: Kirigami.Theme.defaultFont }

    Repeater {
        model: summary.metrics
        delegate: PlainPlasmaLabel {
            required property int index
            required property var modelData
            Layout.row: summary.columns === 3 ? 0 : index * 2
            Layout.column: summary.columns === 3 ? index : 0
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            text: modelData.label
            font: Kirigami.Theme.smallFont
            opacity: applet.secondaryTextOpacity
            wrapMode: Text.Wrap
            Accessible.ignored: true
        }
    }

    Repeater {
        model: summary.metrics
        delegate: PlainPlasmaLabel {
            id: summaryValue
            required property int index
            required property var modelData
            Layout.row: summary.columns === 3 ? 1 : index * 2 + 1
            Layout.column: summary.columns === 3 ? index : 0
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignBaseline
            text: modelData.value
            font.weight: Font.DemiBold
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
            font.features: { "tnum": 1 }
            wrapMode: modelData.help ? Text.WordWrap : Text.Wrap
            Accessible.name: i18n("%1: %2", modelData.label, text)
            Accessible.description: modelData.help || ""
            activeFocusOnTab: (modelData.help || "").length > 0
            HoverHandler { id: valueHover }
            PlainToolTip {
                objectName: "analysisSummaryValueToolTip"
                visible: (valueHover.hovered || summaryValue.activeFocus) && (modelData.help || "").length > 0
                plainText: summaryValue.text + "\n" + modelData.help
            }
        }
    }

    PlainPlasmaLabel {
        visible: summary.comparison === null
        Layout.row: summary.columns === 3 ? 2 : 6
        Layout.column: 0
        Layout.columnSpan: summary.columns
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        text: summary.comparisonHelp
        font: Kirigami.Theme.smallFont
        opacity: applet.secondaryTextOpacity
        wrapMode: Text.Wrap
    }
}
