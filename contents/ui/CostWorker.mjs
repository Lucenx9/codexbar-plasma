import * as CostResponse from "./CostResponse.mjs";

WorkerScript.onMessage = function(message) {
    var result;
    try {
        result = CostResponse.response(message.stdoutText, message.stderrText,
            message.historyDays, message.exitCode);
    } catch (_) {
        // Never send raw payloads or exception diagnostics back to the UI.
        result = {outcome: "unsupported", message: ""};
    }
    WorkerScript.sendMessage({serial: message.serial, result: result});
};
