.pragma library
.import "SafeText.js" as SafeText
.import "ProviderNormalizer.js" as Normalizer

function message(value) {
    return SafeText.cliMessage(SafeText.stripLoaderDiagnostics(value), SafeText.maximumCliMessageLength);
}

// The released CLI exits with its last failed fetch's code (1 unexpected,
// 2 missing binary, 3 parse, 4 timeout) and records that code on the error.
// Such errors can accompany healthy siblings, but cannot authorize an
// unexplained success payload. Provider errors carry kind provider, runtime,
// or none (cost); the `cli` record explains the exit only for rejected
// arguments. Limit the scan to the records the caller will consume.
var structuredErrorExitCodes = [1, 2, 3, 4];

function explainsExit(item, exitCode) {
    if (!Normalizer.isCliRecord(item))
        return false;
    var provider = Normalizer.normalizedProviderID(item.provider);
    var error = item.error;
    if (provider.length === 0 || !Normalizer.isCliRecord(error) || error.code !== exitCode)
        return false;
    if (error.kind === "args")
        return true;
    return provider !== "cli" && (error.kind === undefined || error.kind === "provider" || error.kind === "runtime");
}

function hasStructuredError(payload, exitCode, recordLimit) {
    var items = Array.isArray(payload) ? payload : [payload];
    for (var i = 0; i < Math.min(items.length, recordLimit); i++) {
        if (explainsExit(items[i], exitCode))
            return true;
    }
    return false;
}

// A positive record limit opts into structured failure results. All other
// callers require exit 0. Unknown/missing statuses fail closed.
function decode(stdoutValue, stderrValue, exitCode, errorRecordLimit) {
    var acceptsErrors = typeof errorRecordLimit === "number" && isFinite(errorRecordLimit) && errorRecordLimit > 0 && errorRecordLimit <= Normalizer.maximumProviderSnapshots;
    var structuredExit = acceptsErrors && structuredErrorExitCodes.indexOf(exitCode) !== -1;
    if (exitCode !== 0 && !structuredExit)
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
    if (structuredExit && !hasStructuredError(payload, exitCode, Math.floor(errorRecordLimit)))
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
