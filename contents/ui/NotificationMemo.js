// Pure decision helpers for the provider status notification memo.
//
// The memo is a flat string map owned by main.qml, which also owns the timers,
// the refresh-pending state, and the actual notification call. Everything here
// stays side-effect free apart from writing into a caller-supplied memo, so the
// notify/stay-quiet decision can be exercised directly by
// tests/tst_notification_memo.qml instead of only through static assertions.
//
// Status state is deliberately provider-scoped, not account-scoped: a provider
// incident is a property of the provider, not of the signed-in account.

.pragma library

var STATUS_PREFIX = "status:"
var STATUS_PRIMED_PREFIX = "statusPrimed:"

function statusMemoKey(providerID) {
    return STATUS_PREFIX + String(providerID || "")
}

function statusPrimedMemoKey(providerID) {
    return STATUS_PRIMED_PREFIX + String(providerID || "")
}

function isStatusMemoKey(key) {
    var text = String(key || "")
    return text.indexOf(STATUS_PREFIX) === 0 || text.indexOf(STATUS_PRIMED_PREFIX) === 0
}

function hasOwnKey(item, key) {
    return item !== null && item !== undefined
        && Object.prototype.hasOwnProperty.call(item, key)
}

// Encodes the notification identity of an incident. Severity drives escalation
// and the incident key detects a replacement; free-form status text is
// deliberately excluded so provider copy edits cannot spam notifications.
function statusMemoValue(severity, incidentKey) {
    return String(severity || "") + "|" + String(incidentKey || "")
}

function severityFromMemoValue(value) {
    var text = String(value || "")
    return text.length > 0 ? text.split("|")[0] : ""
}

function incidentKeyFromMemoValue(value) {
    var text = String(value || "")
    var separator = text.indexOf("|")
    return separator >= 0 ? text.slice(separator + 1) : ""
}

function severityRank(severity) {
    switch (String(severity || "")) {
    case "critical":
        return 5
    case "major":
        return 4
    case "minor":
        return 3
    case "maintenance":
        return 2
    case "unknown":
        return 1
    default:
        return 0
    }
}

// A threshold or toggle change rebuilds threshold-derived memo state, but it is
// not a status transition, so the status baseline survives. Dropping it would
// either re-announce an ongoing incident or, once the first observation primes
// silently, swallow an incident that starts while the provider is refreshing.
function preservedMemoAfterReset(memo) {
    var next = ({})
    var source = memo || ({})
    for (var key in source) {
        if (hasOwnKey(source, key) && isStatusMemoKey(key)) {
            next[key] = source[key]
        }
    }
    return next
}

// A provider whose refresh is pending cannot be baselined from its cached
// snapshot, but an existing baseline must be carried into the rebuilt memo.
function carryStatusMemo(memo, providerID, nextMemo) {
    var source = memo || ({})
    if (source[statusPrimedMemoKey(providerID)] !== "1") {
        return
    }
    nextMemo[statusPrimedMemoKey(providerID)] = "1"
    var previousValue = String(source[statusMemoKey(providerID)] || "")
    if (previousValue.length > 0) {
        nextMemo[statusMemoKey(providerID)] = previousValue
    }
}

// The whole notify decision. `value` is a statusMemoValue, or "" when the
// provider currently reports no incident. Returns the value to store and
// whether the caller should raise a notification.
function statusDecision(memo, providerID, value, severity) {
    var source = memo || ({})
    var text = String(value || "")
    // Without a baseline there is no transition to report. This covers a cold
    // start and a provider that was still refreshing when the memo was rebuilt,
    // so a pre-existing incident is recorded rather than announced as new.
    if (source[statusPrimedMemoKey(providerID)] !== "1") {
        return { notify: false, value: text }
    }
    if (text.length === 0) {
        return { notify: false, value: "" }
    }
    var previousValue = String(source[statusMemoKey(providerID)] || "")
    var worsened = severityRank(severity) > severityRank(severityFromMemoValue(previousValue))
    var previousIncidentKey = incidentKeyFromMemoValue(previousValue)
    var currentIncidentKey = incidentKeyFromMemoValue(text)
    var incidentChanged = previousIncidentKey.length > 0
        && currentIncidentKey.length > 0
        && previousIncidentKey !== currentIncidentKey
    return {
        notify: previousValue.length === 0 || worsened || incidentChanged,
        value: text
    }
}

function applyStatusDecision(nextMemo, providerID, decision) {
    nextMemo[statusPrimedMemoKey(providerID)] = "1"
    if (decision.value.length > 0) {
        nextMemo[statusMemoKey(providerID)] = decision.value
    } else {
        delete nextMemo[statusMemoKey(providerID)]
    }
}
