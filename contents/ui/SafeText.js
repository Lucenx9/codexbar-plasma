.pragma library

var maximumCliMessageLength = 500
var maximumDiagnosticLength = 65536
var maximumCliJsonLength = 4 * 1024 * 1024
var credentialRedactionLookaheadLength = 64

function safeLimit(maximumLength, fallback) {
    var limit = Number(maximumLength)
    if (!isFinite(limit) || limit <= 0) {
        limit = fallback
    }
    return Math.max(1, Math.min(maximumDiagnosticLength, Math.floor(limit)))
}

function boundedInspectionText(value, inspectionLimit, lookaheadLength) {
    var text = value === null || value === undefined ? "" : String(value)
    var windowLength = safeLimit(inspectionLimit, maximumCliMessageLength)
    var lookahead = Math.max(0, Math.min(credentialRedactionLookaheadLength, Number(lookaheadLength) || 0))
    var scanLimit = Math.min(text.length, maximumDiagnosticLength)
    var chunkLength = Math.max(256, windowLength)
    for (var offset = 0; offset < scanLimit; offset += chunkLength) {
        var chunk = text.slice(offset, Math.min(scanLimit, offset + chunkLength))
        var firstVisible = chunk.search(/[^\s\u0000-\u001f\u007f]/)
        if (firstVisible !== -1) {
            var start = offset + firstVisible
            return text.slice(start, start + windowLength + lookahead)
        }
    }
    return ""
}

function redactCredentials(value, inspectionLimit) {
    var limit = safeLimit(inspectionLimit, maximumCliMessageLength)
    var inspectionLength = Math.min(maximumDiagnosticLength, limit * 8)
    var text = boundedInspectionText(value, inspectionLength)
    var lookaheadText = boundedInspectionText(value, inspectionLength, credentialRedactionLookaheadLength)
    var redactedText = redactCredentialText(text)
    var redactedLookaheadText = redactCredentialText(lookaheadText)

    // Lookahead may decide that a credential starts inside the visible window,
    // but bytes beyond that window must never become displayable after a
    // replacement shortens earlier text. The startsWith test uses slice instead
    // of String.indexOf: QML's V4 engine returns -1 for "".indexOf("") where
    // ECMAScript returns 0, so an indexOf test turned an empty (no-error)
    // message into "[redacted]".
    if (redactedLookaheadText.slice(0, redactedText.length) !== redactedText) {
        var sharedLength = 0
        while (sharedLength < redactedText.length
                && sharedLength < redactedLookaheadText.length
                && redactedText.charAt(sharedLength) === redactedLookaheadText.charAt(sharedLength)) {
            sharedLength++
        }
        return redactedText.slice(0, sharedLength) + "[redacted]"
    }
    return redactedText
}

