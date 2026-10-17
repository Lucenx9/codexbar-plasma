.pragma library
.import "Guards.js" as Guards
.import "ProviderNormalizer.js" as Normalizer
.import "ProviderSnapshot.js" as ProviderSnapshot
.import "CliResponse.js" as CliResponse
.import "AccountResponse.js" as AccountResponse

// Provider-scoped commands may only replace their requested provider. An
// aggregate response instead needs a valid identity on every accepted record.
// A broken record cannot discard a healthy sibling or strand a queue slot.
function records(payload, providerID, receivedAtMs) {
    var key = Normalizer.normalizedProviderID(providerID);
    var items = Array.isArray(payload) ? payload : [payload];
    var limit = key.length > 0 ? Normalizer.maximumAccountSnapshots : Normalizer.maximumProviderSnapshots;
    var snapshots = [];
    var lastFailure = null;
    for (var i = 0; i < Math.min(items.length, limit); i++) {
        try {
            if (!Normalizer.isCliRecord(items[i])) continue;
            var record = items[i];
            if (key.length > 0) {
                record = Guards.copyObject(record);
                record.provider = key;
            } else if (Normalizer.normalizedProviderID(record.provider).length === 0) {
                continue;
            }
            snapshots.push(ProviderSnapshot.normalize(record, receivedAtMs));
        } catch (error) {
            lastFailure = {outcome: "invalidJson", message: ProviderSnapshot.message(error.message)};
        }
    }
    snapshots = Normalizer.dedupeProviderSnapshots(snapshots);
    if (snapshots.length === 0) return key.length > 0 && lastFailure ? lastFailure : {outcome: "noProviders", message: ""};
    return {outcome: "success", items: snapshots, message: ""};
}

function response(stdoutValue, stderrValue, providerID, receivedAtMs, exitCode, selectedAccount) {
    var parsed = CliResponse.decode(stdoutValue, stderrValue, exitCode,
        providerID ? Normalizer.maximumAccountSnapshots : Normalizer.maximumProviderSnapshots);
    if (parsed.outcome !== "success") return parsed;
    // Codex exposes visible accounts through --all-accounts, not --account.
    // Match before provider deduplication can discard the selected record.
    if (providerID === "codex" && typeof selectedAccount === "string" && selectedAccount.length > 0) {
        var accounts = AccountResponse.records(parsed.payload, providerID, receivedAtMs);
        if (accounts.outcome !== "success") return accounts;
        var selected = accounts.options.filter(function(item) {
            return Normalizer.accountKey(item) === selectedAccount;
        });
        return selected.length > 0 ? {outcome: "success", items: selected, message: ""}
            : {outcome: "noProviders", message: ""};
    }
    var result = records(parsed.payload, providerID, receivedAtMs);
    if (result.outcome === "noProviders" && !providerID)
        result.message = ProviderSnapshot.message(stderrValue);
    return result;
}

function roster(stdoutValue, stderrValue, exitCode) {
    var parsed = CliResponse.decode(stdoutValue, stderrValue, exitCode, 0);
    if (parsed.outcome !== "success") return parsed;
    var entries = Normalizer.normalizeProviderConfigEntries(parsed.payload);
    return entries === null ? {outcome: "noProviders", message: ""}
        : {outcome: "success", providerIDs: entries.providerIDs, displayNames: entries.displayNames, message: ""};
}
