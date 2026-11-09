import QtQuick
import QtTest
import "../contents/ui/config/ProviderSource.js" as Source

TestCase {
    name: "ProviderSource"

    function test_savedSourcesKeepOnlyKnownModesAndOwnIdentifiers() {
        var payload = {providers: [{id: "codex", source: "api", apiKey: "REDACTED"},
            {id: "claude"}, {id: "future", source: "unknown"}, {id: "bad", source: null},
            {id: "constructor", source: "api"}, Object.create({id: "inherited", source: "api"})]};
        var result = Source.savedSources(payload);
        compare(Source.savedMode(result, "codex"), "api");
        compare(Source.savedMode(result, "claude"), "auto");
        compare(Source.savedMode(result, "missing"), "");
        compare(Source.savedMode(result, "future"), "");
        compare(Source.savedMode(result, "bad"), "");
        compare(Source.savedMode(result, "inherited"), "");
        verify(JSON.stringify(result).indexOf("apiKey") < 0);
        compare(payload.providers[0].apiKey, "REDACTED");
        var duplicates = Source.savedSources({providers: [{id: "azureopenai", source: "api"},
            {id: "azure-openai", source: "auto"}]});
        compare(Source.savedMode(duplicates, "azureopenai"), "api");
        compare(Source.savedMode(duplicates, "azure-openai"), "auto");
        var reversed = Source.savedSources({providers: [{id: "azure-openai", source: "auto"},
            {id: "azureopenai", source: "api"}]});
        compare(Source.savedMode(reversed, "azureopenai"), "api");
        compare(Source.savedMode(Source.withSavedMode(reversed, "azureopenai", "cli"), "azure-openai"), "auto");
        var ambiguous = Source.savedSources({providers: [{id: "codex", source: "api"},
            {id: "codex", source: "cli"}]});
        compare(Source.savedMode(ambiguous, "codex"), "");
        for (var invalid of [null, [], {}, {providers: {}}, {providers: new Array(257)},
                Object.create({providers: []})]) compare(Source.savedSources(invalid), null);
        var updated = Source.withSavedMode(result, "codex", "cli");
        compare(Source.savedMode(updated, "codex"), "cli");
        compare(Source.savedMode(result, "codex"), "api");
    }

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
}
