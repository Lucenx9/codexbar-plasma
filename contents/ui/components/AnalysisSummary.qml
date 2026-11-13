import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../UsageAnalysis.js" as Analysis
import "../CostPresentation.mjs" as Costs
import "../CostTrust.mjs" as Trust

GridLayout {
    id: summary
    required property var applet
    required property var costs
    readonly property var totals: Costs.spendTotals(costs)
    readonly property var trust: Trust.costTrustSummary(costs)
    readonly property var comparison: Analysis.comparison(costs, applet.costHistoryShowsTokens, applet.panelClockMs)
    readonly property string changeText: !comparison ? i18n("Unavailable")
        : comparison.changeMultiple !== undefined ? i18n("%1×", comparison.changeMultiple.toLocaleString(Qt.locale(), 'f', 1))
        : comparison.changePercent !== undefined ? i18n("%1%", (comparison.changePercent > 0 ? "+" : "")
            + comparison.changePercent.toLocaleString(Qt.locale(), 'f', 0)) : i18n("No baseline")
    Layout.fillWidth: true
    columns: width >= Kirigami.Units.gridUnit * 24 ? 3 : 1
    columnSpacing: Kirigami.Units.largeSpacing
    visible: totals !== null

    Repeater {
        model: [
            {label: i18n("Cost"), value: summary.totals && summary.totals.cost !== null
                ? applet.qualifiedCostValue(applet.amountString(summary.totals.cost, summary.totals.currency),
                    summary.trust ? summary.trust.valueMode : "plain") : i18n("Cost unavailable")},
            {label: i18n("Tokens"), value: summary.totals && summary.totals.tokens !== null
                ? applet.usageCountText(summary.totals.tokens, "tokens") : i18n("Tokens unavailable")},
            {label: i18n("Last 7 days vs previous 7"), value: summary.comparison && summary.comparison.estimated
                ? applet.qualifiedCostValue(summary.changeText, "estimated") : summary.changeText,
                help: i18n("Comparison excludes today and needs 14 complete days plus a scan from today.")}
        ]
        delegate: ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 1
            spacing: Kirigami.Units.smallSpacing
            PlainPlasmaLabel {
                text: modelData.label
                font: Kirigami.Theme.smallFont
                opacity: applet.secondaryTextOpacity
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
            PlainPlasmaLabel {
                id: summaryValue
                text: modelData.value
                font.weight: Font.DemiBold
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
                font.features: { "tnum": 1 }
                Layout.fillWidth: true
                elide: Text.ElideRight
                Accessible.description: modelData.help || ""
                HoverHandler { id: valueHover }
                PlainToolTip {
                    visible: valueHover.hovered && (summaryValue.truncated || (modelData.help || "").length > 0)
                    plainText: summaryValue.text + (modelData.help ? "\n" + modelData.help : "")
                }
            }
        }
    }
}
