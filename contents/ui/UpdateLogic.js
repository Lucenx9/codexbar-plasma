.pragma library
.import "Guards.js" as Guards

var maximumResultStatusLength = 64
var maximumVersionLength = 128
var maximumAssetUrlLength = 2048
var maximumErrorCodeLength = 128
var maximumErrorDetailLength = 500
var maximumLastCheckLength = 64

function boundedString(value, maximumLength) {
    return typeof value === "string"
        && value.length <= maximumLength
        && value.trim().length > 0
        ? value
        : ""
}

function boundedOwnString(payload, key, maximumLength) {
    return Guards.hasOwnKey(payload, key) ? boundedString(payload[key], maximumLength) : ""
}

function boundedHttpsUrl(value) {
    var text = boundedString(value, maximumAssetUrlLength).trim()
    return text.toLowerCase().indexOf("https://") === 0 ? text : ""
}

function lastCheckMs(value) {
    if (typeof value !== "string") {
        return NaN
    }
    var timestamp = value.trim()
    if (timestamp.length === 0 || timestamp.length > maximumLastCheckLength) {
        return NaN
    }
    var parsed = Date.parse(timestamp)
    return isFinite(parsed) ? parsed : NaN
}

function normalizedVersion(value) {
    var text = typeof value === "string" ? value.trim() : ""
    return text.charAt(0) === "v" || text.charAt(0) === "V" ? text.substring(1) : text
}

// Numeric dotted versions compare like the updater's `sort -V`; anything else
// returns null so callers do not guess an order for custom version strings.
function compareNumericVersions(left, right) {
    var pattern = /^[0-9]+(\.[0-9]+)*$/
    if (!pattern.test(left) || !pattern.test(right)) {
        return null
    }
    var leftParts = left.split(".")
    var rightParts = right.split(".")
    var length = Math.max(leftParts.length, rightParts.length)
    for (var index = 0; index < length; ++index) {
        if (index >= leftParts.length) {
            return -1
        }
        if (index >= rightParts.length) {
            return 1
        }
        var difference = Number(leftParts[index]) - Number(rightParts[index])
        if (difference !== 0) {
            return difference < 0 ? -1 : 1
        }
    }
    return 0
}

// Restores a persisted "update available" version only while it is still newer
// than the running widget, so a release installed another way is not offered.
function restoredAvailableVersion(persistedVersion, installedVersion) {
    var persisted = boundedString(persistedVersion, maximumVersionLength).trim()
    if (persisted.length === 0) {
        return ""
    }
    var installed = normalizedVersion(boundedString(installedVersion, maximumVersionLength))
    if (installed.length === 0) {
        return persisted
    }
    var candidate = normalizedVersion(persisted)
    if (candidate === installed) {
        return ""
    }
    var order = compareNumericVersions(candidate, installed)
    return order !== null && order <= 0 ? "" : persisted
}

function updateCheckDue(updateChecksEnabled, lastCheck, intervalHours, nowMs, forceCheck) {
    if (!updateChecksEnabled) {
        return false
    }
    if (forceCheck === true) {
        return true
    }

    var parsedLastCheckMs = lastCheckMs(lastCheck)
    if (!isFinite(parsedLastCheckMs)) {
        return true
    }

    var hours = Number(intervalHours)
    if (!isFinite(hours) || hours <= 0) {
        return true
    }
    var elapsedMs = Number(nowMs) - parsedLastCheckMs
    return elapsedMs < 0 || elapsedMs >= hours * 60 * 60 * 1000
}

function nextUpdateCheckDelay(updateChecksEnabled, lastCheck, intervalHours, nowMs, minimumDelayMs) {
    if (!updateChecksEnabled) {
        return 0
    }

    var minimum = Number(minimumDelayMs)
    if (!isFinite(minimum) || minimum <= 0) {
        minimum = 1000
    }
    var hours = Number(intervalHours)
    if (!isFinite(hours) || hours <= 0) {
        return minimum
    }

    var intervalMs = hours * 60 * 60 * 1000
    var parsedLastCheckMs = lastCheckMs(lastCheck)
    if (!isFinite(parsedLastCheckMs)) {
        return minimum
    }

    var now = Number(nowMs)
    if (!isFinite(now) || now < parsedLastCheckMs) {
        return minimum
    }
    var remainingMs = parsedLastCheckMs + intervalMs - now
    return Math.max(minimum, Math.min(intervalMs, remainingMs))
}

function updateRetryDelay(consecutiveFailures, baseDelayMs, maximumDelayMs) {
    var base = Number(baseDelayMs)
    if (!isFinite(base) || base <= 0) {
        base = 60000
    }
    var maximum = Number(maximumDelayMs)
    if (!isFinite(maximum) || maximum < base) {
        maximum = base
    }
    var failures = Math.floor(Number(consecutiveFailures))
    if (!isFinite(failures) || failures < 1) {
        failures = 1
    }
    return Math.min(maximum, base * Math.pow(2, Math.min(failures - 1, 30)))
}

function updateRequestDecision(commandActive, activeInstallMode,
        pendingAutomaticCheck, requestedInstallMode) {
    var installMode = requestedInstallMode === true
    if (commandActive !== true) {
        return {
            startNow: true,
            installMode: installMode,
            pendingAutomaticCheck: false
        }
    }

    return {
        startNow: false,
        installMode: activeInstallMode === true,
        pendingAutomaticCheck: pendingAutomaticCheck === true
            || (installMode && activeInstallMode !== true)
    }
}

function updateCompletionDecision(pendingAutomaticCheck,
        updateChecksEnabled, autoUpdateEnabled) {
    return {
        startAutomaticCheck: pendingAutomaticCheck === true
            && updateChecksEnabled === true
            && autoUpdateEnabled === true,
        pendingAutomaticCheck: false
    }
}

function resultIntent(payload, installMode) {
    var status = boundedOwnString(payload, "status", maximumResultStatusLength)
    if (status === "error") {
        return {
            kind: "error",
            successful: false,
            version: "",
            assetUrl: "",
            releaseUrl: "",
            errorCode: boundedOwnString(payload, "errorCode", maximumErrorCodeLength),
            errorDetail: boundedOwnString(payload, "errorDetail", maximumErrorDetailLength),
            notificationKind: ""
        }
    }
    if (status === "available") {
        return {
            kind: "available",
            successful: true,
            version: boundedOwnString(payload, "remoteVersion", maximumVersionLength),
            assetUrl: Guards.hasOwnKey(payload, "assetUrl") ? boundedHttpsUrl(payload.assetUrl) : "",
            releaseUrl: Guards.hasOwnKey(payload, "releaseUrl") ? boundedHttpsUrl(payload.releaseUrl) : "",
            errorCode: "",
            errorDetail: "",
            notificationKind: installMode === true ? "" : "available"
        }
    }
    if (status === "installed") {
        return {
            kind: "installed",
            successful: true,
            version: boundedOwnString(payload, "remoteVersion", maximumVersionLength),
            assetUrl: "",
            releaseUrl: "",
            errorCode: "",
            errorDetail: "",
            notificationKind: "installed"
        }
    }
    if (status === "current" || status === "skipped") {
        return {
            kind: status,
            successful: true,
            version: "",
            assetUrl: "",
            releaseUrl: "",
            errorCode: "",
            errorDetail: "",
            notificationKind: ""
        }
    }
    return {
        kind: "unknown",
        successful: false,
        status: status,
        version: "",
        assetUrl: "",
        releaseUrl: "",
        errorCode: "",
        errorDetail: "",
        notificationKind: ""
    }
}
