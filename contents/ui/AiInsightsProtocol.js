.pragma library
.import "Guards.js" as Guards
.import "AiInsights.js" as AiInsights

// Commands and validated replies for the private helper. QML owns processes,
// input-file writes, deadlines, and stale-result rejection.

var maximumSnapshotLength = 16384
// Mirrors the helper's own bound, so an oversized endpoint fails as invalid
// input instead of an unexecutable command line.
var maximumEndpointLength = 2048
var reasons = ["missing_key", "secret_unavailable", "auth", "credits", "forbidden",
    "rate_limited", "model", "request", "timeout", "network", "unavailable", "routing",
    "refused", "truncated", "format", "invalid_input", "endpoint"]

function scriptPath(scriptUrl) {
    var url = String(scriptUrl)
    try {
        return url.indexOf("file:///") === 0 ? decodeURIComponent(url.slice(7)) : ""
    } catch (error) {
        return ""
    }
}

function generationArguments(provider, value) {
    if (!AiInsights.validModel(provider, value.model)) return null
    var parts = ["--model", Guards.shellQuote(value.model), "--language", AiInsights.languageTag(value.language)]
    if (provider === "openrouter" && value.zdr === false) parts.push("--no-zdr")
    return parts
}

// The helper reads API keys itself; no secret is ever part of this command.
function command(scriptUrl, action, options) {
    var script = scriptPath(scriptUrl)
    if (!script || ["key-status", "set-key", "clear-key", "models", "generate", "prepare", "discard"].indexOf(action) < 0) {
        return ""
    }
    var value = options || ({})
    var provider = AiInsights.safeProvider(value.provider)
    // A dialog waits for the user; network actions are bounded well below it.
    var limit = action === "set-key" ? "330s" : (action === "generate" ? "180s" : "45s")
    var parts = ["exec", "timeout", "--kill-after=2s", limit, "python3", Guards.shellQuote(script),
        "--action", action, "--provider", provider]
    if (provider === "ollama" && (action === "models" || action === "generate")) {
        if (typeof value.endpoint === "string" && value.endpoint.length > maximumEndpointLength) {
            return ""
        }
        parts.push("--endpoint", Guards.shellQuote(AiInsights.endpointText(value.endpoint)))
    }
    if (action === "generate") {
        var generation = generationArguments(provider, value)
        if (!generation) return ""
        parts = parts.concat(generation)
    }
    if (action === "generate" || action === "discard") {
        if (!validInputRequest(value.request)) {
            return ""
        }
        parts.push("--request", value.request)
    }
    if (action === "set-key") {
        parts.push("--prompt", Guards.shellQuote(AiInsights.plainText(value.prompt, 200)))
    }
    parts.push("--supervised")
    return parts.join(" ")
}

function validInputRequest(value) {
    return typeof value === "string" && /^[a-f0-9]{32}$/.test(value)
}

function encodedSnapshot(text) {
    if (typeof text !== "string" || text.length === 0 || text.length > maximumSnapshotLength) {
        return ""
    }
    var bytes = []
    for (var i = 0; i < text.length; i++) {
        var code = text.charCodeAt(i)
        if (code > 127) return ""
        bytes.push(("0" + code.toString(16)).slice(-2))
    }
    return bytes.join("")
}

function preparedInput(text, exitCode, exitStatus) {
    var value = successfulExit(exitCode, exitStatus) ? parseReply(text) : null
    var segments = value && typeof value.path === "string" ? value.path.split("/") : []
    // QtCore.Settings resolves dot segments, so they could move the write
    // outside the helper's private `codexbar-plasma-ai-<uid>/<request>` file.
    if (!value || value.status !== "ready" || !validInputRequest(value.request)
            || typeof value.path !== "string" || value.path.length > 4096
            || value.path.charAt(0) !== "/" || /[\x00-\x1f\x7f]/.test(value.path)
            || segments.slice(1).some(function(segment) { return segment === "" || segment === "." || segment === ".." })
            || !/^codexbar-plasma-ai-[0-9]+$/.test(segments[segments.length - 3])
            || segments[segments.length - 2] !== value.request || segments[segments.length - 1] !== "payload.ini") {
        return null
    }
    return {request: value.request,
        location: "file://" + value.path.split("/").map(encodeURIComponent).join("/")}
}

