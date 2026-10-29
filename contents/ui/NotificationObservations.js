.pragma library
.import "Guards.js" as Guards
.import "ProviderNormalizer.js" as Normalizer
.import "NotificationPlanner.js" as NotificationPlanner
.import "QuotaThresholds.js" as QuotaThresholds

// Public operations: build and freshPending.
// Inputs are the applet's normalized provider snapshots and canonical account /
// refresh maps. No input is mutated. Indexes refer to the original snapshots so
// QML can localize and dispatch the planner's intents without copying raw data.
function selectedAccount(providerID, selectedAccounts) {
    var key = Normalizer.providerSnapshotKey(providerID)
    if (key.length === 0) {
        return ""
    }
    var selected = selectedAccounts[key]
    return selected ? String(selected) : ""
}

function freshPending(items, selectedAccounts, refreshPending) {
    var nextPending = Guards.copyObject(refreshPending)
    for (var i = 0; i < items.length; i++) {
        var item = items[i]
        if (!item || (item.usageStale === true && item.statusKnown !== true)) {
            continue
        }
        var providerID = Normalizer.providerSnapshotKey(item.provider)
        if (providerID.length === 0) {
            continue
        }
        var account = selectedAccount(providerID, selectedAccounts)
        if (account.length > 0 && Normalizer.accountKey(item) !== account) {
            continue
        }
        // A failed account refresh can still carry fresh provider status.
        // The planner separately ignores missing quota evidence.
        delete nextPending[providerID]
    }
    return nextPending
}

function quotaLevel(row, thresholds) {
    if (!row || !row.hasPercent || !Normalizer.authoritativeQuota(row)) {
        return ""
    }
    return QuotaThresholds.level(
        row.usedPercent,
        thresholds.warningPercent,
        thresholds.criticalPercent)
}

function observationRows(item, thresholds) {
    if (item && item.usageStale === true) {
        return []
    }
    var sourceRows = item && Array.isArray(item.rows) ? item.rows : []
    var result = []
    for (var i = 0; i < sourceRows.length; i++) {
        var row = sourceRows[i]
        result.push({
            lane: row && row.lane ? String(row.lane) : "",
            windowId: row ? Normalizer.extraWindowID(row.windowId) : "",
            label: row && row.label ? String(row.label) : "",
            resetsAt: row && row.resetsAt ? String(row.resetsAt) : "",
            hasPercent: row && row.hasPercent === true,
            dataConfidence: row ? row.dataConfidence : "",
            usedPercent: row ? Number(row.usedPercent) : NaN,
            quotaLevel: quotaLevel(row, thresholds),
            paceKnown: row && row.paceKnown === true,
            paceActive: row && Normalizer.authoritativeQuota(row) && row.paceOnTop === false && Number(row.paceEtaSeconds) > 0
        })
    }
    return result
}

function build(providers, selectedAccounts, refreshPending, thresholds) {
    var result = []
    for (var i = 0; i < providers.length; i++) {
        var item = providers[i]
        if (!item) {
            continue
        }
        var providerID = Normalizer.providerSnapshotKey(item.provider)
        var account = selectedAccount(providerID, selectedAccounts)
        var rows = observationRows(item, thresholds)
        result.push({
            providerIndex: i,
            providerID: providerID,
            scopeID: JSON.stringify([providerID, account.length > 0 ? account : Normalizer.accountKey(item)]),
            pending: NotificationPlanner.observationPending(
                (item.usageStale === true && item.statusKnown !== true)
                    || (providerID.length > 0 && refreshPending[providerID] === true),
                String(item.error || "").length > 0,
                item.statusKnown === true,
                rows.length),
            errorPresent: String(item.error || "").length > 0,
            usageStale: item.usageStale === true,
            statusKnown: item.statusKnown === true,
            statusActive: item.hasIncident === true
                && String(item.statusSeverity || "").length > 0
                && String(item.status || "").length > 0,
            statusSeverity: String(item.statusSeverity || ""),
            statusIncidentKey: String(item.statusIncidentKey || ""),
            rows: rows
        })
    }
    return result
}
