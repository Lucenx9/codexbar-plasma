.pragma library
.import "../Guards.js" as Guards
.import "../ProviderIdentity.js" as Identity

// Ephemeral page state only. QML retains the command ledger and supplies whether
// source writes remain active; no command, payload or secret is stored here.
function initialState() {
    return {providers: {}, fields: {}, diagnostics: {}, reloadDeferred: false}
}

function withPendingEntry(state, map, key, active, value) {
    if (["providers", "fields", "diagnostics"].indexOf(map) < 0 || key.length === 0)
        return state
    var next = Guards.copyObject(state)
    next[map] = Guards.copyObject(state[map])
    if (active)
        next[map][key] = value
    else
        delete next[map][key]
    return next
}

function providerPendingChanged(state, provider, active, desiredEnabled) {
    return withPendingEntry(state, "providers", Identity.providerMapKey(provider), active, desiredEnabled === true)
}

function isProviderPending(state, provider) {
    var key = Identity.providerMapKey(provider)
    return key.length > 0 && Guards.hasOwnKey(state.providers, key)
}

function enabledValue(state, provider, fallback) {
    var key = Identity.providerMapKey(provider)
    return key.length > 0 && Guards.hasOwnKey(state.providers, key)
        ? state.providers[key] === true : fallback === true
}

function fieldKey(provider, fieldID) {
    var key = Identity.providerMapKey(provider)
    var field = String(fieldID || "").trim()
    return key.length > 0 && field.length > 0 && field.length <= 128
        ? key + "::" + JSON.stringify(field) : ""
}

function fieldPendingChanged(state, provider, fieldID, active) {
    return withPendingEntry(state, "fields", fieldKey(provider, fieldID), active, true)
}

function fieldPending(state, provider, fieldID) {
    var key = fieldKey(provider, fieldID)
    return key.length > 0 && Guards.hasOwnKey(state.fields, key)
}

function hasFieldOperations(state, provider) {
    var key = Identity.providerMapKey(provider)
    if (key.length === 0)
        return false
    var prefix = key + "::"
    for (var field in state.fields) {
        if (Guards.hasOwnKey(state.fields, field) && field.indexOf(prefix) === 0)
            return true
    }
    return false
}

function diagnosticPendingChanged(state, provider, active) {
    return withPendingEntry(state, "diagnostics", Identity.providerMapKey(provider), active, true)
}

function isDiagnosticPending(state, provider) {
    var key = Identity.providerMapKey(provider)
    return key.length > 0 && Guards.hasOwnKey(state.diagnostics, key)
}

// A deferred reload deliberately keeps the messages present when the last
// source write finishes, not messages captured when the reload was requested.
function reloadRequested(state, sourceWriteActive, preserveMessages, retainedErrorText) {
    var next = Guards.copyObject(state)
    next.reloadDeferred = sourceWriteActive === true
    return {
        state: next,
        reload: !next.reloadDeferred,
        preserveMessages: preserveMessages === true,
        retainedErrorText: retainedErrorText ? String(retainedErrorText) : ""
    }
}

function deferredReload(state, sourceWriteActive, currentErrorText) {
    if (!state.reloadDeferred || sourceWriteActive)
        return {state: state, reload: false}
    return reloadRequested(state, false, true, currentErrorText)
}
