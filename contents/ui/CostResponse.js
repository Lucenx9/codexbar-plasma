.pragma library
.import "ProviderNormalizer.js" as Normalizer
.import "CostPresentation.js" as CostPresentation
.import "CliResponse.js" as CliResponse

// `--period all` reports the days since year 1. Size its window from the
// oldest recorded day to the scan day instead; dates after a known scan day
// cannot extend that span. NaN when no eligible day is recorded.
// Like the daily normalization, read only the newest scan budget of records.
function recordedHistoryDays(daily, scanDay) {
    var first = Infinity;
    var last = -Infinity;
    var scan = Normalizer.parsedCalendarDateKey(scanDay);
    var days = Array.isArray(daily) ? daily : [];
    for (var i = Math.max(0, days.length - Normalizer.maximumCostHistoryScanItems); i < days.length; i++) {
        var day = Normalizer.isCliRecord(days[i])
            ? Normalizer.parsedCalendarDateKey(days[i].date || days[i].day || days[i].dayKey) : null;
        if (day && (!scan || day.timestampMs <= scan.timestampMs)) {
            first = Math.min(first, day.timestampMs);
            last = Math.max(last, day.timestampMs);
        }
    }
    if (scan && isFinite(first)) {
        last = Math.max(last, scan.timestampMs);
    }
    return isFinite(first) ? Math.round((last - first) / 86400000) + 1 : NaN;
}

// Long sparse histories need a calendar denominator, not an array with one
// entry per day. Inspect only the same bounded input tail as the normalizer.
function longHistoryAverage(items, currency, recordedDays, scanDay) {
    var source = Array.isArray(items) ? items : [];
    var first = Math.max(0, source.length - Normalizer.maximumCostHistoryScanItems);
    var scan = Normalizer.parsedCalendarDateKey(scanDay);
    var firstDayMs = scan ? scan.timestampMs - (recordedDays - 1) * 86400000 : NaN;
    var canFill = first === 0 && scan !== null;
    var seen = ({});
    var blocked = ({});
    var retained = [];
    for (var i = first; i < source.length; i++) {
        var item = source[i];
        if (!Normalizer.isCliRecord(item)) continue;
        var day = Normalizer.parsedCalendarDateKey(Normalizer.boundedDisplayText(
            item.date || item.day || item.dayKey || "", 120));
        if (scan && day && (day.timestampMs > scan.timestampMs || day.timestampMs < firstDayMs)) continue;
        if (!Normalizer.costRecordHasAmounts(item)) {
            if (day) blocked[day.key] = true;
            continue;
        }
        if (!day || Normalizer.hasOwnKey(seen, day.key)) canFill = false;
        if (day) seen[day.key] = true;
        retained.push(item);
    }
    // Match daily gap filling: an amount row covers its date even when a
    // second, incomplete record for the same date contains no amounts.
    canFill = canFill && Object.keys(blocked).every(function(key) {
        return Normalizer.hasOwnKey(seen, key);
    });
    var daily = Normalizer.normalizeCostDaily(retained, currency,
        Normalizer.maximumCostHistoryScanItems, undefined, Normalizer.maximumCostHistoryScanItems);
    var zeroDays = canFill && daily.length > 0 ? Math.max(0, recordedDays - daily.length) : 0;
    return {
        cost: CostPresentation.averageDailyValue(daily, false, zeroDays),
        tokens: CostPresentation.averageDailyValue(daily, true, zeroDays)
    };
}

