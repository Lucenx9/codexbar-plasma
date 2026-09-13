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
        compare(OverviewProviders.configuredProviderIDs("codex,claude,gemini,cursor").join(","), "codex,claude,gemini,cursor");
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

    function test_absentSelectionsDoNotOccupyVisibleSlots() {
        var saved = ["claude", "gemini", "copilot"];
        var roster = ["codex", "groqcloud", "cursor", "openai"];
        var next = OverviewProviders.toggledSelection(roster, saved, "codex", true);
        compare(next.join(","), "codex,claude,gemini,copilot");
        next = OverviewProviders.toggledSelection(roster, next, "groq", true);
        next = OverviewProviders.toggledSelection(roster, next, "cursor", true);
        compare(next.join(","), "codex,groq,cursor,claude,gemini,copilot");
        compare(OverviewProviders.toggledSelection(roster, next, "openai", true), next);

        var restored = OverviewProviders.configuredProviderIDs(OverviewProviders.selectionText(next));
        compare(restored, next);
        compare(OverviewProviders.toggledSelection(roster, restored, "codex", false).join(","),
                "groq,cursor,claude,gemini,copilot");
    }

    function test_selectedCountUsesUniqueCanonicalRosterIDs() {
        compare(OverviewProviders.selectedProviderCount(["codex"], ["claude", "gemini", "copilot"]), 0);
        compare(OverviewProviders.selectedProviderCount(["groqcloud", "GROQ", "codex"], ["groq", "CODEX", "missing"]), 2);
        compare(OverviewProviders.selectedProviderCount([null, "constructor", "codex"], ["codex"]), 1);
        compare(OverviewProviders.selectedProviderCount(null, ["codex"]), 0);
        compare(OverviewProviders.selectedProviderCount(["codex"], null), 0);
    }

    function test_returningProvidersKeepTheirSavedSelection() {
        var saved = ["codex", "groq", "cursor", "claude", "gemini", "copilot"];
        var roster = ["claude", "gemini", "copilot", "codex", "groq", "cursor", "openai"];
        compare(OverviewProviders.selectedProviderCount(roster, saved), 6);
        compare(OverviewProviders.toggledSelection(roster, saved, "openai", true), saved);
        compare(OverviewProviders.toggledSelection(roster, saved, "claude", false).join(","),
                "gemini,copilot,codex,groq,cursor");
    }

    function test_maximumMatchesTheOverviewLimit() {
        compare(OverviewProviders.maximumOverviewProviders, 3);
    }

    function healthy(providerID, usedPercent) {
        return {
            provider: providerID,
            rows: [{ hasPercent: true, usedPercent: usedPercent }]
        };
    }

    function errorOnly(providerID) {
        return {
            provider: providerID,
            error: "codexbar exited with status 1",
            rows: [],
            credits: null,
            codexCreditLimit: null
        };
    }

    function providerIDs(items) {
        var result = [];
        for (var i = 0; i < items.length; i++) {
            result.push(items[i].provider);
        }
        return result.join(",");
    }

    function test_placeholderTextYieldsToTheCodexTokenCost() {
        compare(OverviewProviders.placeholderText({ provider: "gemini", placeholder: "No usage yet" }), "No usage yet");
        // Codex renders its token cost on the same line.
        compare(OverviewProviders.placeholderText({ provider: "codex", placeholder: "No usage yet", tokenCost: { total: 1 } }), "");
        compare(OverviewProviders.placeholderText({ provider: "codex", placeholder: "No usage yet" }), "No usage yet");
        compare(OverviewProviders.placeholderText({ provider: "gemini", placeholder: "" }), "");
        compare(OverviewProviders.placeholderText({ provider: "gemini" }), "");
        compare(OverviewProviders.placeholderText(null), "");
        compare(OverviewProviders.placeholderText(undefined), "");
    }

    function test_onlyAnEmptyFailedSnapshotIsErrorOnly() {
        verify(OverviewProviders.isErrorOnly(errorOnly("codex")));
        // Anything the provider still knows keeps its row.
        var survivors = [
            { rows: [{ hasPercent: true, usedPercent: 10 }] },
            { placeholder: "No usage yet" },
            { credits: { remaining: 0 } },
            { codexCreditLimit: 0 },
            { resetCredits: { amount: 1 } },
            { providerCost: { percentUsed: 0 } },
            { tokenCost: { total: 0 } }
        ];
        for (var i = 0; i < survivors.length; i++) {
            var item = survivors[i];
            item.provider = "codex";
            item.error = "status unavailable";
            if (item.credits === undefined) {
                item.credits = null;
            }
            if (item.codexCreditLimit === undefined) {
                item.codexCreditLimit = null;
            }
            verify(!OverviewProviders.isErrorOnly(item), "survivor " + i + " must keep its Overview row");
        }
        // A healthy provider without an error is never error-only.
        verify(!OverviewProviders.isErrorOnly(healthy("claude", 20)));
        verify(!OverviewProviders.isErrorOnly({ provider: "claude", error: "" }));
        verify(!OverviewProviders.isErrorOnly(null));
        verify(!OverviewProviders.isErrorOnly(undefined));
    }

    function test_automaticRowsTakeTheFirstEligibleProviders() {
        var roster = [errorOnly("codex"), healthy("claude", 10), healthy("gemini", 20),
            healthy("cursor", 30), healthy("groq", 40)];
        compare(providerIDs(OverviewProviders.visibleItems(roster, "")), "claude,gemini,cursor");
        compare(providerIDs(OverviewProviders.visibleItems(roster, "   ")), "claude,gemini,cursor");
        compare(providerIDs(OverviewProviders.visibleItems(roster, null)), "claude,gemini,cursor");
        compare(OverviewProviders.visibleItems([errorOnly("codex")], "").length, 0);
    }

    function test_storedSelectionKeepsRosterOrderAndTheVisibleLimit() {
        var roster = [healthy("codex", 10), healthy("claude", 20), healthy("gemini", 30),
            healthy("cursor", 40), healthy("groq", 50)];
        compare(providerIDs(OverviewProviders.visibleItems(roster, "gemini,codex")), "codex,gemini");
        // A selection wider than the visible limit is truncated in roster order.
        compare(providerIDs(OverviewProviders.visibleItems(roster, "groq,cursor,gemini,claude,codex")),
                "codex,claude,gemini");
        // Providers absent from the roster take no slot.
        compare(providerIDs(OverviewProviders.visibleItems(roster, "openai,groq")), "groq");
        compare(OverviewProviders.visibleItems(roster, OverviewProviders.noneValue).length, 0);
    }

    function test_selectionMatchesTheAliasesTheSettingsPageStores() {
        // The settings page normalizes groqcloud to groq before storing it, so
        // a roster still using the raw CLI spelling has to resolve the same way.
        var roster = [healthy("groqcloud", 10), healthy("Codex", 20)];
        compare(providerIDs(OverviewProviders.visibleItems(roster, "groq")), "groqcloud");
        compare(providerIDs(OverviewProviders.visibleItems(roster, "codex")), "Codex");
    }

    function test_unusableSelectionsAndRostersShowNoRows() {
        var roster = [healthy("codex", 10), healthy("claude", 20)];
        compare(OverviewProviders.visibleItems(roster, "constructor,prototype").length, 0);
        compare(OverviewProviders.visibleItems(roster, "__proto__").length, 0);
        compare(OverviewProviders.visibleItems(roster, ",,, ,").length, 0);
        compare(OverviewProviders.visibleItems(null, "").length, 0);
        compare(OverviewProviders.visibleItems(undefined, "codex").length, 0);
        compare(OverviewProviders.visibleItems("codex", "codex").length, 0);
    }

    function test_unusableRosterEntriesTakeNoSlot() {
        var roster = [null, undefined, "codex", [], healthy("claude", 20), { provider: "gemini" }];
        compare(providerIDs(OverviewProviders.visibleItems(roster, "")), "claude,gemini");
        compare(providerIDs(OverviewProviders.visibleItems(roster, "claude")), "claude");
    }
}
