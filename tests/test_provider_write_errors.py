"""Failed provider writes must unlock actions without reporting a saved change."""

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
import "SOURCE_URL/config/ProviderConfigProtocol.js" as ProviderConfigProtocol
TestCase {
    name: "ProviderWriteErrors"
    Component {
        id: harness
        QtObject {
            property bool pending: true
            property int writes: 0
            property int revisions: 0
            property string errorText: ""
            property string statusText: ""
            SOURCE_FUNCTIONS
            function i18n(text, first, second) {
                return text.replace("%1", first).replace("%2", second);
            }
            function displayNameForProvider(provider) { return provider; }
            function markPending(provider, value) { pending = value; }
            function updateProviderEnabled(provider, value) { writes++; }
            function bumpProviderConfigRevision() { revisions++; }
            function invalidateProviderDiagnostic(provider) {}
        }
    }

    function test_failedWrite_data() {
        var cases = [];
        var messages = [undefined, "", "   ", {detail: "failed"}, ["failed"], {toString: null}];
        for (var handler of ["handleToggleResult", "handleSetApiKeyResult"]) {
            for (var index = 0; index < messages.length; index++) {
                for (var wrapped of [false, true]) {
                    cases.push({tag: handler + index + wrapped, handler: handler,
                        message: messages[index], wrapped: wrapped});
                }
            }
        }
        return cases;
    }

    function test_failedWrite(data) {
        var page = createTemporaryObject(harness, this);
        verify(page !== null);
        var payload = {provider: "codex", error: {message: data.message}};
        page[data.handler]({provider: "codex", desiredEnabled: true},
            JSON.stringify(data.wrapped ? [payload] : payload), "", 0);
        verify(!page.pending);
        compare(page.writes, 0);
        compare(page.revisions, 0);
        compare(page.statusText, "");
        compare(page.errorText, "codex: codexbar command failed.");
    }

    function test_onlyApiKeyWriteAcceptsEmptySuccess() {
        var keyPage = createTemporaryObject(harness, this);
        keyPage.handleSetApiKeyResult({provider: "codex"}, "", "", 0);
        verify(!keyPage.pending);
        compare(keyPage.writes, 1);
        compare(keyPage.revisions, 1);
        compare(keyPage.statusText, "codex API key saved");
        compare(keyPage.errorText, "");
        var togglePage = createTemporaryObject(harness, this);
        togglePage.handleToggleResult({provider: "codex", desiredEnabled: true}, "", "", 0);
        verify(!togglePage.pending);
        compare(togglePage.writes, 0);
        compare(togglePage.revisions, 0);
        compare(togglePage.errorText, "codex: codexbar did not return command data.");
    }

    function test_invalidWritePayloadNamesCommandData() {
        for (var handler of ["handleToggleResult", "handleSetApiKeyResult"]) {
            var page = createTemporaryObject(harness, this);
            page[handler]({provider: "codex"}, "true", "", 0);
            compare(page.errorText, "codex: codexbar did not return command data.");
            compare(page.revisions, 0);
        }
    }

    function test_apiKeyCancellationDoesNotCommit() {
        var page = createTemporaryObject(harness, this);
        page.errorText = "previous failure";
        page.statusText = "previous save";
        page.handleSetApiKeyResult({provider: "codex"}, '{"status":"cancelled"}', "", 0);
        verify(!page.pending);
        compare(page.writes, 0);
        compare(page.revisions, 0);
        compare(page.errorText, "");
        compare(page.statusText, "");
    }

    function test_failedExitCannotCommitValidWriteJson() {
        for (var handler of ["handleToggleResult", "handleSetApiKeyResult"]) {
            var page = createTemporaryObject(harness, this);
            page[handler]({provider: "codex", desiredEnabled: true},
                '{"provider":"codex","enabled":true}', "", 7);
            verify(!page.pending);
            compare(page.writes, 0);
            compare(page.revisions, 0);
            compare(page.statusText, "");
            compare(page.errorText, "codex: codexbar exited with code 7");
        }
    }
}
'''


class ProviderWriteErrorsTests(unittest.TestCase):
    def test_failed_writes_preserve_state_and_show_a_failure(self):
        source = (ROOT / "contents/ui/configProviders.qml").read_text()
        surface = Surface("providers", ROOT)
        functions = []
        for name in ("handleToggleResult", "handleSetApiKeyResult", "providerCommandFailureText"):
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + surface.function_body(name) + "}")
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n".join(functions))
        with tempfile.TemporaryDirectory(prefix="codexbar-provider-write-") as temporary:
            fixture = Path(temporary) / "tst_provider_write.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
