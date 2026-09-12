"""Exercise the production cost controller with real timers and isolated CLI processes."""

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
    name: "CostController"

    function i18n(text, first) {
        return text.replace("%1", first === undefined ? "%1" : first);
    }
    function init() {
        var probe = Qt.createComponent("CONTROLLER_URL");
        if (probe.status === Component.Error && /module "org\\.kde\\.[^"]+" is not installed/.test(probe.errorString()))
            skip("CostController needs the optional KDE QML modules");
    }
    function create(script, options) {
        var factory = Qt.createComponent("CONTROLLER_URL");
        compare(factory.status, Component.Ready, factory.errorString());
        var subject = createTemporaryObject(factory, testCase, Object.assign({
            commandPath: "FIXTURE_PATH/" + script, active: false
        }, options || {}));
        verify(subject !== null);
        return subject;
    }
    function completed(subject, label, days) {
        tryVerify(function() {
            return !subject.loading && subject.costs.codex
                && subject.costs.codex.historyLabel === label;
        }, 8000);
        compare(subject.costs.codex.historyDays, days === undefined ? 30 : days);
    }
    function test_startupRunsWhileHiddenAndReentryKeepsFreshData() {
        var subject = create("normal");
        completed(subject, "normal 1");
        subject.active = true;
        wait(100);
        verify(!subject.loading);
        verify(!subject.refresh(false));
        completed(subject, "normal 1");
        compare(subject.errorText, "");
    }
    function test_disabledOrMissingCommandDoesNotStart_data() {
        return [{tag: "disabled", options: {costUsageEnabled: false}},
                {tag: "missing", options: {commandPath: ""}}];
    }
    function test_disabledOrMissingCommandDoesNotStart(data) {
        var subject = create("normal", data.options);
        wait(100);
        compare(subject.costs, {});
        verify(!subject.loading);
        verify(!subject.refresh(true));
        compare(subject.errorText, "");
    }
    function test_sourceBatchUsesOnlyTheFinalSettings() {
        var subject = create("normal");
        completed(subject, "normal 1");
        subject.historyDays = 7;
        subject.commandPath = "FIXTURE_PATH/batched";
        subject.provider = "example'; quoted provider";
        subject.costUsageEnabled = false;
        subject.historyDays = 90;
        subject.costUsageEnabled = true;
        compare(subject.costs, {});
        completed(subject, "batched 2", 90);
        wait(300);
        completed(subject, "batched 2", 90);
        compare(subject.errorText, "");
    }
    function test_rangeRoundTripReattachesBeforeOneQueuedScan() {
        var subject = create("normal");
        completed(subject, "normal 1");
        var stored = subject.costs;
        subject.historyDays = 7;
        compare(subject.costs, {});
        subject.historyDays = 30;
        compare(subject.costs, stored);
        completed(subject, "normal 2");
    }
    function test_failedNewContextCannotExposeOldDataButReturningCan() {
        var subject = create("normal");
        completed(subject, "normal 1");
        var stored = subject.costs;
        subject.commandPath = "FIXTURE_PATH/failure";
        compare(subject.costs, {});
        tryVerify(function() { return !subject.loading && subject.errorText.length > 0; });
        compare(subject.costs, {});
        subject.commandPath = "FIXTURE_PATH/normal";
        compare(subject.costs, stored);
        completed(subject, "normal 3");
    }
    function test_partialFailuresRetainOnlySameContextProviders() {
        var subject = create("partial");
        completed(subject, "partial 1");
        var old = subject.costs.claude;
        verify(subject.refresh(true));
        completed(subject, "partial 2");
        compare(subject.costs.claude, old);
        compare(subject.costs.gemini, undefined);
        compare(subject.errorText, "Some cost data could not be refreshed.");
        subject.provider = "codex";
        compare(subject.costs, {});
        completed(subject, "partial 3");
        compare(subject.costs.claude, undefined);
        verify(subject.errorText.length > 0);
    }
    function test_transientFailuresRetainDataAndThrottleAutomaticRetries_data() {
        return [{tag: "stderr", script: "failure"}, {tag: "malformed", script: "malformed"},
                {tag: "unsupported", script: "unsupported"}, {tag: "empty", script: "missing"}];
    }
    function test_transientFailuresRetainDataAndThrottleAutomaticRetries(data) {
        var subject = create(data.script);
        completed(subject, data.script + " 1");
        var old = subject.costs;
        verify(subject.refresh(true));
        tryCompare(subject, "loading", false);
        verify(subject.errorText.length > 0);
        compare(subject.costs, old);
        verify(!subject.refresh(false));
        subject.active = true;
        wait(100);
        verify(!subject.loading);
        compare(subject.costs, old);
    }
    function test_confirmedEmptyResultReplacesData() {
        var subject = create("empty");
        completed(subject, "empty 1");
        verify(subject.refresh(true));
        tryCompare(subject, "loading", false);
        compare(subject.costs, {});
        compare(subject.errorText, "");
    }
    function test_manualRefreshSupersedesAnActiveScan() {
        var subject = create("slow");
        tryCompare(subject, "loading", true);
        wait(100);
        verify(subject.refresh(true));
        completed(subject, "slow 2");
        wait(1200);
        completed(subject, "slow 2");
    }
    function test_commandChangeRetiresTheOldSourceSynchronously() {
        var subject = create("normal");
        completed(subject, "normal 1");
        subject.commandPath = "FIXTURE_PATH/slow";
        tryCompare(subject, "loading", true);
        wait(100);
        subject.commandPath = "FIXTURE_PATH/normal";
        verify(!subject.loading);
        completed(subject, "normal 1");
        completed(subject, "normal 3");
        wait(1200);
        completed(subject, "normal 3");
    }
    function test_disablingClearsAndRetiresData() {
        var subject = create("normal");
        completed(subject, "normal 1");
        subject.commandPath = "FIXTURE_PATH/slow";
        tryCompare(subject, "loading", true);
        subject.costUsageEnabled = false;
        verify(!subject.loading);
        compare(subject.costs, {});
        wait(1300);
        compare(subject.costs, {});
        compare(subject.errorText, "");
        subject.costUsageEnabled = true;
        completed(subject, "slow 3");
    }
    function test_timeoutPreservesDataAndManualRetryRecovers() {
        var subject = create("late");
        completed(subject, "late 1");
        var old = subject.costs;
        verify(subject.refresh(true));
        // Keep the real 120-second deadline and DataSource in this test.
        tryCompare(subject, "loading", false, 125000);
        verify(subject.errorText.indexOf("timed out") >= 0);
        compare(subject.costs, old);
        verify(!subject.refresh(false));
        verify(subject.refresh(true));
        completed(subject, "late 3");
        wait(300);
        completed(subject, "late 3");
        compare(subject.errorText, "");
    }
}
'''

CLI = '''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
import time

