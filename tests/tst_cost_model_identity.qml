import QtQuick
import QtTest
import "../contents/ui/ProviderNormalizer.js" as Normalizer

TestCase {
    name: "CostModelIdentity"

    function test_displayLabelsDoNotMergeDistinctModels_data() {
        var prefix = "synthetic-model-" + new Array(121).join("x")
        var cases = [
            { tag: "truncated", names: [prefix + "-a", prefix + "-b"], count: 2 },
            { tag: "whitespace", names: ["synthetic  model", "synthetic model"], count: 2 },
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
            var daily = Normalizer.normalizeCostDaily(items, "EUR", 1, "2026-09-11")
            compare(daily.length, 1)
            compare(daily[0].cost, 3)
            compare(daily[0].tokens, 30)
            compare(daily[0].modelsTruncated, false)
            rows = daily[0].models
        } else {
            var period = Normalizer.normalizeCostModels(items, "EUR", 1, "2026-09-11")
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
