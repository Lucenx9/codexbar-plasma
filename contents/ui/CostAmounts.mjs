import * as Guards from "./Guards.mjs";
import * as SafeText from "./SafeText.mjs";
import * as Normalizer from "./ProviderNormalizer.mjs";

// Locale-explicit cost/count formatting and measured-amount arithmetic.
// Missing amounts remain distinct from measured zero; no localization or effects.
// Shared text and snapshot accessors keep the other cost modules on the same inputs.

export function numberFormat(groupSeparator, decimalPoint) {
    return {
        group: typeof groupSeparator === "string" ? groupSeparator : ",",
        decimal: typeof decimalPoint === "string" ? decimalPoint : "."
    }
}

export function boundedText(value, limit) {
    if (value === null || value === undefined) {
        return ""
    }
    return SafeText.truncatedText(String(value), limit)
}

// The metric the charts currently plot. Cost and tokens share one payload, so
// every scale, peak, and summary has to read the same switch.
export function hasMetricValue(point, showsTokens) {
    if (!point) {
        return false
    }
    var value = showsTokens ? point.tokens : point.cost
    return typeof value === "number" && isFinite(value)
}

export function metricValue(point, showsTokens) {
    if (!hasMetricValue(point, showsTokens)) {
        return 0
    }
    return showsTokens ? point.tokens : point.cost
}

export function groupedDecimalString(fmt, value, digits) {
    var numeric = Number(value)
    if (!isFinite(numeric)) return "-"
    // toFixed becomes exponential at this bound; those digits must not be grouped.
    if (Math.abs(numeric) >= 1e21) return String(Math.abs(numeric))
    var f = resolvedFormat(fmt)
    var parts = Math.abs(numeric).toFixed(digits).split(".")
    var whole = groupedDigits(parts[0], f.group)
    return parts.length > 1 ? whole + f.decimal + parts[1] : whole
}

// "Quota" is a credit balance, not money, so it prints as a bare rounded count.
// Like the money path it degrades to "-" for non-numeric input instead of
// printing "NaN".
export function amountString(fmt, value, currency) {
    if (!Guards.isFiniteNumber(value)) return "-"
    var code = typeof currency === "string" ? currency.trim() : ""
    if (code === "Quota") return String(Math.round(value))
    // Apply precision before the sign, so rounded zero never becomes -$0.00.
    var negative = value < 0 && Math.abs(value).toFixed(2) !== "0.00"
    var sign = negative ? "-" : ""
    return sign + currencyPrefix(code) + groupedDecimalString(fmt, Math.abs(value), 2)
}

// Compact counts use the caller's decimal mark, like costs on the same line:
// "1,5K" beside "1.234,50" instead of the C-locale "1.5K".
export function scaledTokenCount(value, fmt) {
    if (value >= 10) return Number(value).toFixed(0)
    return Number(value).toFixed(1).replace(/\.0$/, "").replace(".", resolvedFormat(fmt).decimal)
}

// Credit balances are plain counts: a whole balance keeps no fractional part,
// while a fractional one keeps a single digit. Rounding can carry a fractional
// value across the whole boundary ("99.95" -> "100.0"), so the fractional digit
// drops when the rounded figure is whole instead of choosing the precision
// from the unrounded value.
export function formatCount(fmt, value) {
    var numeric = Number(value)
    if (!isFinite(numeric)) return "-"
    var magnitude = Math.abs(numeric)
    var digits = magnitude >= 100 || magnitude === Math.round(magnitude) ? 0 : 1
    var text = groupedDecimalString(fmt, magnitude, digits)
    if (digits === 1) text = trimWholeFraction(text, resolvedFormat(fmt).decimal)
    return (numeric < 0 && text !== "0" ? "-" : "") + text
}

export function tokenCountString(tokens, fmt) {
    var value = Number(tokens)
    if (!isFinite(value)) {
        return "-"
    }
    var absValue = Math.abs(value)
    var sign = value < 0 ? "-" : ""
    // Round inside each unit before choosing it, so a value that rounds up
    // across a threshold promotes ("1M") instead of printing an overflowing
    // unit ("1000K").
    if (Math.round(absValue / 1000000) >= 1000) {
        return sign + scaledTokenCount(absValue / 1000000000, fmt) + "B"
    }
    if (Math.round(absValue / 1000) >= 1000) {
        return sign + scaledTokenCount(absValue / 1000000, fmt) + "M"
    }
    if (Math.round(absValue) >= 1000) {
        return sign + scaledTokenCount(absValue / 1000, fmt) + "K"
    }
    return Math.round(value).toString()
}

// Returns the peak of the currently plotted metric, so the bars keep their
// scale when the Usage & Spend tab switches between cost and tokens.
export function sparklineMax(points, showsTokens) {
    var maximum = 0
    if (!Array.isArray(points)) {
        return maximum
    }
    for (var i = 0; i < points.length; i++) {
        maximum = Math.max(maximum, metricValue(points[i], showsTokens))
    }
    return maximum
}

export function metricText(fmt, magnitude, currency, showsTokens) {
    return showsTokens
        ? tokenCountString(magnitude, fmt)
        : amountString(fmt, magnitude, currency || "USD")
}

// Missing amounts stay absent; measured zeroes remain visible.
export function amountSummary(fmt, amounts, tokensTextFor) {
    var values = []
    if (hasMetricValue(amounts, false)) {
        values.push(amountString(fmt, amounts.cost, amounts.currency))
    }
    if (hasMetricValue(amounts, true)) {
        values.push(tokensTextFor ? tokensTextFor(amounts.tokens) : tokenCountString(amounts.tokens, fmt))
    }
    return values.length > 0 ? values.join(" · ") : "-"
}

