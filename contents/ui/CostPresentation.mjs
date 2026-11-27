import * as Guards from "./Guards.mjs";
import * as CostAmounts from "./CostAmounts.mjs";
import * as AnalysisAmounts from "./AnalysisAmounts.mjs";
import * as CostChart from "./CostChart.mjs";
import * as CostCurrency from "./CostCurrency.mjs";
import * as CostTrust from "./CostTrust.mjs";

// Build provider cost rows and range-matched spend aggregates.
// Callers own localization, selection, privacy, and process effects.

export var maximumProjectRows = 128

// `entries` is an ordered list of `{ label, tokens }`. Rows with no positive
// token count are dropped rather than printed as zero.
export function breakdownRows(entries, fmt) {
    var rows = []
    if (!Array.isArray(entries)) {
        return rows
    }
    for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        if (!Guards.isRecord(entry)) {
            continue
        }
        var value = Number(entry.tokens)
        if (!isFinite(value) || value <= 0) {
            continue
        }
        rows.push({
            label: entry.label,
            value: CostAmounts.tokenCountString(value, fmt)
        })
    }
    return rows
}

function selectedModelRanking(tokenCost, showsTokens) {
    if (showsTokens !== true || !tokenCost) {
        return null
    }
    var ranking = tokenCost.tokenRanking
    if (!Guards.isRecord(ranking) || !Array.isArray(ranking.rows)) {
        return null
    }
    return ranking
}

function selectedModels(tokenCost, showsTokens) {
    var ranking = selectedModelRanking(tokenCost, showsTokens)
    if (ranking) {
        return ranking.rows
    }
    if (!tokenCost || !Array.isArray(tokenCost.models)) {
        return null
    }
    return tokenCost.models
}

export function modelsTruncated(tokenCost, showsTokens) {
    if (!tokenCost) {
        return false
    }
    var ranking = selectedModelRanking(tokenCost, showsTokens)
    return ranking ? ranking.truncated === true : tokenCost.modelsTruncated === true
}

// `tokensTextFor(tokens)` lets the caller word the token half of each summary.
export function modelRows(fmt, tokenCost, tokensTextFor, showsTokens) {
    var rows = []
    var models = selectedModels(tokenCost, showsTokens)
    if (!models) {
        return rows
    }
    for (var i = 0; i < models.length; i++) {
        var item = models[i]
        if (!Guards.isRecord(item)) {
            continue
        }
        rows.push({
            label: item.label,
            value: AnalysisAmounts.amountSummary(fmt, item, tokensTextFor),
            incompleteRequests: CostTrust.acceptedIncompleteRequests(item)
        })
    }
    return rows
}

// The history rows cover only the newest days of the range. The peak line must
// read the same span, or it names a day the rows neither show nor highlight.
export function recentHistoryPoints(daily) {
    return Array.isArray(daily) ? daily.slice(Math.max(0, daily.length - 7)) : []
}

// The last seven days, newest first, scaled against the peak of the selected
// metric so the bar lengths match the figures beside them. A point whose label
// the payload omitted gets `fallbackLabel`.
export function historyRows(fmt, tokenCost, showsTokens, fallbackLabel) {
    if (!tokenCost) return []
    var visibleDaily = recentHistoryPoints(tokenCost.daily).filter(function(day) {
        return CostAmounts.hasMetricValue(day, showsTokens)
    })
    var maximum = CostAmounts.sparklineMax(visibleDaily, showsTokens)
    return visibleDaily.reverse().map(function(item) {
        return historyRow(item, maximum, showsTokens, { fmt: fmt, fallbackLabel: fallbackLabel })
    })
}

// The calendar periods CLI 0.67.0 computes itself with `cost --period`. Any
// other value means the rolling --days range.
export function costPeriod(value) {
    return value === "month-to-date" || value === "all" ? value : ""
}

// A cached cost snapshot belongs to the selected range only when the CLI
// answered for the same window; a stale snapshot must not be summed into a
// range the user has since changed. A calendar period matches by name, since
// its day count changes as the month goes on.
export function snapshotMatchesRange(tokenCost, historyDays, period) {
    if (!tokenCost) {
        return false
    }
    var requestedPeriod = costPeriod(period)
    if (costPeriod(tokenCost.period) !== requestedPeriod) {
        return false
    }
    if (requestedPeriod.length > 0) {
        return true
    }
    var snapshotDays = Number(tokenCost.historyDays)
    return isFinite(snapshotDays)
        && Math.floor(snapshotDays) === Math.floor(Number(historyDays))
}

