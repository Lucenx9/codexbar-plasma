import QtQuick
import QtTest
import "../contents/ui/config/ProviderCapabilities.js" as Capabilities

TestCase {
    name: "ProviderCapabilities"

    function test_releasedVersionBoundaries_data() {
        return [{tag: "fireworks", provider: "fireworks", key: "fireworks", before: "0.53.9", at: "0.54.0"},
            {tag: "source", key: "source", before: "0.72.9", at: "0.73.0"},
            {tag: "commandcode-fal", provider: "commandcode", key: "commandCodeFal", before: "0.74.9", at: "0.75.0"},
            {tag: "munito", provider: "munito", key: "munito", before: "0.76.9", at: "0.77.0"},
            {tag: "soniox", provider: "soniox", key: "soniox", before: "0.79.9", at: "0.80.0"},
            {tag: "siliconflow", provider: "siliconflow", key: "siliconflowTripo", before: "0.83.9", at: "0.84.0"},
            {tag: "tripo", provider: "tripo", key: "siliconflowTripo", before: "0.83.9", at: "0.84.0"},
            {tag: "chatbox", provider: "chatbox", key: "abliterationChatbox", before: "0.80.9", at: "0.81.0"}]
    }
    function test_releasedVersionBoundaries(data) {
        verify(!Capabilities.versionCapabilities(data.before, 0)[data.key])
        verify(Capabilities.versionCapabilities(data.at, "0")[data.key])
        verify(!Capabilities.versionCapabilities(data.at, 1)[data.key])
        verify(!Capabilities.versionCapabilities(data.at + "-rc.1", 0)[data.key])
        verify(!Capabilities.versionCapabilities("unknown", 0)[data.key])
        if (data.provider) {
            verify(Capabilities.supportsApiKey(data.provider, null, Capabilities.versionCapabilities(data.at, 0)))
            verify(!Capabilities.supportsApiKey(data.provider, null, Capabilities.versionCapabilities(data.before, 0)))
        }
    }
    function test_legacyAllowlistRemainsAvailableBeforeVersionGatedWriters() {
        var capabilities = Capabilities.versionCapabilities("0.53.0", 0)
        var providers = [
        "aerostack", "linkup", "sailresearch", "sofya", "tavily", "aixy", "alibaba", "amp",
        "atlascloud", "azureopenai", "chutes", "codebuff", "clawrouter", "copilot", "crof",
        "crossmodel", "deepgram", "devpass", "doubao", "elevenlabs", "gitkraken", "groq", "ibmbob",
        "kimi", "kimik2", "kilo", "litellm", "llmman", "llmproxy", "minimax", "moonshot", "ollama",
        "openai", "openrouter", "poe", "v0", "venice", "vercel", "warp", "xkiro", "zai"
        ]
        for (var provider of providers) verify(Capabilities.supportsApiKey(provider, null, capabilities), provider)
        for (var unknown of ["constructor", "__proto__", "toString", "future-provider", ""]) {
            verify(!Capabilities.supportsApiKey(unknown, null, capabilities), unknown)
        }
    }

    function test_descriptorOwnedProvidersNeverUseFallback() {
        for (var version of ["0.53.0", "0.83.0"]) {
            var capabilities = Capabilities.versionCapabilities(version, 0)
            for (var provider of ["aiand", "clinepass", "deepinfra", "neuralwatt", "sub2api", "xai", "zenmux"]) {
                verify(!Capabilities.supportsApiKey(provider, null, capabilities), provider + " without descriptor")
                verify(!Capabilities.supportsApiKey(provider, {supportsConfigAPIKey: true}, capabilities), provider)
            }
        }
    }

    function test_providerAndAuthenticationRestrictions() {
        var old = Capabilities.versionCapabilities("0.53.0", 0)
        var current = Capabilities.versionCapabilities("0.84.0", 0)
        for (var provider of ["siliconflow", "tripo", "fireworks", "soniox", "chatbox", "abliteration", "munito", "commandcode", "fal"]) {
            verify(!Capabilities.supportsApiKey(provider, null, old), provider)
            verify(Capabilities.supportsApiKey(provider, null, current), provider)
            verify(!Capabilities.supportsApiKey(provider, {supportsConfigAPIKey: false}, current), provider)
        }
        verify(Capabilities.supportsApiKey("openai", null, old))
        verify(Capabilities.supportsApiKey("openai", {supportsConfigAPIKey: true}, old))
        verify(!Capabilities.supportsApiKey("openai", {}, current))
        verify(!Capabilities.supportsApiKey("future-provider", {supportsConfigAPIKey: true}, current))
        for (var malformed of [["fireworks"], ["soniox"], {}, null, true]) {
            verify(!Capabilities.supportsApiKey(malformed, null, current), String(malformed))
        }
    }
}
