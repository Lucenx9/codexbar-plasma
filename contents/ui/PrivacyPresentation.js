.pragma library
.import "Guards.js" as Guards
.import "ProviderNormalizer.js" as Normalizer

// This is a presentation boundary over normalized snapshots. Private mode
// retains numeric observations and drops provider prose instead of trying to
// guess which words are account, organization, project, or machine names.
function field(record, key, fallback) {
    return record && Guards.hasOwnKey(record, key) ? record[key] : fallback
}

function hasText(record, key) {
    var value = field(record, key, "")
    return typeof value === "string" && value.length > 0
}

function numeric(record, key, fallback) {
    var value = field(record, key, fallback)
    return typeof value === "number" && isFinite(value) ? value : fallback
}

function known(value, options, fallback) {
    return options.indexOf(value) >= 0 ? value : fallback
}

function timestamp(value) {
    var parsed = typeof value === "string" ? Date.parse(value) : NaN
    return isFinite(parsed) ? new Date(parsed).toISOString() : ""
}

function errorText(value, enabled, hiddenText) {
    return enabled ? (typeof value === "string" && value.length > 0 ? hiddenText : "") : value
}

function quota(row, enabled, label) {
    if (!enabled) {
        return row
    }
    if (!Normalizer.isCliRecord(row)) {
        return null
    }
    var used = numeric(row, "usedPercent", NaN)
    var left = numeric(row, "leftPercent", NaN)
    return {
        lane: known(field(row, "lane", ""), ["primary", "secondary", "tertiary", "extra", "monthlyCredits"], "extra"),
        label: label,
        hasPercent: field(row, "hasPercent", false) === true && isFinite(used) && isFinite(left),
        usedPercent: numeric(row, "usedPercent", 0),
        leftPercent: numeric(row, "leftPercent", 0),
        paceKnown: field(row, "paceKnown", false) === true,
        pacePercent: numeric(row, "pacePercent", -1),
        paceOnTop: field(row, "paceOnTop", false) === true,
        paceEtaSeconds: numeric(row, "paceEtaSeconds", 0),
        resetsAt: timestamp(field(row, "resetsAt", "")),
        resetDescription: "",
        reset: "",
        pace: ""
    }
}

function amounts(value) {
    var currency = field(value, "currency", "")
    var hasCurrency = typeof currency === "string" && /^[A-Z]{3}$/.test(currency)
    return {
        cost: hasCurrency ? numeric(value, "cost", null) : null,
        tokens: numeric(value, "tokens", null),
        inputTokens: numeric(value, "inputTokens", null),
        outputTokens: numeric(value, "outputTokens", null),
        cacheReadTokens: numeric(value, "cacheReadTokens", null),
        cacheCreationTokens: numeric(value, "cacheCreationTokens", null),
        currency: hasCurrency ? currency : ""
    }
}

function costTrust(value) {
    if (!Normalizer.isCliRecord(value)) {
        return null
    }
    var coverage = Normalizer.normalizedCostCoverage(field(value, "coverage", null))
    var sourceKind = known(field(value, "sourceKind", ""), ["listPrice", "vendor", "mixed", "unknown"], "")
    return coverage !== null || sourceKind.length > 0
        ? { coverage: coverage, sourceKind: sourceKind } : null
}

// resetCreditsSection builds both strings from local translation literals and
// a validated number. Unlike providerCost, this block contains no CLI prose.
function resetCredits(value) {
    return Normalizer.isCliRecord(value) && hasText(value, "title") && hasText(value, "line")
        ? { title: value.title, line: value.line } : null
}

function providerCost(value) {
    var percent = numeric(value, "percentUsed", NaN)
    return isFinite(percent) && percent >= 0
        ? { percentUsed: Math.min(100, percent) } : null
}

function modelAmounts(snapshot) {
    var models = field(snapshot, "models", [])
    var result = { rows: [], truncated: field(snapshot, "modelsTruncated", false) === true
        || (Array.isArray(models) && models.length > 6) }
    for (var i = 0; Array.isArray(models) && i < Math.min(models.length, 6); i++) {
        result.rows.push(amounts(models[i]))
    }
    return result
}

