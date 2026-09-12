"""Exercise account discovery through production QML and real isolated CLI processes."""
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
    name: "AccountsController"
    function i18n(text, first) { return text.replace("%1", first === undefined ? "%1" : first); }
    function init() {
        var probe = Qt.createComponent("CONTROLLER_URL");
        if (probe.status === Component.Error && /module "org\\.kde\\.[^"]+" is not installed/.test(probe.errorString()))
            skip("AccountsController needs the optional KDE QML modules");
    }
    function create(script, options) {
        var factory = Qt.createComponent("CONTROLLER_URL");
        compare(factory.status, Component.Ready, factory.errorString());
        var subject = createTemporaryObject(factory, testCase, Object.assign({commandPath: "FIXTURE_PATH/" + script}, options || {}));
        verify(subject !== null);
        return subject;
    }
    function completed(subject, provider, label) {
        tryVerify(function() {
            return !subject.loadingForProvider(provider) && subject.options[provider]
                && subject.options[provider][0].accountKey === label;
        }, 8000);
    }
    function test_idleUntilRequestedAndProviderLoadsAreIndependent() {
        var subject = create("normal");
        wait(100);
        compare(subject.options, {});
        verify(subject.load("codex"));
        verify(!subject.load("codex"));
        verify(subject.load("claude"));
        completed(subject, "codex", "normal 1");
        verify(subject.loadingForProvider("claude"));
        completed(subject, "claude", "normal 2");
        compare(subject.options.codex[0].provider, "codex");
        compare(subject.options.claude[0].provider, "claude");
        compare(subject.errorForProvider("codex"), "");
        compare(subject.options.codex[0].rows[0].usedPercent, 0);
    }
    function test_missingCommandAndUnsafeProviderFailWithoutAProcess() {
        var subject = create("normal", {commandPath: ""});
        verify(!subject.load("codex"));
        verify(subject.errorForProvider("codex").length > 0);
        verify(!subject.loadingForProvider("codex"));
        subject.commandPath = "FIXTURE_PATH/normal";
        verify(!subject.load("__proto__"));
        verify(!subject.load(""));
        compare(subject.options, {});
    }
    function test_flagsAndQuotedSourceReachTheCli() {
        var subject = create("flags", {sourceMode: "source'; literal", includeStatus: true});
        verify(subject.load("codex"));
        completed(subject, "codex", "flags 1");
        compare(subject.errorForProvider("codex"), "");
    }
    function test_failuresKeepListsAndReleaseLoading_data() {
        return [{tag: "stderr", script: "failure"}, {tag: "malformed", script: "malformed"},
                {tag: "unsupported", script: "unsupported"}, {tag: "structured", script: "structured"}];
    }
    function test_failuresKeepListsAndReleaseLoading(data) {
        var subject = create(data.script);
        verify(subject.load("codex"));
        completed(subject, "codex", data.script + " 1");
        var old = subject.options.codex;
        verify(subject.load("codex"));
        tryVerify(function() { return !subject.loadingForProvider("codex"); });
        compare(subject.options.codex, old);
        verify(subject.errorForProvider("codex").length > 0);
        verify(subject.load("claude"));
        completed(subject, "claude", data.script + " 3");
        compare(subject.errorForProvider("claude"), "");
        compare(subject.options.codex, old);
    }
    function test_emptySuccessClearsOnlyItsProvider_data() {
        return [{tag: "empty", script: "empty"}, {tag: "missing-token", script: "missing-token"}];
    }
    function test_emptySuccessClearsOnlyItsProvider(data) {
        var subject = create(data.script);
        verify(subject.load("codex"));
        completed(subject, "codex", data.script + " 1");
        verify(subject.load("claude"));
        completed(subject, "claude", data.script + " 2");
        verify(subject.load("codex"));
        tryVerify(function() { return !subject.loadingForProvider("codex"); });
        compare(subject.options.codex, []);
        compare(subject.options.claude[0].accountKey, data.script + " 2");
        compare(subject.errorForProvider("codex"), "");
    }
    function test_changedInputsRetireRequestsBeforeNewLoads_data() {
        return [{tag: "path", field: "commandPath", value: "FIXTURE_PATH/normal"},
                {tag: "source", field: "sourceMode", value: "cli"},
                {tag: "status", field: "includeStatus", value: true}];
    }
    function test_changedInputsRetireRequestsBeforeNewLoads(data) {
        var subject = create("slow");
        verify(subject.load("codex"));
        wait(100);
        subject[data.field] = data.value;
        verify(!subject.loadingForProvider("codex"));
        verify(subject.load("codex"));
        var script = data.field === "commandPath" ? "normal" : "slow";
        completed(subject, "codex", script + " 2");
        wait(1200);
        compare(subject.options.codex[0].accountKey, script + " 2");
    }
    function test_resetRetiresEveryProviderAndClearsLists() {
        var subject = create("normal");
        verify(subject.load("codex"));
        completed(subject, "codex", "normal 1");
        subject.commandPath = "FIXTURE_PATH/slow";
        verify(subject.load("codex"));
        verify(subject.load("claude"));
        subject.reset();
        verify(!subject.loadingForProvider("codex"));
        verify(!subject.loadingForProvider("claude"));
        compare(subject.options, {});
        compare(subject.errorForProvider("codex"), "");
        wait(1500);
        compare(subject.options, {});
        verify(subject.load("codex"));
        completed(subject, "codex", "slow 4");
    }
    function test_unrelatedLoadsCannotRestampCachedMeasurements() {
        var subject = create("normal");
        verify(subject.load("codex"));
        completed(subject, "codex", "normal 1");
        var old = subject.options.codex;
        var received = old[0].usageReceivedAtMs;
        verify(subject.load("claude"));
        completed(subject, "claude", "normal 2");
        compare(subject.options.codex, old);
        compare(subject.options.codex[0].usageReceivedAtMs, received);
        compare(subject.options.codex[0].rows[0].paceObservedAtMs, received);
    }
    function test_timeoutKeepsDataAndAllowsRetry() {
        var subject = create("late");
        verify(subject.load("codex"));
        completed(subject, "codex", "late 1");
        var old = subject.options.codex;
        verify(subject.load("codex"));
        verify(subject.load("claude"));
        completed(subject, "claude", "late 3");
        verify(subject.loadingForProvider("codex"));
        // Exercise the production deadline without overriding its timer.
        tryVerify(function() { return !subject.loadingForProvider("codex"); }, 65000);
        verify(subject.errorForProvider("codex").indexOf("timed out") >= 0);
        compare(subject.options.codex, old);
        verify(subject.load("codex"));
        completed(subject, "codex", "late 4");
        wait(1500);
        compare(subject.options.codex[0].accountKey, "late 4");
        compare(subject.errorForProvider("codex"), "");
    }
}
'''

CLI = '''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
import time
name = Path(sys.argv[0]).name
args = sys.argv[1:]
if args[:2] != ["usage", "--provider"] or args[2] not in ("codex", "claude") or args[3:7] != ["--all-accounts", "--format", "json", "--json-only"]:
    raise SystemExit("unexpected CLI arguments")
