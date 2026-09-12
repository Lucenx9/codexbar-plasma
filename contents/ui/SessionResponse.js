.pragma library
.import "ProviderNormalizer.js" as Normalizer
.import "SafeText.js" as SafeText

function boundedMessage(value) {
    return SafeText.cliMessage(SafeText.stripLoaderDiagnostics(value), SafeText.maximumCliMessageLength);
}

// Failure outcomes carry no snapshot: only a successful response may replace
// the last completed scan, including a confirmed empty session list.
function response(stdoutValue, stderrValue) {
    var text = SafeText.cliJsonText(stdoutValue);
    if (text === null) {
        return { outcome: "tooLarge", message: "" };
    }
    if (text.trim().length === 0) {
        return { outcome: "empty", message: boundedMessage(stderrValue) };
    }
    var payload;
    try {
        payload = JSON.parse(text);
    } catch (error) {
        return { outcome: "invalidJson", message: boundedMessage(error.message) };
    }
    var sessions = Normalizer.normalizeSessions(payload);
    if (sessions === null) {
        return { outcome: "unsupported", message: "" };
    }
    return { outcome: "success", sessions: sessions, message: "" };
}
