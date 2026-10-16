.pragma library
.import "SafeText.js" as SafeText
.import "ProviderNormalizer.js" as Normalizer

function message(value) {
    return SafeText.cliMessage(SafeText.stripLoaderDiagnostics(value), SafeText.maximumCliMessageLength);
}

// Exit 1 is the released CLI's structured provider/argument error contract.
// It can accompany healthy siblings, but cannot authorize an unexplained
// success payload. Limit the scan to the records the caller will consume.
function hasStructuredError(payload, recordLimit) {
    var items = Array.isArray(payload) ? payload : [payload];
    for (var i = 0; i < Math.min(items.length, recordLimit); i++) {
        var item = items[i];
        if (!Normalizer.isCliRecord(item) || Normalizer.normalizedProviderID(item.provider).length === 0)
            continue;
        var error = item.error;
        if (Normalizer.isCliRecord(error) && error.code === 1 && (error.kind === "provider" || error.kind === "args"))
            return true;
    }
    return false;
}

// A positive record limit opts into structured exit-1 results. All other
// callers require exit 0. Unknown/missing statuses fail closed.
function decode(stdoutValue, stderrValue, exitCode, errorRecordLimit) {
    var acceptsErrors = typeof errorRecordLimit === "number" && isFinite(errorRecordLimit) && errorRecordLimit > 0 && errorRecordLimit <= Normalizer.maximumProviderSnapshots;
    if (exitCode !== 0 && !(exitCode === 1 && acceptsErrors))
        return {
            outcome: "commandFailed",
            message: message(stderrValue)
        };
    if (stdoutValue !== null && stdoutValue !== undefined && typeof stdoutValue !== "string")
        return {
            outcome: "invalidJson",
            message: ""
        };
    var text = SafeText.cliJsonText(stdoutValue);
    if (text === null)
        return {
            outcome: "tooLarge",
            message: ""
        };
    if (text.trim().length === 0)
        return {
            outcome: "empty",
            message: message(stderrValue)
        };
    var payload;
    try {
        payload = JSON.parse(text);
    } catch (error) {
        return {
            outcome: "invalidJson",
            message: message(error.message)
        };
    }
    if (exitCode === 1 && !hasStructuredError(payload, Math.floor(errorRecordLimit)))
        return {
            outcome: "commandFailed",
            message: message(stderrValue)
        };
    return {
        outcome: "success",
        payload: payload,
        message: ""
    };
}
