import QtQuick
import QtTest
import "../contents/ui/config/ProviderSource.js" as Source

TestCase {
    name: "ProviderSource"

    function test_plansBoundedModesAndQuotesUnknownProviders() {
        var plan = Source.planWrite("/tmp/cli path'", "future'provider", "api")
        verify(plan.ok)
        verify(plan.commandLine.indexOf("config set-source --provider") >= 0)
        verify(plan.commandLine.indexOf("'future'\\''provider'") >= 0)
        for (var mode of Source.modes)
            verify(Source.planWrite("codexbar", "codex", mode).ok)
        for (var mode of ["", "API", "api; echo bad", null, {}, "future"])
            verify(!Source.planWrite("codexbar", "codex", mode).ok)
        for (var provider of ["", null, "constructor", "bad\nprovider", " codex"])
            verify(!Source.planWrite("codexbar", provider, "auto").ok)
        verify(!Source.planWrite(" ", "codex", "auto").ok)
    }

    function test_acceptsOnlyMatchingSourceWriteRecords() {
        verify(Source.resultMatches({provider: "azureopenai", enabled: false, source: "auto"},
            "azure-openai", "auto"))
        for (var mode of Source.modes) {
            verify(Source.resultMatches({provider: "future", enabled: false, source: mode}, "future", mode))
        }
        var invalid = [null, [], {}, {provider: "codex", source: "api"},
            {provider: "codex", source: "api", enabled: "true"},
            {provider: "claude", source: "api", enabled: true},
            {provider: "codex", source: "web", enabled: true},
            Object.create({provider: "codex", source: "api", enabled: true})]
        for (var payload of invalid)
            verify(!Source.resultMatches(payload, "codex", "api"))
    }
    function test_pendingFieldsAreProviderScopedAndOwnBooleans() {
        verify(Source.hasPendingFields({'codex::"key"': true}, "codex"))
        verify(!Source.hasPendingFields({'codex-other::"key"': true}, "codex"))
        verify(!Source.hasPendingFields({'codex::"key"': "true"}, "codex"))
        verify(!Source.hasPendingFields(Object.create({'codex::"key"': true}), "codex"))
        for (var pending of [null, [], "codex", {}])
            verify(!Source.hasPendingFields(pending, "codex"))
        verify(!Source.hasPendingFields({'constructor::"key"': true}, "constructor"))
    }

}
