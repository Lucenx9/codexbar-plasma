"""Execute production secret-prompt scripts with isolated dialog and CLI fixtures."""

import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/lib"))
from qml_surfaces import Surface

QML = '''import QtQuick
import QtTest
import "SOURCE_URL/Guards.js" as Guards
import "SOURCE_URL/config/ProviderDescriptor.js" as ProviderDescriptor
TestCase {
    name: "SecretPromptCommands"
    property string commandPath: CLI_PATH
    property string errorText: ""
    property string statusText: ""
    property var captured: []
    SOURCE_PROPERTIES
    SOURCE_FUNCTIONS
    function i18n(text) { return text; }
    function displayNameForProvider(provider) { return provider; }
    function providerCliArgument(provider) { return provider; }
    function isPending(provider) { return false; }
    function isFieldPending(provider, field) { return false; }
    function markPending(provider, pending, desired) {}
    function markFieldPending(provider, field, pending) {}
    function runCommand(command, descriptor) {
        captured.push({command: command, descriptor: descriptor});
    }
    function test_generateProductionCommands() {
        var production = {deadline: configSecretPromptTimeoutMs,
            phases: configSecretPromptDialogTimeoutSeconds
                + configSecretPromptDialogKillAfterSeconds
                + configSecretCommandTimeoutSeconds + configSecretCommandKillAfterSeconds};
        configSecretPromptDialogTimeoutSeconds = 0.6;
        configSecretPromptDialogKillAfterSeconds = 0.2;
        configSecretCommandTimeoutSeconds = 0.6;
        configSecretCommandKillAfterSeconds = 0.2;
        setApiKey("codex");
        promptDescriptorSecret("codex", {id: "apiKey", title: "API key", kind: "secret",
            writeCommand: ["codexbar", "config", "set-api-key", "--provider", "codex", "--stdin"]});
        compare(errorText, "");
        compare(captured.length, 2);
        console.log("PROMPT_FIXTURE:" + JSON.stringify({production: production, commands: captured}));
    }
}
'''

PROCESS = '''import json, os, signal, sys, time
from pathlib import Path
role = Path(sys.argv[0]).name
directory = Path(os.environ["PROMPT_DIRECTORY"])
directory.joinpath(role + ".pid").write_text(str(os.getpid()))
mode = os.environ["PROMPT_MODE"]
if role == "kdialog":
    if mode == "cancel":
        sys.exit(1)
    if mode == "dialog-kill":
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
    if mode.startswith("dialog-"):
        time.sleep(30)
    if mode == "late":
        time.sleep(0.45)
    print("synthetic-secret")
else:
    assert sys.stdin.read() == "synthetic-secret"
    assert "synthetic-secret" not in " ".join(sys.argv)
    directory.joinpath("received").touch()
    if mode == "cli-kill":
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
    if mode.startswith("cli-"):
        time.sleep(30)
    if mode == "late":
        time.sleep(0.45)
    print(json.dumps({"ok": True}))
'''


class SecretPromptLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="codexbar prompt 'test-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.directory = Path(cls.temporary.name)
        for name in ("kdialog", "codexbar"):
            script = cls.directory / name
            script.write_text("#!" + sys.executable + "\n" + PROCESS)
            script.chmod(0o700)
        providers = Surface("providers", ROOT)
        page = ROOT / "contents/ui/configProviders.qml"
        source = providers.texts[page]
        providers.texts = {page: source}
        functions = []
        for name in ("setApiKey", "promptDescriptorSecret", "shellQuote"):
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + providers.function_body(name) + "}")
        properties = re.findall(
            r"^    readonly property int configSecret\w+:.*(?:\n[ \t]{8,}\S.*)*", source, re.MULTILINE)
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("CLI_PATH", json.dumps(str(cls.directory / "codexbar")))
        qml = qml.replace("SOURCE_FUNCTIONS", "\n".join(functions))
        qml = qml.replace("SOURCE_PROPERTIES", "\n".join(properties).replace("readonly property int", "property real"))
        fixture = cls.directory / "tst_secret_prompt.qml"
        fixture.write_text(qml)
        result = subprocess.run(
            [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
            env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
            capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        if result.returncode:
            raise AssertionError(output)
        capture = next(line.split("PROMPT_FIXTURE:", 1)[1] for line in output.splitlines()
                       if "PROMPT_FIXTURE:" in line)
        cls.fixture = json.loads(capture)

    def test_ledger_deadline_covers_both_phases_and_disconnect_margin(self):
        production = self.fixture["production"]
        self.assertGreaterEqual(production["deadline"], production["phases"] * 1000 + 5000)

    def test_generated_scripts_cancel_finish_and_leave_no_running_children(self):
        for entry in self.fixture["commands"]:
            for mode in ("cancel", "dialog-term", "dialog-kill", "late", "cli-term", "cli-kill"):
                with self.subTest(kind=entry["descriptor"]["kind"], mode=mode):
                    self.run_prompt(entry, mode)

    def run_prompt(self, entry, mode):
        for marker in self.directory.glob("*.pid"):
            marker.unlink()
        (self.directory / "received").unlink(missing_ok=True)
        self.assertNotIn("synthetic-secret", entry["command"])
        process = subprocess.Popen(
            ["sh", "-c", entry["command"]], start_new_session=True,
            env={**os.environ, "PATH": str(self.directory) + os.pathsep + os.environ["PATH"],
                 "PROMPT_DIRECTORY": str(self.directory), "PROMPT_MODE": mode},
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            stdout, stderr = process.communicate(timeout=5)
            if mode.startswith("cli-"):
                self.assertIn(process.returncode, (124, 137), stderr)
            else:
                self.assertEqual(process.returncode, 0, stderr)
                self.assertEqual(json.loads(stdout), {"ok": True} if mode == "late" else {"cancelled": True})
            self.assertEqual((self.directory / "received").exists(), mode == "late" or mode.startswith("cli-"))
            for marker in self.directory.glob("*.pid"):
                status = Path("/proc") / marker.read_text() / "stat"
                try:
                    state = status.read_text().rsplit(")", 1)[1].split()[0]
                except FileNotFoundError:
                    continue
                self.assertEqual(state, "Z", marker.name)
        finally:
            for marker in self.directory.glob("*.pid"):
                try:
                    os.kill(int(marker.read_text()), signal.SIGKILL)
                except ProcessLookupError:
                    pass
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.communicate()


if __name__ == "__main__":
    unittest.main()
