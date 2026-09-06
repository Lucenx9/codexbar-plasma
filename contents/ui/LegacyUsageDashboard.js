.pragma library
.import "ProviderNormalizer.js" as Normalizer

var maximumRows = 10;
var maximumKpis = 4;
var maximumDepth = 4;

// Return display data only. Label keys and numeric parts are localized by QML;
// no raw dashboard record survives this boundary.
function normalize(usage, item) {
    usage = Normalizer.isCliRecord(usage) ? usage : ({});
    item = Normalizer.isCliRecord(item) ? item : ({});
    var sources = [
        {
            labelKey: "codexDashboard",
            value: item.openaiDashboard
        },
        {
            labelKey: "openaiApi",
            value: usage.openAIAPIUsage
        },
        {
            labelKey: "openRouter",
            value: usage.openRouterUsage
        },
        {
            labelKey: "claudeAdmin",
            value: usage.claudeAdminAPIUsage
        },
        {
            labelKey: "poe",
            value: usage.poeUsage
        },
        {
            labelKey: "deepseek",
            value: usage.deepseekUsage
        },
        {
            labelKey: "minimax",
            value: usage.minimaxUsage
        },
        {
            labelKey: "zai",
            value: usage.zaiUsage
        }
    ];
    var kpis = [];
    var rows = [];
    for (var i = 0; i < sources.length; i++) {
        var sourceRows = dashboardRows(sources[i].value, [], 0);
        if (sourceRows.length === 0) {
            continue;
        }
        if (kpis.length < maximumKpis) {
            kpis.push({
                labelKey: sources[i].labelKey,
                label: "",
                parts: sourceRows[0].parts,
                name: sourceRows[0].name
            });
        }
        for (var j = 0; j < sourceRows.length && rows.length < maximumRows; j++) {
            rows.push(sourceRows[j]);
        }
        if (rows.length >= maximumRows && kpis.length >= maximumKpis) {
            break;
        }
    }
    return kpis.length > 0 || rows.length > 0 ? {
        kpis: kpis,
        rows: rows
    } : null;
}

function dashboardRows(source, seen, depth) {
    if (!Normalizer.isCliRecord(source) || depth > maximumDepth || seen.indexOf(source) !== -1) {
        return [];
    }
    seen.push(source);
    var rows = [];
    appendMetric(rows, "codeReviewRemaining", source.codeReviewRemainingPercent, "percent");
    appendMetric(rows, "creditsRemaining", source.creditsRemaining, "number");
    appendMetric(rows, "plan", source.accountPlan, "text");
    appendMetric(rows, "signedIn", source.signedInEmail, "text");
    appendPeriod(rows, "today", "", source.currentDay || source.today);
    appendPeriod(rows, "last7Days", "", source.last7Days);
    appendPeriod(rows, "last30Days", source.historyWindowLabel, source.last30Days);
    appendPeriod(rows, "currentMonth", "", source.currentMonth || source.month || source.billingSummary);
    appendTop(rows, "topModel", source.topModels);
    appendTop(rows, "usageMix", source.topUsageTypes);

    var daily = latestRecord(source.daily);
    if (daily) {
        appendPeriod(rows, "latest", daily.label || daily.day || daily.date, daily);
    }
    var breakdown = latestRecord(source.usageBreakdown || source.dailyBreakdown);
    if (breakdown) {
        appendPeriod(rows, "latestDashboardDay", breakdown.day || breakdown.date || breakdown.label, {
            costUSD: breakdown.costUSD,
            totalTokens: breakdown.totalTokens,
            requests: breakdown.requests,
            points: breakdown.points,
            value: breakdown.totalCreditsUsed
        });
    }
    if (rows.length < maximumRows && depth < maximumDepth) {
        var modelRows = dashboardRows(source.modelUsage, seen, depth + 1);
        for (var i = 0; i < modelRows.length && rows.length < maximumRows; i++) {
            rows.push(modelRows[i]);
        }
    }
    seen.pop();
    return rows.slice(0, maximumRows);
}

