.pragma library
.import "Guards.js" as Guards

// Pure AI Insights policy: language, request context, persisted cache,
// scheduling, helper commands, and helper replies. QML owns the process,
// configuration writes, and localization.

var providers = ["ollama", "openrouter", "openai"]
var intervalChoices = [0, 6, 12, 24]
var defaultOllamaEndpoint = "http://localhost:11434"
var hourMs = 60 * 60 * 1000
// A failed or interrupted attempt waits this long before the next automatic
// one, including across plasmashell restarts through the persisted attempt.
var transientRetryMs = 30 * 60 * 1000
var minimumRateLimitMs = 5 * 60 * 1000
var maximumRetryAfterSeconds = 24 * 60 * 60
var maximumSummaryLength = 600
var maximumHighlightLength = 160
var maximumHighlights = 3
var maximumReplyLength = 16384
var maximumSnapshotLength = 16384
// Mirrors the helper's own bound, so an oversized endpoint fails as invalid
// input instead of an unexecutable command line.
var maximumEndpointLength = 2048
var reasons = ["missing_key", "secret_unavailable", "auth", "credits", "forbidden",
    "rate_limited", "model", "request", "timeout", "network", "unavailable", "routing",
    "refused", "truncated", "format", "invalid_input", "endpoint"]
// Retrying these cannot succeed until the user changes a setting or a key.
// Malformed and cut-off answers completed and were charged, so they wait for
// the next scheduled generation instead of an early retry.
var permanentReasons = ["missing_key", "secret_unavailable", "auth", "credits", "forbidden",
    "model", "request", "routing", "refused", "truncated", "format", "invalid_input", "endpoint"]
var modelPattern = new RegExp("^[A-Za-z0-9][A-Za-z0-9._:/@+-]{0,199}$")
var controlCharacters = new RegExp("[\\u0000-\\u001f\\u007f-\\u009f\\u2028\\u2029]+", "g")

// The interface language is whatever catalog i18n() actually resolved. The
// applet receives it as the translated value of a marker message, so neither
// the numeric locale nor Qt.uiLanguage can disagree with the displayed text.
function languageTag(value) {
    var text = typeof value === "string" ? value.trim().replace("_", "-") : ""
    var match = /^([A-Za-z]{2,3})(?:-([A-Za-z]{2}))?$/.exec(text)
    if (!match) {
        return "en"
    }
    return match[1].toLowerCase() + (match[2] ? "-" + match[2].toUpperCase() : "")
}

function safeProvider(value) {
    return providers.indexOf(value) >= 0 ? value : "ollama"
}

function intervalHours(value) {
    var hours = Number(value)
    return intervalChoices.indexOf(hours) >= 0 ? hours : 0
}

function validModel(provider, model) {
    return typeof model === "string" && modelPattern.test(model)
        && !(provider === "openrouter" && model.indexOf("openrouter/") === 0)
}

function endpointText(value) {
    var text = typeof value === "string" ? value.trim() : ""
    return text.length > 0 ? text : defaultOllamaEndpoint
}

