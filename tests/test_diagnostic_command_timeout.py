"""Execute production diagnostics commands with shrunken shell timeouts.

`configDiagnostics.qml` retires its own state on timeout, but only a
shell-side `timeout --kill-after` bound actually kills a hung `codexbar`
child. This test extracts the real `runCommand` path, shrinks the timeout
constants in the fixture, and proves against a fake CLI that a child ignoring
SIGTERM really dies on schedule, and that diagnostics still run where GNU
`timeout` is absent. It also extracts the real `handleDiagnosticData` branch
and proves that a completion reaped by the shell bound (GNU timeout's 124,
or 137 when --kill-after escalates to SIGKILL) surfaces the existing timeout
message instead of "exited with code ...", while ordinary failures still
report the CLI's own error.
"""

import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/lib"))
from qml_surfaces import Surface

QML = '''import QtQuick
import QtTest
import "SOURCE_URL/Guards.js" as Guards
import "SOURCE_URL/SafeText.js" as SafeText
TestCase {
    name: "DiagnosticCommandTimeout"
    property string commandPath: CLI_PATH
    property bool diagnosticRunning: false
    property string diagnosticOutput: ""
    property string diagnosticError: ""
    property string activeCommand: ""
    property var diagnosticProviderField: ({text: ""})
    property var diagnosticSource
    property var diagnosticCommandTimeoutTimer
    SOURCE_PROPERTIES
    SOURCE_FUNCTIONS
    function i18n(text, first) {
        return String(text).replace("%1", first);
    }
    function freshBackend() {
        var backend = {connected: [], disconnected: []};
        backend.connectSource = function(name) { backend.connected.push(name); };
        backend.disconnectSource = function(name) { backend.disconnected.push(name); };
        return backend;
    }
    function test_generateProductionCommands() {
        var production = {timeoutMs: diagnosticCommandTimeoutMs,
            timeoutSeconds: diagnosticCommandTimeoutSeconds,
            killAfterSeconds: diagnosticCommandKillAfterSeconds};
        diagnosticCommandTimeoutSeconds = 0.6;
        diagnosticCommandKillAfterSeconds = 0.2;
        diagnosticSource = freshBackend();
        diagnosticCommandTimeoutTimer = {restart: function() {}, stop: function() {}};
        runDiagnostic();
        runProviderList();
        console.log("DIAGNOSTIC_FIXTURE:" + JSON.stringify({production: production,
            commands: diagnosticSource.connected}));
    }
    function exerciseCompletion(stdoutText, stderrText, exitStatus) {
        activeCommand = "CODEXBAR_PLASMA_RUN=99 probe";
        handleDiagnosticData(activeCommand,
            {"stdout": stdoutText, "stderr": stderrText, "exit code": exitStatus});
        return diagnosticError;
    }
    function test_completionMessageMapping() {
        diagnosticSource = freshBackend();
        diagnosticCommandTimeoutTimer = {restart: function() {}, stop: function() {}};
        var messages = {
            shellTimeoutSilent: exerciseCompletion("", "", 124),
            shellKillAfterSilent: exerciseCompletion("", "", 137),
            cliErrorWithMessage: exerciseCompletion("", "cli broke", 1),
            cliErrorSilent: exerciseCompletion("", "", 3),
            cli124WithMessage: exerciseCompletion("", "weird code", 124)
        };
        console.log("DIAGNOSTIC_MESSAGES:" + JSON.stringify(messages));
    }
}
'''

FAKE_CLI = '''import json, os, signal, sys, time
from pathlib import Path
directory = Path(os.environ["DIAG_DIRECTORY"])
directory.joinpath("codexbar.pid").write_text(str(os.getpid()))
if os.environ["DIAG_MODE"] == "hang":
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    time.sleep(30)
print(json.dumps({"ok": True}))
'''

DIAGNOSTIC_FUNCTIONS = (
    "shellQuote",
    "boundedDiagnosticCommand",
    "commandWithRunNonce",
    "finishDiagnosticCommand",
    "runCommand",
    "runDiagnostic",
    "runProviderList",
    "handleDiagnosticData",
)


class DiagnosticCommandTimeoutTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="codexbar-diag-timeout-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.directory = Path(cls.temporary.name)
        fake = cls.directory / "codexbar"
        fake.write_text("#!" + sys.executable + "\n" + FAKE_CLI)
        fake.chmod(0o700)
        cls.shell = shutil.which("sh") or "/bin/sh"
        diagnostics = Surface("diagnostics", ROOT)
        page = ROOT / "contents/ui/configDiagnostics.qml"
        source = diagnostics.texts[page]
        diagnostics.texts = {page: source}
        functions = []
        for name in DIAGNOSTIC_FUNCTIONS:
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + diagnostics.function_body(name) + "}")
        serial = re.search(r"^    property int commandRunSerial: 0$", source,
                           re.MULTILINE).group(0)
        timeouts = re.findall(
            r"^    readonly property int diagnosticCommand\w+: \d+$", source, re.MULTILINE)
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("CLI_PATH", json.dumps(str(fake)))
        qml = qml.replace("SOURCE_FUNCTIONS", "\n".join(functions))
        qml = qml.replace("SOURCE_PROPERTIES",
                          "\n".join([serial] + timeouts).replace("readonly property int",
                                                                 "property real"))
        fixture = cls.directory / "tst_diagnostic_timeout.qml"
        fixture.write_text(qml)
        # A PATH with a shell but no GNU timeout, for the graceful-degradation
        # run: the bounded line must fall back to the raw command instead of
        # failing with "sh: command not found" or 127 from `timeout`.
        cls.no_timeout_bin = cls.directory / "no-timeout-bin"
        cls.no_timeout_bin.mkdir(exist_ok=True)
        shim = cls.no_timeout_bin / "sh"
        if not shim.exists():
            shim.symlink_to(Path(cls.shell).resolve())
        result = subprocess.run(
            [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
            env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
            capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        if result.returncode:
            raise AssertionError(output)
        capture = next(line.split("DIAGNOSTIC_FIXTURE:", 1)[1] for line in output.splitlines()
                       if "DIAGNOSTIC_FIXTURE:" in line)
        cls.fixture = json.loads(capture)
        messages = next(line.split("DIAGNOSTIC_MESSAGES:", 1)[1] for line in output.splitlines()
                        if "DIAGNOSTIC_MESSAGES:" in line)
        cls.messages = json.loads(messages)

    def test_production_shell_bound_sits_inside_qml_timer(self):
        production = self.fixture["production"]
        shell_bound_ms = (production["timeoutSeconds"] + production["killAfterSeconds"]) * 1000
        self.assertLess(shell_bound_ms, production["timeoutMs"])

    def test_both_commands_carry_nonce_redact_and_shell_bound(self):
        self.assertEqual(len(self.fixture["commands"]), 2)
        diagnose = next(command for command in self.fixture["commands"]
                        if "diagnose --provider" in command)
        self.assertIn("--redact", diagnose)
        for command in self.fixture["commands"]:
            self.assertTrue(command.startswith("CODEXBAR_PLASMA_RUN="))
            self.assertIn("timeout --kill-after=", command)

    def test_hung_child_is_killed_on_schedule(self):
        for command in self.fixture["commands"]:
            with self.subTest(command=command[:60]):
                self.run_bounded(command, hang=True)

    def test_commands_still_run_without_gnu_timeout(self):
        for command in self.fixture["commands"]:
            with self.subTest(command=command[:60]):
                self.run_bounded(command, hang=False)

    def test_shell_bound_reap_surfaces_timeout_message(self):
        command = next(command for command in self.fixture["commands"]
                       if "diagnose --provider" in command)
        returncode, _, stderr, _ = self.run_shell_capture(command, hang=True)
        # The live reap is silent (GNU timeout prints nothing when it kills),
        # so no CLI stderr outranks the message. A TERM-reaped child reports
        # 124; a child ignoring SIGTERM survives to the kill-after SIGKILL and
        # reports 137 -- both are the shell bound firing, and both must read
        # as a timeout rather than "exited with code ...".
        self.assertIn(returncode, (124, 137), stderr)
        self.assertEqual(stderr, "")
        self.assertEqual(self.messages["shellTimeoutSilent"],
                         "Diagnostic command timed out. Try again.")
        self.assertEqual(self.messages["shellKillAfterSilent"],
                         "Diagnostic command timed out. Try again.")

    def test_ordinary_nonzero_exit_reports_cli_error(self):
        self.assertEqual(self.messages["cliErrorWithMessage"], "cli broke")
        self.assertEqual(self.messages["cliErrorSilent"], "codexbar exited with code 3")
        # stderr precedence holds for 124 as well: a CLI that really says
        # something keeps its own message even at the timeout status.
        self.assertEqual(self.messages["cli124WithMessage"], "weird code")

    def run_shell_capture(self, command, hang):
        (self.directory / "codexbar.pid").unlink(missing_ok=True)
        path = str(self.directory) + os.pathsep + os.environ["PATH"] if hang else str(self.no_timeout_bin)
        process = subprocess.Popen(
            [self.shell, "-c", command], start_new_session=True,
            env={**os.environ, "PATH": path,
                 "DIAG_DIRECTORY": str(self.directory),
                 "DIAG_MODE": "hang" if hang else "quick"},
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            started = time.monotonic()
            stdout, stderr = process.communicate(timeout=10)
            elapsed = time.monotonic() - started
            return process.returncode, stdout, stderr, elapsed
        finally:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.communicate()
            self.kill_leftover_child()

    def run_bounded(self, command, hang):
        returncode, stdout, stderr, elapsed = self.run_shell_capture(command, hang)
        if hang:
            # The fake CLI ignores SIGTERM, so only the kill-after KILL
            # can have reaped it: survival past the shrunken bound would
            # block here until the communicate timeout instead.
            self.assertIn(returncode, (124, 137), stderr)
            self.assertLess(elapsed, 10)
            self.assertFalse(self.child_survives())
        else:
            self.assertEqual(returncode, 0, stderr)
            self.assertEqual(json.loads(stdout), {"ok": True})

    def child_survives(self):
        marker = self.directory / "codexbar.pid"
        if not marker.exists():
            return False
        try:
            state = (Path("/proc") / marker.read_text().strip() / "stat").read_text()
            return state.rsplit(")", 1)[1].split()[0] != "Z"
        except FileNotFoundError:
            return False

    def kill_leftover_child(self):
        marker = self.directory / "codexbar.pid"
        if marker.exists():
            try:
                os.kill(int(marker.read_text().strip()), signal.SIGKILL)
            except (ProcessLookupError, ValueError):
                pass


if __name__ == "__main__":
    unittest.main()
