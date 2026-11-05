// A year of normalized days plus the two partial weeks at its ends.
var maximumCells = 378

function count(cells) {
    return Array.isArray(cells) && cells.length <= maximumCells ? cells.length : 0
}

function dayAt(cells, index) {
    if (!Number.isInteger(index) || index < 0 || index >= count(cells)) {
        return ""
    }
    var cell = cells[index]
    return cell && typeof cell.label === "string" && cell.label.length <= 256
        ? cell.label : ""
}

function indexForDay(cells, day) {
    if (typeof day !== "string" || day.length === 0) {
        return -1
    }
    for (var i = 0; i < count(cells); i++) {
        if (dayAt(cells, i) === day) {
            return i
        }
    }
    return -1
}

// The grid fills columns top to bottom. Horizontal movement keeps the weekday;
// vertical movement stays in the week. Missing days never become selections.
function nextDay(cells, currentDay, direction, mirrored) {
    var size = count(cells)
    var index = indexForDay(cells, currentDay)
    var step = 0
    switch (direction) {
    case "first": step = 1; index = -1; break
    case "last": step = -1; index = size; break
    case "up": step = -1; break
    case "down": step = 1; break
    case "left": step = mirrored === true ? 7 : -7; break
    case "right": step = mirrored === true ? -7 : 7; break
    default: return dayAt(cells, index)
    }
    if (index < 0 && direction !== "first") {
        return nextDay(cells, "", step < 0 ? "last" : "first", false)
    }
    for (var next = index + step; next >= 0 && next < size; next += step) {
        if ((direction === "up" || direction === "down")
            && Math.floor(next / 7) !== Math.floor(index / 7)) {
            break
        }
        if (dayAt(cells, next).length > 0) {
            return dayAt(cells, next)
        }
    }
    return dayAt(cells, index)
}
