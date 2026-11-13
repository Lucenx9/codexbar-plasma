import * as SafeText from "./SafeText.mjs";

// Bound copies across the thread boundary without parsing on the GUI thread.
// Keep one extra stdout unit so decode still classifies an oversized response.
export function message(run, stdoutValue, stderrValue, exitCode) {
    return {
        serial: run.serial,
        stdoutText: typeof stdoutValue === "string"
            ? stdoutValue.slice(0, SafeText.maximumCliJsonLength + 1)
            : stdoutValue === null || stdoutValue === undefined ? "" : {},
        stderrText: typeof stderrValue === "string"
            ? stderrValue.slice(0, SafeText.maximumDiagnosticLength) : "",
        historyDays: run.historyDays,
        exitCode: typeof exitCode === "number" || typeof exitCode === "string" ? exitCode : null
    };
}
