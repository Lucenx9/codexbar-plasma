import * as Guards from "./Guards.mjs";
import * as Normalizer from "./ProviderNormalizer.mjs";
import * as CostAmounts from "./CostAmounts.mjs";

// Cost chart geometry, point selection, and calendar heatmap layout.
// Only paintRoundedTopBar draws, using the canvas supplied by its QML owner.

export var maximumCostHistoryPoints = 365

// Dense charts keep a one-pixel bar, so their drawing step must account for the
// bar width instead of the nominal point slot. Otherwise the newest bar extends
// beyond the right edge of the canvas.
export function chartBarGeometry(width, count) {
    var safeWidth = nonNegative(width)
    var points = pointCount(count, 1)
    var slotStep = safeWidth / points
    var gap = Math.max(0, Math.min(4, slotStep / 4))
    var barWidth = Math.max(1, slotStep - gap)

    if (barWidth > slotStep) {
        return {
            step: points > 1 ? Math.max(0, safeWidth - barWidth) / (points - 1) : 0,
            gap: gap,
            barWidth: barWidth,
            offset: 0
        }
    }

    return {
        step: slotStep,
        gap: gap,
        barWidth: barWidth,
        offset: Math.max(0, slotStep - barWidth) / 2
    }
}

// Keep the largest interactive marker fully inside the canvas at both ends.
export function chartLineX(width, count, index, inset) {
    var safeWidth = nonNegative(width)
    var points = pointCount(count, 1)
    var padding = Math.min(safeWidth / 2, nonNegative(inset))

    if (points === 1) {
        return safeWidth / 2
    }

    var numericIndex = Math.floor(Number(index))
    var boundedIndex = isFinite(numericIndex)
        ? Math.max(0, Math.min(points - 1, numericIndex))
        : 0
    return padding + (safeWidth - padding * 2) * boundedIndex / (points - 1)
}

export function chartLineIndexAt(width, count, positionX, inset) {
    var safeWidth = nonNegative(width)
    var points = pointCount(count, 0)
    if (points === 0 || safeWidth === 0) {
        return -1
    }
    if (points === 1) {
        return 0
    }

    var padding = Math.min(safeWidth / 2, nonNegative(inset))
    var boundedPosition = Math.min(safeWidth, nonNegative(positionX))
    var drawableWidth = safeWidth - padding * 2
    var normalizedPosition = drawableWidth > 0
        ? (boundedPosition - padding) / drawableWidth
        : boundedPosition / safeWidth
    return Math.max(0, Math.min(points - 1,
        Math.round(normalizedPosition * (points - 1))))
}

export function chartLineY(height, fraction, inset) {
    var safeHeight = nonNegative(height)
    var padding = Math.min(safeHeight / 2, nonNegative(inset))
    var boundedFraction = Math.min(1, nonNegative(fraction))
    return safeHeight - padding - (safeHeight - padding * 2) * boundedFraction
}

// Prefer the right of the inspected day; flip or constrain the preview to the
// roomier side rather than covering the guide and its provider markers.
export function chartPreviewGeometry(width, anchor, preferredWidth, gap) {
    var safeWidth = nonNegative(width)
    var x = Math.min(safeWidth, nonNegative(anchor))
    var spacing = Math.min(safeWidth / 2, nonNegative(gap))
    var left = Math.max(0, x - spacing)
    var right = Math.max(0, safeWidth - x - spacing)
    var wanted = nonNegative(preferredWidth)
    var useRight = wanted <= right || right >= left
    var size = Math.min(wanted, useRight ? right : left)
    return {x: useRight ? Math.min(safeWidth, x + spacing) : Math.max(0, x - spacing - size), width: size}
}

export function paintRoundedTopBar(context, bounds, radius) {
    var x = bounds.x
    var baseline = bounds.baseline
    var safeWidth = nonNegative(bounds.width)
    var safeHeight = nonNegative(bounds.height)
    var top = baseline - safeHeight
    var corner = Math.max(0, Math.min(radius, safeWidth / 2, safeHeight))

    context.beginPath()
    context.moveTo(x, baseline)
    context.lineTo(x, top + corner)
    context.quadraticCurveTo(x, top, x + corner, top)
    context.lineTo(x + safeWidth - corner, top)
    context.quadraticCurveTo(x + safeWidth, top, x + safeWidth, top + corner)
    context.lineTo(x + safeWidth, baseline)
    context.closePath()
    context.fill()
}

