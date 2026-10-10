import QtQuick
import "../CostPresentation.js" as CostPresentation
import "../ProviderNormalizer.js" as Normalizer

// Localized text for a provider's cost history: summary lines, breakdown,
// model and day rows. CostPresentation.js computes the values; this object
// words them in the catalog and dates CLI calendar keys in the locale.
QtObject {
    id: root

    required property var applet
    readonly property var numberFormat: applet.costNumberFormat
    readonly property bool showsTokens: applet.costHistoryShowsTokens

    function costSparklineSummary(points) {
        var summary = CostPresentation.sparklineSummary(root.numberFormat, points, root.showsTokens)
        if (!summary) {
            return ""
        }
        return i18n("%1: %2", summary.label.length > 0 ? root.costDayLabel(summary.label) : i18n("Latest"), summary.value)
    }

    function costBreakdownRows(tokenCost) {
        if (!tokenCost || !tokenCost.totals) {
            return []
        }

        var totals = tokenCost.totals
        return CostPresentation.breakdownRows([
            { label: i18n("Total tokens"), tokens: totals.tokens },
            { label: i18n("Input"), tokens: totals.inputTokens },
            { label: i18n("Output"), tokens: totals.outputTokens },
            { label: i18n("Cache read"), tokens: totals.cacheReadTokens },
            { label: i18n("Cache write"), tokens: totals.cacheCreationTokens }
        ], root.numberFormat)
    }

    function costModelRows(tokenCost) {
        return CostPresentation.modelRows(root.numberFormat, tokenCost, function(tokens) {
            return root.applet.usageCountText(tokens, "tokens")
        })
    }

    // Cost text dates a CLI calendar key like the chart does; other labels
    // stay as sent.
    function costDayLabel(label) {
        var date = Normalizer.calendarKeyLocalDate(label)
        return date ? date.toLocaleDateString(Qt.locale(), Locale.ShortFormat) : label
    }

    function costHistoryRows(tokenCost) {
        return CostPresentation.historyRows(root.numberFormat, tokenCost, root.showsTokens, i18n("Latest"))
            .map(function (row) {
                row.label = root.costDayLabel(row.label)
                return row
            })
    }

    function costPeakLine(points) {
        var peak = CostPresentation.peakPoint(CostPresentation.recentHistoryPoints(points), root.showsTokens)
        if (!peak) {
            return ""
        }
        return i18n("Peak: %1 - %2",
            peak.label.length > 0 ? root.costDayLabel(peak.label) : i18n("Latest"),
            root.showsTokens
                ? CostPresentation.tokenCountString(peak.magnitude, root.numberFormat)
                : CostPresentation.amountString(root.numberFormat, peak.magnitude, peak.currency))
    }

    // A calendar period longer than the chart supplies its whole-range average.
    function costAverageDailyLine(points, averageDaily) {
        var average = averageDaily ? averageDaily[root.showsTokens ? "tokens" : "cost"]
            : CostPresentation.averageDailyValue(points, root.showsTokens)
        if (!average) {
            return ""
        }
        return i18n("Average/day: %1", root.showsTokens
            ? CostPresentation.tokenCountString(average.value, root.numberFormat)
            : CostPresentation.amountString(root.numberFormat, average.value, average.currency))
    }

    function costPerMillionLine(tokenCost) {
        var perMillion = CostPresentation.perMillionAmount(tokenCost)
        if (!perMillion) {
            return ""
        }
        return i18n("Average: %1 / 1M tokens",
            CostPresentation.amountString(root.numberFormat, perMillion.value, perMillion.currency))
    }
}