args = sys.argv[1:]
name = Path(sys.argv[0]).name
expected_provider = ["--provider", "example'; quoted provider"] if name == "batched" else ["--provider", "codex"]
if args[:5] != ["cost", "--format", "json", "--json-only", "--days"] or args[5] not in ("7", "30", "90") or args[6:] not in ([], expected_provider):
    print("unexpected CLI arguments", file=sys.stderr)
    sys.exit(1)
run = int(os.environ["CODEXBAR_PLASMA_RUN"])
time.sleep(0.2)
if name == "slow":
    time.sleep(1)
if name == "late" and run == 2:
    time.sleep(122)
if name == "late" and run == 3:
    time.sleep(3)
if run > 1:
    if name == "failure":
        print("synthetic cost failure", file=sys.stderr)
        sys.exit(1)
    if name in ("malformed", "unsupported", "empty"):
        print({"malformed": "{", "unsupported": "null", "empty": "[]"}[name])
        sys.exit(0)
    if name == "missing":
        sys.exit(0)
result = [{"provider": "codex", "historyLabel": name + " " + str(run),
           "totals": {"totalCost": run}}]
if name == "partial":
    result.append({"provider": "claude", **({"totals": {"totalCost": 9}} if run == 1 else {"error": {"message": {"toString": None}}})})
    if run == 1:
        result.append({"provider": "gemini", "totals": {"totalCost": 8}})
print(json.dumps(result))
'''


class CostContextTests(unittest.TestCase):
    def test_production_lifecycle_with_synthetic_cli(self):
        with tempfile.TemporaryDirectory(prefix="codexbar cost 'test-") as temporary:
            directory = Path(temporary)
            for name in ("normal", "batched", "partial", "slow", "late", "failure",
                         "malformed", "unsupported", "missing", "empty"):
                script = directory / name
                script.write_text(CLI)
                script.chmod(0o700)
            fixture = directory / "tst_cost.qml"
            fixture.write_text(QML.replace("CONTROLLER_URL", (ROOT / "contents/ui/controllers/CostController.qml").as_uri())
                               .replace("FIXTURE_PATH", str(directory)))
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=185)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            if os.environ.get("QML_TEST_REQUIRE_NO_SKIPS") == "1" and "SKIP" in output:
                self.fail("QML tests were skipped; the test environment must provide the KDE QML modules.")
            if "SKIP" in output:
                self.skipTest("CostController needs the optional KDE QML modules")
            warnings = [line for line in output.splitlines() if "QWARN" in line and not (
                'QProcess: Destroyed while process ("/bin/sh") is still running.' in line
                and any(case in line for case in (
                    "test_manualRefreshSupersedesAnActiveScan()",
                    "test_commandChangeRetiresTheOldSourceSynchronously()",
                    "test_disablingClearsAndRetiresData()",
                    "test_timeoutPreservesDataAndManualRetryRecovers()")))]
            self.assertEqual(warnings, [])


if __name__ == "__main__":
    unittest.main()
