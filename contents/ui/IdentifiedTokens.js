.pragma library
.import "Guards.js" as Guards
.import "SafeText.js" as SafeText

var maximumRecords = 50000;
var maximumCount = 9007199254740991;
var dayMs = 86400000;

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
    return {outcome: "ready", command: command, historyDays: days,
        startUnixMs: start, endUnixMs: endUnixMs, remoteHost: remoteHost};
}

// IDs exist only within this bounded decoder. Duplicate ledger rows are rejected;
// native parsing and cross-source identity reconciliation belong to the CLI.
function ledgerSummary(ledger, plan) {
    if (!record(ledger) || ledger.schemaVersion !== 1 || ledger.provider !== "codex"
            || ledger.startUnixMs !== plan.startUnixMs || ledger.endUnixMs !== plan.endUnixMs
            || typeof ledger.partial !== "boolean" || !count(ledger.excludedCount)
            || !Array.isArray(ledger.records) || ledger.records.length > maximumRecords
            || !Array.isArray(ledger.conflictingIDs) || ledger.conflictingIDs.length > maximumRecords) return null;
    var conflicts = ({});
    var seen = ({});
    var digest = /^[0-9a-f]{64}$/;
    for (var i = 0; i < ledger.conflictingIDs.length; i++) {
        var id = ledger.conflictingIDs[i];
        if (typeof id !== "string" || id.length !== 64 || !digest.test(id) || Guards.hasOwnKey(conflicts, id)) return null;
        conflicts[id] = true;
    }
    var total = 0;
    var allTokens = 0;
    var requests = 0;
    for (var j = 0; j < ledger.records.length; j++) {
        var row = ledger.records[j];
        if (!record(row) || typeof row.id !== "string" || row.id.length !== 64 || !digest.test(row.id)
                || Guards.hasOwnKey(seen, row.id) || !count(row.timestampUnixMs)
                || row.timestampUnixMs < plan.startUnixMs || row.timestampUnixMs > plan.endUnixMs
                || !count(row.inputTokens) || !count(row.outputTokens) || !count(row.cacheReadTokens)
                || row.cacheReadTokens > row.inputTokens
                || (row.reasoningTokens !== undefined && row.reasoningTokens !== null
                    && (!count(row.reasoningTokens) || row.reasoningTokens > row.outputTokens))) return null;
        seen[row.id] = true;
        var tokens = row.inputTokens + row.outputTokens;
        allTokens += tokens;
        if (!count(tokens) || !count(allTokens)) return null;
        if (!Guards.hasOwnKey(conflicts, row.id)) {
            total += tokens;
            requests++;
        }
    }
    return {totalTokens: total, requestCount: requests, conflictCount: ledger.conflictingIDs.length,
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
        startUnixMs: plan.startUnixMs, endUnixMs: plan.endUnixMs, historyDays: plan.historyDays};
}

function envelope(payload, plan, exit) {
    var remote = plan.remoteHost.length > 0;
    if (!record(payload) || !Array.isArray(payload.reports)
            || payload.reports.length !== (remote ? 2 : 1)
            || typeof payload.allSourcesAvailable !== "boolean" || typeof payload.partial !== "boolean") return null;
    var sources = [];
    for (var i = 0; i < payload.reports.length; i++) {
        var report = payload.reports[i];
        if (!record(report) || report.host !== (i === 0 ? "local" : plan.remoteHost)) return null;
        var hasLedger = report.ledger !== null && report.ledger !== undefined;
        if (hasLedger) {
            if (report.error !== undefined && report.error !== null) return null;
            var summary = ledgerSummary(report.ledger, plan);
            if (!summary) return null;
            sources.push(summary);
        } else {
            if (typeof report.error !== "string") return null;
            sources.push(null);
        }
    }
    var available = sources.filter(function(source) { return source !== null; });
    var allAvailable = available.length === sources.length;
    if (payload.allSourcesAvailable !== allAvailable || exit !== (allAvailable ? 0 : 1)) return null;
    var subtotal = payload.subtotal;
    if (available.length === 0) {
        return (subtotal === null || subtotal === undefined) && payload.partial
            ? {outcome: "unavailable"} : null;
    }
    // Successful local-only collection uses a bare ledger, never this envelope.
    if (!remote || !record(subtotal) || subtotal.kind !== "identified-request-subtotal"
            || subtotal.costUSD !== null || typeof subtotal.partial !== "boolean"
            || !count(subtotal.totalTokens) || !count(subtotal.requestCount)
            || !count(subtotal.conflictCount) || !count(subtotal.excludedCount)
            || subtotal.requestCount > maximumRecords * 2 || subtotal.conflictCount > maximumRecords * 2
            || (subtotal.requestCount === 0 && subtotal.totalTokens !== 0)
            || payload.partial !== (!allAvailable || subtotal.partial)) return null;
    var tokens = 0, requests = 0, excluded = 0, conflicts = 0, partial = false;
    for (var j = 0; j < available.length; j++) {
        tokens += available[j].totalTokens;
        requests += available[j].requestCount;
        excluded += available[j].excludedCount;
        conflicts = Math.max(conflicts, available[j].conflictCount);
        partial = partial || available[j].partial;
    }
    if (!count(tokens) || !count(excluded) || subtotal.excludedCount !== excluded
            || subtotal.totalTokens > tokens || subtotal.requestCount > requests
            || subtotal.conflictCount < conflicts
            || subtotal.partial !== (partial || subtotal.conflictCount > 0 || excluded > 0)) return null;
    if (available.length === 1) {
        var only = available[0];
        if (subtotal.totalTokens !== only.totalTokens || subtotal.requestCount !== only.requestCount
                || subtotal.conflictCount !== only.conflictCount || subtotal.partial !== only.partial) return null;
    }
    return {outcome: "data", snapshot: snapshot(subtotal, plan, sources[0] !== null,
        sources[1] !== null, payload.partial)};
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
        var summary = exit === 0 ? ledgerSummary(payload, plan) : null;
        return summary ? {outcome: "data", snapshot: snapshot(summary, plan, true, false, summary.partial)}
            : {outcome: "unsupported"};
    }
    return envelope(payload, plan, exit) || {outcome: "unsupported"};
}
