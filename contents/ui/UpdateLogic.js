.pragma library

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