// Settings presentation only; the helper validates the destination again.
function isLocalEndpoint(value) {
    var match = /^https?:\/\/(\[[^\]]+\]|[^\/:?#]+)(:\d{1,5})?\/?$/i.exec(endpointText(value))
    if (!match) {
        return false
    }
    var host = match[1].toLowerCase()
    return host === "localhost" || host === "[::1]" || /^127(\.\d{1,3}){3}$/.test(host)
}

function context(settings) {
    var provider = safeProvider(settings.provider)
    var model = typeof settings.model === "string" ? settings.model.trim() : ""
    return {
        provider: provider,
        model: model,
        language: languageTag(settings.language),
        endpoint: provider === "ollama" ? endpointText(settings.endpoint) : "",
        zdr: provider === "openrouter" && settings.zdr !== false,
        configured: validModel(provider, model)
    }
}

// Everything that changes which answer is valid: a cached insight or a late
// reply belongs only to the context that produced it.
function contextKey(value) {
    return JSON.stringify([value.provider, value.model, value.language, value.endpoint, value.zdr])
}

function plainText(value, limit) {
    if (typeof value !== "string") {
        return ""
    }
    var text = value.replace(controlCharacters, " ")
        .replace(/\s+/g, " ").trim()
    return text.length > limit ? text.slice(0, limit - 1) + "\u2026" : text
}

function highlights(value) {
    var result = []
    for (var i = 0; Array.isArray(value) && i < value.length && result.length < maximumHighlights; i++) {
        var text = plainText(value[i], maximumHighlightLength)
        if (text.length > 0) {
            result.push(text)
        }
    }
    return result
}

function timestampMs(value) {
    var parsed = typeof value === "string" ? Date.parse(value) : NaN
    return isFinite(parsed) ? parsed : NaN
}

function cacheText(entry) {
    return JSON.stringify({
        version: 1,
        summary: plainText(entry.summary, maximumSummaryLength),
        highlights: highlights(entry.highlights),
        generatedAt: new Date(entry.generatedAtMs).toISOString(),
        context: entry.contextKey,
        provider: safeProvider(entry.provider),
        model: plainText(entry.model, 200),
        language: languageTag(entry.language),
        snapshot: plainText(entry.snapshotId, 32)
    })
}

// Persisted JSON is untrusted: rebuild the entry from bounded fields.
function parseCache(text) {
    if (typeof text !== "string" || text.length === 0 || text.length > maximumReplyLength) {
        return null
    }
    var value
    try {
        value = JSON.parse(text)
    } catch (error) {
        return null
    }
    if (!value || typeof value !== "object" || Array.isArray(value) || value.version !== 1) {
        return null
    }
    var summary = plainText(value.summary, maximumSummaryLength)
    var generatedAtMs = timestampMs(value.generatedAt)
    if (summary.length === 0 || !isFinite(generatedAtMs) || typeof value.context !== "string"
            || value.context.length > 4096) {
        return null
    }
    return {
        summary: summary,
        highlights: highlights(value.highlights),
        generatedAtMs: generatedAtMs,
        contextKey: value.context,
        provider: safeProvider(value.provider),
        model: plainText(value.model, 200),
        language: languageTag(value.language),
        snapshotId: plainText(value.snapshot, 32)
    }
}

// "otherContext" covers a changed language, provider, model, or endpoint: that
// text must not be presented as the current insight.
function cacheState(entry, currentContextKey, nowMs, hours) {
    if (!entry) {
        return "none"
    }
    if (entry.contextKey !== currentContextKey) {
        return "otherContext"
    }
    var freshForMs = (hours > 0 ? hours : 24) * hourMs
    return nowMs - entry.generatedAtMs > freshForMs || entry.generatedAtMs > nowMs + hourMs
        ? "stale" : "current"
}

function retryDelayMs(reason, retryAfterSeconds, hours) {
    if (reason === "rate_limited") {
        var seconds = Number(retryAfterSeconds)
        return Math.max(minimumRateLimitMs, isFinite(seconds) ? Math.min(seconds, maximumRetryAfterSeconds) * 1000 : 0)
    }
    if (permanentReasons.indexOf(reason) >= 0) {
        return (hours > 0 ? hours : 24) * hourMs
    }
    return transientRetryMs
}

// Automatic generation follows the configured interval only. Opening the
// popup, a usage refresh, or a changed language never makes it due by itself.
function automaticDue(observation) {
    var o = observation
    if (!o.enabled || !o.configured || !(o.intervalHours > 0) || o.busy || !o.sufficient) {
        return false
    }
    var intervalMs = o.intervalHours * hourMs
    if (o.nowMs < o.retryAtMs) {
        return false
    }
    if (isFinite(o.lastAttemptMs) && o.lastAttemptMs <= o.nowMs
            && o.nowMs - o.lastAttemptMs < Math.min(transientRetryMs, intervalMs)) {
        return false
    }
    if (isFinite(o.lastSuccessMs) && o.lastSuccessMs <= o.nowMs && o.nowMs - o.lastSuccessMs < intervalMs) {
        return false
    }
    // Nothing changed since the cached insight: another paid request would
    // only repeat it.
    return !(o.cacheMatchesContext && o.snapshotId.length > 0 && o.snapshotId === o.cachedSnapshotId)
}

function scriptPath(scriptUrl) {
    var url = String(scriptUrl)
    try {
        return url.indexOf("file:///") === 0 ? decodeURIComponent(url.slice(7)) : ""
    } catch (error) {
        return ""
    }
}

// The helper reads API keys itself; no secret is ever part of this command.
function command(scriptUrl, action, options) {
    var script = scriptPath(scriptUrl)
    if (!script || ["key-status", "set-key", "clear-key", "models", "generate"].indexOf(action) < 0) {
        return ""
    }
    var value = options || ({})
    var provider = safeProvider(value.provider)
    // A dialog waits for the user; network actions are bounded well below it.
    var limit = action === "set-key" ? "330s" : (action === "generate" ? "90s" : "45s")
    var parts = ["timeout", "--kill-after=2s", limit, "python3", Guards.shellQuote(script),
        "--action", action, "--provider", provider]
    if (provider === "ollama" && (action === "models" || action === "generate")) {
        if (typeof value.endpoint === "string" && value.endpoint.length > maximumEndpointLength) {
            return ""
        }
        parts.push("--endpoint", Guards.shellQuote(endpointText(value.endpoint)))
    }
    if (action === "generate") {
        if (!validModel(provider, value.model) || typeof value.snapshot !== "string"
                || value.snapshot.length === 0 || value.snapshot.length > maximumSnapshotLength) {
            return ""
        }
        parts.push("--model", Guards.shellQuote(value.model), "--language", languageTag(value.language),
            "--snapshot", Guards.shellQuote(value.snapshot))
        if (provider === "openrouter" && value.zdr === false) {
            parts.push("--no-zdr")
        }
    }
    if (action === "set-key") {
        parts.push("--prompt", Guards.shellQuote(plainText(value.prompt, 200)))
    }
    return parts.join(" ")
}

function safeReason(value) {
    return reasons.indexOf(value) >= 0 ? value : "unavailable"
}

function parseReply(text) {
    if (typeof text !== "string" || text.length === 0 || text.length > maximumReplyLength * 4) {
        return null
    }
    try {
        var value = JSON.parse(text)
        return value && typeof value === "object" && !Array.isArray(value) ? value : null
    } catch (error) {
        return null
    }
}

function generationReply(text) {
    var value = parseReply(text)
    if (!value) {
        return {outcome: "error", reason: "format", retryAfterSeconds: 0}
    }
    if (value.status === "ok") {
        var summary = plainText(value.summary, maximumSummaryLength)
        return summary.length > 0
            ? {outcome: "ok", summary: summary, highlights: highlights(value.highlights)}
            : {outcome: "error", reason: "format", retryAfterSeconds: 0}
    }
    var retry = Number(value.retryAfter)
    return {
        outcome: "error",
        reason: safeReason(value.reason),
        retryAfterSeconds: isFinite(retry) && retry > 0 ? Math.min(retry, maximumRetryAfterSeconds) : 0
    }
}

function modelsReply(text) {
    var value = parseReply(text)
    if (!value) {
        return {outcome: "error", reason: "format", models: [], key: ""}
    }
    if (value.status !== "ok") {
        return {outcome: "error", reason: safeReason(value.reason),
            models: [], key: ""}
    }
    var models = []
    var seen = ({})
    var items = Array.isArray(value.models) ? value.models : []
    for (var i = 0; i < items.length && models.length < 500; i++) {
        var id = items[i] && typeof items[i].id === "string" ? items[i].id : ""
        if (modelPattern.test(id) && !Guards.hasOwnKey(seen, id)) {
            seen[id] = true
            models.push(id)
        }
    }
    return {outcome: "ok", reason: "", models: models,
        key: ["valid", "none"].indexOf(value.key) >= 0 ? value.key : ""}
}

function statusReply(text, allowed) {
    var value = parseReply(text)
    return value && allowed.indexOf(value.status) >= 0 ? value.status : "unavailable"
}
