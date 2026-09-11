.pragma library

var automaticRefreshIntervalMs = 60 * 60 * 1000
var clearAction = "clear"
var keepAction = "keep"
var startAction = "start"

function padDayPart(value) {
    return (value < 10 ? "0" : "") + String(value)
}

// Local calendar bucket for spend history. Day changes (including timezone
// shifts that move the local date) make yesterday's snapshot stale even when
// the hourly attempt cooldown has not elapsed. Returns "" for unusable input.
function bucketDayForMs(nowMs) {
    var now = Number(nowMs)
    if (!isFinite(now) || now < 0) {
        return ""
    }
    var date = new Date(now)
    if (isNaN(date.getTime())) {
        return ""
    }
    return date.getFullYear() + "-" + padDayPart(date.getMonth() + 1)
        + "-" + padDayPart(date.getDate())
}

// True only when two valid timestamps fall on different local days with a
// forward clock. Rollbacks and invalid input stay false: the hourly baseline
// already restarts on rollback, and invalid clocks keep the current state.
function isNewBucketDay(lastAttemptAtMs, nowMs) {
    var previous = Number(lastAttemptAtMs)
    var now = Number(nowMs)
    if (!isFinite(previous) || previous < 0 || !isFinite(now) || now < 0
            || now < previous) {
        return false
    }
    var previousDay = bucketDayForMs(previous)
    var currentDay = bucketDayForMs(now)
    return previousDay.length > 0 && currentDay.length > 0
        && previousDay !== currentDay
}

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
    // A calendar-day change makes the snapshot stale even within the hour.
    // Loading already returned keep above, so an active scan is never replaced.
    if (isNewBucketDay(previous, now)) {
        return startAction
    }
    return now - previous >= automaticRefreshIntervalMs ? startAction : keepAction
}
