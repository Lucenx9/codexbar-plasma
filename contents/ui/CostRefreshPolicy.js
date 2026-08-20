.pragma library

var automaticRefreshIntervalMs = 60 * 60 * 1000
var clearAction = "clear"
var keepAction = "keep"
var startAction = "start"

function refreshAction(commandAvailable, loading, forced, lastAttemptAtMs, nowMs) {
    if (commandAvailable !== true) {
        return clearAction
    }
    if (forced === true) {
        return startAction
    }
    if (loading === true) {
        return keepAction
    }

    var now = Number(nowMs)
    if (!isFinite(now) || now < 0) {
        return keepAction
    }

    var previous = Number(lastAttemptAtMs)
    if (typeof lastAttemptAtMs !== "number" || !isFinite(previous)
            || previous < 0 || now < previous) {
        return startAction
    }
    return now - previous >= automaticRefreshIntervalMs ? startAction : keepAction
}
