"""Exercise the updater module through real, isolated executable requests."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]

QML = '''import QtQuick
import QtTest
TestCase {
    id: testCase
    name: "WidgetUpdateController"
    property var subject: null

    function i18n(text, first, second) {
        return text.replace("%1", first === undefined ? "%1" : first)
                   .replace("%2", second === undefined ? "%2" : second);
    }
    SignalSpy { id: recorded; target: subject; signalName: "statusRecorded" }
    SignalSpy { id: succeeded; target: subject; signalName: "checkSucceeded" }
    SignalSpy { id: available; target: subject; signalName: "updateAvailable" }
    SignalSpy { id: installed; target: subject; signalName: "updateInstalled" }

    function init() {
        var probe = Qt.createComponent("CONTROLLER_URL");
        if (probe.status === Component.Error && /module "org\\.kde\\.[^"]+" is not installed/.test(probe.errorString())) {
            skip("WidgetUpdateController needs the optional KDE QML modules");
            return;
        }
        subject = null;
        recorded.clear();
        succeeded.clear();
        available.clear();
        installed.clear();
    }
    function create(script, options) {
        var factory = Qt.createComponent("CONTROLLER_URL");
        compare(factory.status, Component.Ready, factory.errorString());
        subject = createTemporaryObject(factory, testCase, Object.assign({
            scriptUrl: "FIXTURE_URL/" + script,
            updateChecksEnabled: false
        }, options || {}));
        verify(subject !== null);
        // Model the applet's configuration write feeding the successful timestamp back.
        subject.checkSucceeded.connect(function(timestamp) { subject.autoUpdateLastCheck = timestamp; });
        return subject;
    }
    function test_disabledChecksCannotBeForced() {
        var updater = create("missing");
        updater.checkNow();
        wait(100);
        verify(!updater.busy);
        compare(recorded.count, 0);
    }
    function test_recentStartupStillChecksAndCoalescesRequests() {
        var updater = create("normal", {updateChecksEnabled: true,
            autoUpdateLastCheck: new Date().toISOString()});
        tryCompare(succeeded, "count", 1);
        compare(available.count, 1);
        updater.checkNow();
        updater.checkNow();
        verify(updater.busy);
        tryCompare(succeeded, "count", 2);
        compare(available.count, 2);
        compare(recorded.count, 2);
        compare(updater.errorText, "");
        updater.checkNow();
        tryCompare(succeeded, "count", 3);
        compare(available.count, 3);
        compare(recorded.count, 3);
    }
    function test_installQueuedDuringCheckKeepsRequestModes() {
        var updater = create("queued", {updateChecksEnabled: true});
        tryCompare(updater, "busy", true);
        updater.autoUpdateEnabled = true;
        updater.checkNow();
        tryCompare(installed, "count", 1);
        compare(available.count, 1);
        compare(succeeded.count, 2);
        compare(recorded.count, 2);
        compare(updater.errorText, "");
        verify(!updater.busy);
    }
    function test_disablingChecksCancelsQueuedInstall() {
        var updater = create("disable", {updateChecksEnabled: true});
        tryCompare(updater, "busy", true);
        updater.autoUpdateEnabled = true;
        wait(0);
        updater.updateChecksEnabled = false;
        tryCompare(succeeded, "count", 1);
        wait(250);
        compare(available.count, 1);
        compare(installed.count, 0);
        compare(recorded.count, 1);
        verify(!updater.busy);
    }
    function test_disablingAutomaticInstallDoesNotChangeActiveMode() {
        var updater = create("captured", {updateChecksEnabled: true, autoUpdateEnabled: true});
        tryCompare(updater, "busy", true);
        updater.autoUpdateEnabled = false;
        tryCompare(succeeded, "count", 1);
        compare(recorded.count, 1);
        compare(available.count, 0);
        verify(updater.statusText.indexOf("available") >= 0);
    }
    function test_invalidResults_data() {
        return [{tag: "malformed", script: "malformed"},
                {tag: "structured", script: "structured"},
                {tag: "missing", script: "missing"}];
    }
    function test_invalidResults(data) {
        var updater = create(data.script, {updateChecksEnabled: true});
        tryCompare(recorded, "count", 1);
        verify(!updater.busy);
        verify(updater.errorText.length > 0);
        compare(succeeded.count, 0);
        compare(available.count, 0);
        compare(installed.count, 0);
        updater.updateChecksEnabled = false;
    }
    function test_timeoutCancelsRequestAndNextRunSucceeds() {
        var updater = create("late", {updateChecksEnabled: true});
        tryCompare(updater, "busy", true);
        // Use the production 60-second deadline, without changing timers or private state.
        tryCompare(recorded, "count", 1, 65000);
        verify(!updater.busy);
        verify(updater.errorText.indexOf("timed out") >= 0);
        compare(succeeded.count, 0);
        updater.checkNow();
        verify(updater.busy);
        tryCompare(succeeded, "count", 1, 10000);
        wait(500);
        compare(available.count, 0);
        compare(recorded.count, 2);
        compare(updater.statusText, "Widget is up to date.");
        compare(updater.errorText, "");
        verify(!updater.busy);
    }
}
'''

NORMAL = '''#!/bin/sh
sleep 0.2
if [ "$1" = --install ]; then
    printf '%s\\n' '{"status":"installed","remoteVersion":"2.0"}'
else
    printf '%s\\n' '{"status":"available","remoteVersion":"2.0","assetUrl":"https://example.test/widget"}'
fi
'''


class WidgetUpdateControllerTests(unittest.TestCase):
    def test_production_lifecycle_with_synthetic_updater(self):
        with tempfile.TemporaryDirectory(prefix="codexbar updater 'test-") as temporary:
            directory = Path(temporary)
            scripts = {
                "normal": NORMAL, "queued": NORMAL, "disable": NORMAL,
                "captured": '#!/bin/sh\nsleep 0.2\nprintf \'%s\\n\' \'{"status":"available","remoteVersion":"2.0"}\'\n',
                "malformed": '#!/bin/sh\nprintf \'%s\\n\' \'{broken\'\n',
                "structured": '#!/bin/sh\nprintf \'%s\\n\' \'{"status":"error","errorCode":"missing_tool","errorDetail":"jq"}\'\n',
                "late": '''#!/bin/sh
if [ "$CODEXBAR_PLASMA_RUN" = 1 ]; then
    sleep 62
    printf '%s\\n' '{"status":"available","remoteVersion":"old"}'
else
    sleep 3
    printf '%s\\n' '{"status":"current"}'
fi
''',
            }
            for name, source in scripts.items():
                path = directory / name
                path.write_text(source)
                path.chmod(0o700)
            qml = QML.replace("CONTROLLER_URL", (ROOT / "contents/ui/controllers/WidgetUpdateController.qml").as_uri())
            qml = qml.replace("FIXTURE_URL", directory.as_uri())
            fixture = directory / "tst_updater.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=95)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            if os.environ.get("QML_TEST_REQUIRE_NO_SKIPS") == "1" and "SKIP" in output:
                self.fail("QML tests were skipped; the CI environment must provide the KDE QML modules.")
            if "SKIP" in output:
                self.skipTest("WidgetUpdateController needs the optional KDE QML modules")
            # Plasma destroys the timed-out QProcess when its source disconnects.
            warnings = [line for line in output.splitlines()
                        if "QWARN" in line and not (
                            "test_timeoutCancelsRequestAndNextRunSucceeds()" in line
                            and 'QProcess: Destroyed while process ("/bin/sh") is still running.' in line)]
            self.assertEqual(warnings, [])


class WidgetUpdateControllerRunnerTests(unittest.TestCase):
    def run_fixture_result(self, returncode, output, strict):
        result = unittest.TestResult()
        case = WidgetUpdateControllerTests("test_production_lifecycle_with_synthetic_updater")
        completed = subprocess.CompletedProcess(["qmltestrunner"], returncode, output, "")
        with mock.patch.dict(os.environ, {"QML_TEST_REQUIRE_NO_SKIPS": "1" if strict else "0"}):
            with mock.patch.object(subprocess, "run", return_value=completed):
                case.run(result)
        self.assertEqual(result.errors, [])
        return result

    def test_runner_failure_with_skip_is_never_hidden(self):
        for strict in (False, True):
            with self.subTest(strict=strict):
                result = self.run_fixture_result(7, "SKIP   : optional module unavailable\n", strict)
                self.assertEqual(len(result.failures), 1)
                self.assertEqual(result.skipped, [])
                self.assertIn("7 != 0", result.failures[0][1])

    def test_successful_optional_module_skip_is_reported(self):
        result = self.run_fixture_result(0, "SKIP   : optional module unavailable\n", False)
        self.assertEqual(result.failures, [])
        self.assertEqual(len(result.skipped), 1)

    def test_strict_mode_rejects_successful_runner_skips(self):
        result = self.run_fixture_result(0, "SKIP   : optional module unavailable\n", True)
        self.assertEqual(len(result.failures), 1)
        self.assertEqual(result.skipped, [])
        self.assertIn("QML tests were skipped", result.failures[0][1])

    def test_successful_runner_passes(self):
        result = self.run_fixture_result(0, "PASS   : synthetic fixture\n", True)
        self.assertTrue(result.wasSuccessful())
        self.assertEqual(result.skipped, [])


if __name__ == "__main__":
    unittest.main()
