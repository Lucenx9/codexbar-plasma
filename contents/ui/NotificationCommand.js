.pragma library
.import "Guards.js" as Guards

var maximumTitleLength = 256
var maximumBodyLength = 1024
var maximumActionLabelLength = 64

function boundedText(value, maximumLength) {
    return value.slice(0, maximumLength).trim()
}

// A default action makes the notification body clickable. The action name is
// fixed; only its display label comes from the caller.
function actionArgument(actionLabel) {
    if (typeof actionLabel !== "string") {
        return ""
    }
    var cleanLabel = boundedText(actionLabel, maximumActionLabelLength)
    return cleanLabel.length > 0 ? " --action=" + Guards.shellQuote("default=" + cleanLabel) : ""
}

function notifySendArguments(urgencyQuoted, action, titleQuoted, bodyQuoted) {
    return "notify-send --app-name=CodexBar --icon=view-statistics --urgency="
        + urgencyQuoted + action + " -- " + titleQuoted + " " + bodyQuoted
}

function command(title, body, urgency, actionLabel) {
    if (typeof title !== "string" || typeof body !== "string") {
        return ""
    }
    var cleanTitle = boundedText(title, maximumTitleLength) || "CodexBar"
    var cleanBody = boundedText(body, maximumBodyLength)
    var cleanUrgency = typeof urgency === "string" ? urgency.trim() : "normal"
    if (cleanUrgency !== "low" && cleanUrgency !== "normal" && cleanUrgency !== "critical") {
        cleanUrgency = "normal"
    }
    var action = actionArgument(actionLabel)
    var plainSend = notifySendArguments(Guards.shellQuote(cleanUrgency), "",
        Guards.shellQuote(cleanTitle), Guards.shellQuote(cleanBody))
    // A nonce assignment cannot directly prefix the shell's reserved word `if`.
    if (action.length === 0) {
        return ":; if command -v notify-send >/dev/null 2>&1; then " + plainSend + "; fi"
    }
    // Actions need libnotify's notify-send 0.8 or newer; probe instead of
    // failing the whole notification on an older build.
    var actionSend = notifySendArguments(Guards.shellQuote(cleanUrgency), action,
        Guards.shellQuote(cleanTitle), Guards.shellQuote(cleanBody))
    return ":; if command -v notify-send >/dev/null 2>&1; then if notify-send --help 2>&1 | grep -q -- "
        + Guards.shellQuote("--action") + "; then " + actionSend + "; else " + plainSend + "; fi; fi"
}
