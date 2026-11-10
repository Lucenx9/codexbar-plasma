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
    } else {
        // Badges gate on hasIncident alone, so an unknown status must not
        // keep showing the previous outage as if it were current.
        next.status = ""
        next.statusSeverity = ""
        next.statusIncidentKey = ""
        next.hasIncident = false
        next.statusUrl = ""
    }
    return next
}

// Explicit account selections are memory-only and absent from the disk cache
// context, so a provider with an override is neither saved nor restored: its
// quota must never come back as the default account's after a restart, and the
// default account's saved quota must never fill in for the selected one.
function accountOverridden(accounts, providerID) {
    return Normalizer.isCliRecord(accounts)
        && Guards.hasOwnKey(accounts, providerID)
        && typeof accounts[providerID] === "string"
        && accounts[providerID].length > 0
}

function canRetainQuota(old, incoming, nowMs) {
    if (!(incoming.error.length > 0) || !hasQuota(old) || !recent(old.lastGoodAtMs, nowMs)) return false
    var account = Normalizer.accountKey(incoming)
    return account.length === 0 || account === Normalizer.accountKey(old)
}

function measurementTime(item, nowMs) {
    var measuredAt = timestamp(item.updatedAt)
    // Account selection must not renew a missing/future timestamp's receipt time.
    var receivedAt = typeof item.usageReceivedAtMs === "number"
        && isFinite(item.usageReceivedAtMs) && item.usageReceivedAtMs > 0
        && item.usageReceivedAtMs <= nowMs ? item.usageReceivedAtMs : nowMs
    return !isFinite(measuredAt) || measuredAt > receivedAt ? receivedAt : measuredAt
}

function currentSnapshot(item, nowMs) {
    var next = Guards.copyObject(item)
    if (item.error.length !== 0) {
        next.lastGoodAtMs = 0
        next.usageStale = false
        return next
    }
    var measuredAt = measurementTime(item, nowMs)
    if (isFinite(measuredAt) && measuredAt <= nowMs && nowMs - measuredAt <= maximumAgeMs) {
        next.lastGoodAtMs = measuredAt
        next.usageStale = false
    } else if (!hasQuota(next) || !isFinite(measuredAt) || measuredAt > nowMs) {
        next.lastGoodAtMs = nowMs
        next.usageStale = false
    } else {
        next.lastGoodAtMs = measuredAt
        next.usageStale = true
    }
    return next
}

function staleSnapshot(item) {
    var next = Guards.copyObject(item)
    // A retained measurement cannot support live forecasts or supplemental data.
    next.rows = next.rows.map(function(row) {
        var copy = Guards.copyObject(row)
        copy.paceKnown = false
        copy.pace = ""
        copy.paceParts = []
        copy.pacePercent = -1
        copy.paceEtaSeconds = 0
        return copy
    })
    next.primaryRow = next.rows.filter(function(row) { return row.lane === "primary" })[0] || null
    next.subscriptionDates = []
    next.providerDetails = []
    next.usageDashboard = null
    next.providerCost = null
    next.panelBudget = null
    next.resetCredits = null
    next.tokenCost = null
    next.codexCreditLimit = null
    next.credits = null
    return next
}

// A successful empty result replaces quotas; only failure can reuse the same account.
function reconcile(previous, incoming, nowMs) {
    var byProvider = ({})
    previous.forEach(function(item) { byProvider[item.provider] = item })
    return incoming.map(function(item) {
        var old = byProvider[item.provider]
        var next
        if (canRetainQuota(old, item, nowMs)) {
            next = withCurrentStatus(old, item)
            next.error = item.error
            next.usageStale = true
        } else {
            next = currentSnapshot(item, nowMs)
        }
        return next.usageStale ? staleSnapshot(next) : next
    })
}

