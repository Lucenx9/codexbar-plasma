.pragma library

function pointValue(point) {
    var value = point && point.value !== undefined ? Number(point.value) : 0
    return isFinite(value) ? value : 0
}

// Both signed detail points and nonnegative cost points arrive normalized.
// Include zero so bar direction and line positions use the same domain.
function domain(points) {
    var minimum = 0
    var maximum = 0
    var items = points && typeof points.length === "number" ? points : []
    for (var i = 0; i < items.length; i++) {
        var value = pointValue(items[i])
        minimum = Math.min(minimum, value)
        maximum = Math.max(maximum, value)
    }
    return {
        minimum: minimum,
        maximum: maximum
    }
}

function fraction(value, domain) {
    var minimumValue = domain ? Number(domain.minimum) : Number.NaN
    var maximumValue = domain ? Number(domain.maximum) : Number.NaN
    if (!isFinite(minimumValue) || !isFinite(maximumValue)) {
        return 0
    }
    var numericValue = Number(value)
    if (!isFinite(numericValue)) {
        return 0
    }
    domain = { minimum: minimumValue, maximum: maximumValue }
    var magnitude = Math.max(-domain.minimum, domain.maximum)
    if (magnitude === 0) {
        return 0
    }
    // Divide first so the span of finite signed extremes cannot overflow.
    var minimum = domain.minimum / magnitude
    var maximum = domain.maximum / magnitude
    return Math.max(0, Math.min(1, (numericValue / magnitude - minimum) / (maximum - minimum)))
}

function barGeometry(height, value, domain) {
    var bottom = Math.max(0, height - 1)
    var plotHeight = Math.max(0, height - 3)
    var zeroFraction = fraction(0, domain)
    var baseline = bottom - plotHeight * zeroFraction
    var valueFraction = fraction(value, domain)
    var negative = value < 0
    var availableHeight = negative ? bottom - baseline : baseline
    var barHeight = value !== 0 ? Math.max(2, plotHeight * Math.abs(valueFraction - zeroFraction)) : 1
    return {
        baseline: baseline,
        height: Math.min(availableHeight, barHeight),
        negative: negative
    }
}
