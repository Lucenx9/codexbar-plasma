"""Exercise the usage controller with real DataSource processes and deadlines."""
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
    name: "UsageController"
    function i18n(text, first) { return text.replace("%1", first === undefined ? "%1" : first); }
    Component {
        id: observation
        QtObject {
            property var subject
            property var snapshots: []
            property var failures: []
            property int emptyRosters: 0
        }
    }
    function init() {
        var factory = Qt.createComponent("CONTROLLER_URL");
        if (factory.status === Component.Error && /module "org\\.kde\\.[^"]+" is not installed/.test(factory.errorString()))
            skip("UsageController needs the optional KDE QML modules");
    }
    function create(script, options) {
        var factory = Qt.createComponent("CONTROLLER_URL");
        compare(factory.status, Component.Ready, factory.errorString());
        var subject = createTemporaryObject(factory, testCase, Object.assign({
            commandPath: "FIXTURE_PATH/" + script, refreshIntervalSec: 0, providerConfigStamp: "synthetic-stamp"
        }, options || {}));
        verify(subject !== null);
        var observed = createTemporaryObject(observation, testCase, {subject: subject});
        subject.snapshotReceived.connect(function(items) { observed.snapshots = observed.snapshots.concat([items]); });
        subject.failed.connect(function(message) { observed.failures = observed.failures.concat(message); });
        subject.emptyRoster.connect(function() { observed.emptyRosters++; });
        return observed;
    }
    function completed(observed, count) {
        tryVerify(function() { return observed.snapshots.length === count && !observed.subject.loading; }, 8000);
    }
    function latest(observed) { return observed.snapshots[observed.snapshots.length - 1]; }

    function test_rosterCacheAndManualBypass() {
        var o = create("normal");
        completed(o, 1);
        compare(latest(o).map(function(item) { return item.provider; }), ["codex", "claude"]);
        compare(latest(o)[0].account, "run 2");
        compare(o.subject.providerDisplayNames.codex, "Synthetic Codex");
        o.subject.refresh(false);
        completed(o, 2);
        compare(latest(o)[0].account, "run 4");
        o.subject.refresh(true);
        completed(o, 3);
        compare(latest(o)[0].account, "run 7");
        o.subject.providerConfigRevision++;
        completed(o, 4);
        compare(latest(o)[0].account, "run 10");
    }
    function test_firstChecksumDoesNotCacheAnOlderRoster() {
        var o = create("slow-roster", {providerConfigStamp: ""});
        tryCompare(o.subject, "loading", true);
        wait(50);
        o.subject.providerConfigStamp = "arrived-during-discovery";
        completed(o, 1);
        compare(latest(o)[0].account, "run 3");
        o.subject.refresh(false);
        completed(o, 2);
        compare(latest(o)[0].account, "run 5");
    }
    function test_scopedArgumentsKeepExactAccountAndSource() {
        var o = create("flags", {provider: "codex", sourceMode: "source'; literal",
            includeStatus: true, selectedAccounts: {codex: "Work  Team'; literal"}});
        completed(o, 1);
        compare(latest(o)[0].accountKey, "Work  Team'; literal");
        compare(latest(o)[0].provider, "codex");
        compare(latest(o)[0].rows[0].usedPercent, 0);
        verify(latest(o)[0].rows[0].paceObservedAtMs > 0);
    }
    function test_batchedInputsStartOneReplacementAndRejectOldReply_data() {
        return [{tag: "aggregate", provider: "", sourceMode: "cli"},
            {tag: "scoped", provider: "codex", sourceMode: ""}];
    }
    function test_batchedInputsStartOneReplacementAndRejectOldReply(data) {
        var o = create("slow-first", {provider: data.provider, sourceMode: data.sourceMode});
        tryCompare(o.subject, "loading", true);
        wait(50);
        o.subject.selectedAccounts = {codex: "new account"};
        o.subject.sourceMode = "cli";
        o.subject.includeStatus = true;
        verify(!o.subject.loading);
        completed(o, 1);
        compare(latest(o)[0].accountKey, "new account");
        var snapshot = o.snapshots;
        wait(1300);
        compare(o.snapshots, snapshot);
        compare(o.failures, []);
    }
    function test_refreshCoalescesExplicitSchedulingWithAccountChanges() {
        var o = create("normal", {provider: "codex"});
        completed(o, 1);
        o.subject.reset();
        o.subject.selectedAccounts = {codex: "target"};
        o.subject.scheduleRefresh();
        o.subject.scheduleRefresh();
        completed(o, 2);
        compare(latest(o)[0].accountKey, "target");
        wait(400);
        compare(o.snapshots.length, 2);
        compare(latest(o)[0].version, "2");
    }
    function test_queueContinuesAfterScopedFailuresAndPreservesOrder() {
        var o = create("queue");
        completed(o, 1);
        compare(latest(o).length, 11);
        compare(latest(o)[0].provider, "synthetic0");
        compare(latest(o)[0].commandFailed, true);
        compare(latest(o)[1].provider, "synthetic1");
        compare(latest(o)[1].commandFailed, true);
        compare(latest(o)[10].provider, "synthetic10");
        compare(latest(o)[10].rows[0].usedPercent, 0);
        verify(latest(o).every(function(item) { return !item.version || Number(item.version) <= 8; }));
        compare(o.failures, []);
    }
    function test_failuresReleaseLoadingAndManualRetryRecovers_data() {
        return [{tag: "malformed", script: "malformed"}, {tag: "empty", script: "empty"},
            {tag: "no-records", script: "no-records"}, {tag: "too-large", script: "too-large"}];
    }
    function test_failuresReleaseLoadingAndManualRetryRecovers(data) {
        var o = create(data.script, {sourceMode: "cli"});
        tryVerify(function() { return o.failures.length === 1 && !o.subject.loading; });
        compare(o.snapshots.length, 0);
        verify(o.subject.errorText.length > 0);
        o.subject.refresh(true);
        completed(o, 1);
        compare(o.subject.errorText, "");
    }
    function test_emptyRosterIsDistinctFromBrokenDiscovery() {
        var empty = create("empty-roster");
        var broken = create("broken-roster");
        tryCompare(empty, "emptyRosters", 1);
        tryVerify(function() { return broken.failures.length === 1; });
        compare(empty.snapshots.length, 0);
        compare(empty.subject.errorText, "");
        compare(empty.subject.lastCompletedAtMs, -1);
        compare(broken.emptyRosters, 0);
    }
    function test_expiredMeasurementsDoNotAdvanceFreshness() {
        var o = create("ancient", {sourceMode: "cli"});
        completed(o, 1);
        verify(o.subject.lastAttemptAtMs > 0);
        compare(o.subject.lastCompletedAtMs, -1);
    }
    function test_resetAndMissingCommandRetireOldReplies() {
        var o = create("slow-first", {sourceMode: "cli"});
        tryCompare(o.subject, "loading", true);
        wait(50);
        o.subject.reset();
        verify(!o.subject.loading);
        wait(1300);
        compare(o.snapshots.length, 0);
        o.subject.commandPath = "";
        tryVerify(function() { return o.failures.length === 1; });
        verify(!o.subject.loading);
    }
    function test_popupFreshnessAndPendingRequestsSuppressDuplicateFetches() {
        var o = create("slow-first", {sourceMode: "cli", refreshOnOpen: true});
        tryCompare(o.subject, "loading", true);
        o.subject.popupVisible = true;
        o.subject.popupVisible = false;
        o.subject.popupVisible = true;
        completed(o, 1);
        var at = o.subject.lastAttemptAtMs;
        o.subject.popupVisible = false;
        o.subject.popupVisible = true;
        wait(300);
        compare(o.subject.lastAttemptAtMs, at);
        compare(o.snapshots.length, 1);
    }
    function test_periodicRefreshWaitsForPendingWork() {
        var o = create("slow-first", {sourceMode: "cli", refreshIntervalSec: 1});
        completed(o, 1);
        compare(latest(o)[0].account, "run 1");
        completed(o, 2);
        o.subject.refreshIntervalSec = 0;
        compare(latest(o)[0].account, "run 2");
    }
    function test_productionTimeoutsReleaseEveryKindAndRejectLateReplies() {
        var aggregate = create("timeout-aggregate", {sourceMode: "cli"});
        var roster = create("timeout-roster");
        var scoped = create("timeout-scoped", {provider: "codex"});
        tryVerify(function() { return aggregate.failures.length === 1 && roster.failures.length === 1
            && scoped.snapshots.length === 1; }, 123000);
        verify(!aggregate.subject.loading && !roster.subject.loading && !scoped.subject.loading);
        compare(latest(scoped)[0].commandFailed, true);
        for (var o of [aggregate, roster, scoped]) o.subject.refresh(true);
        completed(aggregate, 1);
        completed(roster, 1);
        completed(scoped, 2);
        wait(4500);
        compare(aggregate.snapshots.length, 1);
        compare(roster.snapshots.length, 1);
        compare(scoped.snapshots.length, 2);
        compare(latest(aggregate)[0].account, "run 2");
        compare(latest(scoped)[0].account, "run 2");
    }
}
'''

CLI = '''#!/usr/bin/env python3
import fcntl
import json
import os
from pathlib import Path
import sys
import time
name = Path(sys.argv[0]).name
args = sys.argv[1:]
run = int(os.environ["CODEXBAR_PLASMA_RUN"])
assert args[0] in ("usage", "config")
assert "--json-only" in args and args[args.index("--format") + 1] == "json"
assert all(flag in ("--json-only", "--format", "--provider", "--source", "--status", "--account")
           for flag in args if flag.startswith("--"))
