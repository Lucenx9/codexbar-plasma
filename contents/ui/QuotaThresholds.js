.pragma library

var minimumPercent = 1
var maximumPercent = 100
// Warning must leave room for a distinct critical step above it.
var maximumWarningPercent = 99
var defaultWarningPercent = 80
var defaultCriticalPercent = 95

// Plasmoid.configuration returns whatever is on disk, and Number(null) is 0
// rather than NaN, so an unset or corrupted entry would silently become a
// 1% threshold that fires on every provider. Treat every non-number as absent.
function numericPercent(value) {
    if (value === null || value === undefined || value === "" || typeof value === "boolean") {
        return Number.NaN
    }
    return Number(value)
}

function boundedPercent(value, fallback, minimum, maximum) {
    var numeric = numericPercent(value)
    if (!isFinite(numeric)) {
        return fallback
    }
    return Math.max(minimum, Math.min(maximum, Math.floor(numeric)))
}

function warningPercent(value) {
    return boundedPercent(value, defaultWarningPercent, minimumPercent, maximumWarningPercent)
}

// A critical threshold below the warning threshold would make "major"
// unreachable, so the invariant is enforced here rather than at each call site.
function criticalPercent(warning, value) {
    var bounded = boundedPercent(value, defaultCriticalPercent, minimumPercent, maximumPercent)
    var floor = boundedPercent(warning, defaultWarningPercent, minimumPercent, maximumWarningPercent)
    return Math.max(floor, bounded)
}

function level(usedPercent, warning, critical) {
    var used = numericPercent(usedPercent)
    if (!isFinite(used)) {
        return ""
    }
    if (used >= critical) {
        return "major"
    }
    if (used >= warning) {
        return "minor"
    }
    return ""
}

// The meter can count down instead of up, so a threshold expressed on "used"
// has to be mirrored to land on the same physical point of the track.
function markers(warning, critical, barsShowUsed) {
    var boundedWarning = warningPercent(warning)
    var boundedCritical = criticalPercent(boundedWarning, critical)
    return [
        {
            percent: barsShowUsed ? boundedWarning : maximumPercent - boundedWarning,
            severity: "minor"
        },
        {
            percent: barsShowUsed ? boundedCritical : maximumPercent - boundedCritical,
            severity: "major"
        }
    ]
}
