.pragma library
.import "SafeText.js" as SafeText
.import "CostPresentation.js" as Costs

function record(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
}

function amount(value) {
    return typeof value === "number" && isFinite(value) && value >= 0 && value <= Number.MAX_SAFE_INTEGER
        ? value : null
}

// Export only aggregate fields, never serialize a CLI or presentation object.
function label(value) {
    if (typeof value !== "string") return ""
    return SafeText.cliMessage(value, 120)
        .replace(/\S+@\S+|\b(?:https?|file):\S+/g, "[redacted]")
        .replace(/(^|\s)(?:\/|~\/|[A-Za-z]:\\)\S+/g, "$1[redacted]")
        .replace(/[\u202a-\u202e\u2066-\u2069]/g, "")
}

function quantities(value) {
    var item = record(value) ? value : {}
    var currency = typeof item.currency === "string" && /^[A-Z]{3}$/.test(item.currency)
        ? item.currency : ""
    return { tokens: amount(item.tokens), cost: currency ? amount(item.cost) : null, currency: currency }
}

function rank(a, b) {
    return (b.tokens === null ? -1 : b.tokens) - (a.tokens === null ? -1 : a.tokens)
        || a.label.localeCompare(b.label)
}

function snapshot(costs, days, createdAt, refreshFailed) {
    var items = Array.isArray(costs) ? costs : []
    var result = { providers: [], models: [], currencies: [], tokens: null,
        days: typeof days === "number" && isFinite(days) ? Math.max(1, Math.min(365, Math.floor(days))) : 30,
        createdAt: typeof createdAt === "string" && isFinite(Date.parse(createdAt)) ? createdAt : "",
        partial: refreshFailed === true || items.length > 128, omittedProviders: 0, omittedModels: 0 }
    var models = []
    for (var i = 0; i < Math.min(items.length, 128); i++) {
        var item = items[i]
        if (!record(item) || item.historyDays !== result.days) continue
        var totals = quantities(item.totals)
        var provider = label(item.provider)
        if (!provider) continue
        var trust = Costs.costTrustSummary([{totals: totals, trust: item.trust}])
        result.partial = result.partial || item.historyCoverageEstablished === false
            || totals.tokens === null || totals.cost === null
            || (trust !== null && trust.valueMode !== "plain")
        totals.provider = provider
        totals.label = provider
        result.providers.push(totals)
        if (totals.tokens !== null) {
            result.tokens = (result.tokens === null ? 0 : result.tokens) + totals.tokens
        }
        if (totals.cost !== null) {
            var index = result.currencies.findIndex(function(row) { return row.currency === totals.currency })
            if (index < 0) {
                result.currencies.push({ currency: totals.currency, cost: totals.cost })
            } else {
                result.currencies[index].cost += totals.cost
            }
        }
        var rows = Array.isArray(item.models) ? item.models : []
        result.omittedModels += Math.max(0, rows.length - 128)
        result.partial = result.partial || item.modelsTruncated === true
        for (var j = 0; j < Math.min(rows.length, 128); j++) {
            if (!record(rows[j])) continue
            var model = quantities(rows[j])
            model.label = label(rows[j].label)
            model.provider = provider
            if (model.label && model.tokens !== null) models.push(model)
        }
    }
    if (result.tokens !== null && amount(result.tokens) === null) result.partial = true
    result.tokens = amount(result.tokens)
    result.currencies.sort(function(a, b) { return a.currency.localeCompare(b.currency) })
    result.currencies.forEach(function(row) {
        if (amount(row.cost) === null) result.partial = true
        row.cost = amount(row.cost)
    })
    result.providers.sort(rank)
    models.sort(rank)
    result.omittedProviders = Math.max(0, result.providers.length - 8)
    result.omittedModels += Math.max(0, models.length - 6)
    result.providers = result.providers.slice(0, 8)
    result.models = models.slice(0, 6)
    return result
}

function localPngUrl(value) {
    return typeof value === "string" && /^file:\/\/\/(?!\/)/.test(value)
        && !/[\u0000-\u001f\u007f?#]/.test(value) && /\.png$/i.test(value)
}
