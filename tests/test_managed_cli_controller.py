"""Managed CLI process lifecycle with isolated synthetic responses."""
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
    name: "ManagedCliController"
    property var subject: null
    function i18n(text, arg) { return text.replace("%1", arg === undefined ? "%1" : arg) }
    SignalSpy { id: selected; target: subject; signalName: "installed" }
    SignalSpy { id: changed; target: subject; signalName: "changed" }
    function create(options) {
        var factory = Qt.createComponent("CONTROLLER");
        compare(factory.status, Component.Ready, factory.errorString());
        subject = createTemporaryObject(factory, testCase, Object.assign({scriptUrl: "FIXTURE", commandPath: "codexbar"}, options || {}));
        verify(subject !== null); selected.clear(); changed.clear();
        return subject;
    }
    function test_statusDoesNotSelectOrMutate() {
        var updater = create();
        updater.run("status"); tryCompare(updater, "busy", false);
        compare(updater.result.version, "0.62.0");
        compare(selected.count, 0); compare(changed.count, 0);
        verify(!updater.selected);
        updater.commandPath = "/home/test/.local/share/codexbar-plasma/cli/current/codexbar";
        verify(updater.selected);
        compare(updater.result.status, "ready");
        updater.run("status"); tryCompare(updater, "busy", false);
        verify(updater.selected);
    }
    function test_installSelectsOnlyOnSuccess() {
        var updater = create();
        updater.run("install"); updater.run("install");
        tryCompare(selected, "count", 1); compare(changed.count, 1);
        compare(selected.signalArguments[0][0], updater.result.path);
    }
    function test_retiredReplyCannotSelectChangedCommand() {
        var updater = create();
        updater.run("install"); var oldSource = updater.activeSource;
        updater.commandPath = "external";
        verify(!updater.busy);
        updater.accept(oldSource, {"exit code": 0, stdout: '{}'});
        wait(300); compare(selected.count, 0); compare(changed.count, 0);
    }
    function test_timeoutAllowsRetry() {
        var updater = create(); updater.run("install");
        findChild(updater, "managedCliDeadline").triggered();
        verify(!updater.busy); compare(updater.result.status, "error");
        updater.run("install"); tryCompare(selected, "count", 1);
    }
    function test_automaticDoesNotSelectAndRetiresOnDisable() {
        var updater = create({automaticUpdates: true});
        tryCompare(updater, "busy", true); updater.automaticUpdates = false;
        verify(!updater.busy); wait(300); compare(selected.count, 0);
        updater.nextAttempt = 0; updater.automaticUpdates = true;
        tryCompare(updater, "busy", true); tryCompare(updater, "busy", false);
        compare(selected.count, 0);
        updater.checkIfDue(); verify(!updater.busy);
    }
}
'''

class ManagedCliControllerTests(unittest.TestCase):
    def test_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix="cli updater 'test-") as directory:
            path = Path(directory)
            script = path / "fixture.py"
            script.write_text('''import sys, time, json
time.sleep(0.2)
action = sys.argv[sys.argv.index("--action") + 1]
print(json.dumps(dict(status="installed" if action == "install" else "ready", version="0.62.0",
    previous="0.61.0", path="/home/test/.local/share/codexbar-plasma/cli/current/codexbar")))
''')
            qml = QML.replace("CONTROLLER", (ROOT / "contents/ui/controllers/ManagedCliController.qml").as_uri()).replace("FIXTURE", script.as_uri())
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
