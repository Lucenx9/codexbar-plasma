"""Exercise the production AI Insights controller through real executable requests.

A synthetic helper replaces scripts/ai-insights.py. It records every invocation,
so the tests count actual processes instead of trusting controller state.
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

HELPER = '''import json, sys, time
arguments = sys.argv[1:]
with open(LOG_PATH, "a") as log:
    log.write(json.dumps(arguments) + "\\n")
values = dict(zip(arguments[::2], arguments[1::2]))
model = values.get("--model", "")
if model == "slow-model":
    time.sleep(1.5)
if model == "auth-model":
    print(json.dumps({"status": "error", "reason": "auth"}))
elif model == "rate-model":
    print(json.dumps({"status": "error", "reason": "rate_limited", "retryAfter": 600}))
elif model == "garbage-model":
    print("{not json")
else:
    print(json.dumps({"status": "ok", "summary": "Insight [" + values.get("--language", "") + "] <b>plain</b>",
                      "highlights": ["One", 2, "Two"]}))
'''

QML = '''import QtQuick
import QtTest
TestCase {
    id: testCase
    name: "AiInsightsController"
    property var subject: null
    property int callBaseline: 0
    readonly property string snapshot: JSON.stringify({version: 1, providers: [{id: "codex", state: "current",
        quotas: [{window: "primary", usedPercent: 40}]}], signals: []})

    SignalSpy { id: generated; target: subject; signalName: "generated" }
    SignalSpy { id: attempts; target: subject; signalName: "attemptStarted" }

    function init() {
        var probe = Qt.createComponent("CONTROLLER_URL");
        if (probe.status === Component.Error && /module "org\\.kde\\.[^"]+" is not installed/.test(probe.errorString())) {
            skip("AiInsightsController needs the optional KDE QML modules");
            return;
        }
        subject = null;
        callBaseline = 0;
        callBaseline = calls().length;
        generated.clear();
        attempts.clear();
    }
    function calls() {
        var request = new XMLHttpRequest();
        request.open("GET", "LOG_URL", false);
        try { request.send(); } catch (error) { return []; }
        return request.responseText.split("\\n").filter(function(line) { return line.length > 0; })
            .map(function(line) { return JSON.parse(line); }).slice(callBaseline);
    }
    function create(options) {
        var factory = Qt.createComponent("CONTROLLER_URL");
        compare(factory.status, Component.Ready, factory.errorString());
        subject = createTemporaryObject(factory, testCase, Object.assign({
            scriptUrl: "HELPER_URL",
            insightsEnabled: true,
            provider: "openrouter",
            model: "ok-model",
            language: "it",
            intervalHours: 0,
            snapshotText: snapshot,
            snapshotId: "0000abcd"
        }, options || {}));
        verify(subject !== null);
        subject.attemptStarted.connect(function(timestamp) { subject.lastAttempt = timestamp; });
        subject.generated.connect(function(text) { subject.cacheText = text; });
        return subject;
    }
    function argument(call, name) {
        var index = call.indexOf(name);
        return index >= 0 ? call[index + 1] : undefined;
    }

    function test_1_disabledStartsNothing() {
        var controller = create({insightsEnabled: false, intervalHours: 6});
        verify(!controller.generate());
        wait(400);
        verify(!controller.busy);
        compare(calls().length, 0);
        compare(attempts.count, 0);
    }
    function test_2_manualGenerationRunsOnceAndCarriesTheLanguage() {
        var controller = create();
        wait(400);
        compare(calls().length, 0, "manual mode must not start on its own");
        verify(controller.generate());
        verify(controller.busy);
        tryCompare(generated, "count", 1, 10000);
        var call = calls()[0];
        compare(argument(call, "--action"), "generate");
        compare(argument(call, "--language"), "it");
        compare(argument(call, "--provider"), "openrouter");
        compare(JSON.parse(argument(call, "--snapshot")), JSON.parse(snapshot));
        verify(call.indexOf("--no-zdr") < 0);
        var cache = JSON.parse(generated.signalArguments[0][0]);
        compare(cache.summary, "Insight [it] <b>plain</b>");
        compare(cache.highlights, ["One", "Two"]);
        compare(cache.language, "it");
        compare(cache.context, controller.contextKey);
        compare(cache.snapshot, "0000abcd");
        compare(attempts.count, 1);
    }
    function test_3_duplicateRequestsAreCoalesced() {
        var controller = create({model: "slow-model"});
        verify(controller.generate());
        verify(!controller.generate());
        verify(!controller.generate());
        tryCompare(generated, "count", 1, 10000);
        compare(calls().length, 1);
        compare(attempts.count, 1);
    }
    function test_4_automaticGenerationRespectsTheScheduleAndRestarts() {
        var recent = create({intervalHours: 6, lastAttempt: new Date(Date.now() - 60000).toISOString()});
        wait(400);
        compare(calls().length, 0, "a recent persisted attempt must block a restart request");
        recent.destroy();
        var cached = create({intervalHours: 6, cacheText: JSON.stringify({version: 1, summary: "Old",
            generatedAt: new Date(Date.now() - 3600000).toISOString(), context: "other"})});
        wait(400);
        compare(calls().length, 0, "an insight younger than the interval is not regenerated");
        cached.destroy();
        var due = create({intervalHours: 6});
        tryCompare(generated, "count", 1, 10000);
        compare(calls().length, 1);
        // The snapshot changing every minute does not start another request.
        due.snapshotId = "0000ffff";
        wait(400);
        compare(calls().length, 1);
    }
    function test_5_languageChangeRetiresTheRequestInFlight() {
        var controller = create({model: "slow-model"});
        verify(controller.generate());
        controller.language = "de";
        verify(!controller.busy);
        wait(2500);
        compare(generated.count, 0, "a late Italian reply must not be stored for German");
        compare(calls().length, 1, "changing the language must not start a paid request");
    }
    function test_6_modelChangeAndDisableRetireTheRequestInFlight() {
        var controller = create({model: "slow-model"});
        verify(controller.generate());
        controller.model = "other-model";
        verify(!controller.busy);
        verify(controller.generate());
        controller.insightsEnabled = false;
        verify(!controller.busy);
        wait(2500);
        compare(generated.count, 0);
        compare(calls().length, 2);
    }
    function test_7_failuresAreReportedWithoutRetryLoops_data() {
        return [{tag: "auth", model: "auth-model", reason: "auth", manualRetry: true},
                {tag: "rate limit", model: "rate-model", reason: "rate_limited", manualRetry: false},
                {tag: "malformed", model: "garbage-model", reason: "format", manualRetry: true}];
    }
    function test_7_failuresAreReportedWithoutRetryLoops(data) {
        var controller = create({model: data.model, intervalHours: 6});
        tryCompare(controller, "errorReason", data.reason, 10000);
        verify(!controller.busy);
        compare(generated.count, 0);
        verify(controller.retryAtMs > Date.now());
        // Automatic generation never retries on its own within the delay.
        wait(400);
        compare(calls().length, 1);
        // An explicit retry waits only for a provider's Retry-After.
        compare(controller.generate(), data.manualRetry);
        if (data.manualRetry)
            tryCompare(controller, "busy", false, 10000);
        wait(200);
        compare(calls().length, data.manualRetry ? 2 : 1);
    }
    function test_8_destructionDuringGeneration() {
        var controller = create({model: "slow-model"});
        verify(controller.generate());
        controller.destroy();
        wait(2500);
        compare(generated.count, 0);
    }
}
'''


class AiInsightsControllerTests(unittest.TestCase):
    def test_production_lifecycle_with_synthetic_helper(self):
        with tempfile.TemporaryDirectory(prefix="codexbar ai 'test-") as temporary:
            directory = Path(temporary)
            log = directory / "calls.jsonl"
            helper = directory / "ai-insights.py"
            helper.write_text("LOG_PATH = " + json.dumps(str(log)) + "\n" + HELPER)
            qml = (QML.replace("CONTROLLER_URL", (ROOT / "contents/ui/controllers/AiInsightsController.qml").as_uri())
                   .replace("HELPER_URL", helper.as_uri()).replace("LOG_URL", log.as_uri()))
            fixture = directory / "tst_ai_insights_controller.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software",
                     "QML_XHR_ALLOW_FILE_READ": "1",
                     "PATH": os.path.dirname(sys.executable) + ":" + os.environ.get("PATH", "")},
                capture_output=True, text=True, timeout=120)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            if os.environ.get("QML_TEST_REQUIRE_NO_SKIPS") == "1" and "SKIP" in output:
                self.fail("QML tests were skipped; the CI environment must provide the KDE QML modules.")
            if "SKIP" in output:
                self.skipTest("AiInsightsController needs the optional KDE QML modules")
            # Plasma destroys a retired QProcess while the slow helper still runs.
            warnings = [line for line in output.splitlines() if "QWARN" in line
                        and "QProcess: Destroyed while process" not in line]
            self.assertEqual(warnings, [], output)


if __name__ == "__main__":
    unittest.main()
