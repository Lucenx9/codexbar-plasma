.pragma library

var keepAction = "keep"
var startAction = "start"
var missingCommandAction = "missingCommand"
var defaultStaleAfterMs = 300000

function staleAfterMs(refreshIntervalSeconds) {
    if (typeof refreshIntervalSeconds !== "number"
            || !isFinite(refreshIntervalSeconds)
            || refreshIntervalSeconds <= 0) {
        return defaultStaleAfterMs
    }
    return Math.max(1000, Math.floor(refreshIntervalSeconds * 1000))
}

function refreshAction(observation) {
    var current = observation && typeof observation === "object"
        && !Array.isArray(observation) ? observation : ({})
    var forced = current.force === true
    if (!forced && current.visible !== true) {
        return keepAction
    }
    if (current.loading === true) {
        return keepAction
    }

    var commandSource = typeof current.commandSource === "string"
        ? current.commandSource.trim() : ""
    if (commandSource.length === 0) {
        return missingCommandAction
    }
    if (forced) {
        return startAction
    }

    var loadedCommandSource = typeof current.loadedCommandSource === "string"
        ? current.loadedCommandSource.trim() : ""
    if (loadedCommandSource !== commandSource) {
        return startAction
    }

    var completedAtMs = current.lastCompletedAtMs
    if (typeof completedAtMs !== "number" || !isFinite(completedAtMs)
            || completedAtMs < 0) {
        return startAction
    }
    var nowMs = current.nowMs
    if (typeof nowMs !== "number" || !isFinite(nowMs) || nowMs < completedAtMs) {
        return startAction
    }
    var maximumAgeMs = typeof current.staleAfterMs === "number"
        && isFinite(current.staleAfterMs) && current.staleAfterMs > 0
        ? Math.floor(current.staleAfterMs)
        : defaultStaleAfterMs
    return nowMs - completedAtMs >= maximumAgeMs ? startAction : keepAction
}
