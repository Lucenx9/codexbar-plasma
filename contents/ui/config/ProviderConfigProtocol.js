.pragma library
.import "../Guards.js" as Guards
.import "../ProviderIdentity.js" as ProviderIdentity
.import "../SafeText.js" as SafeText
.import "ProviderDescriptor.js" as ProviderDescriptor

// Pure trust boundary for `codexbar config providers` and redacted provider
// diagnostics. The Providers page keeps JSON error localization, process state,
// selection, retries, and effects; this module only returns bounded display data
// or classifies the one compatibility error needed before a retry.

var maximumProviderItems = 256
var maximumDiagnosticListItems = 64
var maximumCliVersionTextLength = 128

function providerListResultIsCurrent(descriptor, currentRevision) {
    if (!isCliRecord(descriptor)
            || !Guards.hasOwnKey(descriptor, "providerConfigRevision")) {
        return false
    }
    var startedRevision = Number(descriptor.providerConfigRevision)
    var latestRevision = Number(currentRevision)
    return isFinite(startedRevision)
        && isFinite(latestRevision)
        && startedRevision === latestRevision
}

function normalizeProviderList(payload, fallbackTitleResolver) {
    var items = Array.isArray(payload) ? payload : [payload]
    var providers = []
    var itemLimit = Math.min(items.length, maximumProviderItems)
    for (var i = 0; i < itemLimit; i++) {
        var item = items[i]
        if (!isCliRecord(item)) {
            continue
        }
        var providerID = boundedProviderID(item.provider)
        if (providerID.length === 0) {
            continue
        }
        var displayName = SafeText.boundedDisplayText(item.displayName, 120)
        providers.push({
            provider: providerID,
            displayName: displayName.length > 0
                ? displayName
                : fallbackTitle(fallbackTitleResolver, providerID),
            enabled: item.enabled === true,
            defaultEnabled: item.defaultEnabled === true,
            descriptor: ProviderDescriptor.normalize(item.descriptor, fallbackTitleResolver)
        })
    }
    return providers
}

function providerListHasSupportedDescriptors(providers) {
    if (!Array.isArray(providers)) {
        return false
    }
    for (var i = 0; i < providers.length; i++) {
        var item = providers[i]
        if (isCliRecord(item)
                && isCliRecord(item.descriptor)
                && item.descriptor.schemaVersion === 1) {
            return true
        }
    }
    return false
}

function cliVersionAtLeast(value, requiredMajor, requiredMinor, requiredPatch) {
    if (typeof value !== "string") {
        return false
    }
    var text = SafeText.cliMessage(
        SafeText.stripLoaderDiagnostics(value), maximumCliVersionTextLength)
    var match = text.match(/(?:^|\s)v?(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?:\s|$)/)
    if (!match) {
        return false
    }
    var actual = [Number(match[1]), Number(match[2]), Number(match[3])]
    var required = [
        Number(requiredMajor), Number(requiredMinor), Number(requiredPatch)
    ]
    for (var i = 0; i < required.length; i++) {
        if (!isFinite(required[i]) || required[i] < 0
                || required[i] !== Math.floor(required[i])) {
            return false
        }
        if (actual[i] !== required[i]) {
            return actual[i] > required[i]
        }
    }
    return true
}

function commandError(payload) {
    if (!payload) {
        return ""
    }
    var probe = Array.isArray(payload) ? (payload.length > 0 ? payload[0] : null) : payload
    if (probe && probe.error && probe.error.message) {
        return boundedCliMessage(probe.error.message)
    }
    return ""
}

// Classified result of one finished provider command run (enable/disable,
// set-api-key, descriptor field or action). `payload` is the already-parsed
// stdout JSON, or undefined when stdout was empty; `stderrText` and
// `exitCode` are the raw process results.
//
// A healthy parsed envelope with exit 0 is a success regardless of stderr,
// because loader diagnostics and other library noise can make a successful
// run's stderr non-empty. Every other result keeps the historical ordering:
// structured error envelopes, stderr, timeout/exit code, unsupported data,
// then structured cancellation or status.
//
// Returns { outcome, message, exitCode } where outcome is one of:
//   "success"      payload was valid; stderr was noise
//   "cancelled"    user aborted inside the CLI flow
//   "envelopeError"  message = bounded redacted text from the payload
//   "statusError"    same, for status-flagged payloads; message may be ""
//   "timeout"
//   "exitCodeError"  exitCode = the non-zero numeric exit code
//   "stderrError"  message = bounded redacted stderr
//   "empty"        no stdout at all and no stderr to explain it
//   "invalidPayload"  stdout JSON had an unsupported shape
function commandOutcome(payload, stderrText, exitCode) {
    var record = isCliRecord(payload) ? payload : null
    var envelopeMessage = commandError(payload)
    if (envelopeMessage.length > 0) {
        return ({ outcome: "envelopeError", message: envelopeMessage })
    }

    var hasStatus = record && Guards.hasOwnKey(record, "status")
    var status = hasStatus && typeof record.status === "string"
        ? record.status.trim().toLowerCase()
        : ""
    var statusCancelled = status === "cancelled" || status === "canceled"
    var cancelled = record
        && (record.cancelled === true || statusCancelled)
    var statusFailed = status === "error" || status === "failed" || status === "failure"
    var statusSupported = !hasStatus
        || status === "ok"
        || statusCancelled
        || statusFailed
    var supportedPayload = commandPayloadIsSupported(payload)
    var code = Number(exitCode)
    var timedOut = code === 124 || code === 137

    if (supportedPayload && statusSupported && !cancelled && !statusFailed && code === 0) {
        return ({ outcome: "success", message: "" })
    }

    var stderrMessage = boundedCliMessage(stderrText)
    if (stderrMessage.length > 0) {
        return ({ outcome: "stderrError", message: stderrMessage })
    }
    if (timedOut) {
        return ({ outcome: "timeout", message: "" })
    }
    if (!isFinite(code) || code !== 0) {
        return ({ outcome: "exitCodeError", message: "", exitCode: code })
    }
    if (!supportedPayload || !statusSupported) {
        return ({
            outcome: payload === undefined ? "empty" : "invalidPayload",
            message: ""
        })
    }
    if (cancelled) {
        return ({ outcome: "cancelled", message: "" })
    }
    if (statusFailed) {
        return ({
            outcome: "statusError",
            message: record.message ? boundedCliMessage(record.message) : ""
        })
    }
    return ({ outcome: "success", message: "" })
}

