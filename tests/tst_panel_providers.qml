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

    function test_filterRejectsMalformedInput() {
        verify(PanelProviders.filteredItems(null, "codex").length === 0);
        compare(PanelProviders.filteredItems("codex", "codex").length, 0);
        var withJunk = [null, [], "codex", {provider: "constructor"}, {provider: "claude"}, {}];
        compare(ids(PanelProviders.filteredItems(withJunk, "claude,constructor")), "claude");
    }

    function test_toggleFollowsRosterOrderAndKeepsAbsentSelection() {
        var roster = ["codex", "claude", "gemini"];

        var next = PanelProviders.toggledSelection(roster, ["claude"], "gemini", true);
        compare(next.join(","), "claude,gemini");

        next = PanelProviders.toggledSelection(roster, ["claude", "gemini"], "claude", false);
        compare(next.join(","), "gemini");

        // Roster order wins even when the stored selection lists another order.
        next = PanelProviders.toggledSelection(roster, ["gemini", "codex"], "claude", true);
        compare(next.join(","), "codex,claude,gemini");

        // A selected provider missing from the roster survives a later toggle.
        next = PanelProviders.toggledSelection(["codex"], ["codex", "opencode"], "codex", false);
        compare(next.join(","), "opencode");
    }

    function test_toggleRejectsMalformedInput() {
        // A provider can only be toggled into the selection through a roster
        // entry, so an empty roster yields an empty selection.
        var next = PanelProviders.toggledSelection(null, null, "codex", true);
        compare(next.join(","), "");
        next = PanelProviders.toggledSelection(["codex"], "claude", "claude", false);
        compare(next.join(","), "");
        next = PanelProviders.toggledSelection(["codex"], ["codex"], "", true);
        compare(next.join(","), "codex");
        next = PanelProviders.toggledSelection(["codex"], ["codex"], new Array(600).join("x"), true);
        compare(next.join(","), "codex");
        next = PanelProviders.toggledSelection(["codex"], ["codex"], "constructor", true);
        compare(next.join(","), "codex");
    }

    function test_toggleNormalizesProviderIDs() {
        var next = PanelProviders.toggledSelection(["groqcloud"], [], "groqcloud", true);
        compare(next.join(","), "groq");
        next = PanelProviders.toggledSelection(["groq"], ["groq"], "GROQCLOUD", false);
        compare(next.join(","), "");
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
