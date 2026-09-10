import QtQuick
import QtTest
import "../contents/ui/OverviewProviders.js" as OverviewProviders

TestCase {
    name: "OverviewProviders"

    function test_emptySelectionIsInactiveAndKeepsAutomaticProviders() {
        verify(!OverviewProviders.selectionActive(""));
        verify(!OverviewProviders.selectionActive("   "));
        verify(!OverviewProviders.selectionActive(null));
        verify(!OverviewProviders.selectionActive(undefined));

        compare(OverviewProviders.configuredProviderIDs("").length, 0);
        compare(OverviewProviders.resolvedProviderIDs(["codex", "claude"], "").join(","), "codex,claude");
        compare(OverviewProviders.resolvedProviderIDs(["codex", "claude"], "  ").join(","), "codex,claude");
        compare(OverviewProviders.resolvedProviderIDs(["codex", "claude"], null).join(","), "codex,claude");
    }

    function test_noneValueIsAnActiveEmptySelection() {
        verify(OverviewProviders.selectionActive(OverviewProviders.noneValue));
        compare(OverviewProviders.configuredProviderIDs(OverviewProviders.noneValue).length, 0);
        compare(OverviewProviders.resolvedProviderIDs(["codex"], OverviewProviders.noneValue).length, 0);
        verify(!OverviewProviders.isSelected([], "codex"));
    }

    function test_configuredProviderIDsNormalizeAliasesAndRejectJunk() {
        compare(OverviewProviders.configuredProviderIDs("groqcloud,Codex").join(","), "groq,codex");
        compare(OverviewProviders.configuredProviderIDs(" codex , ,claude, ").join(","), "codex,claude");
        compare(OverviewProviders.configuredProviderIDs("codex,codex,CODEX").join(","), "codex");
        compare(OverviewProviders.configuredProviderIDs("constructor,prototype").length, 0);
        compare(OverviewProviders.configuredProviderIDs(new Array(600).join("x")).length, 0);
        compare(OverviewProviders.configuredProviderIDs("codex,claude,gemini,cursor").join(","), "codex,claude,gemini");
    }

    function test_automaticSelectionUsesRosterOrderAndNormalizes() {
        compare(OverviewProviders.resolvedProviderIDs(["groqcloud", "codex", "claude", "cursor"], "").join(","), "groq,codex,claude");
        compare(OverviewProviders.resolvedProviderIDs(["codex", "codex", "claude"], "").join(","), "codex,claude");
        compare(OverviewProviders.resolvedProviderIDs([null, [], "codex",
            {}
        ], "").join(","), "codex");
        compare(OverviewProviders.resolvedProviderIDs(null, "").length, 0);
    }

    function test_isSelectedRecognizesAliasesAndMixedCase() {
        verify(OverviewProviders.isSelected(["groq"], "groqcloud"));
        verify(OverviewProviders.isSelected(["groq"], "GROQCLOUD"));
        verify(OverviewProviders.isSelected(["codex"], "Codex"));
        verify(!OverviewProviders.isSelected(["groq"], "codex"));
        verify(!OverviewProviders.isSelected(["groq"], ""));
        verify(!OverviewProviders.isSelected(null, "codex"));
    }

    function test_toggleFollowsRosterOrderAndKeepsAbsentSelection() {
        var roster = ["codex", "claude", "gemini"];

        var next = OverviewProviders.toggledSelection(roster, ["claude"], "gemini", true);
        compare(next.join(","), "claude,gemini");

        next = OverviewProviders.toggledSelection(roster, ["claude", "gemini"], "claude", false);
        compare(next.join(","), "gemini");

        // Roster order wins even when the stored selection lists another order.
        next = OverviewProviders.toggledSelection(roster, ["gemini", "codex"], "claude", true);
        compare(next.join(","), "codex,claude,gemini");

        // A selected provider missing from the roster survives a later toggle.
        next = OverviewProviders.toggledSelection(["codex"], ["codex", "opencode"], "codex", false);
        compare(next.join(","), "opencode");
    }

    function test_toggleNormalizesAliasesAndEnforcesTheVisibleLimit() {
        var next = OverviewProviders.toggledSelection(["groqcloud"], [], "groqcloud", true);
        compare(next.join(","), "groq");
        next = OverviewProviders.toggledSelection(["groq"], ["groq"], "GROQCLOUD", false);
        compare(next.join(","), "");
        // A stored raw spelling still toggles through its canonical ID.
        next = OverviewProviders.toggledSelection(["groqcloud"], ["groqcloud"], "groqcloud", false);
        compare(next.join(","), "");
        next = OverviewProviders.toggledSelection(["groqcloud", "codex"], ["groqcloud"], "codex", true);
        compare(next.join(","), "groq,codex");

        next = OverviewProviders.toggledSelection(["codex", "claude", "gemini", "cursor"], ["codex", "claude", "gemini"], "cursor", true);
        compare(next.join(","), "codex,claude,gemini");

        next = OverviewProviders.toggledSelection(["codex"], ["codex"], "", true);
        compare(next.join(","), "codex");
        next = OverviewProviders.toggledSelection(["codex"], ["codex"], new Array(600).join("x"), true);
        compare(next.join(","), "codex");
        next = OverviewProviders.toggledSelection(["codex"], ["codex"], "constructor", true);
        compare(next.join(","), "codex");
        next = OverviewProviders.toggledSelection(null, null, "codex", true);
        compare(next.join(","), "");
    }

    function test_selectionTextRoundTripsEmptyAsNone() {
        compare(OverviewProviders.selectionText(["codex", "claude"]), "codex,claude");
        compare(OverviewProviders.selectionText([]), OverviewProviders.noneValue);
        compare(OverviewProviders.selectionText(null), OverviewProviders.noneValue);
        compare(OverviewProviders.selectionText("codex"), OverviewProviders.noneValue);
    }

    function test_maximumMatchesTheOverviewLimit() {
        compare(OverviewProviders.maximumOverviewProviders, 3);
    }
}
