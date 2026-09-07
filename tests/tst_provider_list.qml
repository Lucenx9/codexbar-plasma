import QtQuick
import QtTest
import "../contents/ui/config/ProviderList.js" as ProviderList

TestCase {
    name: "ProviderList"

    readonly property var roster: [
        {
            provider: "codex",
            displayName: "Codex",
            enabled: true
        },
        {
            provider: "claude",
            displayName: "Claude",
            enabled: false
        },
        {
            provider: "openrouter",
            displayName: "OpenRouter",
            enabled: true
        },
        {
            provider: "future-provider",
            displayName: "Future",
            enabled: false
        }
    ]

    function ids(items) {
        return items.map(item => item.provider).join(",");
    }

    function test_searchAndScopeComposeWithoutChangingRecordsOrOrder() {
        var before = JSON.stringify(roster);
        compare(ids(ProviderList.filteredProviders(roster, "", "all")), "codex,claude,openrouter,future-provider");
        compare(ids(ProviderList.filteredProviders(roster, "", "enabled")), "codex,openrouter");
        compare(ids(ProviderList.filteredProviders(roster, "", "disabled")), "claude,future-provider");
        compare(ids(ProviderList.filteredProviders(roster, "  COdEx  ", "enabled")), "codex");
        compare(ProviderList.filteredProviders(roster, "codex", "disabled").length, 0);
        compare(ids(ProviderList.filteredProviders(roster, "-provider", "all")), "future-provider");
        compare(ProviderList.filteredProviders(roster, "", "enabled")[0], roster[0]);
        compare(JSON.stringify(roster), before);
    }

    function test_malformedInputsAndUnknownScopeDegradeToAll() {
        for (var input of [null, undefined, "codex",
            {},
            12])
            compare(ProviderList.filteredProviders(input, "", "all").length, 0);
        var items = [null, [], "codex",
            {},
            {
                provider: "__proto__"
            },
            {
                provider: 5
            },
            roster[0],
            {
                provider: "example",
                displayName: {},
                enabled: "true"
            }
        ];
        compare(ids(ProviderList.filteredProviders(items, null, "unknown")), "codex,example");
        compare(ids(ProviderList.filteredProviders(items, {}, "enabled")), "codex");
        compare(ids(ProviderList.filteredProviders(items, "example", "disabled")), "example");
    }

    function test_searchAndRosterAreBounded() {
        var items = [];
        for (var i = 0; i < 300; i++)
            items.push({
                provider: "example-" + i,
                displayName: "x".repeat(300),
                enabled: true
            });
        compare(ProviderList.filteredProviders(items, "", "all").length, 256);
        compare(ProviderList.filteredProviders(items, "x".repeat(300), "all").length, 256);
        compare(ProviderList.filteredProviders(items, "example-299", "all").length, 0);
    }
}
