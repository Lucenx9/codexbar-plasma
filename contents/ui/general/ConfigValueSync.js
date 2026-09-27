.pragma library
.import "../PopupHiddenRows.js" as PopupHiddenRows
.import "../PopupHiddenSections.js" as PopupHiddenSections

// Keeps a KCM value distinct from the runtime configuration while the user has
// a pending edit. Plasma injects cfg_* values as creation-time properties, so a
// binding declared on cfg_* does not survive page construction.

function afterUserEdit(value, persistedValue) {
    return state(value, !valuesMatch(value, persistedValue))
}

function afterPersistedChange(pendingValue, hasPendingEdit, persistedValue) {
    if (hasPendingEdit === true && !valuesMatch(pendingValue, persistedValue)) {
        return state(pendingValue, true)
    }
    return state(persistedValue, false)
}

function afterSave(pendingValue) {
    return state(pendingValue, false)
}

function valuesMatch(left, right) {
    return String(left) === String(right)
}

function state(pendingValue, hasPendingEdit) {
    return {
        pendingValue: pendingValue,
        hasPendingEdit: hasPendingEdit === true
    }
}

// The popup hides and restores items live, while a settings page only
// restores them. When the stored list changes, keep the page's pending
// restores (items in `base` but not in `pending`) and adopt everything else,
// so Apply neither re-hides nor re-shows an item the popup changed meanwhile.
// Entries are the normalized records of PopupHiddenRows/PopupHiddenSections.
function hiddenItemsAfterPersistedChange(pending, base, persisted) {
    var key = function(entry) { return JSON.stringify(entry) }
    var kept = (Array.isArray(pending) ? pending : []).map(key)
    var restored = (Array.isArray(base) ? base : []).map(key).filter(function(item) {
        return kept.indexOf(item) < 0
    })
    return (Array.isArray(persisted) ? persisted : []).filter(function(entry) {
        return restored.indexOf(key(entry)) < 0
    })
}

// The same rule over the stored text of each hidden-item setting.
function hiddenUsageRowsAfterPersistedChange(pending, base, persisted) {
    return PopupHiddenRows.serialize(hiddenItemsAfterPersistedChange(
        PopupHiddenRows.parse(pending), PopupHiddenRows.parse(base), PopupHiddenRows.parse(persisted)))
}

function hiddenDetailSectionsAfterPersistedChange(pending, base, persisted) {
    return PopupHiddenSections.serialize(hiddenItemsAfterPersistedChange(
        PopupHiddenSections.parse(pending), PopupHiddenSections.parse(base), PopupHiddenSections.parse(persisted)))
}

// Days and calendar mode select one range. Matching only one persisted field
// must not release a pending edit while the other field still differs.
function historyRangeAfterUserEdit(days, period, persistedDays, persistedPeriod) {
    return historyRangeState(days, period,
        !valuesMatch(days, persistedDays) || !valuesMatch(period, persistedPeriod))
}

function historyRangeAfterPersistedChange(days, period, hasPendingEdit, persistedDays, persistedPeriod) {
    var pending = historyRangeAfterUserEdit(days, period, persistedDays, persistedPeriod)
    return hasPendingEdit === true && pending.hasPendingEdit
        ? pending : historyRangeState(persistedDays, persistedPeriod, false)
}

function historyRangeState(days, period, hasPendingEdit) {
    return { days: days, period: period, hasPendingEdit: hasPendingEdit }
}
