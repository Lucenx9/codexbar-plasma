import QtQuick
import QtTest
import "../contents/ui/ShareUsage.js" as ShareUsage
import "../contents/ui/CostResponse.js" as CostResponse
import "../contents/ui/PrivacyPresentation.js" as Privacy
import "../contents/ui/ProviderNormalizer.js" as Normalizer

TestCase {
    name: "ShareUsage"

    function cost(provider, tokens, value, currency) {
        return { provider: provider, historyDays: 30,
            totals: { tokens: tokens, cost: value, currency: currency },
            models: [{ label: "model", tokens: tokens, cost: value, currency: currency }] }
    }

    function test_separateCurrenciesAndUnknownValues() {
        var data = ShareUsage.snapshot([cost("codex", 100, 2, "USD"), cost("claude", 50, 3, "EUR"),
            cost("muse", 20, null, "USD"), cost("pi", null, 0, "USD")], 30, "2026-09-22T12:00:00Z", false)
        compare(data.tokens, 170)
        compare(data.currencies, [{currency: "EUR", cost: 3}, {currency: "USD", cost: 2}])
        verify(data.partial)
        compare(data.providers[2].cost, null)
        compare(data.providers[3].tokens, null)
        compare(data.providers[3].cost, 0)
        compare(data.models.length, 3)
        compare(ShareUsage.snapshot([cost("pi", null, null, "USD")], 30, "", false).tokens, null)
    }

    function test_allowlistAndDetachedSnapshot() {
        var input = cost("codex", 100, 1, "USD")
        input.account = "private@example.com"
        input.projects = [{path: "/home/private"}]
        input.models[0].label = "model private@example.com /home/private token=sk-abcdefghijklmnopqrstuvwxyz123456"
        input.raw = "secret"
        var data = ShareUsage.snapshot([input], 30, "2026-09-22", false)
        var serialized = JSON.stringify(data)
        verify(serialized.indexOf("private@example.com") === -1)
        verify(serialized.indexOf("/home/private") === -1)
        verify(serialized.indexOf("sk-abcdefghijklmnopqrstuvwxyz") === -1)
        verify(serialized.indexOf('"account"') === -1)
        verify(serialized.indexOf('"projects"') === -1)
        input.totals.tokens = 0
        input.models[0].tokens = 0
        compare(data.tokens, 100)
        compare(data.models[0].tokens, 100)
    }

    function test_embeddedAbsolutePathsDoNotEnterExportLabels() {
        var input = cost("codex", 100, 1, "USD")
        input.models[0].label = "model=/home/alice/private-project"
        var data = ShareUsage.snapshot([input], 30, "", false)
        verify(JSON.stringify(data).indexOf("/home/alice/private-project") === -1)
    }

    function test_malformedBoundsAndRanges() {
        compare(ShareUsage.snapshot(null, NaN, {}, false).providers.length, 0)
        var wrongRange = cost("codex", 10, 2, "USD")
        wrongRange.historyDays = 7
        var input = cost("claude", "10", Infinity, "bad")
        var data = ShareUsage.snapshot([null, [], wrongRange, input], 30, "invalid", false)
        compare(data.providers.length, 1)
        compare(data.tokens, null)
        compare(data.currencies.length, 0)
        compare(data.createdAt, "")
        var many = []
        for (var i = 0; i < 140; i++) many.push(cost("p" + i, i, 1, "USD"))
        data = ShareUsage.snapshot(many, 30, "", false)
        compare(data.providers.length, 8)
        compare(data.models.length, 6)
        verify(data.omittedProviders > 0)
        verify(data.omittedModels > 0)
        verify(data.partial)
        compare(data.models[0].tokens, 127)
    }

    function test_partialAndOverflow() {
        var input = cost("codex", 0, 0, "USD")
        verify(!ShareUsage.snapshot([input], 30, "", false).partial)
        verify(ShareUsage.snapshot([input], 30, "", true).partial)
        input.historyCoverageEstablished = false
        verify(ShareUsage.snapshot([input], 30, "", false).partial)
        input.historyCoverageEstablished = true
        input.trust = { incompleteRequests: 2 }
        input.totals.tokens = 1
        verify(ShareUsage.snapshot([input], 30, "", false).partial)
        input.totals.tokens = Number.MAX_SAFE_INTEGER
        compare(ShareUsage.snapshot([input, input], 30, "", false).tokens, null)
    }

    function test_tokenRankingPrecedesCostCap() {
        var models = []
        for (var i = 0; i < 8; i++)
            models.push({modelName: "private model " + i, cost: 8 - i, totalTokens: i + 1})
        models.push({modelName: "unpriced leader", totalTokens: 900})
        models.push({modelName: "unknown tokens", cost: 100})
        var response = CostResponse.response(JSON.stringify([{provider: "codex", historyDays: 30,
            totals: {totalCost: 136, totalTokens: 936},
            daily: [{date: "2026-09-22", modelBreakdowns: models}]}]), "", 30)
        var cost = response.costs.codex
        compare(cost.models.length, 6)
        compare(cost.models[0].label, "unknown tokens")
        compare(cost.tokenRanking.rows.length, 6)
        compare(cost.tokenRanking.rows[0].label, "unpriced leader")
        compare(cost.tokenRanking.omitted, 3)
        var shared = ShareUsage.snapshot([cost], 30, "", false)
        compare(shared.models[0].label, "unpriced leader")
        compare(shared.models[0].tokens, 900)
        compare(shared.models[0].cost, null)
        compare(shared.omittedModels, 3)
        verify(shared.partial)
        var privateCost = Privacy.cost(cost, true)
        compare(privateCost.tokenRanking.rows.length, 6)
        compare(privateCost.tokenRanking.rows[0].tokens, 900)
        compare(privateCost.tokenRanking.omitted, 3)
        verify(JSON.stringify(privateCost).indexOf("private model") === -1)
        verify(JSON.stringify(privateCost).indexOf("unpriced leader") === -1)
        // QML supplies anonymous localized labels after the privacy projection.
        privateCost.tokenRanking.rows.forEach(function(row, index) { row.label = "Model " + (index + 1) })
        compare(ShareUsage.snapshot([privateCost], 30, "", false).models[0].tokens, 900)
    }

    function test_hiddenModelRowsDoNotClaimIncompleteData() {
        var models = []
        for (var i = 0; i < 7; i++)
            models.push({modelName: "model " + i, cost: 1, totalTokens: 10})
        function normalizedCost(rows) {
            var response = CostResponse.response(JSON.stringify([{provider: "codex", historyDays: 30,
                totals: {totalCost: rows.length, totalTokens: rows.length * 10},
                daily: [{date: "2026-09-22", modelBreakdowns: rows}]}]), "", 30)
            return response.costs.codex
        }
        var complete = normalizedCost(models)
        compare(complete.tokenRanking.omitted, 1)
        compare(complete.tokenRanking.truncated, true)
        compare(complete.tokenRanking.sourceTruncated, false)
        var shared = ShareUsage.snapshot([complete], 30, "", false)
        compare(shared.omittedModels, 1)
        compare(shared.partial, false)
        compare(ShareUsage.snapshot([Privacy.cost(complete, true)], 30, "", false).partial, false)

        models[6].cost = null
        var unknownHiddenCost = normalizedCost(models)
        compare(unknownHiddenCost.tokenRanking.hasUnknownCost, true)
        compare(ShareUsage.snapshot([unknownHiddenCost], 30, "", false).partial, true)
        compare(ShareUsage.snapshot([Privacy.cost(unknownHiddenCost, true)], 30, "", false).partial, true)
        models[6].cost = 1

        // A source day exceeding the bounded scan genuinely loses model data.
        for (var j = 7; j < 129; j++)
            models.push({modelName: "model " + j, cost: 1, totalTokens: 10})
        var incomplete = normalizedCost(models)
        compare(incomplete.tokenRanking.sourceTruncated, true)
        compare(ShareUsage.snapshot([incomplete], 30, "", false).partial, true)
        compare(ShareUsage.snapshot([Privacy.cost(incomplete, true)], 30, "", false).partial, true)
    }

    function test_mixedKnownAndUnknownModelCostsStayPartial() {
        var days = [
            {date: "2026-09-21", modelBreakdowns: [{modelName: "model", totalTokens: 10}]},
            {date: "2026-09-22", modelBreakdowns: [{modelName: "model", cost: 2, totalTokens: 20}]}
        ]
        var ranking = Normalizer.normalizeCostModels(days, "USD", 30,
            "2026-09-22T12:00:00Z", true).tokenRanking
        compare(ranking.rows[0].cost, 2)
        compare(ranking.rows[0].tokens, 30)
        compare(ranking.hasUnknownCost, true)
        var input = cost("codex", 30, 2, "USD")
        input.tokenRanking = ranking
        compare(ShareUsage.snapshot([input], 30, "", false).partial, true)
        compare(ShareUsage.snapshot([Privacy.cost(input, true)], 30, "", false).partial, true)
    }

    function test_exhaustedModelDayScanStaysPartial() {
        var days = [{date: "2026-09-21", modelBreakdowns: [
            {modelName: "older model", cost: 2, totalTokens: 10}]}]
        for (var i = 0; i < Normalizer.maximumCostHistoryScanItems; i++)
            days.push({date: "2026-08-01", modelBreakdowns: []})
        var ranking = Normalizer.normalizeCostModels(days, "USD", 30,
            "2026-09-22T12:00:00Z", true).tokenRanking
        compare(ranking.rows.length, 0)
        compare(ranking.sourceTruncated, true)
        var input = cost("codex", 10, 2, "USD")
        input.tokenRanking = ranking
        compare(ShareUsage.snapshot([input], 30, "", false).partial, true)
        compare(ShareUsage.snapshot([Privacy.cost(input, true)], 30, "", false).partial, true)
    }

    function test_localPngUrl_data() {
        return [
            {tag: "local", url: "file:///tmp/a.png", valid: true},
            {tag: "encoded", url: "file:///tmp/a%20b.png", valid: true},
            {tag: "remote", url: "https://example.org/a.png", valid: false},
            {tag: "host", url: "file://example.org/a.png", valid: false},
            {tag: "relative", url: "a.png", valid: false},
            {tag: "format", url: "file:///tmp/a.jpg", valid: false},
            {tag: "query", url: "file:///tmp/a.png?x", valid: false},
            {tag: "type", url: {}, valid: false}
        ]
    }
    function test_localPngUrl(data) {
        compare(ShareUsage.localPngUrl(data.url), data.valid)
    }
}
