import * as Amounts from "./CostAmounts.mjs";
import * as Guards from "./Guards.mjs";

function subcentText(format, value, currency, lowerBound) {
    if (lowerBound !== true)
        return "< " + Amounts.amountString(format, 0.01, currency)
    // Partial sums are lower bounds; an upper-bound label cannot describe them.
    var code = typeof currency === "string" ? currency.trim() : ""
    var text = String(value).replace(".", Amounts.resolvedFormat(format).decimal)
    return Amounts.currencyPrefix(code) + text
}

// Keep positive sub-cent measurements distinct from zero without changing
// the precision of provider-detail balances or aggregate arithmetic.
export function amountText(format, value, currency, lowerBound) {
    if (currency !== "Quota" && Guards.isFiniteNumber(value) && value > 0 && value < 0.01)
        return subcentText(format, value, currency, lowerBound)
    return Amounts.amountString(format, value, currency)
}

export function metricText(format, value, currency, showsTokens) {
    return showsTokens ? Amounts.tokenCountString(value, format)
        : amountText(format, value, currency || "USD")
}

// Missing amounts stay absent; measured zeroes remain visible.
export function amountSummary(fmt, amounts, tokensTextFor) {
    var values = []
    if (Amounts.hasMetricValue(amounts, false)) {
        values.push(amountText(fmt, amounts.cost, amounts.currency))
    }
    if (Amounts.hasMetricValue(amounts, true)) {
        values.push(tokensTextFor ? tokensTextFor(amounts.tokens) : Amounts.tokenCountString(amounts.tokens, fmt))
    }
    return values.length > 0 ? values.join(" · ") : "-"
}

function axisDigits(step) {
    if (step >= 1000) return 0
    if (step > 0 && step < 1) return Math.max(2, Math.ceil(-Math.log(step) / Math.LN10) + 1)
    return 2
}

function axisNumber(format, value, digits) {
    if (digits > 12 && value !== 0)
        return value.toExponential(2).replace(".", Amounts.resolvedFormat(format).decimal)
    return Amounts.groupedDecimalString(format, value, Math.min(digits, 12))
}

function tokenAxisText(format, value) {
    var units = ["", "K", "M", "B"]
    var unit = 0
    while (value >= 1000 && unit < units.length - 1) {
        value /= 1000
        unit++
    }
    // The nice scale and its midpoint use at most three significant digits.
    var tick = Number(value.toPrecision(3))
    return String(tick).replace(".", Amounts.resolvedFormat(format).decimal) + units[unit]
}

// Axis ticks describe exact scale positions, so small scales need more digits
// than an amount readout. Extremely small values use bounded scientific text.
export function axisText(format, value, options) {
    if (options.showsTokens && Guards.isFiniteNumber(value))
        return tokenAxisText(format, value)
    if (options.currency === "Quota" || !Guards.isFiniteNumber(value))
        return Amounts.metricText(format, value, options.currency, options.showsTokens)
    return Amounts.currencyPrefix(options.currency || "USD")
        + axisNumber(format, value, axisDigits(options.step))
}
