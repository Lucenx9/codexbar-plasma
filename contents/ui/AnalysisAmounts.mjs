import * as Amounts from "./CostAmounts.mjs";
import * as Guards from "./Guards.mjs";

// Keep positive sub-cent measurements distinct from zero without changing
// the precision of provider-detail balances or aggregate arithmetic.
export function metricText(format, value, currency, showsTokens) {
    if (!showsTokens && currency !== "Quota" && Guards.isFiniteNumber(value) && value > 0 && value < 0.01)
        return "< " + Amounts.amountString(format, 0.01, currency || "USD")
    return Amounts.metricText(format, value, currency, showsTokens)
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

// Axis ticks describe exact scale positions, so small scales need more digits
// than an amount readout. Extremely small values use bounded scientific text.
export function axisText(format, value, options) {
    if (options.showsTokens || options.currency === "Quota" || !Guards.isFiniteNumber(value))
        return Amounts.metricText(format, value, options.currency, options.showsTokens)
    return Amounts.currencyPrefix(options.currency || "USD")
        + axisNumber(format, value, axisDigits(options.step))
}