function setApiKeyOutcomeIsSuccess(result) {
    return result !== null
        && result !== undefined
        && (result.outcome === "success" || result.outcome === "empty")
}

function commandPayloadIsSupported(payload) {
    if (isCliRecord(payload)) {
        return true
    }
    if (!Array.isArray(payload)
            || payload.length === 0
            || payload.length > maximumProviderItems) {
        return false
    }
    // Descriptor command statuses belong to one structured result object.
    // Status-bearing arrays are not part of that contract.
    for (var i = 0; i < payload.length; i++) {
        if (!isCliRecord(payload[i]) || Guards.hasOwnKey(payload[i], "status")) {
            return false
        }
    }
    return true
}

function descriptorUnsupportedMessage(stdoutText, stderrText) {
    var stderrMessage = boundedCliMessage(stderrText)
    if (isDescriptorUnsupportedMessage(stderrMessage)) {
        return stderrMessage
    }

    var trimmed = String(stdoutText || "").trim()
    if (trimmed.length === 0) {
        return ""
    }
    try {
        var message = commandError(JSON.parse(trimmed))
        return isDescriptorUnsupportedMessage(message) ? message : ""
    } catch (error) {
        return ""
    }
}

function normalizeProviderDiagnostic(payload) {
    var candidate = Array.isArray(payload) ? (payload.length > 0 ? payload[0] : ({})) : payload
    var item = isCliRecord(candidate) ? candidate : ({})
    var settings = isCliRecord(item.settings) ? item.settings : ({})
    var auth = isCliRecord(item.auth) ? item.auth : ({})
    return {
        provider: item.provider ? SafeText.cliMessage(item.provider, 128) : "",
        displayName: item.displayName ? SafeText.cliMessage(item.displayName, 120) : "",
        source: item.source ? SafeText.cliMessage(item.source, 120) : "",
        sourceMode: item.sourceMode ? SafeText.cliMessage(item.sourceMode, 120) : "",
        authConfigured: auth.configured === true,
        authModes: boundedDiagnosticList(auth.modes),
        settingsKeys: boundedDiagnosticList(ownDiagnosticKeys(settings)),
        fetchAttempts: Array.isArray(item.fetchAttempts) ? item.fetchAttempts.length : 0
    }
}

function isCliRecord(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
}

function boundedProviderID(value) {
    if (typeof value !== "string") {
        return ""
    }
    var providerID = value.trim()
    if (providerID.length === 0 || providerID.length > ProviderIdentity.maximumProviderIDLength) {
        return ""
    }
    var key = ProviderIdentity.providerMapKey(ProviderIdentity.resolveProviderKey(providerID))
    return key.length > 0 ? providerID : ""
}

function fallbackTitle(resolver, providerID) {
    return typeof resolver === "function" ? resolver(providerID) : providerID
}

function boundedCliMessage(value) {
    return SafeText.cliMessage(
        SafeText.stripLoaderDiagnostics(value), SafeText.maximumCliMessageLength)
}

function isDescriptorUnsupportedMessage(message) {
    var text = String(message || "").toLowerCase()
    if (text.indexOf("descriptor") === -1) {
        return false
    }
    return text.indexOf("unknown option") !== -1
        || text.indexOf("unknown argument") !== -1
        || text.indexOf("unrecognized option") !== -1
        || text.indexOf("unrecognized argument") !== -1
        || text.indexOf("unexpected option") !== -1
        || text.indexOf("unexpected argument") !== -1
        || text.indexOf("unsupported option") !== -1
        || text.indexOf("unsupported argument") !== -1
        || text.indexOf("invalid option") !== -1
}

function ownDiagnosticKeys(item) {
    var keys = []
    for (var key in item) {
        if (!Guards.hasOwnKey(item, key)) {
            continue
        }
        keys.push(key)
        if (keys.length >= maximumDiagnosticListItems) {
            break
        }
    }
    keys.sort()
    return keys
}

function boundedDiagnosticList(items) {
    if (!Array.isArray(items)) {
        return ""
    }
    var result = []
    var limit = Math.min(items.length, maximumDiagnosticListItems)
    for (var i = 0; i < limit; i++) {
        var value = SafeText.cliMessage(items[i], 120)
        if (value.length > 0) {
            result.push(value)
        }
    }
    return SafeText.boundedDisplayText(result.join(", "), 500)
}
