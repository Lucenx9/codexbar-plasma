import QtQuick
import QtTest
import "../contents/ui/UsageAnalysis.js" as Analysis
import "../contents/ui/ModelComparison.js" as ModelComparison
import "../contents/ui/AnalysisAmounts.mjs" as Display
import "../contents/ui/ChartLines.mjs" as Chart
import "../contents/ui/CostResponse.mjs" as CostResponse
import "../contents/ui/CostTrust.mjs" as CostTrust
import "../contents/ui/PrivacyPresentation.js" as Privacy

TestCase {
    name: "UsageAnalysis"
    readonly property double now: new Date(2026, 10, 13, 12).getTime()

    function test_smallAmountsAndScalePrecision() {
        var format = {group: ".", decimal: ","}
        compare(Display.metricText(format, 0.003, "USD", false), "< $0,01")
        compare(Display.metricText(format, 0, "USD", false), "$0,00")
        compare(Display.metricText(format, "0.003", "USD", false), "-")
        compare(Display.metricText(format, 0.01, "EUR", false), "EUR 0,01")
        compare(Display.axisText(format, 0.005, {step: 0.0025, currency: "USD", showsTokens: false}), "$0,0050")
        compare(Display.axisText(format, 0.0025, {step: 0.0025, currency: "USD", showsTokens: false}), "$0,0025")
        compare(Display.axisText(format, 20000, {step: 10000, currency: "USD", showsTokens: false}), "$20.000")
        verify(Display.axisText(format, Number.MIN_VALUE, {step: Number.MIN_VALUE, currency: "USD", showsTokens: false}).indexOf("e-") > 0)
        compare(Display.axisText(format, 120000, {step: 60000, currency: "USD", showsTokens: true}), "120K")
        var cost = snapshot("codex", "USD", 0.003, 0.003)
        var points = Analysis.dailyPoints(format, [cost], false)
        compare(points[0].displayValue, "< $0,01")
        compare(Analysis.providerLines(format, [cost], points, false)[0].points[0].displayValue, "< $0,01")
    }

    function test_tokenAxisLabelsMatchTickPositions_data() {
        return [
            {tag: "one-token", peak: 1, labels: ["1,2", "0,6", "0"]},
            {tag: "thousands", peak: 22000, labels: ["25K", "12,5K", "0"]},
            {tag: "millions", peak: 2000000, labels: ["2,5M", "1,25M", "0"]}
        ]
    }

    function test_tokenAxisLabelsMatchTickPositions(data) {
        var maximum = Chart.domain([{points: [{value: data.peak}]}]).maximum
        var format = {group: ".", decimal: ","}
        var labels = [maximum, maximum / 2, 0].map(function(value) {
            return Display.axisText(format, value, {step: maximum / 2, showsTokens: true})
        })
        compare(labels, data.labels)
    }

    function test_legacySequenceRemainsInspectable() {
        var cost = snapshot("codex", "USD", 1, 1)
        cost.daily = [{label: "Mon", cost: 2, tokens: 20, currency: "USD"},
            {label: "Tue", cost: 3, tokens: 30, currency: "USD"}]
        var points = Analysis.dailyPoints(null, [cost], false)
        compare(points.length, 2)
        compare(Analysis.hasCalendarHistory(points), false)
        compare(points[0].label, "Mon")
        compare(points[0].displayValue, "$2.00")
        compare(Analysis.dayCosts([cost], "Tue")[0].totals.cost, 3)
        cost.daily.push({label: "2026-11-13", cost: 4, currency: "USD"})
        points = Analysis.dailyPoints(null, [cost], false)
        compare(points.length, 3)
        compare(Analysis.hasCalendarHistory(points), false)
        cost.daily = [{label: "2026-02-30", cost: 2, currency: "USD"}]
        compare(Analysis.dailyPoints(null, [cost], false).length, 0)
    }

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

    function test_recordedDayKeepsItsPricingAndExclusions() {
        var cost = snapshot("codex", "USD", 2, 1)
        cost.historyCoverageEstablished = false
        cost.valueMode = "partial"
        cost.trust = {sourceKind: "listPrice", incompleteRequests: 3}
        var observed = Analysis.dayCosts([cost], cost.daily[0].label)[0]
        verify(!CostTrust.incompleteHistory(observed))
        compare(observed.valueMode, "estimated")
        compare(observed.totals.cost, 2)
        cost.daily[0].incompleteRequests = 1
        compare(Analysis.dayCosts([cost], cost.daily[0].label)[0].valueMode, "partial")
        for (var tokens of [false, true]) {
            var points = Analysis.dailyPoints(null, [cost], tokens)
            compare(points.filter(point => point.partial).map(point => point.label), [cost.daily[0].label])
        }
        var missing = Analysis.dayCosts([cost], "2020-01-01")[0]
        compare(missing.totals.cost, null)
        verify(CostTrust.incompleteHistory(missing))
        verify(CostTrust.incompleteHistory(cost))
    }

    function test_completeHistoryCleanDayClearsPeriodExcludedRequests() {
        var cost = snapshot("codex", "USD", 10, 5)
        cost.historyCoverageEstablished = true
        cost.valueMode = "partial"
        cost.trust = {
            sourceKind: "vendor",
            coverage: {priced: 2, unpriced: 0, unmetered: 0, estimated: 0},
            incompleteRequests: 1
        }
        cost.daily[0].incompleteRequests = 0
        cost.daily[0].models = [{label: "gpt-5", cost: 10, tokens: 100, currency: "USD", incompleteRequests: 0}]
        cost.daily[1].incompleteRequests = 1
        cost.daily[1].models = [{label: "gpt-5", cost: 5, tokens: 100, currency: "USD", incompleteRequests: 1}]

        var cleanDay = Analysis.dayCosts([cost], cost.daily[0].label)[0]
        compare(cleanDay.trust.incompleteRequests, 0)
        compare(cleanDay.valueMode, "plain")
        var cleanComparison = ModelComparison.comparison([cost], cost.daily[0].label, false, false)
        compare(cleanComparison.incompleteCurrencies, [])
        compare(cleanComparison.rows.length, 1)
        compare(cleanComparison.rows[0].spendShare, 1)

        var excludedDay = Analysis.dayCosts([cost], cost.daily[1].label)[0]
        compare(excludedDay.trust.incompleteRequests, 1)
        compare(excludedDay.valueMode, "partial")
        var excludedComparison = ModelComparison.comparison([cost], cost.daily[1].label, false, false)
        compare(excludedComparison.incompleteCurrencies, ["USD"])
        compare(excludedComparison.rows[0].spendShare, null)
    }

    function test_excludedDayQualifiesAnotherProvidersMeasurement_data() {
        return [{tag: "excluded-only", tokens: null}, {tag: "tokens-recorded", tokens: 3}]
    }

    function test_excludedDayQualifiesAnotherProvidersMeasurement(data) {
        var date = "2026-11-13"
        var parsed = CostResponse.response(JSON.stringify([
            {provider: "codex", currencyCode: "EUR", updatedAt: date,
                historyCoverageIsEstablished: true, daily: [{date: date, totalTokens: data.tokens, incompleteRequestCount: 1}]},
            {provider: "claude", currencyCode: "EUR", updatedAt: date,
                daily: [{date: date, totalCost: 0, totalTokens: 7}]}
        ]), "", 1, 0)
        for (var privacy of [false, true]) {
            var excluded = Privacy.cost(parsed.costs.codex, privacy)
            var observed = Privacy.cost(parsed.costs.claude, privacy)
            compare(excluded.daily.length, data.tokens === null ? 0 : 1)
            for (var tokens of [false, true]) {
                compare(Analysis.dailyPoints(null, [excluded], tokens).length, tokens && data.tokens !== null ? 1 : 0)
                var point = Analysis.dailyPoints(null, [observed, excluded], tokens)[0]
                compare(point.value, tokens ? 7 + (data.tokens || 0) : 0)
                compare(point.partial, true)
            }
            var foreign = Object.assign({}, excluded, {totals: {currency: "USD"}})
            verify(!Analysis.dailyPoints(null, [observed, foreign], false)[0].partial)
            var malformed = Privacy.cost(Object.assign({}, parsed.costs.codex, {totals: {currency: "usd"}}), privacy)
            verify(!Analysis.dailyPoints(null, [observed, malformed], false)[0].partial)
            compare(Analysis.dailyPoints(null, [observed, malformed], true)[0].partial, true)
        }
    }

    function test_partialDayDependsOnTheSelectedMetric() {
        var first = snapshot("claude", "USD", 1, 0)
        var second = snapshot("codex", "USD", 0, 0)
        second.historyCoverageEstablished = false
        second.daily[0].cost = null
        second.daily[1].tokens = null
        function partialDates(tokens) {
            return Analysis.dailyPoints(null, [first, second], tokens)
                .filter(point => point.partial).map(point => point.label)
        }
        compare(partialDates(false), [second.daily[0].label])
        compare(partialDates(true), [second.daily[1].label])
        second.totals.cost = null
        second.daily.forEach(day => { day.cost = null })
        compare(partialDates(false), [])
        compare(partialDates(true), [second.daily[1].label])
        second.totals.tokens = null
        second.daily.forEach(day => { day.tokens = null })
        compare(partialDates(true), [])
        second.daily = []
        second.totals.tokens = 0
        compare(partialDates(true), [])
    }

    function test_ambiguityBeyondRenderedProviders_data() {
        return [{tag: "129-cost", count: 129, tokens: false, foreign: false, expected: null},
            {tag: "256-tokens", count: 256, tokens: true, foreign: false, expected: null},
            {tag: "129-foreign-cost", count: 129, tokens: false, foreign: true, expected: 128},
            {tag: "129-foreign-tokens", count: 129, tokens: true, foreign: true, expected: null},
            {tag: "outside-snapshot-bound", count: 257, tokens: false, foreign: false, expected: 256}]
    }

    function test_ambiguityBeyondRenderedProviders(data) {
        var costs = []
        for (var i = 0; i < data.count; i++) {
            var currency = data.foreign && i === data.count - 1 ? "EUR" : "USD"
            var day = {label: "2026-11-13", cost: 1, tokens: 1, currency: currency}
            costs.push({provider: "provider-" + i, currency: currency, totals: day, daily: [day]})
        }
        var last = costs[costs.length - 1]
        last.daily.push(last.daily[0])
        var original = JSON.stringify(costs)
        var points = Analysis.dailyPoints(null, costs, data.tokens)
        compare(points.length, 1)
        compare(points[0].value, data.expected)
        compare(Analysis.providerLines(null, costs, points, data.tokens).length, 128)
        compare(JSON.stringify(costs), original)
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

    function test_incompletePricingDoesNotHideCompleteTokenComparison_data() {
        return [
            {tag: "unpriced", field: "unpriced", privacy: false},
            {tag: "unmetered", field: "unmetered", privacy: false},
            {tag: "unpriced-private", field: "unpriced", privacy: true},
            {tag: "unmetered-private", field: "unmetered", privacy: true}
        ]
    }

    function test_incompletePricingDoesNotHideCompleteTokenComparison(data) {
        var cost = snapshot("codex", "USD", 2, 1)
        cost.trust = {sourceKind: "listPrice", incompleteRequests: 0,
            coverage: {priced: 1, unpriced: 0, unmetered: 0, estimated: 0}}
        cost.trust.coverage[data.field] = 1
        cost = Privacy.cost(cost, data.privacy)
        cost.valueMode = CostTrust.costTrustSummary([cost]).valueMode
        compare(cost.valueMode, "partial")
        compare(Analysis.comparison([cost], false, now), null)
        var result = Analysis.comparison([cost], true, now)
        verify(result !== null, "Incomplete prices must not hide fourteen complete days of tokens")
        compare(result.current, 700)
        compare(result.previous, 700)
        compare(result.changePercent, 0)

        cost.daily[1].incompleteRequests = 1
        compare(Analysis.comparison([cost], true, now), null)
        cost.daily[1].incompleteRequests = 0
        cost.daily[1].tokens = null
        compare(Analysis.comparison([cost], true, now), null)
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
        compare(points.filter(function(p) { return p.label === "2026-11-13" })[0].value, null)
        compare(values["2026-11-12"], 0)
        compare(values["2026-11-11"], null)
        compare(points.filter(function(p) { return p.label === "2026-11-11" })[0].value, null)
        compare(JSON.stringify(cost), original)
        cost.daily[1].cost = null
        lines = Analysis.providerLines(null, [cost], points, false)
        compare(lines[0].points.filter(function(p) { return p.label === "2026-11-12" })[0].value, null)
    }

    function test_dailyTotalsRejectProviderDuplicates_data() {
        return [
            {tag: "single-cost", tokens: false, second: false, foreign: false, duplicate: true, expected: null},
            {tag: "duplicate-overflow", tokens: false, second: false, foreign: false, duplicate: true, overflow: true, expected: null},
            {tag: "single-tokens", tokens: true, second: false, foreign: false, duplicate: true, expected: null},
            {tag: "shared-day-cost", tokens: false, second: true, foreign: false, duplicate: false, expected: 5},
            {tag: "shared-day-tokens", tokens: true, second: true, foreign: false, duplicate: false, expected: 50},
            {tag: "ambiguous-subtotal", tokens: false, second: true, foreign: false, duplicate: true, expected: null},
            {tag: "foreign-money", tokens: false, second: true, foreign: true, duplicate: true, expected: 2},
            {tag: "foreign-tokens", tokens: true, second: true, foreign: true, duplicate: true, expected: null}
        ]
    }

    function test_dailyTotalsRejectProviderDuplicates(data) {
        var first = snapshot("codex", "USD", 2, 1)
        first.daily = [{label: "2026-11-13", cost: 2, tokens: 20, currency: "USD"}]
        if (data.overflow) first.daily[0].cost = Number.MAX_VALUE
        var costs = [first]
        if (data.second) {
            var currency = data.foreign ? "EUR" : "USD"
            var second = snapshot("claude", currency, 3, 1)
            second.daily = [{label: "2026-11-13", cost: 3, tokens: 30, currency: currency}]
            costs.push(second)
        }
        if (data.duplicate) costs[costs.length - 1].daily.push(costs[costs.length - 1].daily[0])
        var original = JSON.stringify(costs)
        var points = Analysis.dailyPoints(null, costs, data.tokens)
        compare(points.length, 1)
        compare(points[0].value, data.expected)
        if (data.expected === null) verify(!points[0].displayValue)
        var lines = Analysis.providerLines(null, costs, points, data.tokens)
        if (data.duplicate && !data.second) {
            compare(lines[0].points[0].value, null)
            compare(Chart.domain(lines).maximum, 0)
        }
        if (data.second) compare(lines[0].points[0].value, data.tokens ? 20 : 2)
        compare(JSON.stringify(costs), original)
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

    function test_modelComparisonRanksProvidersWithinEachCurrency() {
        var usd = snapshot("codex", "USD", 2, 1)
        var other = snapshot("claude", "USD", 5, 1)
        other.models[0].cost = other.totals.cost = 150
        var eur = snapshot("pi", "EUR", 3, 1)
        var comparison = ModelComparison.comparison([usd, other, eur], "", false, false)
        compare(comparison.rows.map(row => row.provider), ["pi", "claude", "codex"])
        compare(comparison.rows.map(row => row.spendShare), [1, 0.75, 0.25])
        compare(comparison.incompleteCurrencies, [])
        other.daily[0].models = [{label: "daily", cost: 5, tokens: 10, currency: "USD"}]
        usd.daily[0].models = [{label: "daily", cost: 2, tokens: 30, currency: "USD"}]
        var dailyCost = ModelComparison.comparison([usd, other], "2026-11-13", false, false)
        compare(dailyCost.rows.map(row => row.provider), ["claude", "codex"])
        compare(dailyCost.rows.map(row => row.spendShare), [5 / 7, 2 / 7])
        compare(dailyCost.incompleteCurrencies, [])
        var day = ModelComparison.comparison([usd, other], "2026-11-13", true, false)
        compare(day.rows.map(row => row.provider), ["codex", "claude"])
        compare(day.rows.map(row => row.label), ["daily", "daily"])
        compare(day.rows.map(row => row.spendShare), [null, null])
    }

    function test_modelSharesRequireCompleteComparablePrices_data() {
        return ["unpriced", "truncated", "sourceTruncated", "mixedPricing", "partial",
            "missingTotal", "excluded", "historyCoverage", "unattributed", "currencyMismatch", "overflow", "zero", "error"].map(kind => ({tag: kind, kind: kind}))
    }

    function test_modelSharesRequireCompleteComparablePrices(data) {
        var codex = snapshot("codex", "USD", 2, 1)
        var pi = snapshot("pi", "USD", 1, 1)
        var claude = snapshot("claude", "EUR", 3, 1)
        switch (data.kind) {
        case "unpriced": pi.models[0].cost = null; break
        case "truncated": pi.modelsTruncated = true; break
        case "sourceTruncated": pi.tokenRanking = {sourceTruncated: true}; break
        case "mixedPricing": pi.tokenRanking = {hasUnknownCost: true}; break
        case "partial": pi.valueMode = "partial"; break
        case "missingTotal": pi.totals.cost = null; break
        case "excluded": pi.models[0].incompleteRequests = 1; break
        case "historyCoverage": pi.historyCoverageEstablished = false; break
        case "unattributed": pi.totals.cost += 0.01; break
        case "currencyMismatch": pi.models[0].currency = "EUR"; break
        case "overflow":
            codex.totals.cost = codex.models[0].cost = Number.MAX_VALUE
            pi.totals.cost = pi.models[0].cost = Number.MAX_VALUE
            break
        case "zero":
            codex.totals.cost = codex.models[0].cost = 0
            pi.totals.cost = pi.models[0].cost = 0
        }
        var comparison = ModelComparison.comparison([pi, claude, codex], "", false, data.kind === "error")
        compare(comparison.incompleteCurrencies,
            data.kind === "error" ? ["EUR", "USD"] : data.kind === "zero" ? [] : ["USD"])
        compare(comparison.rows.filter(row => row.provider === "codex")[0].spendShare, null)
        compare(comparison.rows.filter(row => row.provider === "pi")[0].spendShare, null)
        compare(comparison.rows.filter(row => row.provider === "claude")[0].spendShare, data.kind === "error" ? null : 1)
    }

    function test_missingPricesRetainProviderCurrencyAndPrivacyOnPin() {
        var valid = snapshot("claude", "EUR", 2, 1)
        var missing = {provider: "pi", currency: "EUR", totals: {}, models: [], daily: []}
        var period = ModelComparison.comparison([missing, valid], "", false, false)
        compare(period.incompleteCurrencies, ["EUR"])
        compare(period.rows[0].spendShare, null)
        valid.daily[0].models = [{label: "Private model", cost: 2, currency: "EUR"}]
        var privateCost = Privacy.cost(valid, true)
        privateCost.valueMode = "partial"
        var day = ModelComparison.comparison([privateCost], "2026-11-13", false, false)
        compare(day.incompleteCurrencies, ["EUR"])
        compare(day.rows[0].spendShare, null)
        verify(JSON.stringify(day).indexOf("Private model") === -1)
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

    function test_modelRankingPrecedesDisplayCap_data() {
        var cases = []
        for (var day of ["", "2026-11-13"]) {
            for (var privacy of [false, true]) {
                for (var tokens of [false, true]) {
                    for (var leaderCost of [null, 0, 0.01]) {
                        cases.push({tag: (day || "period") + "-privacy-" + privacy + "-tokens-" + tokens + "-cost-" + leaderCost,
                            day: day, privacy: privacy, tokens: tokens, leaderCost: leaderCost})
                    }
                }
            }
        }
        return cases
    }

    function test_modelRankingPrecedesDisplayCap(data) {
        var breakdowns = Array.from({length: 6}, function(_, i) {
            return {modelName: "priced-" + i, cost: 10 - i, totalTokens: 10 + i}
        })
        breakdowns.push({modelName: "token-leader", totalTokens: 1000, cost: data.leaderCost})
        var cost = CostResponse.normalizeSnapshot({provider: "codex", currencyCode: "USD",
            historyDays: 1, updatedAt: "2026-11-13T12:00:00Z",
            daily: [{date: "2026-11-13", totalCost: 45, totalTokens: 1075,
                modelBreakdowns: breakdowns}]}, 1)
        cost = Privacy.cost(cost, data.privacy)
        var original = JSON.stringify(cost)
        var models = Analysis.modelRows([cost], data.day, data.tokens)
        compare(models.rows.length, 6)
        verify(models.truncated)
        if (data.tokens) {
            compare(models.rows[0].tokens, 1000)
            compare(models.rows[0].cost, data.leaderCost)
        } else {
            compare(models.rows[0].cost, 10)
            compare(models.rows[0].tokens, 10)
        }
        if (data.privacy) verify(JSON.stringify(models).indexOf("token-leader") < 0)
        compare(JSON.stringify(cost), original)
    }

    function test_dayModelsNeverInheritPeriodTokenRanking() {
        var cost = snapshot("codex", "USD", 2, 1)
        cost.tokenRanking = {rows: [{label: "period-only", tokens: 1000}], truncated: true}
        cost.daily[0].models = [{label: "legacy-day", tokens: 20}]
        var selected = Analysis.modelRows([cost], "2026-11-13", true)
        compare(selected.rows.length, 1)
        compare(selected.rows[0].label, "legacy-day")
        compare(selected.truncated, false)
        cost.daily[0].tokenRanking = {rows: [], truncated: false}
        compare(Analysis.modelRows([cost], "2026-11-13", true).rows, [])
        compare(Analysis.modelRows([cost], "2026-11-12", true).rows, [])
        compare(Analysis.modelRows([cost], "2025-01-01", true).rows, [])
        cost.daily.push(cost.daily[0])
        compare(Analysis.modelRows([cost], "2026-11-13", true).rows, [])
    }
}
