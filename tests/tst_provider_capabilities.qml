import QtQuick
import QtTest
import "../contents/ui/config/ProviderCapabilities.js" as Capabilities

TestCase {
    name: "ProviderCapabilities"

    function test_releasedVersionBoundaries_data() {
        return [{tag: "fireworks", key: "fireworks", before: "0.53.9", at: "0.54.0"},
            {tag: "source", key: "source", before: "0.72.9", at: "0.73.0"},
            {tag: "commandcode-fal", key: "commandCodeFal", before: "0.74.9", at: "0.75.0"},
            {tag: "munito", key: "munito", before: "0.76.9", at: "0.77.0"},
            {tag: "soniox", key: "soniox", before: "0.79.9", at: "0.80.0"},
            {tag: "chatbox", key: "abliterationChatbox", before: "0.80.9", at: "0.81.0"}]
    }
    function test_releasedVersionBoundaries(data) {
        verify(!Capabilities.versionCapabilities(data.before, 0)[data.key])
        verify(Capabilities.versionCapabilities(data.at, "0")[data.key])
        verify(!Capabilities.versionCapabilities(data.at, 1)[data.key])
        verify(!Capabilities.versionCapabilities(data.at + "-rc.1", 0)[data.key])
        verify(!Capabilities.versionCapabilities("unknown", 0)[data.key])
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

    function test_providerAndAuthenticationRestrictions() {
        var old = Capabilities.versionCapabilities("0.53.0", 0)
        var current = Capabilities.versionCapabilities("0.83.0", 0)
        for (var provider of ["fireworks", "soniox", "chatbox", "abliteration", "munito", "commandcode", "fal"]) {
            verify(!Capabilities.supportsApiKey(provider, null, old), provider)
            verify(Capabilities.supportsApiKey(provider, null, current), provider)
            verify(!Capabilities.supportsApiKey(provider, {supportsConfigAPIKey: false}, current), provider)
        }
        verify(Capabilities.supportsApiKey("openai", null, old))
        verify(Capabilities.supportsApiKey("openai", {supportsConfigAPIKey: true}, old))
        verify(!Capabilities.supportsApiKey("openai", {}, current))
        verify(!Capabilities.supportsApiKey("future-provider", {supportsConfigAPIKey: true}, current))
    }
}
