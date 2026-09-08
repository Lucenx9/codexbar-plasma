.pragma library

var defaultStaleAfterMs = 300000

function staleAfterMs(refreshIntervalSeconds) {
    return typeof refreshIntervalSeconds === "number"
        && isFinite(refreshIntervalSeconds) && refreshIntervalSeconds > 0
        ? Math.max(1000, Math.min(3600000, Math.floor(refreshIntervalSeconds * 1000)))
        : defaultStaleAfterMs
}

function validTimestamp(value) {
    return typeof value === "number" && isFinite(value) && value >= 0
}

function shouldRefresh(observation) {
    var current = observation && typeof observation === "object"
        && !Array.isArray(observation) ? observation : ({})
    if (current.enabled !== true || current.visible !== true
            || current.loading === true || current.scheduled === true
            || typeof current.commandSource !== "string"
            || current.commandSource.trim().length === 0
            || !validTimestamp(current.nowMs)) {
        return false
    }

    // Failed attempts also get a cooldown: reopening a popup must not turn
    // an unavailable provider into a tight retry loop. Manual refresh is separate.
    var lastActivityAtMs = -1
    if (validTimestamp(current.lastAttemptAtMs)) {
        lastActivityAtMs = current.lastAttemptAtMs
    }
    if (validTimestamp(current.lastCompletedAtMs)) {
        lastActivityAtMs = Math.max(lastActivityAtMs, current.lastCompletedAtMs)
    }
    return lastActivityAtMs < 0 || current.nowMs < lastActivityAtMs
        || current.nowMs - lastActivityAtMs >= staleAfterMs(current.refreshIntervalSeconds)
}
