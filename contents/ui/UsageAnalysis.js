.pragma library
.import "Guards.js" as Guards
.import "CostAmounts.mjs" as Amounts
.import "AnalysisAmounts.mjs" as Display
.import "CostCurrency.mjs" as Currency
.import "CostPresentation.mjs" as Costs
.import "AiInsightsSnapshot.js" as Snapshot
.import "ChartLines.mjs" as Lines
.import "ProviderNormalizer.mjs" as Normalizer

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
        tokenRanking: row ? row.tokenRanking : null,
        projects: null
    })
}

function dailyPoints(format, costs, showsTokens) {
    var items = filterCosts(costs, "").slice(0, Normalizer.maximumCostSnapshots)
    var ambiguous = ambiguousDates(items, showsTokens)
    var points = Costs.spendDailyPoints(format, items, showsTokens).filter(function(point) {
        return !Guards.hasOwnKey(ambiguous, point.label)
    })
    // Retain the date even when duplicate values overflowed or had no metric.
    // A partial sum from healthy providers cannot establish this day's total.
    Object.keys(ambiguous).forEach(function(label) { points.push({label: label, value: null}) })
    points.sort(function(a, b) { return a.label.localeCompare(b.label) })
    var currency = Currency.spendCurrency(items)
    var formatted = points.slice(-365).filter(function(point) {
        return !/^\d{4}-\d{2}-\d{2}$/.test(point.label)
            || Normalizer.parsedCalendarDateKey(point.label) !== null
    }).map(function(point) {
        return Object.assign({}, point, {displayValue: point.value === null ? null
            : Display.metricText(format, point.value, currency, showsTokens)})
    })
    return hasCalendarHistory(formatted) ? Lines.calendarPoints(formatted) : formatted
}

function hasCalendarHistory(points) {
    return points.length > 0 && points.every(function(point) { return Normalizer.parsedCalendarDateKey(point.label) !== null })
}

function ambiguousDates(items, showsTokens) {
    var currency = Currency.spendCurrency(items)
    var result = ({})
    items.filter(function(item) {
        return showsTokens || Currency.costMatchesSpendCurrency(item, currency)
    }).forEach(function(item) {
        var dates = Snapshot.historyDates(Array.isArray(item.daily) ? item.daily : [])
        Object.keys(dates).forEach(function(label) {
            if (dates[label] === null) result[label] = true
        })
    })
    return result
}

function providerLines(format, costs, points, showsTokens) {
    var items = filterCosts(costs, "")
    var currency = Currency.spendCurrency(items)
    return items.filter(function(item) {
        return typeof item.provider === "string" && !Guards.isUnsafeObjectKey(item.provider)
            && (showsTokens || Currency.costMatchesSpendCurrency(item, currency))
    }).slice(0, 128).map(function(item) {
        var dates = Snapshot.historyDates(Array.isArray(item.daily) ? item.daily : [])
        return {provider: item.provider, points: points.slice(0, 365).map(function(point) {
            return Object.assign({label: point.label}, providerAmount(format, dates[point.label], currency, showsTokens))
        })}
    })
}

function providerAmount(format, day, currency, showsTokens) {
    var known = Amounts.hasMetricValue(day, showsTokens)
        && (showsTokens || (day.currency || currency) === currency)
    var value = known ? Amounts.metricValue(day, showsTokens) : null
    if (value < 0) value = null
    return {value: value,
        displayValue: value === null ? null : Display.metricText(format, value, currency, showsTokens)}
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
    // Privacy projections retain the amounts' currency, not the envelope field.
    var snapshot = Object.assign({}, item, {currency: item.totals.currency})
    var period = showsTokens ? Snapshot.tokens(snapshot, nowMs) : Snapshot.unroundedSpend(snapshot, nowMs)
    return period && !period.incomplete ? period : null
}

function modelSource(item, showsTokens) {
    var ranking = showsTokens ? item.tokenRanking : null
    if (ranking && Array.isArray(ranking.rows))
        return ranking
    return {rows: Array.isArray(item.models) ? item.models : [], truncated: item.modelsTruncated === true}
}

function appendModels(result, item, showsTokens) {
    var source = modelSource(item, showsTokens)
    var models = source.rows
    result.truncated = result.truncated || source.truncated === true || models.length > 128
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
