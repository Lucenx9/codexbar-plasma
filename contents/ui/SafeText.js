.pragma library

var maximumCliMessageLength = 500
var maximumDiagnosticLength = 65536

function safeLimit(maximumLength, fallback) {
    var limit = Number(maximumLength)
    if (!isFinite(limit) || limit <= 0) {
        limit = fallback
    }
    return Math.max(1, Math.min(maximumDiagnosticLength, Math.floor(limit)))
}

function redactCredentials(value, inspectionLimit) {
    var text = typeof value === "string" ? value : String(value || "")
    text = text.slice(0, safeLimit(inspectionLimit, maximumCliMessageLength) * 8)
    return text
        .replace(/(authorization\s*[:=]\s*)(?:bearer\s+)?[^\s,;]+/gi, "$1[redacted]")
        .replace(/\bbearer\s+[^\s,;]+/gi, "Bearer [redacted]")
        .replace(/(cookie\s*[:=]\s*)[^\r\n]*/gi, "$1[redacted]")
        .replace(/((?:api[-_ ]?key|access[-_ ]?token|refresh[-_ ]?token|token)\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;]+)/gi, "$1[redacted]")
        .replace(/\bsk-[A-Za-z0-9_-]{8,}\b/g, "[redacted]")
}

function boundedDisplayText(value, maximumLength) {
    var limit = safeLimit(maximumLength, maximumCliMessageLength)
    var text = String(value || "")
        .replace(/[\u0000-\u001f\u007f]/g, " ")
        .replace(/\s+/g, " ")
        .trim()
    return text.length > limit ? text.slice(0, limit) : text
}

function cliMessage(value, maximumLength) {
    var limit = safeLimit(maximumLength, maximumCliMessageLength)
    return boundedDisplayText(redactCredentials(value, limit), limit)
}

function cliDiagnostic(value, maximumLength) {
    var limit = safeLimit(maximumLength, maximumDiagnosticLength)
    var text = redactCredentials(value, limit)
        .replace(/\r\n?/g, "\n")
        .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, " ")
        .trim()
    return text.length > limit ? text.slice(0, limit) : text
}
