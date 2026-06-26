.pragma library

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

function providerIconSource(value) {
    var key = providerKey(value)
    var aliases = {
        "aws-bedrock": "bedrock",
        "gemini": "gemini-white.png",
        "kimi-k2": "kimik2"
    }
    key = aliases[key] || key
    var fileName = key.indexOf(".") === -1 ? key + ".svg" : key
    return "../icons/providers/" + fileName
}
