.pragma library
.import "Guards.js" as Guards
.import "AiInsights.js" as AiInsights

// Commands and validated replies for the private helper. QML owns processes,
// input-file writes, deadlines, and stale-result rejection.

var maximumSnapshotLength = 16384
// 500 records with 200-character IDs and labels (including JSON escaping)
// exceed the small completion envelope. Only model listings need this bound.
var maximumModelsReplyLength = 256 * 1024
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
    var request = requestArguments(value.request)
    if (!request) return null
    var parts = ["--model", Guards.shellQuote(value.model), "--language", AiInsights.languageTag(value.language)]
    if (provider === "openrouter" && value.zdr === false) parts.push("--no-zdr")
    return parts.concat(request)
}

function requestArguments(request) {
    return validInputRequest(request) ? ["--request", request] : null
}

function actionArguments(action, provider, value) {
    switch (action) {
    case "generate": return generationArguments(provider, value)
    case "discard": return requestArguments(value.request)
    case "set-key": return ["--prompt", Guards.shellQuote(AiInsights.plainText(value.prompt, 200))]
    default: return []
    }
}

function endpointArguments(action, provider, value) {
    if (provider !== "ollama") return []
    if (["models", "generate"].indexOf(action) < 0) return []
    if (typeof value.endpoint === "string" && value.endpoint.length > maximumEndpointLength) return null
    return ["--endpoint", Guards.shellQuote(AiInsights.endpointText(value.endpoint))]
}

// A dialog waits for the user; network actions are bounded well below it.
var actionDeadlines = {"key-status": "45s", "set-key": "330s", "clear-key": "45s",
    "models": "45s", "generate": "180s", "prepare": "45s", "discard": "45s"}

// The helper reads API keys itself; no secret is ever part of this command.
function command(scriptUrl, action, options) {
    var script = scriptPath(scriptUrl)
    if (!script || typeof action !== "string") return ""
    if (!Guards.hasOwnKey(actionDeadlines, action)) return ""
    var value = options || ({})
    var provider = AiInsights.safeProvider(value.provider)
    var endpoint = endpointArguments(action, provider, value)
    var args = actionArguments(action, provider, value)
    if (!endpoint || !args) return ""
    var parts = ["exec", "timeout", "--kill-after=2s", actionDeadlines[action], "python3", Guards.shellQuote(script),
        "--action", action, "--provider", provider]
    return parts.concat(endpoint, args, ["--supervised"]).join(" ")
}

function validInputRequest(value) {
    return typeof value === "string" && /^[a-f0-9]{32}$/.test(value)
}

function encodedSnapshot(text) {
    if (!boundedText(text, maximumSnapshotLength)) {
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

function boundedText(value, maximumLength) {
    return typeof value === "string" && value.length > 0 && value.length <= maximumLength
}

function inputPathSegments(path) {
    if (!boundedText(path, 4096)) return null
    if (path.charAt(0) !== "/" || /[\x00-\x1f\x7f]/.test(path)) return null
    var segments = path.split("/")
    // QtCore.Settings resolves dot segments, so they could escape the private file.
    var unsafe = segments.slice(1).some(function(segment) {
        return ["", ".", ".."].indexOf(segment) >= 0
    })
    return unsafe ? null : segments
}

function matchesInputRequest(segments, request) {
    return /^codexbar-plasma-ai-[0-9]+$/.test(segments[segments.length - 3])
        && segments[segments.length - 2] === request
        && segments[segments.length - 1] === "payload.ini"
}

function preparedInput(text, exitCode, exitStatus) {
    if (!successfulExit(exitCode, exitStatus)) return null
    var value = parseReply(text)
    if (!value || value.status !== "ready") return null
    if (!validInputRequest(value.request)) return null
    var segments = inputPathSegments(value.path)
    if (!segments || !matchesInputRequest(segments, value.request)) return null
    return {request: value.request,
        location: "file://" + segments.map(encodeURIComponent).join("/")}
}

function safeReason(value) {
    return reasons.indexOf(value) >= 0 ? value : "unavailable"
}

function parseReply(text, maximumLength) {
    if (!boundedText(text, maximumLength || AiInsights.maximumReplyLength * 4)) {
        return null
    }
    try {
        var value = JSON.parse(text)
        return Guards.isRecord(value) ? value : null
    } catch (error) {
        return null
    }
}

// GNU timeout's normal deadline is 124; shell-wrapped SIGKILL is 137.
// With exec, Qt reports a killed owner as signal 9 with CrashExit (1).
function timeoutExit(exitCode, exitStatus) {
    return [124, 137].indexOf(exitCode) >= 0 || (exitCode === 9 && exitStatus === 1)
}

// Reads the executable engine's process result. Only a number or an integer
// string counts; null, booleans, blank strings, arrays and missing fields stay
// NaN, so they can never coerce to a successful exit.
function processResult(data) {
    var result = data || ({})
    return {
        exitCode: Guards.exitCode(result["exit code"]),
        exitStatus: Guards.exitCode(result["exit status"])
    }
}

function successfulExit(exitCode, exitStatus) {
    return exitCode === 0 && (exitStatus === undefined || exitStatus === 0)
}

// Timeout and malformed output outrank helper status; a claimed success also
// requires a clean process exit. Keep the error payload for retry metadata.
function helperReply(text, exitCode, exitStatus, maximumLength) {
    if (timeoutExit(exitCode, exitStatus)) return {reason: "timeout", value: null}
    var value = parseReply(text, maximumLength)
    if (!value) return {reason: "format", value: null}
    if (value.status !== "ok") return {reason: safeReason(value.reason), value: value}
    if (!successfulExit(exitCode, exitStatus)) return {reason: "unavailable", value: null}
    return {reason: "", value: value}
}

function retryAfterSeconds(value) {
    if (!value) return 0
    var retry = Number(value.retryAfter)
    return isFinite(retry) && retry > 0 ? Math.min(retry, AiInsights.maximumRetryAfterSeconds) : 0
}

function generationReply(text, exitCode, exitStatus) {
    var reply = helperReply(text, exitCode, exitStatus)
    if (reply.reason) {
        return {outcome: "error", reason: reply.reason, retryAfterSeconds: retryAfterSeconds(reply.value)}
    }
    var summary = AiInsights.plainText(reply.value.summary, AiInsights.maximumSummaryLength)
    return summary.length > 0
        ? {outcome: "ok", summary: summary, highlights: AiInsights.highlights(reply.value.highlights)}
        : {outcome: "error", reason: "format", retryAfterSeconds: 0}
}

function modelIds(value) {
    var models = []
    var seen = ({})
    var items = Array.isArray(value) ? value : []
    for (var i = 0; i < items.length && models.length < 500; i++) {
        var id = items[i] && typeof items[i].id === "string" ? items[i].id : ""
        if (AiInsights.modelPattern.test(id) && !Guards.hasOwnKey(seen, id)) {
            seen[id] = true
            models.push(id)
        }
    }
    return models
}

function modelsReply(text, exitCode, exitStatus) {
    var reply = helperReply(text, exitCode, exitStatus, maximumModelsReplyLength)
    if (reply.reason) return {outcome: "error", reason: reply.reason, models: [], key: ""}
    return {outcome: "ok", reason: "", models: modelIds(reply.value.models),
        key: ["valid", "none"].indexOf(reply.value.key) >= 0 ? reply.value.key : ""}
}

function statusReply(text, allowed, exitCode, exitStatus) {
    if (!successfulExit(exitCode, exitStatus)) {
        return "unavailable"
    }
    var value = parseReply(text)
    return value && allowed.indexOf(value.status) >= 0 ? value.status : "unavailable"
}
