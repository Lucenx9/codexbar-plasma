"""Exercise worker scheduling through the production cost controller's public state.

The harness controls message delivery at the WorkerScript boundary without
CPU-dependent sleeps. Process execution, refresh policy and deadlines use the
production controller; tst_cost_worker.qml covers the real worker separately.
"""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from test_cost_context import CLI

ROOT = Path(__file__).resolve().parents[1]

WORKER = '''import QtQuick
QtObject {
    id: worker
    property bool ready: true
    property url source
    signal message(var messageObject)
    function sendMessage(request) {
        testCase.starts = testCase.starts.concat([request.serial]);
        testCase.pending.push({worker: worker, request: request});
    }
}
'''

QML = '''import QtQuick
import QtTest
import "RESPONSE_URL" as CostResponse
TestCase {
    id: testCase
    name: "CostNormalization"
    property var starts: []
    property var pending: []
    property int cliReplies: 0
    function i18n(text, first) { return text.replace("%1", first); }
    function init() { starts = []; pending = []; cliReplies = 0; }
    function deliver() {
        verify(pending.length > 0);
        var job = pending.shift();
        var request = job.request;
        job.worker.message({serial: request.serial, result: CostResponse.response(
            request.stdoutText, request.stderrText, request.historyDays, request.exitCode)});
    }
    function create() {
        var factory = Qt.createComponent("Controller.qml");
        if (factory.status === Component.Error && /module "org\\.kde\\.[^"]+" is not installed/.test(factory.errorString()))
            skip("CostController needs the optional KDE QML modules");
        compare(factory.status, Component.Ready, factory.errorString());
        var subject = createTemporaryObject(factory, testCase, {commandPath: "CLI_PATH"});
        verify(subject !== null);
        return subject;
    }
    function finished(subject, label) {
        tryVerify(function() {
            if (pending.length) deliver();
            return !subject.loading && subject.costs.codex
                && subject.costs.codex.historyLabel === label;
        }, 8000);
    }
    function test_loadingCoversNormalizationAndPublishesBeforeCompletion() {
        var subject = create();
        tryVerify(function() { return starts.length === 1; });
        verify(subject.loading);
        compare(subject.costs, {});
        verify(!subject.refresh(false));
        var completions = [];
        subject.loadingChanged.connect(function() {
            if (!subject.loading) completions.push(subject.costs.codex ? subject.costs.codex.historyLabel : "missing");
        });
        finished(subject, "normal 1");
        compare(completions, ["normal 1"]);
        compare(subject.errorText, "");
    }
    function test_forcedRefreshCoalescesWaitingRepliesAndIgnoresOldCompletion() {
        var subject = create();
        tryVerify(function() { return starts.length === 1; });
        verify(subject.refresh(true));
        tryCompare(testCase, "cliReplies", 2);
        verify(subject.loading);
        compare(subject.costs, {});
        verify(subject.refresh(true));
        tryCompare(testCase, "cliReplies", 3);
        finished(subject, "normal 3");
        compare(starts.length, 2);
        compare(subject.errorText, "");
    }
    function test_contextRoundTripRejectsEarlierSerial() {
        var subject = create();
        tryVerify(function() { return starts.length === 1; });
        subject.historyDays = 7;
        subject.historyDays = 30;
        compare(subject.costs, {});
        finished(subject, "normal 2");
        compare(starts.length, 2);
    }
    function test_disableDropsWorkerResultAndQueuedReply() {
        var subject = create();
        tryVerify(function() { return starts.length === 1; });
        verify(subject.refresh(true));
        tryCompare(testCase, "cliReplies", 2);
        subject.costUsageEnabled = false;
        verify(!subject.loading);
        deliver();
        compare(subject.costs, {});
        compare(subject.errorText, "");
        compare(starts.length, 1);
        subject.costUsageEnabled = true;
        finished(subject, "normal 3");
    }
    function test_reentrantRefreshDuringReleaseKeepsTheNewRequest() {
        var subject = create();
        tryVerify(function() { return starts.length === 1; });
        var triggered = false;
        subject.loadingChanged.connect(function() {
            if (!subject.loading && !triggered) {
                triggered = true;
                verify(subject.refresh(true));
            }
        });
        verify(!subject.refresh(true));
        finished(subject, "normal 2");
        compare(starts.length, 2);
    }
    function test_refreshDuringPublicationCannotClearNewLoading() {
        var subject = create();
        var triggered = false;
        subject.costsChanged.connect(function() {
            if (subject.costs.codex && !triggered) {
                triggered = true;
                verify(subject.refresh(true));
                verify(subject.loading);
            }
        });
        finished(subject, "normal 2");
        compare(starts.length, 2);
    }
    function test_workerTimeoutRetainsSnapshotAndLateResultCannotRecoverIt() {
        var subject = create();
        finished(subject, "normal 1");
        var previous = subject.costs;
        subject.historyDays = 90;
        tryVerify(function() { return !subject.loading && subject.errorText.length > 0; }, 5000);
        verify(subject.errorText.indexOf("timed out") >= 0);
        compare(subject.costs, {});
        deliver();
        compare(subject.costs, {});
        verify(subject.errorText.indexOf("timed out") >= 0);
        subject.historyDays = 30;
        compare(subject.costs, previous);
        finished(subject, "normal 3");
    }
}
'''


class CostNormalizationTests(unittest.TestCase):
    def test_worker_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix="codexbar-worker-") as temporary:
            directory = Path(temporary)
            cli = directory / "normal"
            cli.write_text(CLI)
            cli.chmod(0o700)
            (directory / "ControlledWorker.qml").write_text(WORKER)
            controller = (ROOT / "contents/ui/controllers/CostController.qml").read_text()
            controller = controller.replace('import "../', 'import "' + (ROOT / "contents/ui").as_uri() + '/')
            controller = controller.replace('import QtQuick\n', 'import QtQuick\nimport "' + (ROOT / "contents/ui/controllers").as_uri() + '"\n', 1)
            controller = controller.replace('    WorkerScript {', '    ControlledWorker {')
            controller = controller.replace('lifecycle.acceptReply(context,', 'testCase.cliReplies += 1; lifecycle.acceptReply(context,')
            controller = controller.replace('commandTimeoutMs: 120000', 'commandTimeoutMs: 1800')
            (directory / "Controller.qml").write_text(controller)
            fixture = directory / "tst_worker.qml"
            fixture.write_text(QML.replace("CLI_PATH", str(cli)).replace("RESPONSE_URL", (ROOT / "contents/ui/CostResponse.mjs").as_uri()))
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=50)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            if "SKIP" in output:
                if os.environ.get("QML_TEST_REQUIRE_NO_SKIPS") == "1":
                    self.fail(output)
                self.skipTest("CostController needs the optional KDE QML modules")
            self.assertNotIn("QWARN", output)


if __name__ == "__main__":
    unittest.main()
