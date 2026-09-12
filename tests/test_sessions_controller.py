"""Exercise the Sessions controller with real timers and isolated CLI processes."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

QML = '''import QtQuick
import QtTest
TestCase {
    id: testCase
    name: "SessionsController"

    function i18n(text, first) {
        return text.replace("%1", first === undefined ? "%1" : first);
    }
    function init() {
        var probe = Qt.createComponent("CONTROLLER_URL");
        if (probe.status === Component.Error && /module "org\\.kde\\.[^"]+" is not installed/.test(probe.errorString())) {
            skip("SessionsController needs the optional KDE QML modules");
        }
    }
    function create(script, options) {
        var factory = Qt.createComponent("CONTROLLER_URL");
        compare(factory.status, Component.Ready, factory.errorString());
        var subject = createTemporaryObject(factory, testCase, Object.assign({
            commandPath: "FIXTURE_PATH/" + script, active: false, refreshIntervalSec: 300
        }, options || {}));
        verify(subject !== null);
        return subject;
    }
    function completed(subject, name) {
        tryVerify(function() {
            return !subject.loading && subject.sessions.length === 1
                && subject.sessions[0].projectName === name;
        }, 8000);
        verify(subject.lastUpdatedAtMs > 0);
        compare(subject.errorText, "");
    }
    function test_hiddenViewStaysIdleAndManualRefreshRejectsDuplicates() {
        var subject = create("normal");
        wait(100);
        verify(!subject.loading);
        compare(subject.lastUpdatedAtMs, -1);
        verify(subject.refresh());
        verify(subject.loading);
        verify(!subject.refresh());
        completed(subject, "normal 1");
        verify(subject.refresh());
        completed(subject, "normal 2");
    }
    function test_visibleTimerRefreshesAndStopsWhenHidden() {
        var subject = create("normal", {active: true, refreshIntervalSec: 1});
        completed(subject, "normal 1");
        completed(subject, "normal 2");
        subject.active = false;
        var updatedAt = subject.lastUpdatedAtMs;
        wait(1300);
        compare(subject.lastUpdatedAtMs, updatedAt);
        subject.active = true;
        completed(subject, "normal 3");
        subject.active = false;
    }
    function test_intervalChangesRescheduleFromTheLastCompletion() {
        var subject = create("normal", {active: true, refreshIntervalSec: 300});
        completed(subject, "normal 1");
        subject.refreshIntervalSec = 1;
        completed(subject, "normal 2");
        subject.refreshIntervalSec = 300;
        wait(1300);
        compare(subject.sessions[0].projectName, "normal 2");
        subject.active = false;
    }
    function test_queuedEntryRechecksVisibility() {
        var subject = create("normal");
        subject.active = true;
        subject.active = false;
        wait(100);
        verify(!subject.loading);
        compare(subject.lastUpdatedAtMs, -1);
    }
    function test_hidingDoesNotDiscardAnAlreadyRunningScan() {
        var subject = create("normal", {active: true});
        tryCompare(subject, "loading", true);
        subject.active = false;
        completed(subject, "normal 1");
    }
    function test_missingCommandIsReportedOnlyWhenRequested() {
        var subject = create("normal", {commandPath: ""});
        wait(100);
        compare(subject.errorText, "");
        subject.active = true;
        tryVerify(function() { return subject.errorText.length > 0; });
        verify(!subject.loading);
        verify(!subject.refresh());
    }
    function test_failedRefreshPreservesTheSnapshotAndTimestamp_data() {
        return [{tag: "stderr", script: "failure"}, {tag: "invalid-json", script: "malformed"},
                {tag: "unsupported", script: "unsupported"}, {tag: "empty-stdout", script: "missing"}];
    }
    function test_failedRefreshPreservesTheSnapshotAndTimestamp(data) {
        var subject = create(data.script);
        verify(subject.refresh());
        completed(subject, data.script + " 1");
        var updatedAt = subject.lastUpdatedAtMs;
        verify(subject.refresh());
        tryCompare(subject, "loading", false);
        verify(subject.errorText.length > 0);
        compare(subject.sessions[0].projectName, data.script + " 1");
        compare(subject.lastUpdatedAtMs, updatedAt);
        subject.active = true;
        wait(150);
        verify(!subject.loading);
        subject.active = false;
    }
    function test_confirmedEmptyResultReplacesTheSnapshot() {
        var subject = create("empty");
        verify(subject.refresh());
        completed(subject, "empty 1");
        var updatedAt = subject.lastUpdatedAtMs;
        verify(subject.refresh());
        tryCompare(subject, "loading", false);
        compare(subject.sessions.length, 0);
        compare(subject.errorText, "");
        verify(subject.lastUpdatedAtMs > updatedAt);
    }
    function test_longFailureCooldownStartsAtCompletionAndManualRetryBypassesIt() {
        var subject = create("slow-failure", {active: true, refreshIntervalSec: 1});
        tryCompare(subject, "loading", true);
        tryCompare(subject, "loading", false, 5000);
        compare(subject.lastUpdatedAtMs, -1);
        verify(subject.errorText.length > 0);
        subject.active = false;
        subject.active = true;
        wait(200);
        verify(!subject.loading);
        verify(subject.refresh());
        verify(!subject.refresh());
        completed(subject, "slow-failure 2");
        subject.active = false;
    }
    function test_failedScanRetriesAutomaticallyAfterTheCooldown() {
        var subject = create("retry", {active: true, refreshIntervalSec: 1});
        tryCompare(subject, "loading", true);
        tryCompare(subject, "loading", false);
        verify(subject.errorText.length > 0);
        compare(subject.lastUpdatedAtMs, -1);
        completed(subject, "retry 2");
        subject.active = false;
    }
    function test_commandChangeInvalidatesDataAndRetiresTheRunningSource() {
        var subject = create("normal", {active: true});
        completed(subject, "normal 1");
        subject.commandPath = "FIXTURE_PATH/slow";
        compare(subject.sessions.length, 0);
        compare(subject.lastUpdatedAtMs, -1);
        tryCompare(subject, "loading", true);
        subject.commandPath = "FIXTURE_PATH/retry";
        compare(subject.sessions.length, 0);
        compare(subject.errorText, "");
        completed(subject, "retry 3");
        wait(1200);
        compare(subject.sessions[0].projectName, "retry 3");
        subject.active = false;
        subject.commandPath = "FIXTURE_PATH/normal";
        compare(subject.sessions.length, 0);
        compare(subject.lastUpdatedAtMs, -1);
        wait(100);
        verify(!subject.loading);
    }
    function test_commandChangeClearsAFailedScanCooldown() {
        var subject = create("retry", {active: true});
        tryCompare(subject, "loading", true);
        tryCompare(subject, "loading", false);
        verify(subject.errorText.length > 0);
        subject.commandPath = "FIXTURE_PATH/normal";
        completed(subject, "normal 2");
        subject.active = false;
    }
    function test_failedNewCommandCannotRestoreThePreviousSnapshot() {
        var subject = create("normal");
        verify(subject.refresh());
        completed(subject, "normal 1");
        subject.commandPath = "FIXTURE_PATH/failure";
        compare(subject.sessions.length, 0);
        compare(subject.lastUpdatedAtMs, -1);
        verify(subject.refresh());
        tryCompare(subject, "loading", false);
        verify(subject.errorText.length > 0);
        compare(subject.sessions.length, 0);
        compare(subject.lastUpdatedAtMs, -1);
    }
    function test_timeoutPreservesTheSnapshotAndAllowsANewRequest() {
        var subject = create("late");
        verify(subject.refresh());
        completed(subject, "late 1");
        var updatedAt = subject.lastUpdatedAtMs;
        verify(subject.refresh());
        // Exercise the production 60-second deadline with the real DataSource.
        tryCompare(subject, "loading", false, 65000);
        verify(subject.errorText.indexOf("timed out") >= 0);
        compare(subject.sessions[0].projectName, "late 1");
        compare(subject.lastUpdatedAtMs, updatedAt);
        subject.active = true;
        wait(150);
        verify(!subject.loading);
        subject.active = false;
        verify(subject.refresh());
        completed(subject, "late 3");
        wait(300);
        compare(subject.sessions[0].projectName, "late 3");
    }
}
'''

CLI = '''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
import time

if sys.argv[1:] != ["sessions", "--json-v2"]:
    print("unexpected CLI arguments", file=sys.stderr)
    sys.exit(1)
name = Path(sys.argv[0]).name
run = int(os.environ["CODEXBAR_PLASMA_RUN"])
time.sleep(0.2)
if name == "slow":
    time.sleep(1)
if name == "late" and run == 2:
    time.sleep(62)
if name == "late" and run == 3:
    time.sleep(3)
if name in ("retry", "slow-failure") and run == 1:
    if name == "slow-failure":
        time.sleep(1.3)
    print("synthetic scan failure", file=sys.stderr)
    sys.exit(1)
if run > 1:
    if name == "failure":
        print("synthetic scan failure", file=sys.stderr)
        sys.exit(1)
    if name == "malformed":
        print("{")
        sys.exit(0)
    if name == "unsupported":
        print("{}")
        sys.exit(0)
    if name == "missing":
        sys.exit(0)
    if name == "empty":
        print("[]")
        sys.exit(0)
print(json.dumps([{"provider": "codex", "projectName": name + " " + str(run),
                  "state": "active", "source": "cli"}]))
'''


class SessionsControllerTests(unittest.TestCase):
    def test_production_lifecycle_with_synthetic_cli(self):
        with tempfile.TemporaryDirectory(prefix="codexbar sessions 'test-") as temporary:
            directory = Path(temporary)
            for name in ("normal", "slow", "late", "retry", "slow-failure", "failure",
                         "malformed", "unsupported", "missing", "empty"):
                script = directory / name
                script.write_text(CLI)
                script.chmod(0o700)
            qml = QML.replace("CONTROLLER_URL", (ROOT / "contents/ui/controllers/SessionsController.qml").as_uri())
            qml = qml.replace("FIXTURE_PATH", str(directory))
            fixture = directory / "tst_sessions.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=115)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            if os.environ.get("QML_TEST_REQUIRE_NO_SKIPS") == "1" and "SKIP" in output:
                self.fail("QML tests were skipped; the test environment must provide the KDE QML modules.")
            if "SKIP" in output:
                self.skipTest("SessionsController needs the optional KDE QML modules")
            # Disconnecting a running Plasma source destroys its QProcess.
            warnings = [line for line in output.splitlines() if "QWARN" in line and not (
                'QProcess: Destroyed while process ("/bin/sh") is still running.' in line
                and any(case in line for case in (
                    "test_commandChangeInvalidatesDataAndRetiresTheRunningSource()",
                    "test_timeoutPreservesTheSnapshotAndAllowsANewRequest()")))]
            self.assertEqual(warnings, [])


if __name__ == "__main__":
    unittest.main()
