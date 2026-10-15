"""Run the identified-token owner with synthetic executable processes and timers."""

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
    name: "IdentifiedTokensController"
    function create(name, options) {
        var factory = Qt.createComponent("CONTROLLER_URL");
        if (factory.status === Component.Error && /module "org\\.kde\\.[^"]+" is not installed/.test(factory.errorString()))
            skip("Identified tokens need the optional KDE QML modules");
        compare(factory.status, Component.Ready, factory.errorString());
        var subject = createTemporaryObject(factory, testCase, Object.assign({
            commandPath: "FIXTURES/" + name, collectionEnabled: true,
            sshHost: "build@host", historyDays: 7
        }, options || {}));
        verify(subject !== null);
        return subject;
    }
    function completed(subject, total) {
        tryVerify(function() { return !subject.loading && subject.snapshot !== null; }, 8000);
        compare(subject.snapshot.totalTokens, total);
        compare(subject.errorKind, "");
        verify(!/records|reports|costUSD|build@host/.test(JSON.stringify(subject.snapshot)));
    }
    function test_noAutomaticLoadOrDisabledRequests() {
        var idle = create("idle");
        wait(250);
        verify(!idle.loading && idle.snapshot === null);
        idle.historyDays = 90;
        idle.sshHost = "other";
        wait(250);
        verify(!idle.loading && idle.snapshot === null);
        var disabled = create("disabled", {collectionEnabled: false});
        verify(!disabled.request(false));
        verify(!disabled.request(true));
    }
    function test_localActionIgnoresConfiguredSsh() {
        var subject = create("local");
        verify(subject.request(false));
        completed(subject, 110);
        verify(!subject.snapshot.remoteRequested && subject.snapshot.allSourcesAvailable);
        wait(200);
        completed(subject, 110);
    }
    function test_unavailableRemoteRetainsLocalSubtotal() {
        var subject = create("remote-failure");
        verify(subject.request(true));
        completed(subject, 110);
        verify(subject.snapshot.partial && !subject.snapshot.requestsPartial);
        verify(subject.snapshot.localAvailable && !subject.snapshot.remoteAvailable);
    }
    function test_partialExitZeroAndUnavailableLocal() {
        var partial = create("partial");
        verify(partial.request(false));
        completed(partial, 110);
        verify(partial.snapshot.requestsPartial && partial.snapshot.allSourcesAvailable);
        var failed = create("local-failure");
        verify(failed.request(false));
        tryCompare(failed, "loading", false, 8000);
        compare(failed.snapshot, null);
        compare(failed.errorKind, "unavailable");
    }
    function test_contextChangesRetireAndNeverRestart() {
        var subject = create("slow-context");
        verify(subject.request(true));
        wait(150);
        subject.historyDays = 30;
        verify(!subject.loading && subject.snapshot === null);
        wait(1800);
        compare(subject.snapshot, null);
        compare(subject.errorKind, "");
        verify(subject.request(false));
        completed(subject, 110);
        subject.sshHost = "other";
        compare(subject.snapshot, null);
        verify(!subject.loading);
        subject.commandPath = "FIXTURES/local";
        subject.collectionEnabled = false;
        wait(200);
        verify(!subject.loading && subject.snapshot === null);
    }
    function test_timeoutAndDestructionRetirePendingSources() {
        var subject = create("slow-timeout");
        verify(subject.request(false));
        wait(150);
        var lifecycle = findChild(subject, "identifiedTokensLifecycle");
        verify(lifecycle !== null);
        lifecycle.expireRequests(Date.now() + 121000);
        verify(!subject.loading);
        compare(subject.errorKind, "timeout");
        wait(1800);
        compare(subject.snapshot, null);
        compare(subject.errorKind, "timeout");
        var doomed = create("slow-destroy");
        verify(doomed.request(true));
        wait(150);
        doomed.destroy();
        wait(1800);
    }
    function test_badSshNeverStartsAndNewRequestSupersedes() {
        var invalid = create("invalid-host", {sshHost: "host; touch bad"});
        verify(!invalid.sshAvailable);
        verify(!invalid.request(true));
        var subject = create("slow-replace");
        verify(subject.request(true));
        wait(150);
        verify(subject.request(false));
        completed(subject, 110);
        verify(!subject.snapshot.remoteRequested);
        wait(200);
        verify(!subject.snapshot.remoteRequested);
    }
}
'''

CLI = '''#!/usr/bin/env python3
import json
from pathlib import Path
import sys
import time