export function chartPoints(fmt, points, showsTokens) {
    var result = []
    if (!Array.isArray(points)) {
        return result
    }
    for (var i = 0; i < points.length; i++) {
        var point = points[i]
        if (!CostAmounts.hasMetricValue(point, showsTokens)) {
            continue
        }
        var value = Math.max(0, CostAmounts.metricValue(point, showsTokens))
        result.push({
            label: CostAmounts.boundedText(point.label, 120),
            sourceIndex: i,
            value: value,
            displayValue: CostAmounts.metricText(fmt, value, point.currency, showsTokens)
        })
    }
    return result
}

// Returns the previous points while the daily rows, format, and metric are the
// same objects. Qt 6.8 re-notifies a var binding that re-evaluates to an equal
// object, so a shallow provider copy would otherwise hand the chart a new array
// for an unchanged snapshot. Writes only into the caller-owned memo.
export function memoizedChartPoints(memo, fmt, points, showsTokens) {
    if (!memo || typeof memo !== "object") return chartPoints(fmt, points, showsTokens)
    if (!memo.result || !chartMemoMatches(memo, fmt, points, showsTokens)) {
        memo.points = points
        memo.fmt = fmt
        memo.showsTokens = showsTokens
        memo.result = chartPoints(fmt, points, showsTokens)
    }
    return memo.result
}

// Chart points omit unavailable amounts. Their index is not a daily-row index.
export function selectedCostDay(daily, points, activeIndex) {
    if (!Guards.isArrayIndex(points, activeIndex)) return null
    var point = points[activeIndex]
    var sourceIndex = point && point.sourceIndex
    if (!Guards.isArrayIndex(daily, sourceIndex)) return null
    return daily[sourceIndex] || null
}

export function uniqueCostDayIndex(points, label) {
    var found = -1
    for (var i = 0; i < points.length; i++) {
        if (points[i] && points[i].label === label) {
            if (found !== -1) {
                return -1
            }
            found = i
        }
    }
    return found
}

export function costDayIndexAfterRefresh(previousPoints, selectedIndex, points) {
    if (!Array.isArray(points)) return -1
    if (!Guards.isArrayIndex(previousPoints, selectedIndex)) return -1
    var previous = previousPoints[selectedIndex]
    if (!hasDayLabel(previous)) return -1
    if (uniqueCostDayIndex(previousPoints, previous.label) !== selectedIndex) return -1
    return uniqueCostDayIndex(points, previous.label)
}

// The selected metric can omit unavailable days. Use the unfiltered snapshots'
// calendar bounds so missing values at either edge keep their slots too.
// Legacy labels with no unambiguous calendar order keep their bounded sequence.
export function spendHeatmapDays(points, costs) {
    var items = Array.isArray(points) ? points.slice(-maximumCostHistoryPoints) : []
    if (items.length === 0) return []
    var window = indexedCalendarPoints(items)
    if (!window) return items
    var snapshots = Array.isArray(costs) ? costs : []
    for (var i = 0; i < Math.min(snapshots.length, Normalizer.maximumCostSnapshots); i++) {
        extendSnapshotCalendar(window, snapshots[i])
    }
    // UTC keys preserve civil-day slots through daylight-saving transitions.
    var dayMs = 24 * 60 * 60 * 1000
    var firstDayMs = Math.max(window.firstDayMs, window.lastDayMs - (maximumCostHistoryPoints - 1) * dayMs)
    var days = []
    for (var day = firstDayMs; day <= window.lastDayMs; day += dayMs) {
        days.push(Guards.hasOwnKey(window.byDate, day) ? window.byDate[day] : null)
    }
    return days
}

// Lays the daily points out for the activity heatmap's fixed seven rows,
// filled top to bottom and column by column. The newest day is followed by
// `trailingSlots` empty slots that close its week, so every row stays one
// weekday; the oldest end is padded with `null` placeholders, which keeps a
// ragged first column from cutting a notch out of the block. Points beyond the
// capacity are dropped, oldest first.
export function spendHeatmapCells(points, capacity, trailingSlots) {
    var items = Array.isArray(points) ? points : []
    var slots = Math.max(0, Math.floor(Number(capacity) || 0))
    var trailing = Math.max(0, Math.min(slots, Math.floor(Number(trailingSlots) || 0)))
    var dayCapacity = slots - trailing
    var visible = dayCapacity > 0 ? items.slice(Math.max(0, items.length - dayCapacity)) : []
    var cells = []
    for (var i = visible.length; i < dayCapacity; i++) {
        cells.push(null)
    }
    cells = cells.concat(visible)
    for (var j = 0; j < trailing; j++) {
        cells.push(null)
    }
    return cells
}

