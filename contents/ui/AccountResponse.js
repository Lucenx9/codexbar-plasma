.pragma library
.import "Guards.js" as Guards
.import "ProviderNormalizer.js" as Normalizer
.import "ProviderSnapshot.js" as ProviderSnapshot
.import "CliResponse.js" as CliResponse

// An empty named-account list is a successful result. Failed refreshes carry
// no options so the controller can retain the last successful list. Successes
// report availability: "named", "none" (default sign-in only) or "unsupported".
function response(stdoutValue, stderrValue, providerID, receivedAtMs, exitCode) {
    var parsed = CliResponse.decode(stdoutValue, stderrValue, exitCode, Normalizer.maximumAccountSnapshots);
    if (parsed.outcome !== "success") return parsed;
    var payload = parsed.payload;
    return records(payload, providerID, receivedAtMs);
}

function records(payload, providerID, receivedAtMs) {
    var key = Normalizer.normalizedProviderID(providerID);
    if (key.length === 0) return {outcome: "empty", message: ""};
    var items = Array.isArray(payload) ? payload : [payload];
    var options = [];
    var failure = null;
    var sawMissingTokenAccounts = false;
    var sawUnsupportedTokenAccounts = false;
    for (var i = 0; i < Math.min(items.length, Normalizer.maximumAccountSnapshots); i++) {
        if (!Normalizer.isCliRecord(items[i])) continue;
        var snapshot;
        try {
            var record = Guards.copyObject(items[i]);
            record.provider = key;
            snapshot = ProviderSnapshot.normalize(record, receivedAtMs);
        } catch (error) {
            failure = {outcome: "recordError", message: ProviderSnapshot.message(error.message)};
            continue;
        }
        if (snapshot.commandFailed && Normalizer.accountLabel(snapshot).length === 0) {
            if (Normalizer.isMissingTokenAccountsError(snapshot.error)) {
                sawMissingTokenAccounts = true;
            } else if (Normalizer.isUnsupportedTokenAccountsError(snapshot.error)) {
                sawUnsupportedTokenAccounts = true;
            } else {
                failure = {outcome: "commandFailed", message: snapshot.error};
            }
            continue;
        }
        options.push(snapshot);
    }
    options = Normalizer.dedupeAccountOptions(options);
    if (options.length === 0) {
        if (failure) return failure;
        if (sawUnsupportedTokenAccounts) return {outcome: "success", options: [], availability: "unsupported", message: ""};
        if (items.length > 0 && !sawMissingTokenAccounts) return {outcome: "empty", message: ""};
    }
    return {outcome: "success", options: options, availability: options.length > 0 ? "named" : "none", message: ""};
}
