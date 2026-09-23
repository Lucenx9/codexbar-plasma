.pragma library
.import "Guards.js" as Guards

// Builds the only data AI Insights may send: an explicit allowlist of
// numeric facts and deterministic signals over already-normalized provider
// snapshots. Nothing is copied wholesale, so account identities, CLI prose,
// labels, projects, paths, and model names can never reach the request.

var maximumProviders = 8
var maximumQuotas = 4
var maximumSignals = 12
var comparisonDays = 7
var changeSignalPercent = 25
var providerPattern = new RegExp("^[a-z0-9][a-z0-9._-]{0,63}$")
var lanes = ["primary", "secondary", "tertiary", "extra"]
var severities = ["minor", "major", "critical", "maintenance"]

function field(record, key) {
    return record && typeof record === "object" && Guards.hasOwnKey(record, key) ? record[key] : undefined
}

function finite(value) {
    return typeof value === "number" && isFinite(value)
}

function hours(ms) {
    var value = ms / 3600000
    return value < 10 ? Math.round(value * 10) / 10 : Math.round(value)
}

function quota(row, nowMs) {
    if (field(row, "hasPercent") !== true || !finite(field(row, "usedPercent"))) {
        return null
    }
    var result = {
        window: lanes.indexOf(field(row, "lane")) >= 0 ? row.lane : "extra",
        usedPercent: Math.round(Math.max(0, Math.min(100, row.usedPercent)))
    }
    var minutes = field(row, "windowMinutes")
    if (finite(minutes) && minutes > 0) {
        result.windowHours = hours(minutes * 60000)
    }
    var resetsAtMs = typeof field(row, "resetsAt") === "string" ? Date.parse(row.resetsAt) : NaN
    if (isFinite(resetsAtMs) && resetsAtMs > nowMs) {
        result.resetsInHours = hours(resetsAtMs - nowMs)
    }
    // Forecasts come from the CLI pace record; nothing is extrapolated here.
    if (field(row, "paceKnown") === true) {
        var eta = field(row, "paceEtaSeconds")
        if (field(row, "paceOnTop") === false && finite(eta) && eta > 0) {
            result.forecast = "runsOutBeforeReset"
            result.runsOutInHours = hours(eta * 1000)
        } else if (field(row, "paceOnTop") !== false) {
            result.forecast = "lastsUntilReset"
        }
    }
    var expected = field(row, "pacePercent")
    if (finite(expected) && expected >= 0) {
        result.expectedUsedPercentNow = Math.round(Math.min(100, expected))
    }
    return result
}

function dateKey(date) {
    var month = date.getMonth() + 1
    var day = date.getDate()
    return date.getFullYear() + "-" + (month < 10 ? "0" : "") + month + "-" + (day < 10 ? "0" : "") + day
}

// Two complete, adjacent seven-day periods ending yesterday, or nothing. Today
// is partial and a missing or unknown day would make the comparison invented.
function periods(tokenCost, nowMs, metric) {
    var daily = field(tokenCost, "daily")
    if (!Array.isArray(daily) || field(tokenCost, "historyCoverageEstablished") === false) {
        return null
    }
    var byDate = ({})
    for (var i = 0; i < daily.length && i < 400; i++) {
        var label = field(daily[i], "label")
        if (typeof label === "string" && /^\d{4}-\d{2}-\d{2}$/.test(label) && !Guards.isUnsafeObjectKey(label)) {
            byDate[label] = daily[i]
        }
    }
    var sums = [0, 0]
    var incomplete = false
    var now = new Date(nowMs)
    for (var offset = 1; offset <= comparisonDays * 2; offset++) {
        var day = new Date(now.getFullYear(), now.getMonth(), now.getDate() - offset)
        var record = Guards.hasOwnKey(byDate, dateKey(day)) ? byDate[dateKey(day)] : null
        var value = field(record, metric)
        if (!finite(value) || value < 0) {
            return null
        }
        sums[offset <= comparisonDays ? 0 : 1] += value
        incomplete = incomplete || (finite(field(record, "incompleteRequests")) && record.incompleteRequests > 0)
    }
    var result = {last7Days: sums[0], previous7Days: sums[1]}
    if (sums[1] > 0) {
        result.changePercent = Math.round((sums[0] - sums[1]) / sums[1] * 100)
    }
    if (incomplete) {
        result.incomplete = true
    }
    return result
}