args = sys.argv[1:]
name = Path(sys.argv[0]).name
with Path(sys.argv[0] + ".log").open("a") as log:
    log.write(json.dumps(args) + "\\n")
assert args[:3] == ["cost", "--provider", "codex"]
assert "--identified-only" in args and "--json" in args
assert "--period" not in args
end = int(args[args.index("--identified-end") + 1])
days = int(args[args.index("--days") + 1])
start = end - end % 86400000 - (days - 1) * 86400000
ledger = dict(schemaVersion=1, provider="codex", startUnixMs=start, endUnixMs=end,
              records=[dict(id="a" * 64, timestampUnixMs=end, inputTokens=100,
                            outputTokens=10, cacheReadTokens=40)],
              conflictingIDs=[], excludedCount=1 if name == "partial" else 0,
              partial=name == "partial")
if name.startswith("slow"):
    time.sleep(1.5)
if name == "local-failure":
    print(json.dumps(dict(reports=[dict(host="local", error="synthetic SECRET")],
                         allSourcesAvailable=False, partial=True)))
    sys.exit(1)
if "--remote" in args:
    host = args[args.index("--remote") + 1]
    assert host == "build@host"
    report = dict(host=host, error="synthetic SECRET") if name == "remote-failure" else dict(host=host, ledger=ledger)
    failed = name == "remote-failure"
    print(json.dumps(dict(reports=[dict(host="local", ledger=ledger), report],
                         subtotal=dict(kind="identified-request-subtotal", totalTokens=110,
                                       requestCount=1, conflictCount=0, excludedCount=0,
                                       partial=False, costUSD=None),
                         allSourcesAvailable=not failed, partial=failed)))
    sys.exit(1 if failed else 0)
print(json.dumps(ledger))
'''


class IdentifiedTokensContextTest(unittest.TestCase):
    def test_manual_controller(self):
        with tempfile.TemporaryDirectory(prefix="codexbar-identified-") as temporary:
            work = Path(temporary)
            names = ("idle", "disabled", "local", "remote-failure", "partial", "local-failure",
                     "slow-context", "slow-timeout", "slow-destroy", "invalid-host", "slow-replace")
            for name in names:
                script = work / name
                script.write_text(CLI)
                script.chmod(0o700)
            qml = work / "tst_identified_context.qml"
            qml.write_text(QML.replace("CONTROLLER_URL", (ROOT / "contents/ui/controllers/IdentifiedTokensController.qml").as_uri())
                           .replace("FIXTURES", work.as_posix()))
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(qml)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                text=True, capture_output=True, timeout=60, check=False)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            unexpected_warnings = [line for line in (result.stdout + result.stderr).splitlines()
                                   if "QWARN" in line and not line.endswith(
                                       'QProcess: Destroyed while process ("/bin/sh") is still running.')]
            self.assertEqual(unexpected_warnings, [])
            if "SKIP " in result.stdout:
                if os.environ.get("QML_TEST_REQUIRE_NO_SKIPS") == "1":
                    self.fail(result.stdout)
                self.skipTest("Identified tokens need the optional KDE QML modules")
            for name in ("idle", "disabled", "invalid-host"):
                self.assertFalse((work / (name + ".log")).exists(), name + " spawned unexpectedly")
            self.assertEqual(len((work / "local.log").read_text().splitlines()), 1)


if __name__ == "__main__":
    unittest.main()
