import QtQuick
import QtTest
import "../contents/ui/PanelProviders.js" as PanelProviders

TestCase {
    name: "PanelProviders"

    function ids(items) {
        return items.map(function (item) {
            return item.provider;
        }).join(",");
    }

    function test_emptySelectionIsInactiveAndKeepsEveryProvider() {
        verify(!PanelProviders.selectionActive(""));
        verify(!PanelProviders.selectionActive("   "));
        verify(!PanelProviders.selectionActive(null));
        verify(!PanelProviders.selectionActive(undefined));

        var providers = [{provider: "codex"}, {provider: "claude"}];
        compare(PanelProviders.filteredItems(providers, "").length, 2);
        compare(PanelProviders.filteredItems(providers, "  ").length, 2);
        compare(PanelProviders.filteredItems(providers, null).length, 2);
        compare(PanelProviders.filteredItems(providers, undefined).length, 2);
        compare(PanelProviders.configuredProviderIDs("").length, 0);
    }

    function test_noneValueIsAnActiveEmptySelection() {
        verify(PanelProviders.selectionActive(PanelProviders.noneValue));
        compare(PanelProviders.configuredProviderIDs(PanelProviders.noneValue).length, 0);
        compare(PanelProviders.filteredItems([{provider: "codex"}], PanelProviders.noneValue).length, 0);
    }

    function test_selectionFiltersItemsInRosterOrder() {
        var providers = [
            {provider: "codex"},
            {provider: "claude"},
            {provider: "gemini"}
        ];

        compare(ids(PanelProviders.filteredItems(providers, "claude,gemini")), "claude,gemini");
        // Stored order never reorders the roster; it only filters it.
        compare(ids(PanelProviders.filteredItems(providers, "gemini,claude")), "claude,gemini");
        // Unknown providers are ignored, not fabricated.
        compare(ids(PanelProviders.filteredItems(providers, "claude,unknown")), "claude");
        compare(PanelProviders.filteredItems(providers, "unknown").length, 0);
    }

    function test_configuredProviderIDsNormalizeAliasesAndRejectJunk() {
        compare(PanelProviders.configuredProviderIDs("groqcloud,Codex").join(","), "groq,codex");
        compare(PanelProviders.configuredProviderIDs(" codex , ,claude, ").join(","), "codex,claude");
        compare(PanelProviders.configuredProviderIDs("codex,codex,codex").join(","), "codex");
        compare(PanelProviders.configuredProviderIDs("constructor,prototype").length, 0);
        compare(PanelProviders.configuredProviderIDs(new Array(600).join("x")).length, 0);
    }

    function test_manualSelectionCapsVisibleProvidersInRosterOrder() {
        var providers = ["codex", "claude", "gemini", "cursor", "copilot"].map(function (id) {
            return {provider: id};
        });
        compare(ids(PanelProviders.filteredItems(providers, "copilot,cursor,gemini,claude,codex")),
            "codex,claude,gemini,cursor");
        compare(PanelProviders.filteredItems(providers, "").length, 5);
        compare(ids(PanelProviders.filteredItems(providers.slice(1), "codex,claude,gemini,cursor,copilot")),
            "claude,gemini,cursor,copilot");
    }

    function test_filterRejectsMalformedInput() {
        verify(PanelProviders.filteredItems(null, "codex").length === 0);
        compare(PanelProviders.filteredItems("codex", "codex").length, 0);
        var withJunk = [null, [], "codex", {provider: "constructor"}, {provider: "claude"}, {}];
        compare(ids(PanelProviders.filteredItems(withJunk, "claude,constructor")), "claude");
    }

    function test_selectionTextRoundTripsEmptyAsNone() {
        compare(PanelProviders.selectionText(["codex", "claude"]), "codex,claude");
        compare(PanelProviders.selectionText([]), PanelProviders.noneValue);
        compare(PanelProviders.selectionText(null), PanelProviders.noneValue);
        compare(PanelProviders.selectionText("codex"), PanelProviders.noneValue);
    }

    function test_maximumMatchesTheCompactMeterLimit() {
        verify(PanelProviders.maximumSelectableProviders >= 1);
    }
}