function redactCredentialText(text) {
    return text
        .replace(/((?:proxy-)?authorization["']?\s*[:=]\s*)(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\r\n]*)/gi, "$1[redacted]")
        .replace(/\bbearer\s+(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s,;]+)/gi, "Bearer [redacted]")
        .replace(/((?:set-cookie|cookie)["']?\s*[:=]\s*)(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\r\n]*)/gi, "$1[redacted]")
        .replace(/((?:api[-_ ]?key|access[-_ ]?token|refresh[-_ ]?token|id[-_ ]?token|token)["']?\s*[:=]\s*)(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s,;]+)/gi, "$1[redacted]")
        .replace(/\bsk-[A-Za-z0-9_-]{8,}\b/gi, "[redacted]")
}

// A structured value in a display field is a payload bug, not text. Coercing it
// puts "[object Object]", or a comma-joined array, into the popup as if the CLI
// had really labelled something that way. Display text drops it so the caller's
// own fallback shows instead. Diagnostics deliberately keep coercing: there,
// seeing the malformed shape beats seeing nothing.
function isStructuredValue(value) {
    return value !== null && typeof value === "object"
}

// Some Kirigami controls render Text.AutoText internally and do not expose
// textFormat. Wrap escaped plain text in harmless rich text so CLI-controlled
// tags stay visible as text instead of becoming images or links. This helper
// escapes display-ready text; CLI adapters still own bounding and redaction.
function plainTextAsRichText(value) {
    if (isStructuredValue(value) || value === null || value === undefined) {
        return ""
    }
    var text = String(value)
        .replace(/\r\n?/g, "\n")
        .replace(/[\u0000-\u0009\u000b\u000c\u000e-\u001f\u007f]/g, " ")
    if (text.length === 0) {
        return ""
    }
    return "<span>" + text
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/\"/g, "&quot;")
        .replace(/'/g, "&#39;")
        .replace(/\n/g, "<br>")
        + "</span>"
}

// Qt Quick abstract-button styles pass their label through mnemonic handling
// before parsing rich text. A single ampersand is consumed there, which would
// corrupt the entities emitted above ("&lt;" becomes "lt;"). Doubling entity
// ampersands preserves one for the rich-text parser while still keeping the
// provider text escaped.
function plainTextAsMnemonicRichText(value) {
    return plainTextAsRichText(value).replace(/&/g, "&&")
}

// The desktop Plasma button style draws its label through the native style
// item instead of a QML Text item, so feeding it a rich-text wrapper prints the
// wrapper literally. Keep markup as ordinary text and escape only mnemonic
// ampersands for that native label path.
function plainTextAsMnemonicLabel(value) {
    if (isStructuredValue(value) || value === null || value === undefined) {
        return ""
    }
    return String(value)
        .replace(/\r\n?/g, "\n")
        .replace(/[\u0000-\u0009\u000b\u000c\u000e-\u001f\u007f]/g, " ")
        .replace(/&/g, "&&")
}

function plainButtonText(value, hasContentItem) {
    return hasContentItem === true
        ? plainTextAsMnemonicRichText(value)
        : plainTextAsMnemonicLabel(value)
}

function boundedDisplayText(value, maximumLength) {
    if (isStructuredValue(value)) {
        return ""
    }
    var limit = safeLimit(maximumLength, maximumCliMessageLength)
    var inspectionLimit = Math.min(maximumDiagnosticLength, limit * 8)
    var text = boundedInspectionText(value, inspectionLimit)
        .replace(/[\u0000-\u001f\u007f]/g, " ")
        .replace(/\s+/g, " ")
        .trim()
    return text.length > limit ? text.slice(0, limit) : text
}

// Dynamic-loader warnings reach stderr before the CLI produces any output, so
// they lead the bounded stderr excerpt shown as a failure reason. The common
// case is glibc's "no version information available", emitted when the upstream
// glibc build (linked against Debian's versioned libcurl) runs on a distro that
// ships libcurl without symbol versioning. They are non-fatal and say nothing
// about why a command failed, so drop them and let the real message surface.
var loaderDiagnosticMarker = "no version information available"
var loaderDiagnosticPattern = /^.*:\s*no version information available\s*\(required by .*\)$/

function stripLoaderDiagnostics(value, maximumLength) {
    var limit = safeLimit(maximumLength, maximumCliMessageLength)
    var text = boundedInspectionText(value, Math.min(maximumDiagnosticLength, limit * 8))
    if (text.indexOf(loaderDiagnosticMarker) === -1) {
        return text
    }

    var lines = text.split("\n")
    var kept = []
    for (var index = 0; index < lines.length; index++) {
        if (!loaderDiagnosticPattern.test(lines[index].replace(/\r$/, "").trim())) {
            kept.push(lines[index])
        }
    }

    // Keep the original text when loader noise was all stderr carried, so a
    // failure never surfaces as an empty message.
    var stripped = kept.join("\n")
    return stripped.trim().length > 0 ? stripped : text
}

function cliJsonText(value) {
    var text = typeof value === "string" ? value : String(value || "")
    return text.length <= maximumCliJsonLength ? text : null
}

function cliMessage(value, maximumLength) {
    if (isStructuredValue(value)) {
        return ""
    }
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