function spend(tokenCost, nowMs) {
    var currency = field(tokenCost, "currency")
    // Amounts stay per provider in their own currency; nothing is summed across.
    if (typeof currency !== "string" || !/^[A-Z]{3}$/.test(currency)) {
        return null
    }
    var result = periods(tokenCost, nowMs, "cost")
    if (!result) {
        return null
    }
    result.currency = currency
    result.last7Days = Math.round(result.last7Days * 100) / 100
    result.previous7Days = Math.round(result.previous7Days * 100) / 100
    var trust = field(tokenCost, "trust")
    var sourceKind = field(trust, "sourceKind")
    if (sourceKind === "listPrice" || sourceKind === "mixed" || field(tokenCost, "valueMode") === "estimated") {
        result.estimated = true
    }
    return result
}

function tokens(tokenCost, nowMs) {
    var result = periods(tokenCost, nowMs, "tokens")
    if (result) {
        result.last7Days = Math.round(result.last7Days)
        result.previous7Days = Math.round(result.previous7Days)
    }
    return result
}

function providerRecord(item, nowMs) {
    var id = field(item, "provider")
    if (typeof id !== "string" || !providerPattern.test(id)) {
        return null
    }
    // A retained measurement is not current consumption, so it carries no numbers.
    if (field(item, "usageStale") === true) {
        return {id: id, state: "stale"}
    }
    var record = {id: id, state: "current", quotas: []}
    var rows = field(item, "rows")
    for (var i = 0; Array.isArray(rows) && i < rows.length && record.quotas.length < maximumQuotas; i++) {
        var row = quota(rows[i], nowMs)
        if (row) {
            record.quotas.push(row)
        }
    }
    var tokenCost = field(item, "tokenCost")
    var spent = tokenCost ? spend(tokenCost, nowMs) : null
    var used = tokenCost ? tokens(tokenCost, nowMs) : null
    if (spent) {
        record.spend = spent
    }
    if (used) {
        record.tokens = used
    }
    var severity = field(item, "statusSeverity")
    if (field(item, "statusKnown") === true && severities.indexOf(severity) >= 0) {
        record.incident = severity
    }
    if (record.quotas.length === 0 && !spent && !used) {
        var error = field(item, "error")
        return {id: id, state: typeof error === "string" && error.length > 0 ? "unavailable" : "noData"}
    }
    return record
}

function signals(records, warningPercent) {
    var result = []
    function add(signal) {
        if (result.length < maximumSignals) {
            result.push(signal)
        }
    }
    for (var i = 0; i < records.length; i++) {
        var record = records[i]
        for (var j = 0; record.quotas && j < record.quotas.length; j++) {
            var q = record.quotas[j]
            if (q.usedPercent >= 100) {
                add({kind: "quotaExhausted", provider: record.id, window: q.window,
                    resetsInHours: q.resetsInHours})
            } else if (q.forecast === "runsOutBeforeReset") {
                add({kind: "quotaRunsOutBeforeReset", provider: record.id, window: q.window,
                    runsOutInHours: q.runsOutInHours, resetsInHours: q.resetsInHours})
            } else if (q.usedPercent >= warningPercent) {
                add({kind: "quotaNearLimit", provider: record.id, window: q.window, usedPercent: q.usedPercent})
            }
        }
        var kinds = [["spend", "spendChange"], ["tokens", "tokenChange"]]
        for (var k = 0; k < kinds.length; k++) {
            var period = record[kinds[k][0]]
            if (period && finite(period.changePercent) && Math.abs(period.changePercent) >= changeSignalPercent) {
                var signal = {kind: kinds[k][1], provider: record.id, changePercent: period.changePercent}
                if (period.currency) {
                    signal.currency = period.currency
                }
                add(signal)
            }
        }
        if (record.incident) {
            add({kind: "serviceIncident", provider: record.id, severity: record.incident})
        }
    }
    return result
}

// FNV-1a over the serialized snapshot identifies the data an insight describes.
function identity(text) {
    var hash = 0x811c9dc5
    for (var i = 0; i < text.length; i++) {
        hash ^= text.charCodeAt(i)
        hash = Math.imul(hash, 0x01000193) >>> 0
    }
    return ("0000000" + hash.toString(16)).slice(-8)
}

function build(items, nowMs, warningPercent) {
    var records = []
    var seen = ({})
    for (var i = 0; Array.isArray(items) && i < items.length && records.length < maximumProviders; i++) {
        var record = providerRecord(items[i], nowMs)
        if (record && !Guards.hasOwnKey(seen, record.id)) {
            seen[record.id] = true
            records.push(record)
        }
    }
    var sufficient = records.some(function(record) {
        return record.state === "current"
    })
    var snapshot = {
        version: 1,
        notes: "Quota percentages are per provider window. Spend and token periods are the last 7 complete days versus the 7 days before.",
        providers: records,
        signals: signals(records, finite(warningPercent) ? warningPercent : 80)
    }
    var text = JSON.stringify(snapshot)
    return {text: sufficient ? text : "", id: sufficient ? identity(text) : "", sufficient: sufficient}
}
