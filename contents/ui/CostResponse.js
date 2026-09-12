.pragma library
.import "ProviderNormalizer.js" as Normalizer
.import "CostPresentation.js" as CostPresentation
.import "SafeText.js" as SafeText

function boundedMessage(value) {
    return SafeText.cliMessage(SafeText.stripLoaderDiagnostics(value), SafeText.maximumCliMessageLength);
}

function normalizeSnapshot(item, requestedHistoryDays) {
    var provider = Normalizer.providerSnapshotKey(item.provider);
    var currency = Normalizer.boundedDisplayText(item.currencyCode || "USD", 12);
    var emittedDays = Normalizer.strictFiniteNumber(item.historyDays);
    var fallbackDays = Normalizer.strictFiniteNumber(requestedHistoryDays);
    var historyDays = isFinite(emittedDays) && emittedDays > 0 ? emittedDays
        : (isFinite(fallbackDays) && fallbackDays > 0 ? fallbackDays : 30);
    historyDays = Math.max(1, Math.min(Normalizer.maximumCostHistoryPoints, Math.floor(historyDays)));
    var totals = Normalizer.normalizeProviderCostTotals(provider, item.totals,
        item.last30DaysCostUSD, item.last30DaysTokens, currency);
    var trust = Normalizer.normalizeCostTrustMetadata(item);
    var summary = CostPresentation.costTrustSummary([{totals: totals, trust: trust}]);
    var modelSummary = Normalizer.normalizeCostModels(item.daily, currency, historyDays, item.updatedAt);
    return {
        provider: provider,
        currency: currency,
        historyDays: historyDays,
        historyCoverageEstablished: item.historyCoverageIsEstablished !== false,
        historyLabel: item.historyLabel ? Normalizer.boundedDisplayText(item.historyLabel, 120) : null,
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
        modelsTruncated: modelSummary.truncated,
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
    for (var i = 0; i < items.length; i++) {
        var item = items[i];
        if (Normalizer.costRecordHasError(item)) {
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
        costs: costs, failedProviders: failedProviders, message: message};
}