if name.startswith("timeout-") and run == 1: time.sleep(124)
if name == "slow-first" and run == 1: time.sleep(1.2)
if args[0] == "config":
    assert args == ["config", "providers", "--format", "json", "--json-only"]
    if name == "slow-roster": time.sleep(0.3)
    if name == "broken-roster": print("null"); sys.exit(0)
    ids = ["synthetic" + str(i) for i in range(11)] if name == "queue" else ["codex", "claude"]
    print(json.dumps([] if name == "empty-roster" else [
        {"provider": key, "displayName": "Synthetic Codex" if key == "codex" else key, "enabled": True} for key in ids]))
    sys.exit(0)
provider = args[args.index("--provider") + 1] if "--provider" in args else "codex"
account = args[args.index("--account") + 1] if "--account" in args else "run " + str(run)
if name == "flags":
    assert args[args.index("--source") + 1] == "source'; literal"
    assert account == "Work  Team'; literal" and "--status" in args
if run == 1:
    if name == "malformed": print("{"); sys.exit(0)
    if name == "empty": raise SystemExit("Synthetic usage failure")
    if name == "no-records": print("null"); sys.exit(0)
    if name == "too-large": print("x" * (4 * 1024 * 1024 + 1)); sys.exit(0)
version = str(run)
if name == "queue":
    state = Path(sys.argv[0]).with_suffix(".state")
    with state.open("a+") as file:
        fcntl.flock(file, fcntl.LOCK_EX)
        file.seek(0)
        active, maximum = json.loads(file.read() or "[0, 0]")
        active += 1
        maximum = max(active, maximum)
        file.seek(0); file.truncate(); json.dump([active, maximum], file)
    time.sleep(0.3)
    with state.open("r+") as file:
        fcntl.flock(file, fcntl.LOCK_EX)
        active, maximum = json.load(file)
        file.seek(0); file.truncate(); json.dump([active - 1, maximum], file)
    version = str(maximum)
    if provider == "synthetic0": print("{"); sys.exit(0)
    if provider == "synthetic1": print("[]"); sys.exit(0)
