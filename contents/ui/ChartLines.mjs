import * as Guards from "./Guards.mjs";
import * as Geometry from "./CostChart.mjs";

function boundedList(value, limit) {
    return Array.isArray(value) ? value.slice(0, limit) : []
}

function dayNumber(label) {
    if (typeof label !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(label)) return null
    var time = Date.parse(label + "T12:00:00Z")
    return isFinite(time) && new Date(time).toISOString().slice(0, 10) === label
        ? Math.floor(time / 86400000) : null
}

function indexedDays(points) {
    var dates = ({})
    for (var point of boundedList(points, 365)) {
        var day = dayNumber(point && point.label)
        if (day === null) continue
        dates[day] = Guards.hasOwnKey(dates, day) ? {label: point.label, value: null} : point
    }
    return dates
}

// Missing days occupy calendar space without becoming measured zeroes.
export function calendarPoints(points) {
    var dates = indexedDays(points)
    var days = Object.keys(dates).map(Number).sort(function(a, b) { return a - b })
    if (!days.length) return []
    var last = days[days.length - 1]
    var first = Math.max(days[0], last - 364)
    return Array.from({length: last - first + 1}, function(_, index) {
        var day = first + index
        return dates[day] || {label: new Date(day * 86400000).toISOString().slice(0, 10), value: null}
    })
}

function known(point) {
    return Guards.isRecord(point) && Guards.isFiniteNumber(point.value) && point.value >= 0
}

function lineMaximum(line) {
    return boundedList(line && line.points, 365).reduce(function(maximum, point) {
        return known(point) ? Math.max(maximum, point.value) : maximum
    }, 0)
}

export function domain(series) {
    var maximum = boundedList(series, 128).reduce(function(peak, line) {
        return Math.max(peak, lineMaximum(line))
    }, 0)
    return {minimum: 0, maximum: niceMaximum(maximum)}
}

// Leave room above the peak and use readable ticks, without overflowing.
function niceMaximum(maximum) {
    if (maximum === 0) return 0
    var target = maximum * 1.05
    var unit = Math.pow(10, Math.floor(Math.log(target) / Math.LN10))
    if (!isFinite(target) || !isFinite(unit) || unit === 0) return maximum
    for (var step of [1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]) {
        var rounded = step * unit
        if (isFinite(rounded) && rounded >= target) return rounded
    }
    return maximum
}

function segmentSlopes(run) {
    return run.slice(1).map(function(point, index) {
        var span = point.x - run[index].x
        return span > 0 ? (point.y - run[index].y) / span : 0
    })
}

function tangent(before, after) {
    return before * after > 0 ? 2 / (1 / before + 1 / after) : 0
}

// Equally spaced calendar samples use harmonic-mean tangents. Only plateaus
// and turning points get horizontal tangents; each segment stays monotone.
function curve(run) {
    var slopes = segmentSlopes(run)
    var tangents = slopes.slice(1).map(function(slope, index) { return tangent(slopes[index], slope) })
    tangents.unshift(slopes[0] || 0)
    tangents.push(slopes[slopes.length - 1] || 0)
    for (var k = 1; k < run.length; k++) {
        var third = (run[k].x - run[k - 1].x) / 3
        run[k].c1 = {x: run[k - 1].x + third, y: run[k - 1].y + tangents[k - 1] * third}
        run[k].c2 = {x: run[k].x - third, y: run[k].y - tangents[k] * third}
    }
    return run
}

function projectSample(point, index, count, geometry) {
    if (!known(point)) return null
    var day = dayNumber(point.label)
    if (day === null) return null
    return {index: index, day: day,
        x: Geometry.chartLineX(geometry.width, count, index, geometry.inset),
        y: Geometry.chartLineY(geometry.height, geometry.maximum > 0 ? point.value / geometry.maximum : 0, geometry.inset)}
}

function continuousRuns(samples) {
    var result = []
    var run = []
    for (var sample of samples) {
        var previous = run[run.length - 1]
        var consecutive = !previous || (sample && sample.day === previous.day + 1)
        if (!sample || !consecutive) {
            if (run.length) result.push(run)
            run = []
        }
        if (sample) run.push(sample)
    }
    if (run.length) result.push(run)
    return result
}

// Split before projecting curves so missing dates never become connecting lines.
export function paths(points, geometry) {
    var source = boundedList(points, 365)
    var samples = source.map(function(point, index) { return projectSample(point, index, source.length, geometry) })
    return continuousRuns(samples).map(curve)
}