function cost(snapshot, enabled) {
    if (!enabled) {
        return snapshot
    }
    if (!Normalizer.isCliRecord(snapshot)) {
        return null
    }
    var models = modelAmounts(snapshot)
    var result = {
        provider: field(snapshot, "provider", ""),
        historyDays: Math.max(1, Math.min(365, Math.floor(numeric(snapshot, "historyDays", 30)))),
        historyCoverageEstablished: field(snapshot, "historyCoverageEstablished", true) !== false,
        trust: costTrust(field(snapshot, "trust", null)),
        totals: amounts(field(snapshot, "totals", null)),
        today: amounts(field(snapshot, "today", null)),
        daily: [],
        models: models.rows,
        modelsTruncated: models.truncated,
        projects: { rows: [], truncated: false }
    }
    var daily = field(snapshot, "daily", [])
    for (var i = 0; Array.isArray(daily) && i < Math.min(daily.length, 365); i++) {
        var day = amounts(daily[i])
        var label = field(daily[i], "label", "")
        day.label = typeof label === "string" && /^\d{4}-\d{2}-\d{2}$/.test(label) ? label : ""
        var dayModels = modelAmounts(daily[i])
        day.models = dayModels.rows
        day.modelsTruncated = dayModels.truncated
        result.daily.push(day)
    }
    var projects = field(snapshot, "projects", null)
    var projectRows = field(projects, "rows", [])
    result.projects.truncated = field(projects, "truncated", false) === true
        || (Array.isArray(projectRows) && projectRows.length > 128)
    for (var k = 0; Array.isArray(projectRows) && k < Math.min(projectRows.length, 128); k++) {
        var project = amounts(projectRows[k])
        project.label = ""
        result.projects.rows.push(project)
    }
    return result
}

function provider(snapshot, enabled, labels) {
    if (!enabled) {
        return snapshot
    }
    if (!Normalizer.isCliRecord(snapshot)) {
        return null
    }
    var rows = field(snapshot, "rows", [])
    var rowLabels = field(labels, "rowLabels", [])
    var presentedRows = []
    var primaryRow = null
    for (var i = 0; Array.isArray(rows) && i < Math.min(rows.length, 67); i++) {
        var row = quota(rows[i], true, rowLabels[i] || labels.usage)
        if (!row) {
            continue
        }
        presentedRows.push(row)
        if (rows[i] === field(snapshot, "primaryRow", null)) {
            primaryRow = row
        }
    }
    var credit = field(snapshot, "codexCreditLimit", null)
    var privateCredit = credit ? {
        title: "", used: numeric(credit, "used", 0), remaining: numeric(credit, "remaining", 0),
        limit: numeric(credit, "limit", 0), usedPercent: numeric(credit, "usedPercent", 0),
        leftPercent: numeric(credit, "leftPercent", 0), resetsAt: timestamp(field(credit, "resetsAt", ""))
    } : null
    return {
        provider: field(snapshot, "provider", ""),
        title: labels.title,
        account: hasText(snapshot, "account") ? labels.account : "",
        organization: "", loginMethod: "", source: "", version: "", planText: "",
        rows: presentedRows, primaryRow: primaryRow,
        providerDetails: [], usageDashboard: null,
        providerCost: providerCost(field(snapshot, "providerCost", null)),
        resetCredits: resetCredits(field(snapshot, "resetCredits", null)),
        tokenCost: cost(field(snapshot, "tokenCost", null), true),
        codexCreditLimit: privateCredit,
        credits: numeric(snapshot, "credits", null),
        status: hasText(snapshot, "status") ? labels.status : "",
        statusKnown: field(snapshot, "statusKnown", false) === true,
        statusSeverity: known(field(snapshot, "statusSeverity", ""), ["minor", "major", "critical", "maintenance", "unknown"], ""),
        hasIncident: field(snapshot, "hasIncident", false) === true,
        error: errorText(field(snapshot, "error", ""), true, labels.error),
        placeholder: hasText(snapshot, "placeholder") ? labels.placeholder : "",
        updatedAt: timestamp(field(snapshot, "updatedAt", ""))
    }
}

function session(snapshot, enabled) {
    if (!enabled) {
        return snapshot
    }
    if (!Normalizer.isCliRecord(snapshot)) {
        return null
    }
    return {
        provider: field(snapshot, "provider", ""),
        projectName: "", sessionName: "", host: "",
        state: known(field(snapshot, "state", "unknown"), ["active", "idle", "running", "working"], "unknown"),
        source: known(field(snapshot, "source", "unknown"), ["cli", "desktopApp", "ide"], "unknown"),
        activityMs: numeric(snapshot, "activityMs", 0)
    }
}