function row(labelKey, label, parts, name) {
    return {
        labelKey: label ? "" : labelKey,
        label: label ? Normalizer.boundedDisplayText(label, 120) : "",
        parts: parts,
        name: name || ""
    };
}

function metric(value, kind) {
    if (value === null || value === undefined) {
        return null;
    }
    if (kind === "text") {
        var text = Normalizer.boundedDisplayText(value, 120);
        return text.length > 0 ? {
            kind: "text",
            value: text
        } : null;
    }
    var numeric = Normalizer.strictFiniteNumber(value);
    if (isFinite(numeric)) {
        return {
            kind: kind,
            value: numeric
        };
    }
    if (kind === "number" && typeof value === "string") {
        return metric(value, "text");
    }
    return null;
}

function appendMetric(rows, labelKey, value, kind) {
    var part = metric(value, kind);
    if (part) {
        rows.push(row(labelKey, "", [part], ""));
    }
}

function appendPeriod(rows, labelKey, label, source) {
    if (!Normalizer.isCliRecord(source)) {
        return;
    }
    var parts = [];
    var currency = Normalizer.boundedDisplayText(source.currency || source.currencyCode || "USD", 12);
    var cost = Normalizer.firstStrictFiniteNumber(source.costUSD, source.cost);
    if (!isFinite(cost)) {
        cost = Normalizer.strictFiniteNumber(source.totalCost);
    }
    var tokens = Normalizer.firstStrictFiniteNumber(source.totalTokens, source.tokens);
    var requests = Normalizer.firstStrictFiniteNumber(source.requests, source.requestCount);
    var points = Normalizer.firstStrictFiniteNumber(source.points, source.totalPoints);
    if (isFinite(cost)) {
        parts.push({
            kind: "currency",
            value: cost,
            currency: currency
        });
    }
    if (isFinite(tokens) && tokens > 0) {
        parts.push({
            kind: "tokens",
            value: tokens
        });
    }
    if (isFinite(requests) && requests > 0) {
        parts.push({
            kind: "requests",
            value: requests
        });
    }
    if (isFinite(points) && points > 0) {
        parts.push({
            kind: "points",
            value: points
        });
    }
    if (parts.length === 0) {
        var fallback = Normalizer.firstStrictFiniteNumber(source.value, Normalizer.firstStrictFiniteNumber(source.total, source.used));
        if (!isFinite(fallback)) {
            var aliases = [source.value, source.total, source.used];
            fallback = "";
            for (var i = 0; i < aliases.length && fallback.length === 0; i++) {
                if (typeof aliases[i] === "string") {
                    fallback = Normalizer.boundedDisplayText(aliases[i], 120);
                }
            }
        }
        var fallbackPart = metric(fallback, "number");
        if (fallbackPart) {
            parts.push(fallbackPart);
        }
    }
    if (parts.length > 0) {
        rows.push(row(labelKey, label, parts, ""));
    }
}

function appendTop(rows, labelKey, items) {
    if (!Array.isArray(items) || items.length === 0 || !Normalizer.isCliRecord(items[0])) {
        return;
    }
    var item = items[0];
    var name = Normalizer.boundedDisplayText(item.name || item.model || item.label || item.type || "", 120);
    if (name.length === 0) {
        return;
    }
    var suffixes = [
        {
            kind: "currency",
            value: item.costUSD,
            currency: "USD"
        },
        {
            kind: "points",
            value: item.points
        },
        {
            kind: "tokens",
            value: item.totalTokens
        },
        {
            kind: "requests",
            value: item.requests
        }
    ];
    var parts = [];
    for (var i = 0; i < suffixes.length; i++) {
        var numeric = Normalizer.strictFiniteNumber(suffixes[i].value);
        if (isFinite(numeric)) {
            suffixes[i].value = numeric;
            parts.push(suffixes[i]);
            break;
        }
    }
    rows.push(row(labelKey, "", parts, name));
}

function latestRecord(items) {
    if (!Array.isArray(items) || items.length === 0) {
        return null;
    }
    var item = items[items.length - 1];
    return Normalizer.isCliRecord(item) ? item : null;
}
