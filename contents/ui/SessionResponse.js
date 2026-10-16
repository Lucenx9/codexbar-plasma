.pragma library
.import "ProviderNormalizer.js" as Normalizer
.import "CliResponse.js" as CliResponse

// Failure outcomes carry no snapshot: only a successful response may replace
// the last completed scan, including a confirmed empty session list.
function response(stdoutValue, stderrValue, exitCode) {
    var parsed = CliResponse.decode(stdoutValue, stderrValue, exitCode, 0);
    if (parsed.outcome !== "success") return parsed;
    var payload = parsed.payload;
    var sessions = Normalizer.normalizeSessions(payload);
    if (sessions === null) {
        return { outcome: "unsupported", message: "" };
    }
    return { outcome: "success", sessions: sessions, message: "" };
}
