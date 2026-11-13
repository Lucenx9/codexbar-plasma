import * as Guards from "./Guards.mjs";

// Invalid or incomplete splits fall back to the aggregate bar.
export function stackedBarSegments(point, height, baseline) {
    if (!stackablePoint(point)) return []
    var segments = point.segments
    if (!segments.every(validSegment)) return []
    var total = segments.reduce(function(sum, segment) { return sum + segment.value }, 0)
    if (total !== point.value) return []
    var bottom = Math.max(0, baseline)
    return segments.map(function(segment, index) {
        var size = Math.max(0, height) * (segment.value / total)
        var result = {provider: segment.provider, height: size, baseline: bottom,
            rounded: index === segments.length - 1}
        bottom -= size
        return result
    })
}

function stackablePoint(point) {
    return Guards.isRecord(point) && Array.isArray(point.segments)
        && point.segments.length <= 128 && Guards.isFiniteNumber(point.value) && point.value > 0
}

function validSegment(segment) {
    return Guards.isRecord(segment) && typeof segment.provider === "string"
        && Guards.isFiniteNumber(segment.value) && segment.value > 0
}
