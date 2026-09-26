.pragma library
.import "Guards.js" as Guards
.import "ProviderNormalizer.js" as Normalizer

// Popup quota rows the user hid, per provider. This is a local display choice:
// it filters only the provider tab's usage rows, never fetching, notifications,
// the panel, or the Overview summary. Entries are stored as provider ID plus a
// row key, "primary", "secondary", "tertiary", or "extra:<CLI window id>", and
// no provider prose, so a stored entry cannot carry text into the settings page.

var maximumEntries = 64
var laneKeys = ["primary", "secondary", "tertiary"]

// The key of a normalized popup row, or "" when the row cannot be hidden.
function rowKey(row) {
    if (!Normalizer.isCliRecord(row)) {
        return ""
    }
    if (laneKeys.indexOf(row.lane) >= 0) {
        return row.lane
    }
    var windowID = row.lane === "extra" ? Normalizer.extraWindowID(row.windowId) : ""
    return windowID.length > 0 ? "extra:" + windowID : ""
}

function validRowKey(value) {
    if (typeof value !== "string") {
        return false
    }
    var windowID = value.indexOf("extra:") === 0 ? value.slice(6) : ""
    return laneKeys.indexOf(value) >= 0
        || (windowID.length > 0 && Normalizer.extraWindowID(windowID) === windowID)
}

function sameEntry(a, b) {
    return a.provider === b.provider && a.row === b.row
}

// Stored text is untrusted: keep only well-formed, unique entries, in order.
function parse(raw) {
    var result = []
    if (typeof raw !== "string" || raw.length === 0 || raw.length > 16384) {
        return result
    }
    var entries
    try {
        entries = JSON.parse(raw)
    } catch (error) {
        return result
    }
    if (!Array.isArray(entries)) {
        return result
    }
    for (var i = 0; i < entries.length && result.length < maximumEntries; i++) {
        var entry = entries[i]
        if (!Normalizer.isCliRecord(entry) || typeof entry.provider !== "string"
                || !validRowKey(Guards.hasOwnKey(entry, "row") ? entry.row : null)) {
            continue
        }
        var provider = Normalizer.normalizedProviderID(entry.provider)
        var candidate = { provider: provider, row: entry.row }
        if (provider.length > 0 && !result.some(function(item) { return sameEntry(item, candidate) })) {
            result.push(candidate)
        }
    }
    return result
}

function serialize(entries) {
    return Array.isArray(entries) && entries.length > 0 ? JSON.stringify(entries) : ""
}

function isHidden(entries, providerID, key) {
    var candidate = { provider: Normalizer.normalizedProviderID(providerID), row: key }
    return Array.isArray(entries) && entries.some(function(item) { return sameEntry(item, candidate) })
}

// A full list refuses further entries instead of forgetting an older choice.
function hidden(entries, providerID, key) {
    var current = Array.isArray(entries) ? entries.slice() : []
    var provider = Normalizer.normalizedProviderID(providerID)
    if (provider.length === 0 || !validRowKey(key) || isHidden(current, provider, key)
            || current.length >= maximumEntries) {
        return current
    }
    current.push({ provider: provider, row: key })
    return current
}

function restored(entries, providerID, key) {
    var candidate = { provider: Normalizer.normalizedProviderID(providerID), row: key }
    return (Array.isArray(entries) ? entries : []).filter(function(item) {
        return !sameEntry(item, candidate)
    })
}

function visibleRows(rows, entries, providerID) {
    if (!Array.isArray(rows)) {
        return []
    }
    return rows.filter(function(row) {
        var key = rowKey(row)
        return key.length === 0 || !isHidden(entries, providerID, key)
    })
}
