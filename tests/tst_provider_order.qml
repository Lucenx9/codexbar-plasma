import QtQuick
import QtTest
import "../contents/ui/ProviderOrder.js" as ProviderOrder

TestCase {
    name: "ProviderOrder"

    function test_configuredProvidersComeFirstAndNewProvidersAppend() {
        var providers = [
            {
                provider: "codex"
            },
            {
                provider: "claude"
            },
            {
                provider: "gemini"
            }
        ];

        var ordered = ProviderOrder.orderedItems(providers, "claude,codex");

        compare(ordered.map(function (item) {
            return item.provider;
        }).join(","), "claude,codex,gemini");
    }

    function test_settingsGroupsPutEnabledProvidersFirstInPopupOrder() {
        var providers = [
            {
                provider: "openrouter",
                displayName: "OpenRouter",
                enabled: false
            },
            {
                provider: "codex",
                displayName: "Codex",
                enabled: true
            },
            {
                provider: "anthropic",
                displayName: "Anthropic",
                enabled: false
            },
            {
                provider: "antigravity",
                displayName: "Antigravity",
                enabled: true
            }
        ];

        var groups = ProviderOrder.settingsGroups(providers, "antigravity,codex");

        compare(groups.enabled.map(function (item) {
            return item.provider;
        }).join(","), "antigravity,codex");
        compare(groups.disabled.map(function (item) {
            return item.provider;
        }).join(","), "anthropic,openrouter");
    }

    function test_settingsGroupsRejectMalformedItemsAndResolveAliases() {
        var providers = [
            null,
            [],
            "codex",
            {
                provider: "constructor",
                enabled: false
            },
            {
                provider: "gemini",
                enabled: false
            },
            {
                provider: "groqcloud",
                enabled: true
            },
            {
                provider: "codex",
                enabled: true
            }
        ];

        var groups = ProviderOrder.settingsGroups(providers, "groq,codex");

        compare(groups.enabled.map(function (item) {
            return item.provider;
        }).join(","), "groqcloud,codex");
        compare(groups.disabled.map(function (item) {
            return item.provider;
        }).join(","), "gemini");
    }

    function test_settingsGroupsBoundsTheCombinedRoster() {
        var providers = [];
        for (var i = 0; i < 300; i++) {
            providers.push({
                provider: "provider-" + i,
                enabled: i % 2 === 0
            });
        }

        var groups = ProviderOrder.settingsGroups(providers, "provider-12");

        compare(groups.enabled.length + groups.disabled.length,
            ProviderOrder.maximumProviderItems);
        compare(groups.enabled[0].provider, "provider-12");
    }

    function test_moveReturnsTheCompleteCanonicalOrder() {
        var providers = [
            {
                provider: "codex"
            },
            {
                provider: "claude"
            },
            {
                provider: "alibaba-coding-plan"
            }
        ];

        compare(ProviderOrder.movedOrder(providers, "claude,codex", 1, -1), "codex,claude,alibaba");
        compare(ProviderOrder.movedOrder(providers, "claude,codex", 0, -1), "claude,codex,alibaba");
    }

    function test_moveKeepsAbsentProvidersInThePersistedOrder() {
        // The Display page moves providers within the enabled roster only, but
        // the persisted preference must remember disabled providers so they
        // return to their configured position once re-enabled.
        var providers = [
            {
                provider: "codex"
            },
            {
                provider: "gemini"
            }
        ];

        compare(ProviderOrder.movedOrder(providers, "claude,codex,gemini", 1, -1),
            "claude,gemini,codex");
        compare(ProviderOrder.movedOrder(providers, "claude,codex,gemini", 0, 1),
            "claude,gemini,codex");
        compare(ProviderOrder.movedOrder(providers, "claude,codex,gemini", 0, -1),
            "claude,codex,gemini");
        compare(ProviderOrder.movedOrder(providers, "codex,claude,gemini", 1, -1),
            "gemini,claude,codex");
        compare(ProviderOrder.movedOrder(providers, "codex,claude,gemini", 0, 1),
            "gemini,claude,codex");
    }

    function test_moveBetweenDuplicateRosterEntriesKeepsEveryProvider() {
        // Duplicate roster entries share one persisted token, so a move whose
        // anchor is the same provider has no unambiguous target slot: it must
        // degrade to a no-op, never drop or teleport the provider.
        var providers = [
            {
                provider: "codex"
            },
            {
                provider: "codex"
            },
            {
                provider: "claude"
            }
        ];

        compare(ProviderOrder.movedOrder(providers, "", 0, 1), "codex,claude");
        compare(ProviderOrder.movedOrder(["codex", "claude", "codex"], "", 1, 1),
            "codex,claude");
        compare(ProviderOrder.movedOrder(["codex", "claude", "codex"], "", 1, -1),
            "codex,claude");
        compare(ProviderOrder.movedOrder(["groq", "claude", "groqcloud"], "", 1, 1),
            "groq,claude");
    }

    function test_moveAcrossMultipleVisibleSlotsPreservesDisabledSlots() {
        var providers = ["codex", "gemini", "openrouter"];
        var order = "codex,claude,gemini,kiro,openrouter";
        compare(ProviderOrder.movedOrder(providers, order, 0, 2),
            "gemini,claude,openrouter,kiro,codex");
        compare(ProviderOrder.movedOrder(providers, order, 2, -2),
            "openrouter,claude,codex,kiro,gemini");
        compare(ProviderOrder.movedOrder(providers, order, 1, 0), order);
    }

    function test_ordersProviderIDListsUsedByTheFallbackQueue() {
        compare(ProviderOrder.orderedItems(["codex", "claude", "gemini"], "claude,codex").join(","), "claude,codex,gemini");
    }

    function test_fullPersistedOrderReservesSpaceForLiveProviders() {
        var stale = [];
        for (var i = 0; i < ProviderOrder.maximumProviderItems; i++) {
            stale.push("stale-" + i);
        }
        var moved = ProviderOrder.movedOrder(["codex", "gemini"], stale.join(","), 1, -1).split(",");
        compare(moved.length, ProviderOrder.maximumProviderItems);
        compare(moved.slice(-2).join(","), "gemini,codex");
        compare(moved.slice(0, -2).join(","), stale.slice(0, -2).join(","));

        var configured = ["codex"].concat(stale.slice(0, -1));
        moved = ProviderOrder.movedOrder(["codex", "gemini"], configured.join(","), 1, -1).split(",");
        compare(moved.length, ProviderOrder.maximumProviderItems);
        compare(moved[0], "gemini");
        compare(moved[moved.length - 1], "codex");
        compare(moved.slice(1, -1).join(","), stale.slice(0, -2).join(","));
    }

    function test_rejectsUnsafeOrderTokensAndBoundsTheProviderList() {
        var providers = [];
        for (var i = 0; i < 300; i++) {
            providers.push({
                provider: "provider-" + i
            });
        }

        var ordered = ProviderOrder.orderedItems(providers, "constructor,__proto__,provider-12");

        compare(ordered.length, ProviderOrder.maximumProviderItems);
        compare(ordered[0].provider, "provider-12");
    }
}
