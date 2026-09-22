import QtQuick
import QtTest
import "../contents/ui/ShareUsage.js" as ShareUsage

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