// QML's Locale.firstDayOfWeek counts 0 (Sunday) through 6; anything else falls
// back to the ISO week's Monday start.
export function heatmapFirstWeekday(firstWeekday) {
    return typeof firstWeekday === "number" && Math.floor(firstWeekday) === firstWeekday
        && firstWeekday >= 0 && firstWeekday <= 6 ? firstWeekday : 1
}

// Weekday of the newest slot, 0 (Sunday) through 6, or -1 when the slots do not
// carry one weekday per row. spendHeatmapDays keeps unavailable days as `null`
// slots; its fallback for undated or unordered points returns -1 here so the
// caller leaves the rows unlabelled rather than naming the wrong days.
export function spendHeatmapNewestWeekday(days) {
    var items = Array.isArray(days) ? days : []
    if (items.length > maximumCostHistoryPoints) return -1
    var newest = newestCalendarSlot(items)
    return newest === null ? -1 : new Date(newest).getUTCDay()
}

// Weekday of each heatmap row, top to bottom, as 0 (Sunday) through 6. Rows
// start on the locale's first day of the week, so each weekday keeps its row
// as the range moves; [] leaves undated rows unlabelled.
export function spendHeatmapRowWeekdays(days, firstWeekday) {
    if (spendHeatmapNewestWeekday(days) < 0) {
        return []
    }
    var first = heatmapFirstWeekday(firstWeekday)
    var weekdays = []
    for (var row = 0; row < 7; row++) {
        weekdays.push((first + row) % 7)
    }
    return weekdays
}

// Empty slots after the newest day that close its week in the locale's row
// order; 0 when the rows carry no weekday and the newest day simply ends the grid.
export function spendHeatmapTrailingSlots(days, firstWeekday) {
    var newestWeekday = spendHeatmapNewestWeekday(days)
    if (newestWeekday < 0) {
        return 0
    }
    return 6 - (newestWeekday - heatmapFirstWeekday(firstWeekday) + 7) % 7
}

export function nonNegative(value) {
    var numeric = Number(value)
    return isFinite(numeric) ? Math.max(0, numeric) : 0
}

export function pointCount(value, minimum) {
    var numeric = Math.floor(Number(value))
    return isFinite(numeric) ? Math.max(minimum, numeric) : minimum
}

export function hasDayLabel(point) {
    return point && typeof point.label === "string" && point.label.length > 0
}

export function calendarDate(point) {
    return hasDayLabel(point) ? Normalizer.parsedCalendarDateKey(point.label) : null
}

export function indexedCalendarPoints(items) {
    var window = { byDate: ({}), firstDayMs: 0, lastDayMs: 0 }
    for (var i = 0; i < items.length; i++) {
        var date = calendarDate(items[i])
        if (!date) return null
        if (i > 0 && date.timestampMs <= window.lastDayMs) return null
        if (i === 0) window.firstDayMs = date.timestampMs
        window.lastDayMs = date.timestampMs
        window.byDate[date.timestampMs] = items[i]
    }
    return window
}

export function extendSnapshotCalendar(window, snapshot) {
    var daily = snapshot && Array.isArray(snapshot.daily) ? snapshot.daily : []
    for (var i = Math.max(0, daily.length - maximumCostHistoryPoints); i < daily.length; i++) {
        var date = calendarDate(daily[i])
        if (!date) continue
        window.firstDayMs = Math.min(window.firstDayMs, date.timestampMs)
        window.lastDayMs = Math.max(window.lastDayMs, date.timestampMs)
    }
}

export function newestCalendarSlot(items) {
    var newest = null
    var dayMs = 24 * 60 * 60 * 1000
    for (var i = 0; i < items.length; i++) {
        if (items[i] === null) continue
        if (typeof items[i] !== "object") return null
        var date = calendarDate(items[i])
        if (!date) return null
        var slot = date.timestampMs + (items.length - 1 - i) * dayMs
        if (newest !== null && slot !== newest) return null
        newest = slot
    }
    return newest
}

export function chartMemoMatches(memo, fmt, points, showsTokens) {
    return memo.points === points && memo.fmt === fmt && memo.showsTokens === showsTokens
}