function normalizeSnapshot(item, requestedHistoryDays) {
    var provider = Normalizer.providerSnapshotKey(item.provider);
    var currency = Normalizer.boundedDisplayText(item.currencyCode || "USD", 12);
    var reportingPeriod = typeof item.reportingPeriod === "string" ? item.reportingPeriod : "";
    var period = CostPresentation.costPeriod(reportingPeriod);
    var scanDay = Normalizer.localCalendarDateKey(item.updatedAt);
    var emittedDays = Normalizer.strictFiniteNumber(item.historyDays);
    var recordedDays = period === "all" ? recordedHistoryDays(item.daily, scanDay) : NaN;
    if (isFinite(recordedDays)) {
        emittedDays = recordedDays;
    }
    var fallbackDays = Normalizer.strictFiniteNumber(requestedHistoryDays);
    var historyDays = isFinite(emittedDays) && emittedDays > 0 ? emittedDays
        : (isFinite(fallbackDays) && fallbackDays > 0 ? fallbackDays : 30);
    historyDays = Math.max(1, Math.min(Normalizer.maximumCostHistoryPoints, Math.floor(historyDays)));
    var totals = Normalizer.normalizeProviderCostTotals(provider, item.totals,
        item.last30DaysCostUSD, item.last30DaysTokens, currency);
    var trust = Normalizer.normalizeCostTrustMetadata(item);
    var summary = CostPresentation.costTrustSummary([{totals: totals, trust: trust}]);
    // All history charts at most the newest year, but its model totals and
    // daily average cover every recorded day within the scan budget.
    var aggregateBound = Normalizer.maximumCostHistoryScanItems;
    var aggregateDays = isFinite(recordedDays) ? recordedDays : historyDays;
    var modelSummary = Normalizer.normalizeCostModels(item.daily, currency, aggregateDays, item.updatedAt, true, Math.max(aggregateBound, aggregateDays));
    var aggregateDaily = aggregateDays > historyDays && aggregateDays <= aggregateBound
        ? Normalizer.normalizeCostDaily(item.daily, currency, aggregateDays, item.updatedAt, aggregateBound) : null;
    return {
        provider: provider,
        currency: currency,
        period: period,
        historyDays: historyDays,
        historyCoverageEstablished: item.historyCoverageIsEstablished !== false,
        // The local date of the scan: "today" is that day's total. Empty when
        // the CLI omits a usable timestamp.
        scanDay: scanDay,
        // CLI 0.67.0 titles its ranges in English. The widget titles rolling
        // and calendar ranges itself in the user's language.
        historyLabel: item.historyLabel && period.length === 0 && !/^rolling:\d+$/.test(reportingPeriod)
            ? Normalizer.boundedDisplayText(item.historyLabel, 120) : null,
        labelDays: isFinite(emittedDays) && emittedDays > 0 ? Math.max(1, Math.floor(emittedDays)) : historyDays,
        trust: trust,
        valueMode: summary ? summary.valueMode : "plain",
        today: Normalizer.normalizeProviderCostTotals(provider, null, item.sessionCostUSD, item.sessionTokens, currency),
        // Keep the current-session line independent of the history trust mode.
        sessionCost: Normalizer.normalizeProviderCostAmount(provider, item.sessionCostUSD),
        sessionTokens: Normalizer.strictFiniteNumber(item.sessionTokens),
        totals: totals,
        projects: Normalizer.normalizeCostProjects(item.projects, currency),
        models: modelSummary.rows,
        tokenRanking: modelSummary.tokenRanking || { rows: [], omitted: 0, truncated: false,
            sourceTruncated: false, hasUnknownCost: false },
        modelsTruncated: modelSummary.truncated,
        // Null when the charted days already cover the whole range.
        averageDaily: aggregateDays > aggregateBound
            ? longHistoryAverage(item.daily, currency, recordedDays, scanDay)
            : aggregateDaily ? {
            cost: CostPresentation.averageDailyValue(aggregateDaily, false),
            tokens: CostPresentation.averageDailyValue(aggregateDaily, true)
        } : null,
        daily: Normalizer.normalizeCostDaily(item.daily, currency, historyDays, item.updatedAt)
    };
}

// Only success and partial results contain replacement data. Other outcomes
// leave the controller's last completed snapshot untouched.
function response(stdoutValue, stderrValue, requestedHistoryDays, exitCode) {
    var parsed = CliResponse.decode(stdoutValue, stderrValue, exitCode, Normalizer.maximumCostSnapshots);
    if (parsed.outcome !== "success") return parsed;
    var payload = parsed.payload;
    var items = Normalizer.normalizeCostEnvelope(payload);
    if (items === null) {
        return {outcome: "unsupported", message: ""};
    }
    var costs = {};
    var failedProviders = [];
    var message = "";
    // The CLI answers an option it does not know, such as `--period` before
    // 0.67.0, with an `args` error record instead of any provider data.
    var argumentsRejected = false;
    for (var i = 0; i < items.length; i++) {
        var item = items[i];
        if (Normalizer.costRecordHasError(item)) {
            argumentsRejected = argumentsRejected || (Normalizer.isCliRecord(item.error) && item.error.kind === "args");
            failedProviders.push(item.provider);
            if (message.length === 0 && item.error && item.error.message) {
                message = CliResponse.message(Normalizer.safeScalarText(item.error.message));
            }
        } else {
            var cost = normalizeSnapshot(item, requestedHistoryDays);
            costs[cost.provider] = cost;
        }
    }
    // Argument rejection describes the entire command, not a failed provider.
    // No replacement snapshot exists, including for a different history range.
    if (argumentsRejected)
        return {outcome: "commandFailed", message: message, argumentsRejected: true};
    return {outcome: failedProviders.length > 0 ? "partial" : "success",
        costs: costs, failedProviders: failedProviders, message: message,
        argumentsRejected: argumentsRejected};
}
