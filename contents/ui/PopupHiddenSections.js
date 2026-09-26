.pragma library
.import "Guards.js" as Guards
.import "ProviderNormalizer.js" as Normalizer

// Only provider IDs and title digests are persisted. Equal current titles form
// one group; a renamed title is visible again. Untitled sections stay visible.
var maximumEntries = 64

function sectionKey(section) {
    if (!Normalizer.isCliRecord(section) || typeof section.title !== "string"
            || section.title.length > 3840 || section.title.trim().length === 0) {
        return ""
    }
    return "v1:" + Qt.md5(section.title.trim())
}

function validSectionKey(value) {
    return typeof value === "string" && /^v1:[0-9a-f]{32}$/.test(value)
}

function sameEntry(a, b) {
    return a.provider === b.provider && a.section === b.section
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
                || !validSectionKey(Guards.hasOwnKey(entry, "section") ? entry.section : null)) {
            continue
        }
        var provider = Normalizer.normalizedProviderID(entry.provider)
        var candidate = { provider: provider, section: entry.section }
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
    var candidate = { provider: Normalizer.normalizedProviderID(providerID), section: key }
    return Array.isArray(entries) && entries.some(function(item) { return sameEntry(item, candidate) })
}

// A full list refuses further entries instead of forgetting an older choice.
function hidden(entries, providerID, key) {
    var current = Array.isArray(entries) ? entries.slice() : []
    var provider = Normalizer.normalizedProviderID(providerID)
    if (provider.length === 0 || !validSectionKey(key) || isHidden(current, provider, key)
            || current.length >= maximumEntries) {
        return current
    }
    current.push({ provider: provider, section: key })
    return current
}

function restored(entries, providerID, key) {
    var candidate = { provider: Normalizer.normalizedProviderID(providerID), section: key }
    return (Array.isArray(entries) ? entries : []).filter(function(item) {
        return !sameEntry(item, candidate)
    })
}

function visibleSections(sections, entries, providerID) {
    return (Array.isArray(sections) ? sections : []).filter(function(section) {
        var key = sectionKey(section)
        return key.length === 0 || !isHidden(entries, providerID, key)
    })
}

function hiddenSections(sections, entries, providerID) {
    var seen = []
    return (Array.isArray(sections) ? sections : []).filter(function(section) {
        var key = sectionKey(section)
        if (key.length === 0 || seen.indexOf(key) >= 0 || !isHidden(entries, providerID, key)) {
            return false
        }
        seen.push(key)
        return true
    })
}

function providers(entries) {
    var result = []
    var current = Array.isArray(entries) ? entries : []
    current.forEach(function(entry) {
        if (result.indexOf(entry.provider) < 0) {
            result.push(entry.provider)
        }
    })
    return result
}

function restoredProvider(entries, providerID) {
    var provider = Normalizer.normalizedProviderID(providerID)
    return (Array.isArray(entries) ? entries : []).filter(function(entry) {
        return entry.provider !== provider
    })
}