// `titleFor` maps a provider ID to its display title, so the sort order matches
// what the Usage & Spend tab prints.
export function spendSnapshots(tokenCosts, historyDays, titleFor, period) {
    var result = []
    for (var providerID in tokenCosts) {
        if (!Guards.hasOwnKey(tokenCosts, providerID)) {
            continue
        }
        var tokenCost = tokenCosts[providerID]
        if (!snapshotMatchesRange(tokenCost, historyDays, period)) {
            continue
        }
        result.push(tokenCost)
    }
    result.sort(function(a, b) {
        var left = titleFor ? titleFor(a.provider) : String(a.provider)
        var right = titleFor ? titleFor(b.provider) : String(b.provider)
        return left.localeCompare(right)
    })
    return result
}

// Callers supply range-matched snapshots in their displayed provider order.
// Rank within each provider, so different currencies are never compared.
export function projectRows(costs, showsTokens) {
    var result = { rows: [], truncated: false }
    var items = Array.isArray(costs) ? costs : []
    for (var i = 0; i < items.length; i++) {
        appendProjectSnapshot(result, items[i], showsTokens)
    }
    return result
}

export function spendDailyPoints(fmt, costs, showsTokens) {
    var items = Array.isArray(costs) ? costs : []
    var byDate = ({})
    var currency = CostCurrency.spendCurrency(items)
    var incompleteScans = []
    var context = { currency: currency, showsTokens: showsTokens, excludedDates: new Set() }
    for (var i = 0; i < items.length; i++) {
        addDailySnapshot(byDate, items[i], context, incompleteScans)
    }
    var rows = spendPointRows(byDate, fmt, showsTokens)
    rows.sort(function(a, b) { return a.label.localeCompare(b.label) })
    var visible = rows.slice(-CostChart.maximumCostHistoryPoints)
    for (var row of visible) {
        if (context.excludedDates.has(row.label)
                || incompleteScans.some(function(dates) { return !dates.has(row.label) })) row.partial = true
    }
    return visible
}

function dailyCoverage(snapshot, context) {
    if (!snapshot) return null
    if (!context.showsTokens && !CostCurrency.costMatchesSpendCurrency(snapshot, context.currency)) return null
    collectExcludedDates(snapshot, context)
    return CostTrust.incompleteHistory(snapshot) ? new Set() : null
}

function collectExcludedDates(snapshot, context) {
    if (!Array.isArray(snapshot.excludedDates)) return
    // Privacy removes an invalid currency. That exclusion can still qualify tokens.
    if (!context.showsTokens && CostAmounts.snapshotTotals(snapshot).currency !== context.currency) return
    snapshot.excludedDates.slice(0, CostChart.maximumCostHistoryPoints).forEach(function(date) {
        context.excludedDates.add(date)
    })
}

function addDailySnapshot(byDate, snapshot, context, incompleteScans) {
    var measuredDates = dailyCoverage(snapshot, context)
    addSpendDays(byDate, CostAmounts.snapshotDaily(snapshot), context, measuredDates)
    if (!measuredDates) return
    var suppliedTotal = CostTrust.hasObservedAmount(snapshot.totals)
        && CostAmounts.hasMetricValue(snapshot.totals, context.showsTokens)
    if (measuredDates.size > 0 || suppliedTotal) {
        incompleteScans.push(measuredDates)
    }
}

// Money is summed only in the range currency. Tokens have no currency, so the
// total keeps every provider just like the token chart does.
export function spendTotals(costs) {
    var items = Array.isArray(costs) ? costs : []
    if (items.length === 0) return null
    var currency = CostCurrency.spendCurrency(items)
    var cost = null
    var tokens = null
    for (var i = 0; i < items.length; i++) {
        var totals = CostAmounts.snapshotTotals(items[i])
        tokens = CostAmounts.addMetric(tokens, totals, true)
        if (CostCurrency.costMatchesSpendCurrency(items[i], currency)) {
            cost = CostAmounts.addMetric(cost, totals, false)
        }
    }
    return {
        cost: isFinite(cost) ? cost : null,
        tokens: isFinite(tokens) ? tokens : null,
        currency: currency,
        hasMixedCostCurrencies: CostCurrency.spendHasMixedCostCurrencies(items)
    }
}

