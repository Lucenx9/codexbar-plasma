import QtQuick
import QtTest
import "../contents/ui/ProviderIdentity.js" as ProviderIdentity

TestCase {
    name: "ProviderIdentity"

    readonly property var aliases: ({
        "groqcloud": "groq",
        "ai&": "aiand"
    })

    function test_resolvesOnlyOwnAliases() {
        compare(ProviderIdentity.providerKey("groqcloud", aliases), "groq")
        compare(ProviderIdentity.providerKey("ai&", aliases), "aiand")
        compare(ProviderIdentity.providerKey("future-provider", aliases), "future-provider")
    }

    function test_rejectsPrototypeAndMalformedMapKeys() {
        compare(ProviderIdentity.providerKey("__proto__", aliases), "__proto__")
        compare(ProviderIdentity.providerKey("constructor", aliases), "constructor")
        compare(ProviderIdentity.providerMapKey("__proto__"), "")
        compare(ProviderIdentity.providerMapKey("constructor"), "")
        compare(ProviderIdentity.providerMapKey("toString"), "")
        compare(ProviderIdentity.providerMapKey("hasOwnProperty"), "")
        compare(ProviderIdentity.providerMapKey("bad\nprovider"), "")
    }

    function test_preservesValidFutureProviderKeys() {
        compare(ProviderIdentity.providerMapKey("future-provider.v2"), "future-provider.v2")
        compare(ProviderIdentity.providerMapKey("future/provider:v3"), "future/provider:v3")
    }

    function test_resolvesSharedAliasesBeforeEveryLookup() {
        compare(ProviderIdentity.resolveProviderKey("ai&"), "aiand")
        compare(ProviderIdentity.resolveProviderKey("AZURE-OPENAI"), "azureopenai")
        // Every table is keyed by the canonical key, so an alias must find the
        // same entry the canonical spelling does.
        compare(ProviderIdentity.providerDocsUrl("z.ai"), ProviderIdentity.providerDocsUrl("zai"))
        compare(ProviderIdentity.providerCliArgument("aoai"), "azure-openai")
        compare(ProviderIdentity.providerDashboardUrl("bob"),
            ProviderIdentity.providerDashboardUrl("ibmbob"))
    }

    function test_unknownProvidersDegradeInsteadOfBreaking() {
        compare(ProviderIdentity.providerDocsUrl("future-provider"), "")
        compare(ProviderIdentity.providerDashboardUrl("future-provider"), "")
        compare(ProviderIdentity.providerLoginUrl("future-provider"), "")
        compare(ProviderIdentity.providerStatusUrl("future-provider"), "")
        // No override means the CLI takes the canonical key unchanged.
        compare(ProviderIdentity.providerCliArgument("future-provider"), "future-provider")
        compare(ProviderIdentity.providerBrandColorChannels("future-provider").length, 0)
    }

    function test_documentationUrlsStayUnderTheOfficialDocsTree() {
        var url = ProviderIdentity.providerDocsUrl("openai")
        compare(url, ProviderIdentity.documentationBaseUrl + "openai.md")
        verify(url.indexOf("https://github.com/steipete/CodexBar/blob/main/docs/") === 0)
    }

    function test_brandColorsAreThreeChannelsInRange() {
        var channels = ProviderIdentity.providerBrandColorChannels("aiand")
        compare(channels.length, 3)
        for (var i = 0; i < channels.length; i++) {
            verify(channels[i] >= 0 && channels[i] <= 1)
        }
    }

    function test_iconFileNamesRefuseKeysThatCannotNameAnAsset() {
        compare(ProviderIdentity.providerIconFileName("codex"), "codex.svg")
        // The one provider whose asset name differs from its key.
        compare(ProviderIdentity.providerIconFileName("gemini-cli"), "gemini-white.png")
        compare(ProviderIdentity.providerIconFileName("../../etc/passwd"), "")
        compare(ProviderIdentity.providerIconFileName("__proto__"), "")
        compare(ProviderIdentity.providerIconFileName("bad\nprovider"), "")
    }
}
