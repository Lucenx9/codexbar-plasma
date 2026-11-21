.pragma library
.import "Guards.js" as Guards

var keepAction = "keep"
var startAction = "start"
var missingCommandAction = "missingCommand"
// The CLI reports a session as active only within a short activity window, so
// an open Sessions tab rescans at this cadence, like the macOS app's local
// session monitor, even when usage refreshes less often or not at all.
var defaultStaleAfterMs = 30000

function staleAfterMs(refreshIntervalSeconds) {
    if (typeof refreshIntervalSeconds !== "number"
            || !isFinite(refreshIntervalSeconds)
            || refreshIntervalSeconds <= 0) {
        return defaultStaleAfterMs
    }
    return Math.min(defaultStaleAfterMs,
        Math.max(1000, Math.floor(refreshIntervalSeconds * 1000)))
}

// A failed attempt delays automatic retries without making its snapshot fresh.
// QML records attempt completion and clears it whenever the command source changes.
function lastActivityAtMs(current) {
    var source = Guards.isRecord(current) ? current : ({})
    var finished = source.lastFinishedAtMs
    // The most recent scan may finish before a retained snapshot's wall-clock
    // timestamp after a clock rollback. Its cooldown still starts at finish.
    if (Guards.isFiniteNumber(finished) && finished >= 0) {
        return finished
    }
    var completed = source.lastCompletedAtMs
    if (typeof source.loadedCommandSource === "string"
            && typeof source.commandSource === "string"
            && source.loadedCommandSource.trim() === source.commandSource.trim()
            && Guards.isFiniteNumber(completed) && completed >= 0) {
        return completed
    }
    return -1
}

function maximumAgeMs(current) {
    return typeof current.staleAfterMs === "number"
        && isFinite(current.staleAfterMs) && current.staleAfterMs > 0
        ? Math.floor(current.staleAfterMs)
        : defaultStaleAfterMs
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
    return nowMs - activityAtMs >= maximumAgeMs(current) ? startAction : keepAction
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

    if (refreshAction(current) !== keepAction) {
        return maximumAgeMs(current)
    }
    var ageMs = current.nowMs - lastActivityAtMs(current)
    return Math.max(1, maximumAgeMs(current) - ageMs)
}
