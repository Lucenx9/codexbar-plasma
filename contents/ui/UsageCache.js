.pragma library
.import "Guards.js" as Guards
.import "ProviderNormalizer.js" as Normalizer

var maximumAgeMs = 24 * 60 * 60 * 1000
var maximumEntries = 64
var maximumBytes = 65536
var lanes = ["primary", "secondary", "tertiary"]

function timestamp(value) {
    var parsed = typeof value === "string" ? Date.parse(value) : NaN
    return isFinite(parsed) && parsed > 0 ? parsed : NaN
}

function hasQuota(item) {
    return item && Array.isArray(item.rows) && item.rows.some(function(row) {
        return row && row.hasPercent === true
    })
}

function withCurrentStatus(snapshot, source) {
    var next = Guards.copyObject(snapshot)
    next.statusKnown = source ? source.statusKnown === true : false
    if (next.statusKnown) {
        ["status", "statusSeverity", "statusIncidentKey", "hasIncident", "statusUrl"].forEach(function(key) {
            next[key] = source[key]
        })
    }
    return next
}

// Inputs are normalized live snapshots. A successful empty usage result replaces
// old quotas; only an explicit failure may reuse them in the same account scope.
function reconcile(previous, incoming, nowMs) {
    var byProvider = ({})
    previous.forEach(function(item) { byProvider[item.provider] = item })
    return incoming.map(function(item) {
        var next = Guards.copyObject(item)
        var old = byProvider[item.provider]
        if (item.error.length > 0 && hasQuota(old) && recent(old.lastGoodAtMs, nowMs)
                && (!item.account || item.account === old.account)) {
            next = withCurrentStatus(old, item)
            next.error = item.error
            next.usageStale = true
            // Forecasts are live estimates. Retained measurements cannot support
            // an updated run-out prediction while requests are failing.
            next.rows = old.rows.map(function(row) {
                var copy = Guards.copyObject(row)
                copy.paceKnown = false
                copy.pace = ""
                copy.pacePercent = -1
                copy.paceEtaSeconds = 0
                return copy
            })
            next.primaryRow = next.rows.filter(function(row) { return row.lane === "primary" })[0] || null
        } else {
            var measuredAt = timestamp(item.updatedAt)
            next.lastGoodAtMs = item.error.length === 0
                ? (isFinite(measuredAt) && measuredAt <= nowMs ? measuredAt : nowMs) : 0
            next.usageStale = false
        }
        return next
    })
}

// Restores cached provider snapshots during widget initialization, merging any
// cached providers missing from live results while keeping live data fresh.
function restore(cached, live, nowMs) {
    if (!Array.isArray(cached) || cached.length === 0) {
        return Array.isArray(live) ? live : []
    }
    if (!Array.isArray(live) || live.length === 0) {
        return cached.map(function(item) {
            var copy = Guards.copyObject(item)
            copy.usageStale = true
            return copy
        })
    }
    var reconciled = reconcile(cached, live, nowMs)
    var seen = ({})
    reconciled.forEach(function(item) {
        seen[item.provider] = true
    })
    var result = reconciled.slice()
    for (var i = 0; i < cached.length; i++) {
        var item = cached[i]
        if (!Guards.hasOwnKey(seen, item.provider)) {
            seen[item.provider] = true
            var staleItem = Guards.copyObject(item)
            staleItem.usageStale = true
            result.push(staleItem)
        }
    }
    return result
}

function validContext(value) {
    return typeof value === "string" && /^[a-f0-9]{32}$/.test(value)
}

function withinByteLimit(value) {
    if (typeof value !== "string" || value.length > maximumBytes) {
        return false
    }
    try {
        return encodeURIComponent(value).replace(/%[0-9A-F]{2}/g, "x").length <= maximumBytes
    } catch (error) {
        return false
    }
}

function recent(value, nowMs) {
    return typeof value === "number" && isFinite(value) && value > 0
        && value <= nowMs && nowMs - value <= maximumAgeMs
}

function expiredProviderIDs(items, nowMs) {
    return items.filter(function(item) {
        return item.usageStale === true && !recent(item.lastGoodAtMs, nowMs)
    }).map(function(item) { return item.provider })
}

function windowRecord(value) {
    if (!Normalizer.isCliRecord(value) || typeof value.usedPercent !== "number"
            || !isFinite(value.usedPercent) || value.usedPercent < 0 || value.usedPercent > 100) {
        return null
    }
    var resetMs = timestamp(value.resetsAt)
    return {
        usedPercent: value.usedPercent,
        resetsAt: isFinite(resetMs) ? new Date(resetMs).toISOString() : ""
    }
}

function encode(items, context, nowMs) {
    if (!validContext(context)) {
        return ""
    }
    var snapshots = []
    for (var i = 0; i < items.length && snapshots.length < maximumEntries; i++) {
        var item = items[i]
        if (!recent(item.lastGoodAtMs, nowMs) || !hasQuota(item)) {
            continue
        }
        var windows = ({})
        item.rows.forEach(function(row) {
            if (lanes.indexOf(row.lane) >= 0 && row.hasPercent === true) {
                var window = windowRecord(row)
                if (window) {
                    windows[row.lane] = window
                }
            }
        })
        if (Object.keys(windows).length > 0) {
            snapshots.push({ provider: item.provider, measuredAt: item.lastGoodAtMs, windows: windows })
        }
    }
    if (snapshots.length === 0) {
        return ""
    }
    var serialized = JSON.stringify({ version: 1, context: context, snapshots: snapshots })
    return withinByteLimit(serialized) ? serialized : ""
}

// Persisted data is untrusted. Rebuild only the quota contract that QML already
// knows how to normalize, never restore arbitrary provider view models or prose.
function decode(raw, context, nowMs) {
    if (!withinByteLimit(raw) || !validContext(context)) {
        return []
    }
    var cache
    try {
        cache = JSON.parse(raw)
    } catch (error) {
        return []
    }
    if (!Normalizer.isCliRecord(cache) || cache.version !== 1 || cache.context !== context
            || !Array.isArray(cache.snapshots) || cache.snapshots.length > maximumEntries) {
        return []
    }
    var result = []
    var seen = ({})
    for (var i = 0; i < cache.snapshots.length; i++) {
        var item = cache.snapshots[i]
        if (!Normalizer.isCliRecord(item) || typeof item.provider !== "string"
                || Normalizer.normalizedProviderID(item.provider) !== item.provider
                || item.provider.length === 0 || Guards.hasOwnKey(seen, item.provider)
                || !recent(item.measuredAt, nowMs) || !Normalizer.isCliRecord(item.windows)) {
            continue
        }
        var usage = { updatedAt: new Date(item.measuredAt).toISOString() }
        var count = 0
        for (var j = 0; j < lanes.length; j++) {
            var lane = lanes[j]
            var window = Guards.hasOwnKey(item.windows, lane) ? windowRecord(item.windows[lane]) : null
            if (window) {
                usage[lane] = window
                count++
            }
        }
        if (count > 0) {
            seen[item.provider] = true
            result.push({ provider: item.provider, usage: usage })
        }
    }
    return result
}
