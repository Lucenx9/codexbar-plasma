.pragma library

function costSparklineMax(points) {
    var maxCost = 0
    if (!points) {
        return maxCost
    }
    for (var i = 0; i < points.length; i++) {
        maxCost = Math.max(maxCost, Number(points[i].cost) || 0)
    }
    return maxCost
}