allowed_flags = [[], ["--source", "cli"], ["--status"]]
if name == "flags":
    allowed_flags = [["--source", "source'; literal", "--status"]]
if args[7:] not in allowed_flags:
    raise SystemExit("unexpected CLI flags")
provider = args[2]
run = int(os.environ["CODEXBAR_PLASMA_RUN"])
time.sleep(0.2 if provider == "codex" else 0.8)
if name == "slow": time.sleep(1)
if name == "late" and run == 2: time.sleep(62)
if name == "late" and run == 4: time.sleep(3)
if run > 1 and provider == "codex":
    if name == "failure": raise SystemExit("synthetic account failure")
    if name in ("malformed", "unsupported"):
        print("{" if name == "malformed" else "null")
        sys.exit(0)
    if name in ("empty", "missing-token", "structured"):
        print(json.dumps([] if name == "empty" else {"error": {"message":
            "No token accounts configured for codex." if name == "missing-token" else {"toString": None}}}))
        sys.exit(0)
print(json.dumps([{"provider": "deliberately-wrong", "account": name + " " + str(run),
    "usage": {"primary": {"usedPercent": 0}},
    "pace": {"primary": {"expectedUsedPercent": 30, "willLastToReset": False, "etaSeconds": 1800}}}]))
'''


class AccountsControllerTests(unittest.TestCase):
    def test_production_lifecycle_with_synthetic_cli(self):
        with tempfile.TemporaryDirectory(prefix="codexbar accounts 'test-") as temporary:
            directory = Path(temporary)
            for name in ("normal", "flags", "slow", "late", "failure", "malformed", "unsupported", "structured", "empty", "missing-token"):
                script = directory / name
                script.write_text(CLI)
                script.chmod(0o700)
            fixture = directory / "tst_accounts.qml"
            fixture.write_text(QML.replace("CONTROLLER_URL", (ROOT / "contents/ui/controllers/AccountsController.qml").as_uri())
                               .replace("FIXTURE_PATH", str(directory)))
            result = subprocess.run([os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                                    env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                                    capture_output=True, text=True, timeout=110)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            if os.environ.get("QML_TEST_REQUIRE_NO_SKIPS") == "1" and "SKIP" in output:
                self.fail("QML tests were skipped; the test environment must provide the KDE QML modules.")
            if "SKIP" in output:
                self.skipTest("AccountsController needs the optional KDE QML modules")
            warnings = [line for line in output.splitlines() if "QWARN" in line and not (
                'QProcess: Destroyed while process ("/bin/sh") is still running.' in line
                and any(case in line for case in ("test_changedInputsRetireRequestsBeforeNewLoads(",
                    "test_resetRetiresEveryProviderAndClearsLists()", "test_timeoutKeepsDataAndAllowsRetry()")))]
            self.assertEqual(warnings, [])


if __name__ == "__main__":
    unittest.main()
