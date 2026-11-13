.pragma library
.import "Guards.js" as Guards
.import "CostAmounts.mjs" as Amounts
.import "CostCurrency.mjs" as Currency
.import "CostPresentation.mjs" as Costs
.import "AiInsightsSnapshot.js" as Snapshot

// Presentation projections over normalized CLI snapshots. No fetching, pricing,
// localization, or account attribution belongs to an analysis selection.
function filterCosts(costs, provider) {
    return (Array.isArray(costs) ? costs : []).filter(function(item) {
        return Guards.isRecord(item) && (!provider || item.provider === provider)
    })
}

function uniqueDay(snapshot, day) {
    var matches = (Array.isArray(snapshot.daily) ? snapshot.daily : []).filter(function(row) {
        return Guards.isRecord(row) && row.label === day
    })
    return matches.length === 1 ? matches[0] : null
}

function dayCosts(costs, day) {
    if (!day) return filterCosts(costs, "")
    return filterCosts(costs, "").map(function(snapshot) { return selectedDayCost(snapshot, day) })
}

function selectedDayCost(snapshot, day) {
    var row = uniqueDay(snapshot, day)
    return Object.assign({}, snapshot, {
        totals: row || {cost: null, tokens: null, currency: snapshot.currency},
        models: row && Array.isArray(row.models) ? row.models : [],
        modelsTruncated: row ? row.modelsTruncated === true : false,
        projects: null
    })
}

function dailyPoints(format, costs, showsTokens) {
    var items = filterCosts(costs, "")
    var points = Costs.spendDailyPoints(format, items, showsTokens)
    var currency = Currency.spendCurrency(items)
    var series = items.map(function(item) {
        return {provider: item.provider, days: Snapshot.historyDates(item.daily || [])}
    })
    return points.map(function(point) {
        point.segments = daySegments(series, point, showsTokens, currency)
        return point
    })
}

function segmentValue(day, showsTokens, currency) {
    if (!day || !Amounts.hasMetricValue(day, showsTokens)) return 0
    if (!showsTokens && (day.currency || "USD") !== currency) return 0
    return Amounts.metricValue(day, showsTokens)
}

function daySegments(series, point, showsTokens, currency) {
    var segments = []
    var total = 0
    for (var i = 0; i < series.length; i++) {
        var value = segmentValue(series[i].days[point.label], showsTokens, currency)
        if (value > 0) segments.push({provider: series[i].provider, value: value})
        total += value
    }
    // Duplicates or unknown contributions must not draw a plausible split.
    return total === point.value ? segments : []
}

// A fixed, explicitly labelled comparison of the last two complete weeks.
// Narrow ranges cannot supply that evidence and never trigger a hidden scan.
function comparison(costs, showsTokens, nowMs) {
    var items = filterCosts(costs, "")
    var currency = Currency.spendCurrency(items)
    var eligible = items.filter(function(item) {
        return showsTokens || Currency.costMatchesSpendCurrency(item, currency)
    })
    var periods = eligible.map(function(item) { return comparisonPeriod(item, showsTokens, nowMs) })
    if (!periods.length || periods.some(function(period) { return period === null })) return null
    return comparePeriods(periods, currency)
}

function comparePeriods(periods, currency) {
    var current = periods.reduce(function(sum, period) { return sum + period.last7Days }, 0)
    var previous = periods.reduce(function(sum, period) { return sum + period.previous7Days }, 0)
    if (!isFinite(current) || !isFinite(previous)) return null
    var change = Snapshot.periodChange(current, previous)
    return Object.assign({current: current, previous: previous, currency: currency,
        estimated: periods.some(function(period) { return period.estimated === true }),
        providers: periods.length}, change ? {[change.key]: change.value} : {})
}

function comparisonPeriod(item, showsTokens, nowMs) {
    if (!Amounts.hasMetricValue(item.totals, showsTokens) || item.valueMode === "partial") return null
    var period = showsTokens ? Snapshot.tokens(item, nowMs) : Snapshot.spend(item, nowMs)
    return period && !period.incomplete ? period : null
}

function appendModels(result, item, showsTokens) {
    var models = Array.isArray(item.models) ? item.models : []
    result.truncated = result.truncated || item.modelsTruncated === true || models.length > 128
    var rows = sortedModels(models, showsTokens)
    var remaining = 128 - result.rows.length
    result.truncated = result.truncated || rows.length > remaining
    rows.slice(0, remaining).forEach(function(row) {
        result.rows.push(Object.assign({}, row, {provider: item.provider, valueMode: item.valueMode}))
    })
}

function sortedModels(models, showsTokens) {
    var rows = models.slice(0, 128).filter(Guards.isRecord)
    rows.sort(function(a, b) { return Costs.compareProjects(a, b, showsTokens) })
    return rows
}

function modelRows(costs, day, showsTokens) {
    var result = {rows: [], truncated: false}
    var items = dayCosts(costs, day)
    items.slice(0, 128).forEach(function(item) { appendModels(result, item, showsTokens) })
    result.truncated = result.truncated || items.length > 128
    return result
}
