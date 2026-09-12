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

// A failed attempt delays automatic retries without making its snapshot fresh.
// QML records attempt completion and clears it whenever the command source changes.
function lastActivityAtMs(current) {
    var source = current && typeof current === "object"
        && !Array.isArray(current) ? current : ({})
    var finished = source.lastFinishedAtMs
    var baseline = typeof finished === "number" && isFinite(finished) && finished >= 0
        ? finished : -1
    var completed = source.lastCompletedAtMs
    if (typeof source.loadedCommandSource === "string"
            && typeof source.commandSource === "string"
            && source.loadedCommandSource.trim() === source.commandSource.trim()
            && typeof completed === "number" && isFinite(completed) && completed >= 0) {
        baseline = Math.max(baseline, completed)
    }
    return baseline
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

    var activityAtMs = lastActivityAtMs(current)
    if (activityAtMs < 0) {
        return startAction
    }
    var nowMs = current.nowMs
    if (typeof nowMs !== "number" || !isFinite(nowMs) || nowMs < activityAtMs) {
        return startAction
    }
    var maximumAgeMs = typeof current.staleAfterMs === "number"
        && isFinite(current.staleAfterMs) && current.staleAfterMs > 0
        ? Math.floor(current.staleAfterMs)
        : defaultStaleAfterMs
    return nowMs - activityAtMs >= maximumAgeMs ? startAction : keepAction
}

function nextCheckDelay(observation) {
    var current = observation && typeof observation === "object"
        && !Array.isArray(observation) ? observation : ({})
    var commandSource = typeof current.commandSource === "string"
        ? current.commandSource.trim() : ""
    if (current.visible !== true || current.loading === true
            || commandSource.length === 0) {
        return 0
    }

    var maximumAgeMs = typeof current.staleAfterMs === "number"
        && isFinite(current.staleAfterMs) && current.staleAfterMs > 0
        ? Math.floor(current.staleAfterMs)
        : defaultStaleAfterMs
    if (refreshAction(current) !== keepAction) {
        return maximumAgeMs
    }
    var ageMs = current.nowMs - lastActivityAtMs(current)
    return Math.max(1, maximumAgeMs - ageMs)
}
