.pragma library

var defaultOrder = ["identity", "status", "text", "meters"]

function normalizedOrder(value) {
    var source = Array.isArray(value)
        ? value.slice(0, defaultOrder.length * 2)
        : String(value || "").slice(0, 512).split(",")
    var result = []
    var seen = ({})

    for (var i = 0; i < source.length; i++) {
        var candidate = String(source[i] || "").trim()
        if (defaultOrder.indexOf(candidate) === -1 || seen[candidate]) {
            continue
        }
        seen[candidate] = true
        result.push(candidate)
    }

    for (var j = 0; j < defaultOrder.length; j++) {
        var fallback = defaultOrder[j]
        if (!seen[fallback]) {
            result.push(fallback)
        }
    }
    return result
}

function serializedOrder(value) {
    return normalizedOrder(value).join(",")
}

function movedOrder(value, index, delta) {
    var order = normalizedOrder(value)
    var from = Number(index)
    var offset = Number(delta)
    if (!isFinite(from) || !isFinite(offset)) {
        return order
    }

    from = Math.floor(from)
    var target = from + Math.floor(offset)
    if (from < 0 || from >= order.length || target < 0 || target >= order.length) {
        return order
    }

    var item = order[from]
    order.splice(from, 1)
    order.splice(target, 0, item)
    return order
}
