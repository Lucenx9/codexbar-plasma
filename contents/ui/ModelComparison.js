.pragma library
.import "UsageAnalysis.js" as Analysis
.import "CostAmounts.mjs" as Amounts
.import "CostCurrency.mjs" as Currency
.import "CostPresentation.mjs" as Costs
.import "ProviderNormalizer.mjs" as Normalizer

// Use each provider's reported total as the denominator contribution. Never
// compute a percentage against just the visible (capped) model rows.
function comparison(costs, day, showsTokens, historyError) {
    var snapshots = Analysis.filterCosts(costs, "")
    var selected = Analysis.dayCosts(snapshots.slice(0, Normalizer.maximumCostSnapshots), day)
    var truncated = selected.length < snapshots.length
    var incomplete = historyError || truncated
    var groups = new Map()
    selected.forEach(function(item) {
        var group = comparisonCurrencyGroup(groups, item, incomplete)
        var models = {rows: [], truncated: false}
        Analysis.appendModels(models, item, showsTokens)
        truncated = truncated || models.truncated
        collectComparisonModels(group, item, models, showsTokens)
    })
    var result = {rows: [], incompleteCurrencies: []}
    groups.forEach(function(group) { finishCurrencyComparison(result, group, showsTokens) })
    result.rows.sort(function(a, b) { return compareProviderModels(a, b, showsTokens) })
    result.truncated = truncated || result.rows.length > 128
    result.rows = result.rows.slice(0, 128)
    result.incompleteCurrencies.sort()
    return result
}

function comparisonCurrencyGroup(groups, item, incomplete) {
    var currency = Amounts.snapshotTotals(item).currency || item.currency || Currency.spendCurrency([item])
    if (!groups.has(currency))
        groups.set(currency, {currency: currency, total: 0, rows: [], incomplete: incomplete})
    return groups.get(currency)
}

function collectComparisonModels(group, item, models, showsTokens) {
    group.total += Amounts.metricValue(item.totals, false)
    models.rows.forEach(function(row) {
        row.currency = row.currency || group.currency
        group.rows.push(row)
    })
    if (!showsTokens && !completeModelPrices(item, models, group.currency)) group.incomplete = true
}

function finishCurrencyComparison(result, group, showsTokens) {
    var incomplete = group.incomplete || !isFinite(group.total)
    if (incomplete && !showsTokens) result.incompleteCurrencies.push(group.currency)
    var canShare = !showsTokens && !incomplete && group.total > 0
    group.rows.forEach(function(row) {
        row.spendShare = canShare ? Math.min(1, row.cost / group.total) : null
        result.rows.push(row)
    })
}

function compareProviderModels(a, b, showsTokens) {
    var currencyOrder = showsTokens ? 0 : a.currency.localeCompare(b.currency)
    return currencyOrder || Costs.compareProjects(a, b, showsTokens)
}

function completeModelPrices(item, models, currency) {
    if (!hasModelPriceCoverage(item, models)) return false
    var sum = models.rows.reduce(function(total, row) {
        return pricedModelInCurrency(row, currency) ? total + row.cost : NaN
    }, 0)
    // The CLI can sum the same prices in a different order. Only allow
    // floating-point roundoff, including for sub-cent totals.
    var total = item.totals.cost
    return Math.abs(sum - total) <= total * 1e-12
}

function hasModelPriceCoverage(item, models) {
    var totals = Amounts.snapshotTotals(item)
    var ranking = item.tokenRanking || ({})
    var gaps = [
        models.truncated,
        ranking.sourceTruncated,
        ranking.hasUnknownCost,
        item.historyCoverageEstablished === false,
        item.valueMode === "partial",
        !Amounts.hasMetricValue(totals, false),
        totals.incompleteRequests > 0,
        models.rows.length === 0 && totals.tokens > 0
    ]
    return !gaps.some(Boolean)
}

function pricedModelInCurrency(row, currency) {
    return Amounts.hasMetricValue(row, false) && row.cost >= 0
        && !(row.incompleteRequests > 0) && row.currency === currency
}
