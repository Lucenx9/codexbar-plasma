.pragma library
.import "ProviderConfigProtocol.js" as Protocol
.import "../Guards.js" as Guards

// Released Linux writer policy. QML owns probes and publishes these flags.
function versionCapabilities(version, exitCode) {
    var success = Number(exitCode) === 0
    return {
        fireworks: success && Protocol.cliVersionAtLeast(version, 0, 54, 0),
        soniox: success && Protocol.cliVersionAtLeast(version, 0, 80, 0),
        abliterationChatbox: success && Protocol.cliVersionAtLeast(version, 0, 81, 0),
        munito: success && Protocol.cliVersionAtLeast(version, 0, 77, 0),
        commandCodeFal: success && Protocol.cliVersionAtLeast(version, 0, 75, 0),
        source: success && Protocol.cliVersionAtLeast(version, 0, 73, 0)
    }
}

var keyCapabilities = {
    soniox: "soniox", abliteration: "abliterationChatbox", chatbox: "abliterationChatbox",
    munito: "munito", fireworks: "fireworks", commandcode: "commandCodeFal", fal: "commandCodeFal"
}
var legacyApiKeyProviders = [
    "aerostack", "linkup", "sailresearch", "sofya", "tavily", "aixy", "alibaba", "amp",
    "atlascloud", "azureopenai", "chutes", "codebuff", "clawrouter", "copilot", "crof",
    "crossmodel", "deepgram", "devpass", "doubao", "elevenlabs", "gitkraken", "groq", "ibmbob",
    "kimi", "kimik2", "kilo", "litellm", "llmman", "llmproxy", "minimax", "moonshot", "ollama",
    "openai", "openrouter", "poe", "v0", "venice", "vercel", "warp", "xkiro", "zai"
]

function supportsApiKey(providerID, authentication, capabilities) {
    if (authentication && authentication.supportsConfigAPIKey !== true) return false
    if (Guards.hasOwnKey(keyCapabilities, providerID)) return capabilities[keyCapabilities[providerID]]
    return legacyApiKeyProviders.indexOf(providerID) >= 0
}
