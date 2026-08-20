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
