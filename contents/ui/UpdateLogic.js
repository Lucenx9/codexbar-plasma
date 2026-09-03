.pragma library
.import "Guards.js" as Guards

var maximumResultStatusLength = 64
var maximumVersionLength = 128
var maximumAssetUrlLength = 2048
var maximumErrorCodeLength = 128
var maximumErrorDetailLength = 500

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

function updateCheckDue(updateChecksEnabled, lastCheck, intervalHours, nowMs, forceCheck) {
    if (!updateChecksEnabled) {
        return false
    }
    if (forceCheck === true) {
        return true
    }

    var lastCheckMs = Date.parse(String(lastCheck || ""))
    if (!isFinite(lastCheckMs)) {
        return true
    }

    var hours = Number(intervalHours)
    if (!isFinite(hours) || hours <= 0) {
        return true
    }
    var elapsedMs = Number(nowMs) - lastCheckMs
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
    var lastCheckMs = Date.parse(String(lastCheck || ""))
    if (!isFinite(lastCheckMs)) {
        return minimum
    }

    var now = Number(nowMs)
    if (now < lastCheckMs) {
        return minimum
    }
    var remainingMs = lastCheckMs + intervalMs - now
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
        errorCode: "",
        errorDetail: "",
        notificationKind: ""
    }
}
