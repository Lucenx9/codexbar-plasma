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
    return Number(nowMs) - lastCheckMs >= hours * 60 * 60 * 1000
}
