.pragma library
.import "Guards.js" as Guards
.import "ProviderNormalizer.js" as Normalizer
.import "ProviderSnapshot.js" as ProviderSnapshot
.import "SafeText.js" as SafeText

function envelope(stdoutValue, stderrValue) {
    var text = SafeText.cliJsonText(stdoutValue);
    if (text === null) return {outcome: "tooLarge", message: ""};
    if (text.trim().length === 0) return {outcome: "empty", message: ProviderSnapshot.message(stderrValue)};
    try {
        return {outcome: "success", payload: JSON.parse(text), message: ""};
    } catch (error) {
        return {outcome: "invalidJson", message: ProviderSnapshot.message(error.message)};
    }
}

// Provider-scoped commands may only replace their requested provider. An
// aggregate response instead needs a valid identity on every accepted record.
// A broken record cannot discard a healthy sibling or strand a queue slot.
function records(payload, providerID, receivedAtMs) {
    var key = Normalizer.normalizedProviderID(providerID);
    var items = Array.isArray(payload) ? payload : [payload];
    var limit = key.length > 0 ? Normalizer.maximumAccountSnapshots : Normalizer.maximumProviderSnapshots;
    var snapshots = [];
    var failure = null;
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
            failure = {outcome: "invalidJson", message: ProviderSnapshot.message(error.message)};
        }
    }
    snapshots = Normalizer.dedupeProviderSnapshots(snapshots);
    if (snapshots.length === 0) return key.length > 0 && failure ? failure : {outcome: "noProviders", message: ""};
    return {outcome: "success", items: snapshots, message: ""};
}

function response(stdoutValue, stderrValue, providerID, receivedAtMs) {
    var parsed = envelope(stdoutValue, stderrValue);
    if (parsed.outcome !== "success") return parsed;
    var result = records(parsed.payload, providerID, receivedAtMs);
    if (result.outcome === "noProviders" && !providerID)
        result.message = ProviderSnapshot.message(stderrValue);
    return result;
}

function roster(stdoutValue, stderrValue) {
    var parsed = envelope(stdoutValue, stderrValue);
    if (parsed.outcome !== "success") return parsed;
    var entries = Normalizer.normalizeProviderConfigEntries(parsed.payload);
    return entries === null ? {outcome: "noProviders", message: ""}
        : {outcome: "success", providerIDs: entries.providerIDs, displayNames: entries.displayNames, message: ""};
}
