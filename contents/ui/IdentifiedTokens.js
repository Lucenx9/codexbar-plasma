.pragma library
.import "Guards.js" as Guards
.import "SafeText.mjs" as SafeText

var maximumRecords = 50000;
var maximumCount = 9007199254740991;
var dayMs = 86400000;
var processTimeoutSeconds = 110;
var processKillAfterSeconds = 5;
var requestDeadlineMs = 120000;

function validHost(host) {
    return typeof host === "string" && host.length > 0 && host.length <= 255
        && host.charAt(0) !== "-" && !/[^A-Za-z0-9._@:%\[\]-]/.test(host);
}

function count(value) {
    return typeof value === "number" && isFinite(value)
        && value >= 0 && value <= maximumCount && Math.floor(value) === value;
}

function record(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function requestPlan(commandPath, days, endUnixMs, remoteHost) {
    if (typeof commandPath !== "string" || commandPath.trim().length === 0
            || !count(days) || days < 1 || days > 365 || !count(endUnixMs)
            || endUnixMs > 253402300799999 || typeof remoteHost !== "string"
            || (remoteHost.length > 0 && !validHost(remoteHost))) {
        return {outcome: "invalidSettings"};
    }
    var start = endUnixMs - endUnixMs % dayMs - (days - 1) * dayMs;
    if (start < 0) return {outcome: "invalidSettings"};
    var command = Guards.shellQuote(commandPath)
        + " cost --provider codex --days " + days
        + " --identified-only --identified-end " + endUnixMs + " --json";
    if (remoteHost.length > 0) command += " --remote " + Guards.shellQuote(remoteHost);
    // Keep timeout outside the engine-owned shell's lifetime. Disconnecting
    // that shell must not remove the bound from its CLI/SSH descendants.
    var script = "command -v timeout >/dev/null 2>&1 || exit 127\n"
        + "timeout --kill-after=" + processKillAfterSeconds + "s " + processTimeoutSeconds + "s " + command
        + " &\nwait $!";
    return {outcome: "ready", command: "/bin/sh -c " + Guards.shellQuote(script), historyDays: days,
        startUnixMs: start, endUnixMs: endUnixMs, remoteHost: remoteHost};
}

function supportedSchema(version) {
    return version === 1 || version === 2;
}

function boundedRecords(value) {
    return Array.isArray(value) && value.length <= maximumRecords;
}

function ledgerMetadataValid(ledger, plan) {
    if (!record(ledger) || !supportedSchema(ledger.schemaVersion) || ledger.provider !== "codex") return false;
    if (ledger.startUnixMs !== plan.startUnixMs || ledger.endUnixMs !== plan.endUnixMs) return false;
    return typeof ledger.partial === "boolean" && count(ledger.excludedCount)
        && boundedRecords(ledger.records) && boundedRecords(ledger.conflictingIDs);
}

function validDigest(value) {
    return typeof value === "string" && value.length === 64 && /^[0-9a-f]{64}$/.test(value);
}

function conflictSet(ids) {
    var result = ({});
    for (var i = 0; i < ids.length; i++) {
        var id = ids[i];
        if (!validDigest(id) || Guards.hasOwnKey(result, id)) return null;
        result[id] = true;
    }
    return result;
}

function tokenCountsValid(row) {
    if (!count(row.inputTokens) || !count(row.outputTokens) || !count(row.cacheReadTokens)) return false;
    if (row.cacheReadTokens > row.inputTokens) return false;
    if (row.reasoningTokens === undefined || row.reasoningTokens === null) return true;
    return count(row.reasoningTokens) && row.reasoningTokens <= row.outputTokens;
}

function pricingFieldsValid(row) {
    if (typeof row.includedInPlan !== "boolean") return false;
    var model = row.model;
    if (model !== undefined && model !== null) {
        if (typeof model !== "string" || model.length === 0 || model.length > 1024) return false;
    }
    var mode = row.pricingMode;
    return mode === undefined || mode === null || mode === "standard" || mode === "priority";
}

function ledgerRowValid(row, plan, schema) {
    if (!record(row) || !validDigest(row.id) || !count(row.timestampUnixMs)) return false;
    if (row.timestampUnixMs < plan.startUnixMs || row.timestampUnixMs > plan.endUnixMs) return false;
    if (!tokenCountsValid(row)) return false;
    return schema !== 2 || pricingFieldsValid(row);
}

// Validate every row, including conflicts, before publishing any aggregate.
function recordTotals(ledger, plan, conflicts) {
    var seen = ({});
    var total = 0;
    var allTokens = 0;
    var requests = 0;
    for (var j = 0; j < ledger.records.length; j++) {
        var row = ledger.records[j];
        if (!ledgerRowValid(row, plan, ledger.schemaVersion) || Guards.hasOwnKey(seen, row.id)) return null;
        seen[row.id] = true;
        var tokens = row.inputTokens + row.outputTokens;
        allTokens += tokens;
        if (!count(tokens) || !count(allTokens)) return null;
        if (!Guards.hasOwnKey(conflicts, row.id)) {
            total += tokens;
            requests++;
        }
    }
    return {totalTokens: total, requestCount: requests};
}

// IDs exist only within this bounded decoder. Duplicate ledger rows are rejected;
// native parsing and cross-source identity reconciliation belong to the CLI.
function ledgerSummary(ledger, plan) {
    if (!ledgerMetadataValid(ledger, plan)) return null;
    var conflicts = conflictSet(ledger.conflictingIDs);
    if (!conflicts) return null;
    var totals = recordTotals(ledger, plan, conflicts);
    if (!totals) return null;
    return {schemaVersion: ledger.schemaVersion, totalTokens: totals.totalTokens, requestCount: totals.requestCount,
        conflictCount: ledger.conflictingIDs.length,
        excludedCount: ledger.excludedCount,
        partial: ledger.partial || ledger.excludedCount > 0 || ledger.conflictingIDs.length > 0};
}

function snapshot(summary, plan, localAvailable, remoteAvailable, partial) {
    return {totalTokens: summary.totalTokens, requestCount: summary.requestCount,
        conflictCount: summary.conflictCount, excludedCount: summary.excludedCount,
        requestsPartial: summary.partial, partial: partial,
        localAvailable: localAvailable, remoteAvailable: remoteAvailable,
        remoteRequested: plan.remoteHost.length > 0,
        allSourcesAvailable: localAvailable && (plan.remoteHost.length === 0 || remoteAvailable),
        apiEstimateUSD: null, unpricedRequestCount: null,
        startUnixMs: plan.startUnixMs, endUnixMs: plan.endUnixMs, historyDays: plan.historyDays};
}

function reportSummary(report, plan, index) {
    if (!record(report) || report.host !== (index === 0 ? "local" : plan.remoteHost)) return null;
    var source = index === 0 ? "local" : "ssh";
    if (report.source !== undefined && report.source !== source) return null;
    var hasLedger = report.ledger !== null && report.ledger !== undefined;
    if (!hasLedger) {
        return typeof report.error === "string" ? {outcome: "failed", summary: null} : null;
    }
    if (report.error !== undefined && report.error !== null) return null;
    if (record(report.ledger) && report.ledger.schemaVersion !== undefined
            && !supportedSchema(report.ledger.schemaVersion)) return {outcome: "schemaMismatch"};
    var summary = ledgerSummary(report.ledger, plan);
    return summary ? {outcome: "data", summary: summary} : null;
}

function reportMetadataValid(report, index) {
    return report.source === (index === 0 ? "local" : "ssh")
        && typeof report.collectedAt === "string" && isFinite(Date.parse(report.collectedAt));
}

function envelopeSources(reports, plan) {
    var sources = [];
    var schema = null;
    for (var i = 0; i < reports.length; i++) {
        var result = reportSummary(reports[i], plan, i);
        if (!result) return null;
        if (result.outcome === "schemaMismatch") return result;
        var summary = result.summary;
        sources.push(summary);
        if (!summary) continue;
        if (schema !== null && schema !== summary.schemaVersion) return {outcome: "schemaMismatch"};
        schema = summary.schemaVersion;
        if (schema === 2 && !reportMetadataValid(reports[i], i)) return null;
    }
    return {outcome: "data", sources: sources, schema: schema,
        available: sources.filter(function(source) { return source !== null; })};
}

function subtotalCountsValid(subtotal) {
    if (!count(subtotal.totalTokens) || !count(subtotal.requestCount)
            || !count(subtotal.conflictCount) || !count(subtotal.excludedCount)) return false;
    if (subtotal.requestCount > maximumRecords * 2 || subtotal.conflictCount > maximumRecords * 2) return false;
    return subtotal.requestCount !== 0 || subtotal.totalTokens === 0;
}

function subtotalShapeValid(subtotal) {
    return record(subtotal) && subtotal.kind === "identified-request-subtotal"
        && typeof subtotal.partial === "boolean" && subtotalCountsValid(subtotal);
}

function estimateValid(value) {
    return typeof value === "number" && isFinite(value) && value >= 0 && value <= maximumCount;
}

function subtotalPricingValid(subtotal, schema) {
    if (schema === 1) return subtotal.costUSD === null;
    if (!count(subtotal.unpricedRequestCount) || subtotal.unpricedRequestCount > subtotal.requestCount) return false;
    if (subtotal.costUSD !== null && !estimateValid(subtotal.costUSD)) return false;
    if ((subtotal.costUSD === null) !== (subtotal.unpricedRequestCount > 0)) return false;
    return subtotal.requestCount !== 0 || subtotal.costUSD === 0;
}

function sourceTotals(available) {
    var totals = {tokens: 0, requests: 0, excluded: 0, conflicts: 0, partial: false};
    for (var i = 0; i < available.length; i++) {
        var source = available[i];
        totals.tokens += source.totalTokens;
        totals.requests += source.requestCount;
        totals.excluded += source.excludedCount;
        totals.conflicts = Math.max(totals.conflicts, source.conflictCount);
        totals.partial = totals.partial || source.partial;
    }
    return totals;
}

function singleSourceMatches(subtotal, source) {
    return subtotal.totalTokens === source.totalTokens && subtotal.requestCount === source.requestCount
        && subtotal.conflictCount === source.conflictCount && subtotal.partial === source.partial;
}

function subtotalMatchesSources(subtotal, available) {
    var totals = sourceTotals(available);
    if (!count(totals.tokens) || !count(totals.excluded) || subtotal.excludedCount !== totals.excluded) return false;
    if (subtotal.totalTokens > totals.tokens || subtotal.requestCount > totals.requests
            || subtotal.conflictCount < totals.conflicts) return false;
    if (subtotal.partial !== (totals.partial || subtotal.conflictCount > 0 || totals.excluded > 0)) return false;
    return available.length !== 1 || singleSourceMatches(subtotal, available[0]);
}

function subtotalSnapshot(payload, plan, exit, sourceState) {
    var sources = sourceState.sources;
    var available = sourceState.available;
    var allAvailable = available.length === sources.length;
    if (payload.allSourcesAvailable !== allAvailable || exit !== (allAvailable ? 0 : 1)) return null;
    var subtotal = payload.subtotal;
    if (available.length === 0) {
        return (subtotal === null || subtotal === undefined) && payload.partial
            ? {outcome: "unavailable"} : null;
    }
    // Successful local-only collection uses a bare ledger, never this envelope.
    if (plan.remoteHost.length === 0 || !subtotalShapeValid(subtotal)) return null;
    if (payload.partial !== (!allAvailable || subtotal.partial)) return null;
    if (!subtotalPricingValid(subtotal, sourceState.schema) || !subtotalMatchesSources(subtotal, available)) return null;
    var result = snapshot(subtotal, plan, sources[0] !== null,
        sources[1] !== null, payload.partial);
    result.apiEstimateUSD = sourceState.schema === 2 ? subtotal.costUSD : null;
    result.unpricedRequestCount = sourceState.schema === 2 ? subtotal.unpricedRequestCount : null;
    return {outcome: "data", snapshot: result};
}

function envelope(payload, plan, exit) {
    var remote = plan.remoteHost.length > 0;
    if (!record(payload) || !Array.isArray(payload.reports)
            || payload.reports.length !== (remote ? 2 : 1)
            || typeof payload.allSourcesAvailable !== "boolean" || typeof payload.partial !== "boolean") return null;
    var sources = envelopeSources(payload.reports, plan);
    if (!sources || sources.outcome === "schemaMismatch") return sources;
    return subtotalSnapshot(payload, plan, exit, sources);
}

function decode(stdoutText, exitCode, plan) {
    if (Guards.isCommandPathFailure(exitCode)) return {outcome: "commandUnavailable"};
    var exit = typeof exitCode === "number" ? exitCode
        : (typeof exitCode === "string" && /^(0|1|124|137)$/.test(exitCode) ? Number(exitCode) : NaN);
    if (exit === 124 || exit === 137) return {outcome: "timeout"};
    if (exit !== 0 && exit !== 1) return {outcome: "unsupported"};
    if (typeof stdoutText !== "string") return {outcome: "empty"};
    var text = SafeText.cliJsonText(stdoutText);
    if (text === null) return {outcome: "tooLarge"};
    if (text.trim().length === 0) return {outcome: "empty"};
    var payload;
    try { payload = JSON.parse(text); } catch (error) { return {outcome: "invalidJson"}; }
    if (plan.remoteHost.length === 0 && record(payload) && payload.schemaVersion !== undefined) {
        if (!supportedSchema(payload.schemaVersion)) return {outcome: "schemaMismatch"};
        var summary = exit === 0 ? ledgerSummary(payload, plan) : null;
        return summary ? {outcome: "data", snapshot: snapshot(summary, plan, true, false, summary.partial)}
            : {outcome: "unsupported"};
    }
    return envelope(payload, plan, exit) || {outcome: "unsupported"};
}