export function historyRow(item, maximum, showsTokens, labels) {
    var magnitude = Math.max(0, CostAmounts.metricValue(item, showsTokens))
    return {
        label: item.label && item.label.length > 0 ? item.label : labels.fallbackLabel,
        value: AnalysisAmounts.amountSummary(labels.fmt, item),
        incompleteRequests: CostTrust.acceptedIncompleteRequests(item),
        percent: maximum > 0 && magnitude > 0 ? Math.max(3, (magnitude / maximum) * 100) : 0,
        isPeak: maximum > 0 && magnitude === maximum
    }
}

export function compareProjects(a, b, showsTokens) {
    var aHasValue = CostAmounts.hasMetricValue(a, showsTokens)
    var bHasValue = CostAmounts.hasMetricValue(b, showsTokens)
    if (aHasValue !== bHasValue) return aHasValue ? -1 : 1
    var difference = CostAmounts.metricValue(b, showsTokens) - CostAmounts.metricValue(a, showsTokens)
    return difference || CostAmounts.boundedText(a.label, 120).localeCompare(CostAmounts.boundedText(b.label, 120))
}

export function appendProjectSnapshot(result, snapshot, showsTokens) {
    var projects = projectData(snapshot)
    if (!projects) return
    result.truncated = result.truncated || projects.truncated === true
    if (result.rows.length === maximumProjectRows) {
        result.truncated = result.truncated || projects.rows.length > 0
        return
    }
    // Bound inspection before filtering; invalid rows still consume its budget.
    var rows = projects.rows.slice(0, maximumProjectRows).filter(Guards.isRecord)
    rows.sort(function(a, b) { return compareProjects(a, b, showsTokens) })
    var visible = rows.slice(0, maximumProjectRows - result.rows.length)
    var trust = CostTrust.costTrustSummary([snapshot])
    var mode = trust ? trust.valueMode : "plain"
    for (var i = 0; i < visible.length; i++) {
        result.rows.push(projectRow(snapshot.provider, visible[i], mode))
    }
    result.truncated = result.truncated || projects.rows.length > maximumProjectRows || visible.length < rows.length
}

export function projectRow(provider, row, mode) {
    return { provider: provider, label: CostAmounts.boundedText(row.label, 120),
        cost: row.cost, tokens: row.tokens, currency: row.currency, valueMode: mode }
}

export function normalizedSpendDay(point, context) {
    if (!Guards.isRecord(point)) return null
    var label = CostAmounts.boundedText(point.label, 120)
    if (label.length === 0 || Guards.isUnsafeObjectKey(label)) return null
    if (!CostAmounts.hasMetricValue(point, context.showsTokens)) return null
    // Money is currency-scoped. Tokens include every provider's observed count.
    var pointCurrency = CostAmounts.boundedText(point.currency || "USD", 12)
    if (!context.showsTokens && pointCurrency !== context.currency) return null
    return { label: label, value: Math.max(0, CostAmounts.metricValue(point, context.showsTokens)),
        currency: context.currency }
}

export function addSpendDays(byDate, daily, context, measuredDates) {
    for (var i = 0; i < daily.length; i++) {
        var point = normalizedSpendDay(daily[i], context)
        if (!point) continue
        if (measuredDates) measuredDates.add(point.label)
        if (!Guards.hasOwnKey(byDate, point.label)) {
            byDate[point.label] = { label: point.label, value: 0, currency: context.currency }
        }
        byDate[point.label].value += point.value
        if (CostTrust.acceptedIncompleteRequests(daily[i]) > 0) byDate[point.label].partial = true
    }
}

export function spendPointRows(byDate, fmt, showsTokens) {
    var result = []
    for (var day in byDate) {
        if (!Guards.hasOwnKey(byDate, day)) continue
        var item = byDate[day]
        // A sum that overflowed is unavailable, never a fabricated zero.
        if (!isFinite(item.value)) continue
        item.displayValue = AnalysisAmounts.metricText(fmt, item.value, item.currency, showsTokens)
        result.push(item)
    }
    return result
}

export function projectData(snapshot) {
    if (!snapshot || typeof snapshot !== "object") return null
    var projects = snapshot.projects
    if (!projects || !Array.isArray(projects.rows)) return null
    return projects
}
