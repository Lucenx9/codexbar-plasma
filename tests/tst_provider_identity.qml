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
}
