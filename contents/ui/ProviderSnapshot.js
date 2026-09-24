.pragma library
.import "Guards.js" as Guards
.import "ProviderNormalizer.js" as Normalizer
.import "UsageDetails.js" as UsageDetails
.import "LegacyUsageDashboard.js" as LegacyUsageDashboard
.import "PacePresentation.js" as PacePresentation
.import "SafeText.js" as SafeText

function message(value) {
    return SafeText.cliMessage(SafeText.stripLoaderDiagnostics(value), SafeText.maximumCliMessageLength);
}

// Every later reader of the stored `resetsAt` parses it as a date string: the
// live countdown, the panel "resets within" rule, and absolute formatting. A
// numeric CLI date is epoch milliseconds, whose digits Date.parse cannot read,
// so it is stored in its ISO form instead.
function usableEpochMs(value) {
    return typeof value === "number" && isFinite(value) && Math.abs(value) <= 8640000000000000;
}

function resetsAtText(value) {
    if (typeof value === "number") {
        return usableEpochMs(value) ? new Date(value).toISOString() : "";
    }
    return Normalizer.boundedDisplayText(value === undefined || value === null ? "" : value, 128);
}

function windowSnapshot(window, pace, usageKnown, lane, label, receivedAtMs) {
    var metrics = Normalizer.rateWindowMetrics(window, pace, usageKnown);
    if (metrics === null) {
        return null;
    }
    var result = Guards.copyObject(metrics);
    result.lane = lane;
    result.label = label;
    result.paceObservedAtMs = receivedAtMs;
    result.resetsAt = resetsAtText(window.resetsAt);
    result.resetDescription = Normalizer.boundedDisplayText(window.resetDescription || "", 500);
    // Initial reset formatting accepts numeric dates; the stored reset label
    // continues to use the bounded CLI text, as it does for live quota rows.
    // A number Date cannot read is dropped: it would otherwise render as raw
    // digits in the quota row instead of the empty reset.
    result.resetValue = usableEpochMs(window.resetsAt) ? window.resetsAt
        : (typeof window.resetsAt === "string" ? Normalizer.boundedDisplayText(window.resetsAt, 500) : "");
    result.paceParts = PacePresentation.summaryParts(pace);
    return result;
}

function costFields(cost) {
    if (!Normalizer.isCliRecord(cost)) {
        return null;
    }
    return {
        used: Normalizer.strictFiniteNumber(cost.used),
        limit: Normalizer.strictFiniteNumber(cost.limit),
        personalUsed: Normalizer.strictFiniteNumber(cost.personalUsed),
        currencyCode: Normalizer.boundedDisplayText(cost.currencyCode || "USD", 12),
        period: cost.period ? Normalizer.boundedDisplayText(cost.period, 120) : null
    };
}

