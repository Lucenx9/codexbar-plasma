.pragma library
.import "ProviderNormalizer.js" as Normalizer
.import "CostPresentation.js" as CostPresentation
.import "SafeText.js" as SafeText

function boundedMessage(value) {
    return SafeText.cliMessage(SafeText.stripLoaderDiagnostics(value), SafeText.maximumCliMessageLength);
}

// `--period all` reports the days since year 1. Size its window from the
// oldest recorded day to the scan day instead; NaN when no day is recorded.
// Like the daily normalization, read only the newest scan budget of records.
function recordedHistoryDays(daily, scanDay) {
    var first = Infinity;
    var last = -Infinity;
    var days = Array.isArray(daily) ? daily : [];
    for (var i = Math.max(0, days.length - Normalizer.maximumCostHistoryScanItems); i < days.length; i++) {
        var day = Normalizer.isCliRecord(days[i])
            ? Normalizer.parsedCalendarDateKey(days[i].date || days[i].day || days[i].dayKey) : null;
        if (day) {
            first = Math.min(first, day.timestampMs);
            last = Math.max(last, day.timestampMs);
        }
    }
    var scan = Normalizer.parsedCalendarDateKey(scanDay);
    if (scan && isFinite(first)) {
        last = Math.max(last, scan.timestampMs);
    }
    return isFinite(first) ? Math.round((last - first) / 86400000) + 1 : NaN;
}

function normalizeSnapshot(item, requestedHistoryDays) {
    var provider = Normalizer.providerSnapshotKey(item.provider);
    var currency = Normalizer.boundedDisplayText(item.currencyCode || "USD", 12);
    var period = CostPresentation.costPeriod(item.reportingPeriod);
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
    var aggregateDays = isFinite(recordedDays) ? Math.min(aggregateBound, recordedDays) : historyDays;
    var modelSummary = Normalizer.normalizeCostModels(item.daily, currency, aggregateDays, item.updatedAt, true, aggregateBound);
    var aggregateDaily = aggregateDays > historyDays
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
        historyLabel: item.historyLabel && period.length === 0 && !/^rolling:\d+$/.test(item.reportingPeriod)
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
        averageDaily: aggregateDaily ? {
            cost: CostPresentation.averageDailyValue(aggregateDaily, false),
            tokens: CostPresentation.averageDailyValue(aggregateDaily, true)
        } : null,
        daily: Normalizer.normalizeCostDaily(item.daily, currency, historyDays, item.updatedAt)
    };
}

// Only success and partial results contain replacement data. Other outcomes
// leave the controller's last completed snapshot untouched.
function response(stdoutValue, stderrValue, requestedHistoryDays) {
    var text = SafeText.cliJsonText(stdoutValue);
    if (text === null) {
        return {outcome: "tooLarge", message: ""};
    }
    if (text.trim().length === 0) {
        return {outcome: "empty", message: boundedMessage(stderrValue)};
    }
    var payload;
    try {
        payload = JSON.parse(text);
    } catch (error) {
        return {outcome: "invalidJson", message: boundedMessage(error.message)};
    }
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
                message = boundedMessage(Normalizer.safeScalarText(item.error.message));
            }
        } else {
            var cost = normalizeSnapshot(item, requestedHistoryDays);
            costs[cost.provider] = cost;
        }
    }
    return {outcome: failedProviders.length > 0 ? "partial" : "success",
        costs: costs, failedProviders: failedProviders, message: message,
        argumentsRejected: argumentsRejected};
}
