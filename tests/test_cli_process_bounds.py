"""Hung CLI processes and their descendants exit after a timeout or retirement.

Plasma5Support's executable engine keeps a process running after
disconnectSource(), so every CLI owner must bound its command in the shell.
The synthetic CLI ignores SIGTERM and spawns a child, so only a process-group
bound with a kill-after escalation ends both.
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

UI_DEADLINE_MS = 100
# Shell bound (deadline + 2 s) plus the 1 s kill-after grace, with slack.
EXIT_WITHIN_SECONDS = 6.0

# Each line is "pid starttime"; the start time guards cleanup against PID reuse.
CLI = '''#!/bin/sh
trap '' TERM
record() { echo "$1 $(cut -d' ' -f22 "/proc/$1/stat")" >> "$0.pids"; }
record $$
sleep 30 &
record $!
wait
'''

QML = '''import QtQuick
import QtTest
TestCase {
    id: testCase
    name: "CliProcessBounds"
    function i18n(text, first) { return text.replace("%1", first === undefined ? "%1" : first); }
    function init() {
        var factory = Qt.createComponent("UI_URL/controllers/UsageController.qml");
        if (factory.status === Component.Error && /module "org\\.kde\\.[^"]+" is not installed/.test(factory.errorString()))
            skip("CLI owners need the optional KDE QML modules");
    }
    function create(file, properties) {
        var factory = Qt.createComponent("UI_URL/controllers/" + file);
        compare(factory.status, Component.Ready, factory.errorString());
        var subject = createTemporaryObject(factory, testCase, properties || {});
        verify(subject !== null);
        return subject;
    }
    function cli(name) { return "FIXTURE_PATH/" + name; }
    function quoted(name) { return "'" + cli(name).replace(/'/g, "'\\\\''") + "'"; }

    function test_hungCommandsAreBoundedAfterTimeoutAndRetirement() {
        var usageTimeout = create("UsageController.qml", {commandPath: cli("usage-timeout"), sourceMode: "cli", refreshIntervalSec: 0});
        var failures = 0;
        usageTimeout.failed.connect(function() { failures++; });
        var usageReset = create("UsageController.qml", {commandPath: cli("usage-reset"), sourceMode: "cli", refreshIntervalSec: 0});
        var usageDestroyed = create("UsageController.qml", {commandPath: cli("usage-destroyed"), sourceMode: "cli", refreshIntervalSec: 0});
        tryVerify(function() { return usageReset.loading && usageDestroyed.loading; });
        usageReset.reset();
        usageDestroyed.destroy();

        var processTimeout = create("CliProcess.qml");
        var timeouts = 0;
        processTimeout.timedOut.connect(function() { timeouts++; });
        verify(processTimeout.start(quoted("process-timeout"), "timeout", DEADLINE));
        var processCancel = create("CliProcess.qml");
        verify(processCancel.start(quoted("process-cancel"), "cancel", DEADLINE));
        processCancel.cancel();
        var processDestroyed = create("CliProcess.qml");
        verify(processDestroyed.start(quoted("process-destroyed"), "destroyed", DEADLINE));
        processDestroyed.destroy();

        var accountsTimeout = create("AccountsController.qml", {commandPath: cli("accounts-timeout")});
        verify(accountsTimeout.load("codex"));
        var accountsReset = create("AccountsController.qml", {commandPath: cli("accounts-reset")});
        verify(accountsReset.load("codex"));
        accountsReset.reset();
        var accountsDestroyed = create("AccountsController.qml", {commandPath: cli("accounts-destroyed")});
        verify(accountsDestroyed.load("codex"));
        accountsDestroyed.destroy();

        var rosterTimeout = create("ProviderRosterController.qml", {commandPath: cli("roster-timeout")});
        var rosterInactive = create("ProviderRosterController.qml", {commandPath: cli("roster-inactive")});
        var rosterDestroyed = create("ProviderRosterController.qml", {commandPath: cli("roster-destroyed")});
        tryVerify(function() { return rosterInactive.providerRosterLoading && rosterDestroyed.providerRosterLoading; });
        rosterInactive.active = false;
        rosterDestroyed.destroy();

        tryVerify(function() { return failures === 1 && !usageTimeout.loading && timeouts === 1
            && accountsTimeout.errorForProvider("codex").length > 0
            && rosterTimeout.providerRosterError.length > 0 && !rosterTimeout.providerRosterLoading; }, 3000);
        // Keep the runner alive past the hard bound; the harness watches /proc.
        wait(HOLD_MS);
    }
}
'''

OWNERS = {
    "UsageController.qml": (r"defaultCommandTimeoutMs", r"lifecycle\.hasPendingCommandTimeouts\(\)"),
    "CliProcess.qml": (None, r"process\.busy"),
    "AccountsController.qml": (r"accountCommandTimeoutMs", r"CommandLedger\.hasDeadlines\(lifecycle\.commands\)"),
    "ProviderRosterController.qml": (r"providerRosterCommandTimeoutMs", r"controller\.hasPendingProviderRosterCommands\(\)"),
}
SCRIPTS = [owner + "-" + path for owner, paths in {
    "usage": ("timeout", "reset", "destroyed"), "process": ("timeout", "cancel", "destroyed"),
    "accounts": ("timeout", "reset", "destroyed"), "roster": ("timeout", "inactive", "destroyed")}.items()
    for path in paths]


def shrink(text, deadline, sweeper):
    """Shorten only the UI deadline and the sweeper interval of one owner."""
    if deadline:
        text, count = re.subn(r"(readonly\s+property\s+int\s+" + deadline + r"\s*:\s*)\d+",
                              r"\g<1>" + str(UI_DEADLINE_MS), text)
        assert count == 1, deadline
    anchor = re.search(r"running\s*:\s*" + sweeper, text)
    assert anchor, sweeper
    intervals = list(re.finditer(r"interval\s*:\s*\d+", text[:anchor.start()]))
    assert intervals and "Timer" not in text[intervals[-1].end():anchor.start()], sweeper
    start, end = intervals[-1].span()
    return text[:start] + "interval: 50" + text[end:]


def start_time(pid):
    """Return the /proc start time of a live, non-zombie process, else None."""
    try:
        stat = Path(f"/proc/{pid}/stat").read_text()
    except OSError:
        return None
    fields = stat[stat.rindex(")") + 2:].split()
    return None if fields[0] in ("Z", "X") else fields[19]


class CliProcessBoundTests(unittest.TestCase):
    def test_provider_settings_dispatcher_bounds_hung_descendants(self):
        page = ROOT / "contents/ui/configProviders.qml"
        surface = Surface("providers", ROOT)
        surface.texts = {page: page.read_text()}
        functions = []
        for name in ("runCommand", "copyObject"):
            signature = re.search(r"function " + name + r"\([^)]*\)", page.read_text()).group(0)
            functions.append(signature + " {" + surface.function_body(name) + "}")
        with tempfile.TemporaryDirectory(prefix="codexbar provider bounds 'test-") as temporary:
            directory = Path(temporary)
            cli = directory / "codexbar"
            cli.write_text(CLI)
            cli.chmod(0o700)
            fixture = directory / "tst_provider_bounds.qml"
            fixture.write_text('''import QtQuick
import QtTest
import "SOURCE_URL/Guards.js" as Guards
import "SOURCE_URL/CommandLedger.js" as CommandLedger
TestCase {
    name: "ProviderSettingsBounds"
    property string commandPath: CLI_PATH
    property int commandRunSerial: 0
    property int configCommandTimeoutMs: 100
    property var commands: ({})
    property var configSource: ({connectSource: function(source) {
        console.log("PROVIDER_COMMAND:" + JSON.stringify(source))
    }})
    SOURCE_FUNCTIONS
    function test_dispatch() {
        runCommand(Guards.shellQuote(commandPath), {kind: "toggle", provider: "codex", timeoutMs: 100})
        compare(Object.keys(commands).length, 1)
    }
}
'''.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
                .replace("CLI_PATH", json.dumps(str(cli)))
                .replace("SOURCE_FUNCTIONS", "\n".join(functions)))
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            command = json.loads(next(line.split("PROVIDER_COMMAND:", 1)[1]
                                      for line in result.stdout.splitlines() if "PROVIDER_COMMAND:" in line))
            for destroy_engine_shell in (False, True):
                with self.subTest(destroy_engine_shell=destroy_engine_shell):
                    marker = directory / "codexbar.pids"
                    marker.unlink(missing_ok=True)
                    process = subprocess.Popen(["sh", "-c", command], start_new_session=True,
                                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    seen = []
                    try:
                        deadline = time.monotonic() + EXIT_WITHIN_SECONDS
                        while time.monotonic() < deadline:
                            lines = marker.read_text().splitlines() if marker.exists() else []
                            seen = [(int(pid), started) for pid, started in
                                    (line.split() for line in lines)]
                            if len(seen) == 2:
                                break
                            time.sleep(0.02)
                        self.assertEqual(len(seen), 2, "provider command did not start both processes")
                        if destroy_engine_shell:
                            process.kill()
                        while time.monotonic() < deadline and any(start_time(pid) == started for pid, started in seen):
                            time.sleep(0.02)
                        self.assertFalse(any(start_time(pid) == started for pid, started in seen),
                                         "provider CLI or descendant outlived the hard bound")
                    finally:
                        # GNU timeout creates a separate process group; clean
                        # each recorded survivor as well as the engine shell.
                        for pid, started in seen:
                            if start_time(pid) == started:
                                try:
                                    os.kill(pid, signal.SIGKILL)
                                except ProcessLookupError:
                                    pass
                        try:
                            os.killpg(process.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        process.wait(timeout=5)

    def test_hung_cli_and_descendants_exit_after_timeout_or_retirement(self):
        with tempfile.TemporaryDirectory(prefix="codexbar bounds 'test-") as temporary:
            directory = Path(temporary)
            for name in SCRIPTS:
                (directory / name).write_text(CLI)
                (directory / name).chmod(0o700)
            ui = directory / "ui"
            shutil.copytree(ROOT / "contents/ui", ui)
            for owner, (deadline, sweeper) in OWNERS.items():
                path = ui / "controllers" / owner
                path.write_text(shrink(path.read_text(), deadline, sweeper))
            fixture = directory / "tst_bounds.qml"
            fixture.write_text(QML.replace("UI_URL", ui.as_uri()).replace("FIXTURE_PATH", str(directory))
                               .replace("DEADLINE", str(UI_DEADLINE_MS))
                               .replace("HOLD_MS", str(int(EXIT_WITHIN_SECONDS * 1000) + 1500)))
            seen, exited = {}, {}
            runner = subprocess.Popen(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            try:
                deadline = time.monotonic() + 120
                while runner.poll() is None and time.monotonic() < deadline:
                    now = time.monotonic()
                    for name in SCRIPTS:
                        pids = directory / (name + ".pids")
                        lines = pids.read_text().splitlines() if pids.exists() else []
                        for line in lines:
                            pid, started = line.split()
                            seen.setdefault((name, int(pid), started), now)
                    for key in seen:
                        if key not in exited and start_time(key[1]) != key[2]:
                            exited[key] = now
                    time.sleep(0.05)
                if runner.poll() is None:
                    runner.kill()
                output = runner.communicate()[0]
            finally:
                survivors = [key for key in seen if start_time(key[1]) == key[2]]
                for name, pid, started in survivors:
                    try:
                        os.kill(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                until = time.monotonic() + 5
                while time.monotonic() < until and any(start_time(key[1]) == key[2] for key in survivors):
                    time.sleep(0.05)
            self.assertEqual(runner.returncode, 0, output)
            if os.environ.get("QML_TEST_REQUIRE_NO_SKIPS") == "1" and "SKIP" in output:
                self.fail("QML tests were skipped; the test environment must provide the KDE QML modules.")
            if "SKIP" in output:
                self.skipTest("CLI owners need the optional KDE QML modules")
            # Every owner spawned its CLI and the CLI's child.
            self.assertEqual(sorted({key[0] for key in seen}), sorted(SCRIPTS), output)
            self.assertEqual(len(seen), 2 * len(SCRIPTS), output)
            late = sorted(f"{name} pid {pid}" for (name, pid, started), at in seen.items()
                          if (name, pid, started) not in exited
                          or exited[(name, pid, started)] - at > EXIT_WITHIN_SECONDS)
            self.assertEqual(late, [], "processes outlived the hard bound")


if __name__ == "__main__":
    unittest.main()