// Restores cached provider snapshots during widget initialization, merging any
// cached providers missing from live results while keeping live data fresh.
function restore(cached, live, nowMs, accounts) {
    cached = Array.isArray(cached) ? cached.filter(function(item) {
        return !accountOverridden(accounts, item.provider)
    }) : []
    if (cached.length === 0) {
        return Array.isArray(live) ? live : []
    }
    if (!Array.isArray(live) || live.length === 0) {
        return cached.map(function(item) {
            var copy = Guards.copyObject(item)
            copy.usageStale = true
            return copy
        })
    }
    var reconciled = reconcile(cached, live, nowMs).map(function(item, index) {
        var current = live[index]
        // These measurements were already accepted by the live refresh path.
        return hasQuota(current) && recent(current.lastGoodAtMs, nowMs) ? current : item
    })
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

// The identifier-shaped window ID keeps a hidden extra row hidden after a
// restart. It is the CLI key, not prose; the title is never persisted.
function extraRecord(id, window) {
    var windowID = Normalizer.extraWindowID(id)
    return windowID.length > 0 ? { id: windowID, window: window } : { window: window }
}

function savedWindows(rows) {
    var windows = ({})
    var extras = []
    rows.forEach(function(row) {
        if (row.hasPercent !== true) return
        var window = windowRecord(row)
        if (!window) return
        if (lanes.indexOf(row.lane) >= 0) {
            windows[row.lane] = window
        } else if (row.lane === "extra" && extras.length < Normalizer.maximumExtraRateWindows) {
            extras.push(extraRecord(row.windowId, window))
        }
    })
    if (extras.length > 0) windows.extraRateWindows = extras
    return windows
}

function savedSnapshot(item) {
    var windows = savedWindows(item.rows)
    if (Object.keys(windows).length === 0) return null
    var confidence = Normalizer.usageConfidence(item.dataConfidence)
    var saved = { provider: item.provider, measuredAt: item.lastGoodAtMs, windows: windows }
    if (confidence.length > 0) saved.dataConfidence = confidence
    return saved
}

function encode(items, context, nowMs, accounts) {
    if (!validContext(context)) {
        return ""
    }
    var snapshots = []
    for (var i = 0; i < items.length && snapshots.length < maximumEntries; i++) {
        var item = items[i]
        if (!recent(item.lastGoodAtMs, nowMs) || !hasQuota(item)
                || accountOverridden(accounts, item.provider)) {
            continue
        }
        var saved = savedSnapshot(item)
        if (saved) snapshots.push(saved)
    }
    if (snapshots.length === 0) {
        return ""
    }
    // Retain the leading providers that fit instead of clearing every saved
    // quota when another otherwise valid snapshot exceeds the byte budget.
    while (snapshots.length > 0) {
        var serialized = JSON.stringify({ version: 1, context: context, snapshots: snapshots })
        if (withinByteLimit(serialized)) return serialized
        snapshots.pop()
    }
    return ""
}

function cacheEntryValid(item, nowMs) {
    return Normalizer.isCliRecord(item) && typeof item.provider === "string"
        && Normalizer.normalizedProviderID(item.provider) === item.provider && item.provider.length > 0
        && recent(item.measuredAt, nowMs) && Normalizer.isCliRecord(item.windows)
}

function restoredUsage(item) {
    var usage = { updatedAt: new Date(item.measuredAt).toISOString() }
    var confidence = Normalizer.usageConfidenceField(item)
    if (confidence.length > 0) usage.dataConfidence = confidence
    var count = 0
    for (var j = 0; j < lanes.length; j++) {
        var lane = lanes[j]
        var window = Guards.hasOwnKey(item.windows, lane) ? windowRecord(item.windows[lane]) : null
        if (window) {
            usage[lane] = window
            count++
        }
    }
    var extras = restoredExtras(item.windows.extraRateWindows)
    if (extras.length > 0) {
        usage.extraRateWindows = extras
        count += extras.length
    }
    return count > 0 ? usage : null
}

function restoredExtras(value) {
    var extras = Array.isArray(value) ? value : []
    var result = []
    for (var k = 0; k < Math.min(extras.length, Normalizer.maximumExtraRateWindows); k++) {
        var window = Normalizer.isCliRecord(extras[k]) ? windowRecord(extras[k].window) : null
        if (window) result.push(extraRecord(extras[k].id, window))
    }
    return result
}

// Rebuild only quota fields; persisted prose and arbitrary view models are untrusted.
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
        if (!cacheEntryValid(item, nowMs) || Guards.hasOwnKey(seen, item.provider)) continue
        var usage = restoredUsage(item)
        if (usage) {
            seen[item.provider] = true
            result.push({ provider: item.provider, usage: usage })
        }
    }
    return result
}
