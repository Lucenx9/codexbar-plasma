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

    function test_ordersProviderIDListsUsedByTheFallbackQueue() {
        compare(ProviderOrder.orderedItems(["codex", "claude", "gemini"], "claude,codex").join(","), "claude,codex,gemini");
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
