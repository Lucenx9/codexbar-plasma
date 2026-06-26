.pragma library

function providerDocsUrl(key) {
    var mappings = {
        "alibaba": "alibaba-coding-plan",
        "alibabatokenplan": "alibaba-token-plan",
        "commandcode": "command-code",
        "groq": "groqcloud",
        "kimik2": "kimi-k2",
        "llmproxy": "llm-proxy",
        "opencodego": "opencode"
    }

    var knownDocs = [
        "abacus", "alibaba-coding-plan", "alibaba-token-plan", "amp", "antigravity", "augment",
        "bedrock", "chutes", "claude", "codebuff", "command-code", "codex", "crof", "cursor",
        "deepgram", "deepseek", "devin", "doubao", "elevenlabs", "factory", "gemini", "grok",
        "groqcloud", "jetbrains", "kilo", "kimi", "kimi-k2", "kiro", "litellm", "llm-proxy", "manus",
        "mimo", "minimax", "moonshot", "ollama", "opencode", "vertexai", "warp", "windsurf", "zai"
    ]

    var baseName = mappings[key] || key
    if (knownDocs.indexOf(baseName) === -1) {
        return ""
    }

    return "https://github.com/steipete/CodexBar/blob/main/docs/" + baseName + ".md"
}
