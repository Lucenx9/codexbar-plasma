.pragma library
.import "Guards.js" as Guards

// Validates the bounded status-component record printed by
// scripts/status-components.py. Only Claude and OpenAI pages are supported.
var feeds = {
    "claude": "claude",
    "claudeplatform": "claude",
    "codex": "openai",
    "openai": "openai"
}
var indicators = ["none", "minor", "major", "critical", "maintenance", "unknown"]
var maximumComponents = 64
var maximumName = 120

function feed(providerKey) {
    return Guards.hasOwnKey(feeds, providerKey) ? feeds[providerKey] : ""
}

function command(scriptUrl, feedID) {
    var url = String(scriptUrl)
    var script = ""
    try { script = url.indexOf("file:///") === 0 ? decodeURIComponent(url.slice(7)) : "" }
    catch (error) { return "" }
    if (!script || ["claude", "openai"].indexOf(feedID) < 0) return ""
    return "timeout --kill-after=2s 25s python3 " + Guards.shellQuote(script) + " --provider " + feedID
}

function rows(values, depth) {
    if (!Array.isArray(values) || values.length > maximumComponents) return null
    var result = []
    for (var i = 0; i < values.length; i++) {
        var value = values[i]
        if (!value || typeof value !== "object" || typeof value.name !== "string"
                || indicators.indexOf(value.indicator) < 0) return null
        var name = value.name.replace(/[\x00-\x1f\x7f]+/g, " ").trim().slice(0, maximumName)
        var children = depth === 0 ? rows(value.children, 1) : []
        if (name.length === 0 || children === null) return null
        result.push({name: name, indicator: value.indicator, children: children})
    }
    return result
}

// Returns the component rows, or null for any failure or invalid shape.
function response(text) {
    if (typeof text !== "string" || text.length > 262144) return null
    var value
    try { value = JSON.parse(text) } catch (error) { return null }
    if (!value || value.status !== "ok") return null
    var result = rows(value.components, 0)
    return result && result.length > 0 ? result : null
}