// Shared by usage refreshes and account discovery. Only bounded semantic data
// survives; QML adds localized labels, provider links, and the current costs.
function normalize(item, receivedAtMs) {
    if (!Normalizer.isCliRecord(item)) {
        return null;
    }
    var providerID = Normalizer.providerSnapshotKey(item.provider || "unknown") || "unknown";
    var usage = Normalizer.isCliRecord(item.usage) ? item.usage : {};
    var pace = Normalizer.isCliRecord(item.pace) ? item.pace : {};
    var rows = [];
    var lanes = ["primary", "secondary", "tertiary"];
    for (var i = 0; i < lanes.length; i++) {
        var lane = lanes[i];
        var row = windowSnapshot(usage[lane], pace[lane], true, lane, null, receivedAtMs);
        if (row) rows.push(row);
    }
    var extras = Array.isArray(usage.extraRateWindows) ? usage.extraRateWindows : [];
    for (var j = 0; j < Math.min(extras.length, Normalizer.maximumExtraRateWindows); j++) {
        var extra = extras[j];
        if (Normalizer.isCliRecord(extra) && Normalizer.isCliRecord(extra.window)) {
            var label = extra.title || extra.id;
            var extraRow = windowSnapshot(extra.window, null, extra.usageKnown !== false, "extra",
                label ? Normalizer.boundedDisplayText(label, 120) : null, receivedAtMs);
            if (extraRow) rows.push(extraRow);
        }
    }
    var identity = Normalizer.isCliRecord(usage.identity) ? usage.identity : {};
    var account = Normalizer.firstValidAccountIdentity([item.account, identity.accountEmail, usage.accountEmail]);
    var organization = Normalizer.firstValidAccountIdentity([identity.accountOrganization, usage.accountOrganization]);
    var loginMethod = Normalizer.firstValidAccountIdentity([identity.loginMethod, usage.loginMethod]);
    var error = Normalizer.isCliRecord(item.error) ? item.error : null;
    var errorMessage = error ? message(Normalizer.safeScalarText(error.message)) : "";
    var status = Normalizer.isCliRecord(item.status) ? item.status : null;
    var credits = Normalizer.isCliRecord(item.credits) ? item.credits : null;
    var codexCreditLimit = Normalizer.normalizeCodexCreditLimit(providerID,
        credits && Guards.hasOwnKey(credits, "codexCreditLimit") ? credits.codexCreditLimit : null);
    var providerDetails = UsageDetails.normalizeSections(usage.details);
    var dashboard = providerDetails.length > 0 ? null : LegacyUsageDashboard.normalize(usage, item);
    var hasSupplementalUsage = providerDetails.length > 0 || dashboard !== null || codexCreditLimit !== null;
    var placeholder = "";
    if (rows.length === 0 && !hasSupplementalUsage && (!error || errorMessage === "Found sessions, but no rate limit events yet.")) {
        var hasIdentity = account.length > 0 || organization.length > 0 || loginMethod.length > 0;
        placeholder = ["antigravity", "doubao", "codex"].indexOf(providerID) >= 0 && hasIdentity
            && !usage.primary && !usage.secondary && !usage.tertiary ? "limitsUnavailable" : "noUsage";
    }
    var displayName = null;
    for (var candidate of [item.displayName, item.title]) {
        if ((typeof candidate === "string" || typeof candidate === "number" || typeof candidate === "boolean") && candidate) {
            var candidateText = Normalizer.boundedDisplayText(candidate, 120);
            if (candidateText.length > 0) {
                displayName = candidateText;
                break;
            }
        }
    }
    var remaining = credits ? Normalizer.strictFiniteNumber(credits.remaining) : NaN;
    return {
        provider: providerID, displayName: displayName,
        source: Normalizer.boundedDisplayText(item.source || "", 120),
        version: Normalizer.boundedDisplayText(item.version || "", 120),
        account: Normalizer.boundedDisplayText(account, 256),
        organization: Normalizer.boundedDisplayText(organization, 256),
        loginMethod: Normalizer.boundedDisplayText(loginMethod, 120),
        planMethod: Normalizer.boundedDisplayText(loginMethod, Normalizer.maximumAccountIdentityLength),
        accountKey: Normalizer.accountKey({account: account, organization: organization, loginMethod: loginMethod}),
        rows: rows, providerDetails: providerDetails, usageDashboard: dashboard,
        providerCost: costFields(usage.providerCost),
        resetCredits: usage.codexResetCredits ? {availableCount: Normalizer.strictFiniteNumber(usage.codexResetCredits.availableCount)} : null,
        codexCreditLimit: codexCreditLimit,
        credits: isFinite(remaining) ? remaining : null,
        statusRecord: status ? {indicator: Normalizer.boundedDisplayText(Normalizer.safeScalarText(status.indicator), 500),
            description: Normalizer.boundedDisplayText(Normalizer.safeScalarText(status.description).trim(), 500)} : null,
        statusUrl: status ? Normalizer.boundedDisplayText(status.url || "", 4096) : "",
        statusSeverity: Normalizer.statusSeverity(status),
        statusIncidentKey: Normalizer.boundedDisplayText(Normalizer.statusIncidentKey(status), 128),
        commandFailed: error !== null, error: errorMessage, placeholder: placeholder,
        usageReceivedAtMs: receivedAtMs,
        updatedAt: Normalizer.boundedDisplayText(usage.updatedAt || (credits ? credits.updatedAt : ""), 128)
    };
}