// The bars highlight the peak of the selected metric, so this has to name the
// same day, not the most expensive one. Returns null when nothing was spent.
export function peakPoint(points, showsTokens) {
    var items = Array.isArray(points) ? points : []
    var peak = null
    var maximum = 0
    for (var i = 0; i < items.length; i++) {
        var point = items[i]
        if (!Guards.isRecord(point)) continue
        var magnitude = metricValue(point, showsTokens)
        if (magnitude <= maximum) continue
        maximum = magnitude
        peak = { label: existingLabel(point, ""), magnitude: magnitude, currency: point.currency || "USD" }
    }
    return peak
}

export function averageDailyValue(points, showsTokens, zeroDays) {
    if (!Array.isArray(points)) {
        return null
    }
    var average = 0
    var total = 0
    var count = 0
    var currency = "USD"
    for (var i = 0; i < points.length; i++) {
        if (!hasMetricValue(points[i], showsTokens)) {
            continue
        }
        count += 1
        total += Math.max(0, metricValue(points[i], showsTokens))
        // Nonnegative values keep this difference finite even when their sum
        // would overflow before division by the measured day count.
        average += (Math.max(0, metricValue(points[i], showsTokens)) - average) / count
        if (points[i].currency) {
            currency = points[i].currency
        }
    }
    // Only an empty denominator has no average. A range measured as zero keeps
    // its zero, like the history rows built from the same points.
    if (count === 0) {
        return null
    }
    // Preserve ordinary sums' rounding boundaries; use the incremental mean
    // only when the intermediate sum cannot be represented.
    // Sparse all-history aggregates count omitted zero-activity dates without
    // allocating a row per calendar day. An unavailable metric still stays null.
    var denominator = count + zeroDayCount(zeroDays)
    return { value: isFinite(total) ? total / denominator : average * (count / denominator), currency: currency }
}

export function perMillionAmount(tokenCost) {
    var totals = tokenCost ? tokenCost.totals : null
    if (!totals) return null
    var cost = positiveAmount(totals.cost)
    var tokens = positiveAmount(totals.tokens)
    if (!isFinite(cost) || !isFinite(tokens)) return null
    var value = perMillionRatio(cost, tokens)
    return isFinite(value) ? { value: value, currency: totals.currency || "USD" } : null
}

// The CLI's "today" is the total of the day it scanned. A snapshot scanned on
// an earlier local date, such as one taken before midnight or retained after a
// failed refresh, holds that day's spend, so today reads as unknown until a
// scan from today arrives. A snapshot without a scan date keeps its amounts.
export function todayAmounts(tokenCost, nowMs) {
    var today = tokenCost && tokenCost.today ? tokenCost.today : null
    var scanDay = today && typeof tokenCost.scanDay === "string" ? tokenCost.scanDay : ""
    var now = new Date(typeof nowMs === "number" ? nowMs : NaN)
    if (scanIsCurrent(scanDay, now)) {
        return today
    }
    return {
        cost: null,
        tokens: null,
        inputTokens: null,
        outputTokens: null,
        cacheReadTokens: null,
        cacheCreationTokens: null,
        currency: today.currency
    }
}

// Keep an overflowed sum non-finite until its caller publishes it as unknown.
export function addMetric(total, point, showsTokens) {
    if (!hasMetricValue(point, showsTokens)) return total
    var previous = total === null ? 0 : total
    return previous + Math.max(0, metricValue(point, showsTokens))
}

export function resolvedFormat(fmt) {
    var source = fmt && typeof fmt === "object" ? fmt : ({})
    return numberFormat(source.group, source.decimal)
}

export function groupedDigits(whole, separator) {
    var grouped = ""
    for (var i = 0; i < whole.length; i++) {
        if (i > 0 && (whole.length - i) % 3 === 0) grouped += separator
        grouped += whole.charAt(i)
    }
    return grouped
}

export function currencyPrefix(code) {
    if (code === "USD") return "$"
    return code.length === 0 ? "" : code + " "
}

export function trimWholeFraction(text, decimal) {
    var suffix = decimal + "0"
    return text.slice(-suffix.length) === suffix ? text.slice(0, -suffix.length) : text
}

export function existingLabel(point, fallback) {
    return point.label && point.label.length > 0 ? point.label : fallback
}

export function zeroDayCount(value) {
    return Guards.isFiniteNumber(value) ? Math.max(0, Math.floor(value)) : 0
}

export function positiveAmount(value) {
    var numeric = Number(value)
    return isFinite(numeric) && numeric > 0 ? numeric : NaN
}

export function perMillionRatio(cost, tokens) {
    var value = cost * 1000000 / tokens
    // Preserve ordinary rounding; rescale only if the intermediate product overflowed.
    return isFinite(value) ? value : cost / (tokens / 1000000)
}

export function scanIsCurrent(scanDay, now) {
    if (scanDay.length === 0 || !isFinite(now.getTime())) return true
    return scanDay === Normalizer.calendarDateKey(now.getFullYear(), now.getMonth() + 1, now.getDate())
}

export function snapshotTotals(snapshot) {
    return snapshot && typeof snapshot === "object" && snapshot.totals ? snapshot.totals : ({})
}

export function snapshotDaily(snapshot) {
    return snapshot && Array.isArray(snapshot.daily) ? snapshot.daily : []
}
