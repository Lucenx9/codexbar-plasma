import QtQuick
import QtTest
import "../contents/ui/ProviderNormalizer.mjs" as Normalizer

TestCase {
    name: "CostModelIdentity"

    function test_summaryCurrencyIsSanitizedAndScoped_data() {
        return [
            { tag: "ordinary", currency: "EUR", expected: "EUR" },
            { tag: "whitespace", currency: "  EUR\n", expected: "EUR" },
            { tag: "missing", currency: undefined, expected: "USD" },
            { tag: "empty", currency: "", expected: "USD" },
            { tag: "blank", currency: "   ", expected: "" },
            { tag: "bounded", currency: "ABCDEFGHIJKLMNOP", expected: "ABCDEFGHIJKL" },
            { tag: "object", currency: {toString: null}, expected: "" },
            { tag: "array", currency: ["EUR"], expected: "" },
            { tag: "redacted", currency: "sk-synthetic12345", expected: "[redacted]" }
        ]
    }

    function test_summaryCurrencyIsSanitizedAndScoped(data) {
        var breakdowns = []
        for (var i = 0; i < 8; i++)
            breakdowns.push({modelName: "model-" + i, cost: i, totalTokens: 8 - i})
        var items = [{date: "2026-08-29", totalCost: 28, totalTokens: 36,
            modelBreakdowns: breakdowns}]
        var options = {days: 1, updatedAt: "2026-08-29", includeTokenRanking: true}
        var original = JSON.stringify(items)
        var daily = Normalizer.normalizeCostDaily(items, data.currency, options)
        var period = Normalizer.normalizeCostModels(items, data.currency, options)
        compare(period.rows.length, 6)
        compare(period.tokenRanking.rows.length, 6)
        compare(period.rows[0].label, "model-7")
        compare(period.tokenRanking.rows[0].label, "model-0")
        var rows = daily[0].models.concat(period.rows, period.tokenRanking.rows)
        for (var row = 0; row < rows.length; row++)
            compare(rows[row].currency, data.expected)
        var refreshed = Normalizer.normalizeCostModels(items, "GBP", options)
        compare(refreshed.rows[0].currency, "GBP")
        compare(period.rows[0].currency, data.expected)
        compare(JSON.stringify(items), original)
    }

    function test_displayLabelsDoNotMergeDistinctModels_data() {
        var prefix = "synthetic-model-" + new Array(121).join("x")
        var cases = [
            { tag: "truncated", names: [prefix + "-a", prefix + "-b"], count: 2 },
            { tag: "whitespace", names: ["synthetic  model", "synthetic model"], count: 2 },
            { tag: "redacted", names: ["token=synthetic-model-a", "token=synthetic-model-b"], count: 2 },
            { tag: "ordinary", names: ["synthetic-a", "synthetic-b"], count: 2 },
            { tag: "identical", names: ["synthetic-a", "synthetic-a"], count: 1 }
        ]
        var result = []
        for (var i = 0; i < cases.length; i++) {
            result.push({ tag: "daily-" + cases[i].tag,
                names: cases[i].names, count: cases[i].count, daily: true })
            result.push({ tag: "period-" + cases[i].tag,
                names: cases[i].names, count: cases[i].count, daily: false })
        }
        return result
    }

    function test_repeatedLabelsDoNotReuseAmountsAcrossDaysOrRefreshes() {
        var items = [
            { date: "2026-08-28", totalCost: 4,
                modelBreakdowns: [{ modelName: "shared", cost: 4, incompleteRequestCount: 2 }] },
            { date: "2026-08-29", totalCost: 5,
                modelBreakdowns: [{ modelName: "shared", cost: 5, totalTokens: 50 }] }
        ]
        var options = { days: 2, updatedAt: "2026-08-29" }
        var original = JSON.stringify(items)
        var daily = Normalizer.normalizeCostDaily(items, "EUR", options)
        compare(daily[0].models[0], { label: "shared", cost: 4, tokens: null,
            incompleteRequests: 2, currency: "EUR" })
        compare(daily[1].models[0], { label: "shared", cost: 5, tokens: 50,
            incompleteRequests: 0, currency: "EUR" })
        compare(JSON.stringify(items), original)
        items[0].modelBreakdowns[0].cost = 9
        var refreshed = Normalizer.normalizeCostDaily(items, "USD", options)
        compare(refreshed[0].models[0].cost, 9)
        compare(refreshed[0].models[0].currency, "USD")
        compare(daily[0].models[0].cost, 4)
        compare(daily[0].models[0].currency, "EUR")
        refreshed[0].models[0].label = "changed"
        compare(refreshed[1].models[0].label, "shared")
        compare(daily[0].models[0].label, "shared")
    }

    function test_displayLabelsDoNotMergeDistinctModels(data) {
        var items = [{
            date: "2026-09-11",
            totalCost: 3,
            totalTokens: 30,
            modelBreakdowns: [
                { modelName: data.names[0], cost: 1, totalTokens: 10 },
                { modelName: data.names[1], cost: 2, totalTokens: 20 }
            ]
        }]
        var original = JSON.stringify(items)
        var rows
        if (data.daily) {
            var daily = Normalizer.normalizeCostDaily(items, "EUR", { days: 1, updatedAt: "2026-09-11" })
            compare(daily.length, 1)
            compare(daily[0].cost, 3)
            compare(daily[0].tokens, 30)
            compare(daily[0].modelsTruncated, false)
            rows = daily[0].models
        } else {
            var period = Normalizer.normalizeCostModels(items, "EUR", { days: 1, updatedAt: "2026-09-11" })
            compare(period.truncated, false)
            rows = period.rows
        }
        compare(rows.length, data.count)
        compare(rows[0].cost, data.count === 1 ? 3 : 2)
        compare(rows[0].tokens, data.count === 1 ? 30 : 20)
        if (data.count === 2) {
            compare(rows[1].cost, 1)
            compare(rows[1].tokens, 10)
        }
        for (var i = 0; i < rows.length; i++) {
            compare(rows[i].currency, "EUR")
            verify(rows[i].label.length > 0 && rows[i].label.length <= 120)
            verify(!Object.prototype.hasOwnProperty.call(rows[i], "modelName"))
        }
        compare(JSON.stringify(items), original)
    }
}
