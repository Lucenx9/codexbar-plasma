function providerKey(value) {
    var key = String(value || "codex").toLowerCase()
    var aliases = {
        "abacusai": "abacus",
        "agy": "antigravity",
        "alibaba-coding-plan": "alibaba",
        "alibaba-token-plan": "alibabatokenplan",
        "aws-bedrock": "bedrock",
        "droid": "factory",
        "gemini-cli": "gemini",
        "groqcloud": "groq",
        "kimi-k2": "kimik2",
        "vertex": "vertexai"
    }
    return aliases[key] || key
}