function safeReason(value) {
    return reasons.indexOf(value) >= 0 ? value : "unavailable"
}

function parseReply(text) {
    if (typeof text !== "string" || text.length === 0 || text.length > AiInsights.maximumReplyLength * 4) {
        return null
    }
    try {
        var value = JSON.parse(text)
        return value && typeof value === "object" && !Array.isArray(value) ? value : null
    } catch (error) {
        return null
    }
}

// GNU timeout's normal deadline is 124; shell-wrapped SIGKILL is 137.
// With exec, Qt reports a killed owner as signal 9 with CrashExit (1).
function timeoutExit(exitCode, exitStatus) {
    return exitCode === 124 || exitCode === 137 || (exitCode === 9 && exitStatus === 1)
}

// Reads the executable engine's process result. Only a number or an integer
// string counts; null, booleans, blank strings, arrays and missing fields stay
// NaN, so they can never coerce to a successful exit.
function processResult(data) {
    return {
        exitCode: data ? Guards.exitCode(data["exit code"]) : Number.NaN,
        exitStatus: data ? Guards.exitCode(data["exit status"]) : Number.NaN
    }
}

function successfulExit(exitCode, exitStatus) {
    return exitCode === 0 && (exitStatus === undefined || exitStatus === 0)
}

function generationReply(text, exitCode, exitStatus) {
    if (timeoutExit(exitCode, exitStatus)) {
        return {outcome: "error", reason: "timeout", retryAfterSeconds: 0}
    }
    var value = parseReply(text)
    if (!value) {
        return {outcome: "error", reason: "format", retryAfterSeconds: 0}
    }
    if (value.status === "ok") {
        if (!successfulExit(exitCode, exitStatus)) {
            return {outcome: "error", reason: "unavailable", retryAfterSeconds: 0}
        }
        var summary = AiInsights.plainText(value.summary, AiInsights.maximumSummaryLength)
        return summary.length > 0
            ? {outcome: "ok", summary: summary, highlights: AiInsights.highlights(value.highlights)}
            : {outcome: "error", reason: "format", retryAfterSeconds: 0}
    }
    var retry = Number(value.retryAfter)
    return {
        outcome: "error",
        reason: safeReason(value.reason),
        retryAfterSeconds: isFinite(retry) && retry > 0 ? Math.min(retry, AiInsights.maximumRetryAfterSeconds) : 0
    }
}

function modelsReply(text, exitCode, exitStatus) {
    if (timeoutExit(exitCode, exitStatus)) {
        return {outcome: "error", reason: "timeout", models: [], key: ""}
    }
    var value = parseReply(text)
    if (!value) {
        return {outcome: "error", reason: "format", models: [], key: ""}
    }
    if (value.status !== "ok") {
        return {outcome: "error", reason: safeReason(value.reason),
            models: [], key: ""}
    }
    if (!successfulExit(exitCode, exitStatus)) {
        return {outcome: "error", reason: "unavailable", models: [], key: ""}
    }
    var models = []
    var seen = ({})
    var items = Array.isArray(value.models) ? value.models : []
    for (var i = 0; i < items.length && models.length < 500; i++) {
        var id = items[i] && typeof items[i].id === "string" ? items[i].id : ""
        if (AiInsights.modelPattern.test(id) && !Guards.hasOwnKey(seen, id)) {
            seen[id] = true
            models.push(id)
        }
    }
    return {outcome: "ok", reason: "", models: models,
        key: ["valid", "none"].indexOf(value.key) >= 0 ? value.key : ""}
}

function statusReply(text, allowed, exitCode, exitStatus) {
    if (!successfulExit(exitCode, exitStatus)) {
        return "unavailable"
    }
    var value = parseReply(text)
    return value && allowed.indexOf(value.status) >= 0 ? value.status : "unavailable"
}
