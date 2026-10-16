.pragma library
.import "UsageCache.js" as Cache
.import "ProviderOrder.js" as Order

// Inputs are normalized, presented snapshots. Cache remains the authority for
// retention/account isolation and the allowlisted persisted format. A null
// cacheValue means leave disk state untouched; an empty string means clear it.
function publication(items, context, nowMs, label) {
    return {
        providers: items,
        cacheValue: context.length > 0 ? Cache.encode(items, context, nowMs) : null,
        label: label,
        nowMs: nowMs,
        refreshCompleted: false,
        receivedFreshUsage: false,
        advanceClock: false
    }
}

function hasStale(items) {
    return items.some(function(item) { return item.usageStale === true })
}

function accepted(previous, incoming, context, nowMs) {
    // Live results never use the disk restore's verified account pin.
    var items = Cache.reconcile(previous, incoming, nowMs)
    var fresh = items.some(function(item) { return !item.usageStale && item.error.length === 0 })
    var result = publication(items, context, nowMs, hasStale(items) ? "stale" : fresh ? "updated" : "clear")
    result.refreshCompleted = true
    result.receivedFreshUsage = fresh
    return result
}

function restored(previous, cached, accounts, order, context, nowMs) {
    if (context.length === 0)
        return null
    var merged = Cache.restore(cached, previous, nowMs, accounts)
    var items = merged.length > 0 ? Order.orderedItems(merged, order) : previous
    // A fresh early result keeps its update label when the checksum arrives.
    return publication(items, context, nowMs, hasStale(items) ? "stale" : "keep")
}

function invalidated(previous, providerID, replacement, context, nowMs) {
    var items = providerID ? previous.map(function(item) {
        return item.provider === providerID ? replacement : item
    }) : []
    var result = publication(items, context, nowMs, "clear")
    if (!providerID && context.length === 0)
        result.cacheValue = ""
    return result
}

function failed(previous, failures, context, nowMs) {
    var items = Cache.reconcile(previous, failures, nowMs)
    var result = publication(items, context, nowMs, hasStale(items) ? "stale" : "clear")
    result.advanceClock = true
    return result
}

function expired(previous, replacements, context, nowMs) {
    var ids = Cache.expiredProviderIDs(previous, nowMs)
    if (ids.length === 0)
        return null
    var items = previous.map(function(item) {
        if (ids.indexOf(item.provider) < 0)
            return item
        var replacement = replacements.filter(function(candidate) {
            return candidate.provider === item.provider
        })[0]
        var next = Cache.withCurrentStatus(replacement, item)
        next.lastGoodAtMs = 0
        next.usageStale = false
        return next
    })
    return publication(items, context, nowMs, hasStale(items) ? "keep" : "clear")
}
