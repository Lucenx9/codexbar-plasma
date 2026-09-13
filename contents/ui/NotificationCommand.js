.pragma library
.import "Guards.js" as Guards

var maximumTitleLength = 256
var maximumBodyLength = 1024

function boundedText(value, maximumLength) {
    return value.slice(0, maximumLength).trim()
}

function command(title, body, urgency) {
    if (typeof title !== "string" || typeof body !== "string") {
        return ""
    }
    var cleanTitle = boundedText(title, maximumTitleLength) || "CodexBar"
    var cleanBody = boundedText(body, maximumBodyLength)
    var cleanUrgency = typeof urgency === "string" ? urgency.trim() : "normal"
    if (cleanUrgency !== "low" && cleanUrgency !== "normal" && cleanUrgency !== "critical") {
        cleanUrgency = "normal"
    }
    // A nonce assignment cannot directly prefix the shell's reserved word `if`.
    return ":; if command -v notify-send >/dev/null 2>&1; then notify-send --app-name=CodexBar --icon=view-statistics --urgency="
        + Guards.shellQuote(cleanUrgency) + " -- " + Guards.shellQuote(cleanTitle) + " " + Guards.shellQuote(cleanBody) + "; fi"
}
