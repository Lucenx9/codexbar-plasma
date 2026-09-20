"""Exercise the shared release/Versions process owner without network requests."""
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
    name: "CliUpdateController"
    property var subject: null
    function i18n(text, first, second) {
        return text.replace("%1", first === undefined ? "%1" : first)
                   .replace("%2", second === undefined ? "%2" : second)
    }
    SignalSpy { id: available; target: subject; signalName: "updateAvailable" }
    SignalSpy { id: succeeded; target: subject; signalName: "checkedRelease" }
    function create(options) {
        var factory = Qt.createComponent("CONTROLLER");
        if (factory.status === Component.Error && /module "org\\.kde\\.[^"]+" is not installed/.test(factory.errorString())) {
            skip("CliUpdateController needs the optional KDE QML modules");
            return null;
        }
        compare(factory.status, Component.Ready, factory.errorString());
        subject = createTemporaryObject(factory, testCase, Object.assign({scriptUrl: "FIXTURE", commandPath: "normal"}, options || {}));
        verify(subject !== null);
        available.clear(); succeeded.clear();
        return subject;
    }
    function test_blankPathDoesNotUsePathExecutable() {
        var updater = create({commandPath: "   "}); if (!updater) return;
        updater.checkNow();
        verify(!updater.busy);
        verify(updater.checked);
        compare(updater.result.status, "missing");
        compare(updater.result.path, "");
        compare(available.count, 0);
        compare(succeeded.count, 0);
    }
    function test_manualAndLocalChecks() {
        var updater = create(); if (!updater) return;
        wait(50); verify(!updater.busy);
        updater.checkNow(); updater.checkNow();
        verify(updater.busy);
        tryCompare(succeeded, "count", 1);
        compare(available.count, 1);
        compare(updater.result.manager, "pacman");
        updater.localOnly = true;
        updater.checkNow();
        tryCompare(updater, "busy", false);
        compare(updater.result.status, "local");
        compare(available.count, 1);
    }
    function test_recentCheckAndRetarget() {
        var updater = create({automaticChecks: true, lastCheck: new Date().toISOString()});
        if (!updater) return;
        wait(100); verify(!updater.busy); compare(succeeded.count, 0);
        updater.commandPath = "changed";
        tryCompare(succeeded, "count", 1);
        updater.checkIfDue(); wait(50); verify(!updater.busy);
    }
    function test_disabledRetiresAndIgnoresLateReplies() {
        var updater = create({automaticChecks: true}); if (!updater) return;
        tryCompare(updater, "busy", true);
        var source = updater.activeSource;
        updater.automaticChecks = false;
        verify(!updater.busy);
        updater.accept(source, {"exit code": 0, stdout: '{}'});
        compare(updater.checked, false);
        wait(300); compare(available.count, 0);
        updater.checkNow(); tryCompare(succeeded, "count", 1);
    }
    function test_timeoutThenRecovery() {
        var updater = create(); if (!updater) return;
        updater.checkNow();
        var oldSource = updater.activeSource;
        findChild(updater, "cliUpdateDeadline").triggered();
        verify(!updater.busy); verify(updater.checked);
        compare(updater.result.status, "error");
        updater.checkNow();
        updater.accept(oldSource, {"exit code": 0, stdout: '{}'});
        verify(updater.busy);
        tryCompare(succeeded, "count", 1);
    }
    function test_invalidOutputDoesNotNotify() {
        var updater = create({commandPath: "bad"}); if (!updater) return;
        updater.checkNow(); tryCompare(updater, "checked", true);
        compare(updater.result.status, "error");
        compare(available.count, 0); compare(succeeded.count, 0);
    }
}
'''


class CliUpdateControllerTests(unittest.TestCase):
    def test_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix="cli updater 'test-") as directory:
            path = Path(directory)
            script = path / "fixture.py"
            script.write_text('''import sys, time, json
time.sleep(0.2)
if "bad" in sys.argv:
    print("malformed")
else:
    print(json.dumps(dict(status="local" if "--local-only" in sys.argv else "available",
        version="0.60.4", path="/usr/bin/codexbar", manager="pacman", latest="0.62.0", tag="v0.62.0")))
''')
            qml = QML.replace("CONTROLLER", (ROOT / "contents/ui/controllers/CliUpdateController.qml").as_uri()).replace("FIXTURE", script.as_uri())
            (path / "tst_cli.qml").write_text(qml)
            result = subprocess.run([os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(path / "tst_cli.qml")],
                                    env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                                    capture_output=True, text=True, timeout=20)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            if "SKIP" in output:
                if os.environ.get("QML_TEST_REQUIRE_NO_SKIPS") == "1":
                    self.fail(output)
                self.skipTest("KDE QML modules unavailable")
            warnings = [line for line in output.splitlines() if "QWARN" in line and "QProcess: Destroyed while process" not in line]
            self.assertEqual(warnings, [], output)
