import QtQuick
import QtTest
import "../contents/ui/UsageAnalysis.js" as Analysis
import "../contents/ui/ChartStack.mjs" as Chart

TestCase {
    name: "UsageAnalysis"
    readonly property double now: new Date(2026, 10, 13, 12).getTime()

    function snapshot(provider, currency, current, previous) {
        var daily = []
        for (var i = 0; i < 15; i++) {
            var d = new Date(2026, 10, 13 - i, 12)
            var label = "2026-" + (d.getMonth() + 1) + "-" + (d.getDate() < 10 ? "0" : "") + d.getDate()
            daily.push({label: label, cost: i < 8 ? current : previous,
                tokens: 100, currency: currency, models: [], incompleteRequests: 0})
        }
        return {provider: provider, currency: currency, historyCoverageEstablished: true,
            valueMode: "estimated", totals: {cost: 50, tokens: 1500, currency: currency},
            daily: daily, models: [{label: "model", cost: 50, tokens: 1500, currency: currency}]}
    }

    function test_filtersDoNotChangeSources() {
        var costs = [snapshot("codex", "USD", 2, 1), snapshot("claude", "EUR", 3, 2)]
        var original = JSON.stringify(costs)
        compare(Analysis.filterCosts(costs, "codex").length, 1)
        compare(Analysis.filterCosts(costs, "absent").length, 0)
        var day = Analysis.dayCosts(costs, "2026-11-12")
        compare(day[0].totals.cost, 2)
        compare(day[1].totals.currency, "EUR")
        compare(day[0].valueMode, "estimated")
        compare(JSON.stringify(costs), original)
    }

    function test_duplicateMissingAndZeroDays() {
        var cost = snapshot("codex", "USD", 0, 1)
        compare(Analysis.dayCosts([cost], "2026-11-12")[0].totals.cost, 0)
        compare(Analysis.dayCosts([cost], "2025-01-01")[0].totals.cost, null)
        cost.daily.push(cost.daily[1])
        compare(Analysis.dayCosts([cost], "2026-11-12")[0].totals.cost, null)
        compare(Analysis.modelRows([cost], "2026-11-12", false).rows.length, 0)
    }

    function test_comparisonRequiresCompleteCompatibleEvidence() {
        var usd = snapshot("codex", "USD", 2, 1)
        var eur = snapshot("claude", "EUR", 5, 1)
        compare(Analysis.comparison([usd, eur], false, now).changePercent, 100)
        compare(Analysis.comparison([usd, eur], true, now).changePercent, 0)
        usd.daily[1].incompleteRequests = 1
        compare(Analysis.comparison([usd], false, now), null)
        usd.daily[1].incompleteRequests = 0
        usd.daily.pop()
        compare(Analysis.comparison([usd], false, now), null)
        compare(Analysis.comparison([], false, now), null)
    }

    function test_unknownTotalsPartialAndOverflow() {
        var cost = snapshot("codex", "USD", 2, 1)
        cost.valueMode = "partial"
        compare(Analysis.comparison([cost], false, now), null)
        cost.valueMode = "plain"
        cost.daily.forEach(function(day) { day.cost = Number.MAX_VALUE })
        compare(Analysis.comparison([cost], false, now), null)
    }

    function test_stacksKeepCompatibleMoneyAndAllTokens() {
        var usd = snapshot("codex", "USD", 2, 1)
        var eur = snapshot("claude", "EUR", 5, 1)
        var points = Analysis.dailyPoints(null, [usd, eur], false)
        verify(points.length > 0)
        compare(points[0].segments.length, 1)
        compare(points[0].segments[0].provider, "codex")
        compare(points[0].segments[0].value, points[0].value)
        points = Analysis.dailyPoints(null, [usd, eur], true)
        compare(points[0].segments.length, 2)
        var segments = Chart.stackedBarSegments(points[0], 100, 100)
        compare(segments.length, 2)
        compare(segments[0].height, 50)
        compare(segments[1].baseline, 50)
        compare(segments[1].rounded, true)
    }

    function test_stackRejectsAmbiguousAndInvalidSplits() {
        var point = {value: 10, segments: [{provider: "codex", value: 9}]}
        compare(Chart.stackedBarSegments(point, 100, 100).length, 0)
        point.segments[0].value = "10"
        compare(Chart.stackedBarSegments(point, 100, 100).length, 0)
        point.segments[0].value = Infinity
        compare(Chart.stackedBarSegments(point, 100, 100).length, 0)
        compare(Chart.stackedBarSegments(null, 100, 100).length, 0)
        var cost = snapshot("codex", "USD", 2, 1)
        cost.daily.push(cost.daily[0])
        var points = Analysis.dailyPoints(null, [cost], false)
        var duplicate = points.filter(function(point) { return point.label === cost.daily[0].label })[0]
        compare(duplicate.segments.length, 0)
    }

    function test_modelsStayScopedAndBounded() {
        var cost = snapshot("codex", "USD", 2, 1)
        compare(Analysis.modelRows([cost], "2026-11-12", false).rows.length, 0)
        compare(Analysis.modelRows([cost], "", false).rows[0].label, "model")
        cost.modelsTruncated = true
        verify(Analysis.modelRows([cost], "", false).truncated)
        compare(Analysis.modelRows(null, "", false).rows.length, 0)
        cost.models = Array.from({length: 100}, function(_, i) { return {label: "model-" + i, cost: i} })
        var bounded = Analysis.modelRows([cost, cost], "", false)
        compare(bounded.rows.length, 128)
        verify(bounded.truncated)
        compare(bounded.rows[0].cost, 99)
    }
}
