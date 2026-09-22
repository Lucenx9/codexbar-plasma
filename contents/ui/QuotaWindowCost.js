.pragma library

// Splits a provider's local daily cost history by its live quota window, so a
// weekly limit can be read against what that week actually cost. No CLI
// contract backs this: the window comes from the usage row's `resetsAt` and
// `windowMinutes`, and the amounts from the daily history the widget already
// holds.
//
// The history is day-granular while a window resets at an arbitrary instant.
// A whole day is attributed to the window containing its local midnight, and
// a boundary that falls inside a day is reported as estimated rather than
// presented as exact. A window reaching back before the scanned history is
// dropped instead of being shown as a complete week with missing days.

var maximumWindows = 4
var minimumWindowMinutes = 24 * 60
var maximumWindowMinutes = 366 * 24 * 60

function dayRange(label) {
    var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(typeof label === "string" ? label : "")
    if (!match) {
        return null
    }
    var year = Number(match[1])
    var month = Number(match[2]) - 1
    var day = Number(match[3])
    var start = new Date(year, month, day)
    // Reject dates the constructor silently rolled over, such as 2026-02-30.
    if (start.getFullYear() !== year || start.getMonth() !== month || start.getDate() !== day) {
        return null
    }
    return {startMs: start.getTime(), endMs: new Date(year, month, day + 1).getTime()}
}

function isLocalMidnight(timestampMs) {
    var date = new Date(timestampMs)
    return date.getHours() === 0 && date.getMinutes() === 0
        && date.getSeconds() === 0 && date.getMilliseconds() === 0
}

// `expectedDays` counts every scanned local date in the window, so a date the
// history is missing counts as unknown rather than silently as nothing.
function metricTotal(days, field, expectedDays) {
    var sum = 0
    var known = 0
    for (var i = 0; i < days.length; i++) {
        var value = days[i][field]
        if (typeof value === "number" && isFinite(value)) {
            var next = sum + value
            // Two finite values can still overflow; that total is unknown.
            if (!isFinite(next)) {
                return {value: null, partial: false}
            }
            sum = next
            known += 1
        }
    }
    return {
        value: known > 0 ? sum : null,
        // Some days measured, others unknown: the sum is a lower bound.
        partial: known > 0 && known < expectedDays
    }
}

// Local midnights in [startMs, endMs) that fall inside the scanned history.
function expectedDayCount(startMs, endMs, scanStartMs, scanLastMs) {
    var cursor = new Date(startMs)
    if (!isLocalMidnight(startMs)) {
        cursor = new Date(cursor.getFullYear(), cursor.getMonth(), cursor.getDate() + 1)
    }
    var count = 0
    while (cursor.getTime() < endMs && cursor.getTime() <= scanLastMs) {
        if (cursor.getTime() >= scanStartMs) {
            count += 1
        }
        cursor = new Date(cursor.getFullYear(), cursor.getMonth(), cursor.getDate() + 1)
    }
    return count
}

// `daily`: normalized rows `{label: "YYYY-MM-DD", cost, tokens}` covering the
// scanned history. Returns windows newest first, each with exact instants,
// the attributed amounts, and which boundaries are day-estimated. Returns an
// empty list whenever the inputs cannot support an honest split.
function windows(daily, resetsAtMs, windowMinutes, nowMs, limit) {
    if (!Array.isArray(daily) || daily.length === 0
            || typeof resetsAtMs !== "number" || !isFinite(resetsAtMs)
            || typeof nowMs !== "number" || !isFinite(nowMs)
            || typeof windowMinutes !== "number" || !isFinite(windowMinutes)
            || Math.floor(windowMinutes) !== windowMinutes
            || windowMinutes < minimumWindowMinutes || windowMinutes > maximumWindowMinutes) {
        return []
    }
    // A reset already in the past means the usage row is stale; deriving
    // windows from it would label last week as the current one.
    if (resetsAtMs <= nowMs) {
        return []
    }

    var days = []
    for (var i = 0; i < daily.length; i++) {
        var range = daily[i] ? dayRange(daily[i].label) : null
        if (!range) {
            return []
        }
        days.push({startMs: range.startMs, cost: daily[i].cost, tokens: daily[i].tokens})
    }
    days.sort(function(left, right) { return left.startMs - right.startMs })
    // A date reported twice cannot be attributed honestly: summing both would
    // double count it and picking one would guess.
    for (var d = 1; d < days.length; d++) {
        if (days[d].startMs === days[d - 1].startMs) {
            return []
        }
    }
    var scanStartMs = days[0].startMs
    var scanLastMs = days[days.length - 1].startMs

    var count = typeof limit === "number" && limit >= 1 ? Math.min(Math.floor(limit), maximumWindows) : maximumWindows
    var windowMs = windowMinutes * 60 * 1000
    var result = []
    for (var index = 0; index < count; index++) {
        var endMs = resetsAtMs - index * windowMs
        var startMs = endMs - windowMs
        // The first local midnight attributed to this window must have been
        // scanned; otherwise this and every older window is truncated.
        var firstMidnight = new Date(startMs)
        if (!isLocalMidnight(startMs)) {
            firstMidnight = new Date(firstMidnight.getFullYear(), firstMidnight.getMonth(), firstMidnight.getDate() + 1)
        }
        if (firstMidnight.getTime() < scanStartMs) {
            break
        }
        var attributed = days.filter(function(day) { return day.startMs >= startMs && day.startMs < endMs })
        // Right after a mid-day reset the current window holds no local
        // midnight yet: today belongs to the previous window. Skip it rather
        // than stop, or every earlier week would disappear with it.
        if (attributed.length === 0) {
            continue
        }
        var expected = expectedDayCount(startMs, endMs, scanStartMs, scanLastMs)
        var cost = metricTotal(attributed, "cost", expected)
        var tokens = metricTotal(attributed, "tokens", expected)
        result.push({
            startMs: startMs,
            endMs: endMs,
            current: index === 0,
            startEstimated: !isLocalMidnight(startMs),
            endEstimated: !isLocalMidnight(endMs),
            dayCount: attributed.length,
            cost: cost.value,
            costPartial: cost.partial,
            tokens: tokens.value,
            tokensPartial: tokens.partial
        })
    }
    return result
}
