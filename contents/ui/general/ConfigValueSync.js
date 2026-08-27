.pragma library

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
