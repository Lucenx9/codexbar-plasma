import QtQuick
import QtTest
import "../contents/ui/UsageAnalysis.js" as Analysis
import "../contents/ui/ChartLines.mjs" as Chart
import "../contents/ui/PrivacyPresentation.js" as Privacy

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

    function test_privacyPreservesWeeklyComparison_data() {
        return [{tag: "USD", currency: "USD"}, {tag: "EUR", currency: "EUR"}]
    }

    function test_privacyPreservesWeeklyComparison(data) {
        var cost = snapshot("codex", data.currency, 2, 1)
        cost.trust = {sourceKind: "listPrice"}
        var projected = Privacy.cost(cost, true)
        verify(projected.currency === undefined)
        var original = JSON.stringify(projected)
        compare(Analysis.comparison([projected], false, now), Analysis.comparison([cost], false, now))
        compare(Analysis.comparison([projected], true, now), Analysis.comparison([cost], true, now))
        var foreign = snapshot("claude", data.currency === "USD" ? "EUR" : "USD", 5, 1)
        compare(Analysis.comparison([projected, Privacy.cost(foreign, true)], false, now),
            Analysis.comparison([cost, foreign], false, now))
        compare(JSON.stringify(projected), original)
        projected.daily[1].incompleteRequests = 1
        compare(Analysis.comparison([projected], false, now), null)
        projected.daily[1].incompleteRequests = 0
        projected.totals.cost = null
        compare(Analysis.comparison([projected], false, now), null)
    }

    function test_subCentComparisonUsesUnroundedTotals() {
        var cost = snapshot("codex", "USD", 0.002, 0.001)
        var comparison = Analysis.comparison([cost], false, now)
        compare(comparison.changePercent, 100)
        fuzzyCompare(comparison.current, 0.014, 0.0000001)
        fuzzyCompare(comparison.previous, 0.007, 0.0000001)
        verify(comparison.estimated)
        var second = snapshot("claude", "USD", 0.001, 0.002)
        comparison = Analysis.comparison([cost, second], false, now)
        compare(comparison.changePercent, 0)
        fuzzyCompare(comparison.current, 0.021, 0.0000001)
        compare(comparison.providers, 2)
        cost.daily[1].incompleteRequests = 1
        compare(Analysis.comparison([cost, second], false, now), null)
    }

    function test_unknownTotalsPartialAndOverflow() {
        var cost = snapshot("codex", "USD", 2, 1)
        cost.valueMode = "partial"
        compare(Analysis.comparison([cost], false, now), null)
        cost.valueMode = "plain"
        cost.daily.forEach(function(day) { day.cost = Number.MAX_VALUE })
        compare(Analysis.comparison([cost], false, now), null)
    }

    function test_linesKeepCompatibleMoneyAndAllTokens() {
        var costs = [snapshot("codex", "USD", 2, 1), snapshot("claude", "EUR", 5, 1)]
        var points = Analysis.dailyPoints(null, costs, false)
        var lines = Analysis.providerLines(null, costs, points, false)
        compare(lines.length, 1)
        compare(lines[0].provider, "codex")
        compare(lines[0].points[0].value, points[0].value)
        lines = Analysis.providerLines(null, costs, points, true)
        compare(lines.length, 2)
        compare(Chart.domain(lines).maximum, 120)
        compare(Analysis.dailyPoints(null, costs, true)[0].value, 200)
    }

    function test_linesKeepMissingDuplicateAndZeroDaysDistinct() {
        var cost = snapshot("codex", "USD", 0, 1)
        cost.daily.push(cost.daily[0])
        cost.daily = cost.daily.filter(function(day) { return day.label !== "2026-11-11" })
        var original = JSON.stringify(cost)
        var points = Analysis.dailyPoints(null, [cost], false)
        var lines = Analysis.providerLines(null, [cost], points, false)
        var values = ({})
        lines[0].points.forEach(function(point) { values[point.label] = point.value })
        compare(values["2026-11-13"], null)
        compare(values["2026-11-12"], 0)
        compare(values["2026-11-11"], null)
        compare(points.filter(function(p) { return p.label === "2026-11-11" })[0].value, null)
        compare(JSON.stringify(cost), original)
        cost.daily[1].cost = null
        lines = Analysis.providerLines(null, [cost], points, false)
        compare(lines[0].points.filter(function(p) { return p.label === "2026-11-12" })[0].value, null)
    }

    function test_calendarAndPathsRejectBadDataAndRespectBounds() {
        var points = [{label: "2026-11-10", value: 0}, {label: "2026-11-12", value: 8},
            {label: "2026-11-13", value: 2}]
        var timeline = Chart.calendarPoints(points)
        compare(timeline.length, 4)
        compare(timeline[1].value, null)
        var paths = Chart.paths(timeline, {width: 100, height: 80, maximum: 8, inset: 4})
        compare(paths.length, 2)
        compare(paths[0].length, 1)
        compare(paths[0][0].y, 76)
        compare(paths[1].length, 2)
        compare(paths[1][0].y, 4)
        verify(paths[1][1].c1.y > paths[1][0].y)
        verify(paths[1][1].c2.y < paths[1][1].y)
        compare(Chart.paths(points, {width: 100, height: 80, maximum: 8, inset: 4}).length, 2)
        compare(Chart.calendarPoints([{label: "2026-02-30", value: 1}]).length, 0)
        compare(Chart.domain([{points: [{value: null}, {value: -2}, {value: Infinity}, {value: "9"}]}]).maximum, 0)
        compare(Chart.calendarPoints([{label: "2020-01-01", value: 1}, {label: "2026-11-13", value: 2}]).length, 365)
        var zero = Chart.paths([{label: "2026-11-13", value: 0}], {width: 100, height: 80, maximum: 0, inset: 4})
        compare(zero[0][0].x, 50)
        compare(zero[0][0].y, 76)
    }

    function test_lineScaleAddsReadableHeadroomWithoutOverflow() {
        for (var sample of [{value: 2.46, expected: 3}, {value: 103000, expected: 120000},
                {value: 0, expected: 0}, {value: Number.MAX_VALUE, expected: Number.MAX_VALUE},
                {value: Number.MIN_VALUE, expected: Number.MIN_VALUE}]) {
            compare(Chart.domain([{points: [{value: sample.value}]}]).maximum, sample.expected)
        }
    }

    function test_curvesPreserveTrendsWithoutInventingExtrema() {
        for (var values of [[1, 2, 4], [0, 10, 10, 2, 0], [9, 0, 8, 0, 9], [0, 0, 0], [0, 0.001, 10]]) {
            var points = values.map(function(value, index) {
                return {label: "2026-11-" + (10 + index), value: value}
            })
            var run = Chart.paths(points, {width: 300, height: 100, maximum: 12, inset: 4})[0]
            for (var i = 1; i < run.length; i++) {
                var start = run[i - 1]
                var end = run[i]
                for (var step = 0; step <= 100; step++) {
                    var t = step / 100
                    var u = 1 - t
                    var y = u*u*u*start.y + 3*u*u*t*end.c1.y + 3*u*t*t*end.c2.y + t*t*t*end.y
                    verify(y >= Math.min(start.y, end.y) - 1e-8)
                    verify(y <= Math.max(start.y, end.y) + 1e-8)
                }
            }
            if (values.length === 3 && values[0] === 1) {
                verify(run[1].c2.y > run[1].y)
                verify(run[2].c1.y < run[1].y)
                fuzzyCompare((run[1].y - run[1].c2.y) / (run[1].x - run[1].c2.x),
                    (run[2].c1.y - run[1].y) / (run[2].c1.x - run[1].x), 1e-8)
            }
        }
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