else:
    time.sleep(0.1)
print(json.dumps({"provider": provider, "account": account, "version": version,
    "usage": {"primary": {"usedPercent": 0}, "updatedAt": "2000-01-01T00:00:00Z" if name == "ancient" else ""},
    "pace": {"primary": {"willLastToReset": False, "etaSeconds": 1800}}}))
'''


class UsageControllerTests(unittest.TestCase):
    def test_production_lifecycle_with_synthetic_cli(self):
        with tempfile.TemporaryDirectory(prefix="codexbar usage 'test-") as temporary:
            directory = Path(temporary)
            for name in ("ancient", "normal", "slow-roster", "flags", "slow-first", "queue", "malformed", "empty",
                         "no-records", "too-large", "empty-roster", "broken-roster", "timeout-aggregate",
                         "timeout-roster", "timeout-scoped"):
                script = directory / name
                script.write_text(CLI)
                script.chmod(0o700)
            fixture = directory / "tst_usage.qml"
            fixture.write_text(QML.replace("CONTROLLER_URL", (ROOT / "contents/ui/controllers/UsageController.qml").as_uri())
                               .replace("FIXTURE_PATH", str(directory)))
            result = subprocess.run([os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                                    env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                                    capture_output=True, text=True, timeout=300)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            if os.environ.get("QML_TEST_REQUIRE_NO_SKIPS") == "1" and "SKIP" in output:
                self.fail("QML tests were skipped; the test environment must provide the KDE QML modules.")
            if "SKIP" in output:
                self.skipTest("UsageController needs the optional KDE QML modules")
            warnings = [line for line in output.splitlines() if "QWARN" in line
                        and 'QProcess: Destroyed while process ("/bin/sh") is still running.' not in line]
            self.assertEqual(warnings, [])


if __name__ == "__main__":
    unittest.main()
