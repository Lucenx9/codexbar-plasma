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
import "SOURCE_URL/SafeText.js" as SafeText
import "SOURCE_URL/config/ProviderConfigProtocol.js" as ProviderConfigProtocol
TestCase {
    name: "ProviderDiagnosticResults"
    property string commandPath: "codexbar"
    property var commands: ({})
    property var diagnostic: null
    property string diagnosticError: ""
    property bool diagnosticLoading: false
    SOURCE_FUNCTIONS
    function i18n(text, value) { return text.replace("%1", value); }
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
}
'''


class ProviderDiagnosticResultsTests(unittest.TestCase):
    def test_production_completion(self):
        surface = Surface("providers", ROOT)
        source = (ROOT / "contents/ui/configProviders.qml").read_text()
        surface.texts = {ROOT / "contents/ui/configProviders.qml": source}
        functions = []
        for name in ("handleData", "handleDiagnoseResult", "boundedCliMessage",
                     "providerCommandFailureText"):
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
