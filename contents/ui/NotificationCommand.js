.pragma library
.import "Guards.js" as Guards

function command(title, body, urgency) {
    if (typeof title !== "string" || typeof body !== "string") {
        return ""
    }
    var cleanTitle = title.trim() || "CodexBar"
    var cleanBody = body.trim()
    var cleanUrgency = typeof urgency === "string" ? urgency.trim() : "normal"
    if (cleanUrgency !== "low" && cleanUrgency !== "normal" && cleanUrgency !== "critical") {
        cleanUrgency = "normal"
    }
    // A nonce assignment cannot directly prefix the shell's reserved word `if`.
    return ":; if command -v notify-send >/dev/null 2>&1; then notify-send --app-name=CodexBar --icon=view-statistics --urgency="
        + Guards.shellQuote(cleanUrgency) + " -- " + Guards.shellQuote(cleanTitle) + " " + Guards.shellQuote(cleanBody) + "; fi"
}
