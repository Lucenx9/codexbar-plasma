.pragma library
.import "Guards.js" as Guards
.import "ProviderNormalizer.js" as Normalizer
.import "ProviderSnapshot.js" as ProviderSnapshot
.import "SafeText.js" as SafeText

// An empty named-account list is a successful result. Failed refreshes carry
// no options so the controller can retain the last successful list.
function response(stdoutValue, stderrValue, providerID, receivedAtMs) {
    var text = SafeText.cliJsonText(stdoutValue);
    if (text === null) return {outcome: "tooLarge", message: ""};
    if (text.trim().length === 0) return {outcome: "empty", message: ProviderSnapshot.message(stderrValue)};
    var payload;
    try {
        payload = JSON.parse(text);
    } catch (error) {
        return {outcome: "invalidJson", message: ProviderSnapshot.message(error.message)};
    }
    return records(payload, providerID, receivedAtMs);
}

function records(payload, providerID, receivedAtMs) {
    var key = Normalizer.normalizedProviderID(providerID);
    if (key.length === 0) return {outcome: "empty", message: ""};
    var items = Array.isArray(payload) ? payload : [payload];
    var options = [];
    var failure = null;
    var sawMissingTokenAccounts = false;
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
        if (items.length > 0 && !sawMissingTokenAccounts) return {outcome: "empty", message: ""};
    }
    return {outcome: "success", options: options, message: ""};
}
