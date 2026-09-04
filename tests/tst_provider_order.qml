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
