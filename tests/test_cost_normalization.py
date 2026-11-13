"""Exercise worker scheduling through the production cost controller's public state.

A deterministic worker delays delivery and announces when it begins a message.
Only that announcement is intercepted by the harness; result delivery, process
execution, refresh policy and deadlines use the production controller.
"""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from test_cost_context import CLI

ROOT = Path(__file__).resolve().parents[1]

WORKER = '''import * as CostResponse from "RESPONSE_URL";
WorkerScript.onMessage = function(message) {
    WorkerScript.sendMessage({testStarted: message.serial});
    var until = Date.now() + (message.historyDays === 90 ? 2500 : 800);
    while (Date.now() < until) {}
    WorkerScript.sendMessage({serial: message.serial, result: CostResponse.response(
        message.stdoutText, message.stderrText, message.historyDays, message.exitCode)});
};
'''

QML = '''import QtQuick
import QtTest
TestCase {
    id: testCase
    name: "CostNormalization"
    property var starts: []
    function i18n(text, first) { return text.replace("%1", first); }
    function init() { starts = []; }
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
        tryVerify(function() { return !subject.loading && subject.costs.codex
            && subject.costs.codex.historyLabel === label; }, 8000);
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
        wait(300); // The second CLI reply waits while the first worker is running.
        verify(subject.loading);
        compare(subject.costs, {});
        verify(subject.refresh(true));
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
        wait(300);
        subject.costUsageEnabled = false;
        verify(!subject.loading);
        wait(1000);
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
        wait(1200);
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
            worker = directory / "Worker.mjs"
            worker.write_text(WORKER.replace("RESPONSE_URL", (ROOT / "contents/ui/CostResponse.mjs").as_uri()))
            controller = (ROOT / "contents/ui/controllers/CostController.qml").read_text()
            controller = controller.replace('import "../', 'import "' + (ROOT / "contents/ui").as_uri() + '/')
            controller = controller.replace('import QtQuick\n', 'import QtQuick\nimport "' + (ROOT / "contents/ui/controllers").as_uri() + '"\n', 1)
            controller = controller.replace('source: "../CostWorker.mjs"', 'source: "' + worker.as_uri() + '"')
            controller = controller.replace('lifecycle.acceptResult(messageObject);',
                'if (messageObject.testStarted !== undefined) testCase.starts = testCase.starts.concat([messageObject.testStarted]); '
                'else lifecycle.acceptResult(messageObject);')
            controller = controller.replace('commandTimeoutMs: 120000', 'commandTimeoutMs: 1800')
            (directory / "Controller.qml").write_text(controller)
            fixture = directory / "tst_worker.qml"
            fixture.write_text(QML.replace("CLI_PATH", str(cli)))
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
