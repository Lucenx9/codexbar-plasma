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

    function test_normalizesBoundedProviderIDsForSharedConsumers() {
        compare(ProviderIdentity.normalizedProviderID("  GROQCLOUD  "), "groq")
        compare(ProviderIdentity.normalizedProviderID("constructor"), "")
        compare(ProviderIdentity.normalizedProviderID(42), "")
        compare(ProviderIdentity.normalizedProviderID("x".repeat(129)), "")
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

    function test_openRouterDashboardUsesTheCanonicalActivityUrl() {
        compare(ProviderIdentity.providerDashboardUrl("openrouter"),
            "https://openrouter.ai/activity")
    }

    function test_openRouterDocsResolveToTheCanonicalDocsPath() {
        // The docs table pins the canonical path, so the help link stays
        // under the versioned docs tree.
        compare(ProviderIdentity.providerDocsUrl("openrouter"),
            ProviderIdentity.documentationBaseUrl + "openrouter.md")
    }

    function test_brandColorsAreThreeChannelsInRange() {
        var channels = ProviderIdentity.providerBrandColorChannels("aiand")
        compare(channels.length, 3)
        for (var i = 0; i < channels.length; i++) {
            verify(channels[i] >= 0 && channels[i] <= 1)
        }
    }

    function test_official061RegistryProvidersHaveBundledMetadata() {
        // Official 0.61.0 additions, verified in emitted `config providers`
        // output; metadata mirrors the upstream v0.61.0 descriptors.
        var providers = ["coderabbit", "huggingface", "muse", "nous", "replicate"]
        for (var i = 0; i < providers.length; i++) {
            var key = providers[i]
            compare(ProviderIdentity.providerIconFileName(key), key + ".svg")
            var channels = ProviderIdentity.providerBrandColorChannels(key)
            compare(channels.length, 3)
            for (var channel = 0; channel < channels.length; channel++) {
                verify(channels[channel] >= 0 && channels[channel] <= 1)
            }
            verify(ProviderIdentity.providerDashboardUrl(key).indexOf("https://") === 0)
            verify(ProviderIdentity.providerDocsUrl(key).indexOf(
                ProviderIdentity.documentationBaseUrl + key + ".md") === 0)
        }
        compare(ProviderIdentity.providerStatusUrl("coderabbit"), "https://status.coderabbit.ai")
        compare(ProviderIdentity.providerStatusUrl("huggingface"), "https://status.huggingface.co")
        compare(ProviderIdentity.providerStatusUrl("muse"), "")
    }

    function test_official063PiProviderHasMinimalBundledMetadata() {
        // Official 0.63.0 addition, verified in emitted `config providers`
        // output. Only the icon and docs path are bundled: the local-only
        // Pi provider has no verifiable brand color or
        // dashboard/login/status source, so those degrade by design.
        compare(ProviderIdentity.providerIconFileName("pi"), "pi.svg")
        compare(ProviderIdentity.providerDocsUrl("pi"),
            ProviderIdentity.documentationBaseUrl + "pi.md")
        compare(ProviderIdentity.providerBrandColorChannels("pi").length, 0)
        compare(ProviderIdentity.providerDashboardUrl("pi"), "")
        compare(ProviderIdentity.providerLoginUrl("pi"), "")
        compare(ProviderIdentity.providerStatusUrl("pi"), "")
        compare(ProviderIdentity.providerCliArgument("pi"), "pi")
        compare(ProviderIdentity.resolveProviderKey("pi"), "pi")
    }

    function test_official0641RegistryProvidersHaveBundledMetadata() {
        // Official 0.64.0 additions, still present in 0.64.1 `config providers`
        // output. Upstream publishes a setup guide and a dashboard entry point
        // for each; none declares a brand color or a status page, so those
        // degrade by design rather than carrying an invented value.
        var added = {
            "helmcode": "https://cloud.helmcode.com/dashboard",
            "typesafe": "https://console.typesafe.ai/settings/billing",
            "v0": "https://v0.app/settings/billing"
        };
        for (var key in added) {
            compare(ProviderIdentity.providerIconFileName(key), key + ".svg");
            compare(ProviderIdentity.providerDocsUrl(key),
                ProviderIdentity.documentationBaseUrl + key + ".md");
            compare(ProviderIdentity.providerDashboardUrl(key), added[key]);
            compare(ProviderIdentity.providerBrandColorChannels(key).length, 0);
            compare(ProviderIdentity.providerStatusUrl(key), "");
            compare(ProviderIdentity.resolveProviderKey(key), key);
            compare(ProviderIdentity.providerCliArgument(key), key);
        }
        // Only v0 issues its own API key, so it is the only one of the three
        // with a login entry point to send the user to.
        compare(ProviderIdentity.providerLoginUrl("v0"), "https://v0.app/settings/keys");
        compare(ProviderIdentity.providerLoginUrl("helmcode"), "");
        compare(ProviderIdentity.providerLoginUrl("typesafe"), "");
    }

    function test_retiredCrofKeepsBundledMetadataForOlderCliReleases() {
        // 0.64.1 retired Crof, but an installed 0.63.0 still emits it. Dropping
        // the metadata would turn a named provider into the unknown fallback
        // for anyone who has not upgraded.
        compare(ProviderIdentity.providerIconFileName("crof"), "crof.svg");
        compare(ProviderIdentity.resolveProviderKey("crofai"), "crof");
    }

    function test_official061RegistryAliasesResolveCanonically() {
        compare(ProviderIdentity.resolveProviderKey("hf"), "huggingface")
        compare(ProviderIdentity.resolveProviderKey("hermes"), "nous")
        compare(ProviderIdentity.resolveProviderKey("muse-code"), "muse")
        compare(ProviderIdentity.resolveProviderKey("nous-portal"), "nous")
        compare(ProviderIdentity.resolveProviderKey("r8"), "replicate")
        compare(ProviderIdentity.providerDashboardUrl("nous-portal"),
            ProviderIdentity.providerDashboardUrl("nous"))
    }

    function test_iconFileNamesRefuseKeysThatCannotNameAnAsset() {
        compare(ProviderIdentity.providerIconFileName("codex"), "codex.svg")
        // The one provider whose asset name differs from its key.
        compare(ProviderIdentity.providerIconFileName("gemini-cli"), "gemini-white.png")
        compare(ProviderIdentity.providerIconFileName("../../etc/passwd"), "")
        // Dots pass the asset pattern, so only the explicit dotdot guard
        // refuses a parent traversal that stays inside the pattern.
        compare(ProviderIdentity.providerIconFileName("a..b"), "")
        compare(ProviderIdentity.providerIconFileName("__proto__"), "")
        compare(ProviderIdentity.providerIconFileName("bad\nprovider"), "")
    }

    function test_iconFileNamesRefuseInheritedAndOverlongKeys() {
        // providerMapKey bounds the key before the pattern check, so inherited
        // Object.prototype names that pass the pattern and overlong keys still
        // refuse to name an asset.
        compare(ProviderIdentity.providerIconFileName("constructor"), "")
        compare(ProviderIdentity.providerIconFileName("CONSTRUCTOR"), "")
        compare(ProviderIdentity.providerIconFileName("x".repeat(129)), "")
    }
}
