.pragma library
.import "CostAmounts.js" as CostAmounts

// Select monetary amounts in provider order, independently of token totals.
// Totals inherit the selected currency; legacy daily rows default to USD.





function pricedAmountCurrency(amounts) {
    if (!CostAmounts.hasMetricValue(amounts, false)) return null
    var currency = CostAmounts.boundedText(amounts.currency || "", 12)
    return currency.length > 0 ? currency : null
}

function pricedSnapshotCurrency(snapshot) {
    var totalsCurrency = pricedAmountCurrency(CostAmounts.snapshotTotals(snapshot))
    if (totalsCurrency !== null) return totalsCurrency
    var daily = CostAmounts.snapshotDaily(snapshot)
    for (var i = 0; i < daily.length; i++) {
        var currency = pricedAmountCurrency(daily[i])
        if (currency !== null) return currency
    }
    return null
}

// null means no fallback; an unlabelled first daily row still chooses USD.
function fallbackSnapshotCurrency(snapshot) {
    var totals = CostAmounts.snapshotTotals(snapshot)
    var currency = CostAmounts.boundedText(totals.currency || "", 12)
    if (currency.length > 0) return currency
    var daily = CostAmounts.snapshotDaily(snapshot)
    if (daily.length === 0) return null
    var first = daily[0]
    var firstCurrency = first && typeof first === "object" ? first.currency : null
    return CostAmounts.boundedText(firstCurrency || "USD", 12)
}

function firstCurrency(items, select) {
    for (var i = 0; i < items.length; i++) {
        var currency = select(items[i])
        if (currency !== null) return currency
    }
    return null
}

function spendCurrency(costs) {
    var items = Array.isArray(costs) ? costs : []
    // Token-only metadata cannot displace a measured monetary amount.
    var priced = firstCurrency(items, pricedSnapshotCurrency)
    if (priced !== null) return priced
    var fallback = firstCurrency(items, fallbackSnapshotCurrency)
    return fallback === null ? "USD" : fallback
}

function costMatchesSpendCurrency(cost, currency) {
    var totals = cost && cost.totals ? cost.totals : ({})
    return CostAmounts.boundedText(totals.currency || currency, 12) === currency
}

function dailyHasForeignCurrency(point, currency) {
    return CostAmounts.hasMetricValue(point, false)
        && CostAmounts.boundedText(point.currency || "USD", 12) !== currency
}

function snapshotHasForeignCostCurrency(snapshot, currency) {
    if (CostAmounts.hasMetricValue(CostAmounts.snapshotTotals(snapshot), false)
            && !costMatchesSpendCurrency(snapshot, currency)) return true
    return CostAmounts.snapshotDaily(snapshot).some(function(point) {
        return dailyHasForeignCurrency(point, currency)
    })
}

// The caller marks money as a subtotal while retaining all currency-free tokens.
function spendHasMixedCostCurrencies(costs) {
    var items = Array.isArray(costs) ? costs : []
    var currency = spendCurrency(items)
    return items.some(function(snapshot) {
        return snapshotHasForeignCostCurrency(snapshot, currency)
    })
}
