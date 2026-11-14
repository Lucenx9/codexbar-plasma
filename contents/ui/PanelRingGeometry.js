.pragma library

function layout(diameter, count) {
    var size = typeof diameter === "number" && isFinite(diameter)
        ? Math.max(16, Math.min(48, diameter)) : 16;
    var rings = count === 2 ? 2 : count === 1 ? 1 : 0;
    var stroke = Math.max(1.25, Math.min(2.5, size / 14));
    var step = stroke + Math.max(1.25, size / 24);
    var outerRadius = (size - stroke) / 2 - 0.5;
    var radii = [];
    for (var index = 0; index < rings; index++) {
        radii.push(outerRadius - step * index);
    }
    var innerEdge = rings > 0 ? radii[rings - 1] - stroke / 2 : size / 2;
    return {
        diameter: size,
        strokeWidth: stroke,
        radii: radii,
        logoSize: Math.max(6, Math.floor((innerEdge - 1.5) * 2))
    };
}

function arc(percent, radius, strokeWidth) {
    var value = typeof percent === "number" && isFinite(percent)
        ? Math.max(0, Math.min(100, percent)) : 0;
    var circumference = 2 * Math.PI * radius;
    var length = value > 0 ? Math.max(1, circumference * value / 100) : 0;
    // Rounded caps add a stroke's length. Short arcs use flat caps so a tiny
    // positive reading cannot look like a substantial dot or a full quota.
    var rounded = value < 100 && length > strokeWidth * 2;
    return {
        startAngle: -90 + (rounded ? strokeWidth / circumference * 180 : 0),
        sweepAngle: Math.min(360, Math.max(0, length - (rounded ? strokeWidth : 0)) / circumference * 360),
        rounded: rounded
    };
}
