.pragma library

var percentMode = "percent";
var paceMode = "pace";
var bothMode = "both";
var resetTimeMode = "resetTime";
var runOutMode = "runOut";

function safeMode(value) {
    var mode = String(value || percentMode);
    if (mode === percentMode || mode === paceMode || mode === bothMode || mode === resetTimeMode || mode === runOutMode) {
        return mode;
    }
    return percentMode;
}

function hasFiniteNumber(value) {
    return typeof value === "number" && isFinite(value);
}

function rowHasPercent(row) {
    return row !== null && row !== undefined && row.hasPercent === true && hasFiniteNumber(row.usedPercent) && hasFiniteNumber(row.leftPercent);
}

function rowHasPace(row) {
    return row !== null && row !== undefined && hasFiniteNumber(row.pacePercent) && row.pacePercent >= 0;
}

function rowHasReset(row) {
    if (!row) {
        return false;
    }
    return (typeof row.resetsAt === "string" && row.resetsAt.trim().length > 0) || (typeof row.resetDescription === "string" && row.resetDescription.trim().length > 0) || (typeof row.reset === "string" && row.reset.trim().length > 0);
}

function rowHasRunOut(row) {
    return row !== null && row !== undefined && row.paceOnTop === false && hasFiniteNumber(row.paceEtaSeconds) && row.paceEtaSeconds > 0;
}

function rowSupportsMode(row, value) {
    var mode = safeMode(value);
    switch (mode) {
    case paceMode:
        return rowHasPace(row);
    case bothMode:
        return rowHasPercent(row) || rowHasPace(row);
    case resetTimeMode:
        return rowHasReset(row);
    case runOutMode:
        return rowHasRunOut(row);
    default:
        return rowHasPercent(row);
    }
}

// The caller supplies provider-specific preference order. This function only
// decides whether a row carries the data required by the selected mode.
function rowForMode(rows, value) {
    if (!Array.isArray(rows)) {
        return null;
    }
    var mode = safeMode(value);
    if (mode === bothMode) {
        for (var i = 0; i < rows.length; i++) {
            if (rowHasPercent(rows[i]) && rowHasPace(rows[i])) {
                return rows[i];
            }
        }
    }
    for (var j = 0; j < rows.length; j++) {
        if (rowSupportsMode(rows[j], mode)) {
            return rows[j];
        }
    }
    return null;
}

// Forecast ETA is a duration observed with one usage snapshot, not an absolute
// timestamp. Advance it from that observation without triggering another CLI run.
function remainingSeconds(durationSeconds, observedAtMs, nowMs) {
    if (!hasFiniteNumber(durationSeconds) || durationSeconds < 0 || !hasFiniteNumber(observedAtMs) || !hasFiniteNumber(nowMs)) {
        return 0;
    }
    var elapsedSeconds = Math.max(0, (nowMs - observedAtMs) / 1000);
    return Math.max(0, durationSeconds - elapsedSeconds);
}
