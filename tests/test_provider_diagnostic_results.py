"""Execute the Providers page's diagnostic completion path without KDE modules."""

import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/lib"))
from qml_surfaces import Surface

QML = '''import QtQuick
import QtTest
import "SOURCE_URL/CommandLedger.js" as CommandLedger
import "SOURCE_URL/Guards.js" as Guards
import "SOURCE_URL/SafeText.js" as SafeText
import "SOURCE_URL/config/ProviderConfigProtocol.js" as ProviderConfigProtocol
import "SOURCE_URL/config/ProviderSource.js" as ProviderSource
TestCase {
    id: page
    name: "ProviderDiagnosticResults"
    property string commandPath: "codexbar"
    property var commands: ({})
    property var diagnostic: null
    property string diagnosticError: ""
    property bool diagnosticLoading: false
    property string errorText: ""
    property string statusText: ""
    property string selectedProviderID: "codex"
    property QtObject providerSourceBox: QtObject { property int currentIndex: 1 }
    property QtObject configSource: QtObject {
        function disconnectSource(source) {}
    }
    SOURCE_FUNCTIONS
    function i18n(text, first, second) { return text.replace("%1", first).replace("%2", second); }
    function displayNameForProvider(provider) { return provider; }
    function providerCliArgument(provider) { return provider; }
    function markPending(provider, value) {}
    function markFieldPending(provider, field, value) {}
    function updateProviderEnabled(provider, enabled) {}
    function bumpProviderConfigRevision() {}
    function reload(preserve) {}
    function runReloadDeferredBySourceWrite() {}
    function setProviderDiagnostic(provider, value) { diagnostic = value; }
    function setProviderDiagnosticError(provider, value) { diagnosticError = value; }
    function setProviderDiagnosticLoading(provider, value) { diagnosticLoading = value; }
    function deliver(payload, stderr, code) {
        commands = CommandLedger.opened(commands, "probe", {
            kind: "diagnose", provider: "codex", commandPathSignature: commandPath });
        diagnosticLoading = true;
        handleData("probe", payload, stderr, code);
        verify(!diagnosticLoading);
        compare(CommandLedger.find(commands, "probe"), null);
    }
    function init() {
        commands = ({});
        diagnostic = { provider: "previous" };
        diagnosticError = "previous failure";
    }
    function test_failedProcessKeepsPreviousDiagnostic_data() {
        return [
            { tag: "exit", code: 3, stderr: "", error: "codexbar exited with code 3" },
            { tag: "stderr", code: 1, stderr: "synthetic failure", error: "synthetic failure" },
            { tag: "timeout", code: 124, stderr: "", error: "codexbar command timed out. Try again." },
            { tag: "killed", code: 137, stderr: "", error: "codexbar command timed out. Try again." }
        ];
    }
    function test_failedProcessKeepsPreviousDiagnostic(data) {
        deliver('[{"provider":"codex","auth":{"configured":true}}]', data.stderr, data.code);
        compare(diagnostic.provider, "previous");
        compare(diagnosticError, data.error);
    }
    function test_invalidEnvelopeCannotClearAnError_data() {
        return [
            { tag: "empty-error", payload: '{"error":{}}' },
            { tag: "status-failure", payload: '{"status":"failed"}' },
            { tag: "null", payload: 'null' },
            { tag: "empty-array", payload: '[]' },
            { tag: "scalar", payload: 'true' }
        ];
    }
    function test_invalidEnvelopeCannotClearAnError(data) {
        deliver(data.payload, "", 0);
        compare(diagnostic.provider, "previous");
        verify(diagnosticError.length > 0);
    }
    function test_healthyArrayAllowsLoaderNoiseAndClearsError() {
        deliver('[{"provider":"codex","auth":{"configured":true}}]', "loader warning", 0);
        compare(diagnostic.provider, "codex");
        compare(diagnostic.authConfigured, true);
        compare(diagnosticError, "");
    }
    function test_healthyObjectRecoversAfterFailure() {
        deliver('{"provider":"codex"}', "", 3);
        verify(diagnosticError.length > 0);
        deliver('{"provider":"codex","auth":{"configured":false}}', "", 0);
        compare(diagnostic.provider, "codex");
        compare(diagnostic.authConfigured, false);
        compare(diagnosticError, "");
    }
    function test_reportWithFetchFailureIsStillADiagnostic_data() {
        var report = { schemaVersion: "1.0", provider: "codex", source: "failed",
            auth: { configured: false, modes: [] }, settings: { sourceMode: "auto" },
            fetchAttempts: [{ kind: "cli", wasAvailable: false }],
            error: { category: "unknown", safeDescription: "Synthetic fetch failure" } };
        return [{ tag: "object", payload: JSON.stringify(report) },
            { tag: "array", payload: JSON.stringify([report]) }];
    }
    function test_reportWithFetchFailureIsStillADiagnostic(data) {
        deliver(data.payload, "loader warning", 0);
        compare(diagnostic.provider, "codex");
        compare(diagnostic.source, "failed");
        compare(diagnostic.fetchAttempts, 1);
        compare(diagnosticError, "");
        deliver(data.payload, "", 3);
        compare(diagnosticError, "codexbar exited with code 3");
    }
    function test_firstFailedDiagnosticStaysAbsent() {
        diagnostic = null;
        deliver('{"provider":"codex"}', "", 3);
        compare(diagnostic, null);
        compare(diagnosticError, "codexbar exited with code 3");
    }
    function test_structuredErrorWinsOverStderr() {
        deliver('[{"error":{"message":"synthetic provider failure"}}]', "other failure", 1);
        compare(diagnostic.provider, "previous");
        compare(diagnosticError, "synthetic provider failure");
    }
    function test_emptyTimeoutNamesTheTimeout() {
        deliver("", "", 124);
        compare(diagnostic.provider, "previous");
        compare(diagnosticError, "codexbar command timed out. Try again.");
    }
    function test_invalidJsonKeepsDiagnosticAndRedactsParserDetail() {
        var secret = "sk-abcdefghijklmnopqrstuvwxyz1234567890";
        deliver('{"api_key":"' + secret, "", 0);
        compare(diagnostic.provider, "previous");
        verify(diagnosticError.indexOf("Could not parse codexbar diagnostics:") === 0);
        verify(diagnosticError.indexOf(secret) < 0);
    }
    function test_retiredReplyCannotReplaceDiagnostic() {
        handleData("retired", '[{"provider":"codex"}]', "", 0);
        compare(diagnostic.provider, "previous");
        compare(diagnosticError, "previous failure");
    }
    function test_changedCommandCannotReplaceDiagnostic() {
        commands = CommandLedger.opened(commands, "probe", {
            kind: "diagnose", provider: "codex", commandPathSignature: "old-cli" });
        handleData("probe", '[{"provider":"codex"}]', "", 0);
        compare(diagnostic.provider, "previous");
        compare(diagnosticError, "previous failure");
    }
    function mutationCases() {
        return ["handleToggleResult", "handleSetApiKeyResult", "handleSetSourceResult",
            "handleDescriptorFieldResult", "handleDescriptorActionResult"].map(function(handler) {
                return {tag: handler, handler: handler};
            });
    }
    function test_successfulWriteInvalidatesOldDiagnostic_data() { return mutationCases(); }
    function test_successfulWriteInvalidatesOldDiagnostic(data) {
        commands = CommandLedger.opened(commands, "old-diagnostic", {
            kind: "diagnose", provider: "codex", commandPathSignature: commandPath });
        commands = CommandLedger.opened(commands, "other-diagnostic", {
            kind: "diagnose", provider: "claude", commandPathSignature: commandPath });
        diagnosticLoading = true;
        this[data.handler]({provider: "codex", desiredEnabled: true, sourceMode: "api"},
            '{"provider":"codex","enabled":true,"source":"api"}', "", 0);
        compare(diagnostic, null);
        compare(diagnosticError, "");
        verify(!diagnosticLoading);
        compare(CommandLedger.find(commands, "old-diagnostic"), null);
        verify(CommandLedger.find(commands, "other-diagnostic") !== null);
        handleData("old-diagnostic", '{"provider":"codex","auth":{"configured":false}}', "", 0);
        compare(diagnostic, null);
        deliver('{"provider":"codex","auth":{"configured":true}}', "", 0);
        verify(diagnostic.authConfigured);
    }
    function test_failedWritePreservesDiagnostic_data() { return mutationCases(); }
    function test_failedWritePreservesDiagnostic(data) {
        this[data.handler]({provider: "codex", sourceMode: "api"},
            '{"error":{"message":"Synthetic failure"}}', "", 1);
        compare(diagnostic.provider, "previous");
        compare(diagnosticError, "previous failure");
    }
    function test_cancelledKeyPromptPreservesDiagnostic() {
        handleSetApiKeyResult({provider: "codex"}, '{"cancelled":true}', "", 0);
        compare(diagnostic.provider, "previous");
        compare(diagnosticError, "previous failure");
    }
}
'''


class ProviderDiagnosticResultsTests(unittest.TestCase):
    def test_production_completion(self):
        surface = Surface("providers", ROOT)
        source = (ROOT / "contents/ui/configProviders.qml").read_text()
        surface.texts = {ROOT / "contents/ui/configProviders.qml": source}
        functions = []
        for name in ("handleData", "handleDiagnoseResult", "boundedCliMessage",
                     "providerCommandFailureText", "handleToggleResult", "handleSetApiKeyResult",
                     "handleSetSourceResult", "applySetSourceResult", "handleDescriptorFieldResult",
                     "handleDescriptorActionResult", "retireProviderDiagnostic",
                     "invalidateProviderDiagnostic", "hasOwnKey"):
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + surface.function_body(name) + "}")
        qml = (QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
               .replace("SOURCE_FUNCTIONS", "\n".join(functions)))
        with tempfile.TemporaryDirectory(prefix="codexbar-diagnostic-result-") as temporary:
            fixture = Path(temporary) / "tst_results.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"),
                 "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("SKIP", output)


if __name__ == "__main__":
    unittest.main()
