"""Exercise the popup installation owner with the real managed CLI process controller."""

import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/lib"))
from qml_surfaces import Surface

QML = '''import QtQuick
import QtTest
import "SOURCE_URL/controllers" as Controllers
TestCase {
    id: testCase
    name: "PopupCliSetup"
    function i18n(text, arg) { return text.replace("%1", arg === undefined ? "%1" : arg); }
    Component {
        id: harness
        Item {
            id: root
            property alias config: configuration
            property alias controller: managedCli
            property string commandPath: configuration.commandPath
            SOURCE_SETUP_PROPERTIES
            property bool commandPathFailed: true
            property bool loading: false
            property var providers: []
            property int refreshes: 0
            property var accountsController: QtObject {
                property int resets: 0
                function reset() { resets++; }
            }
            function refreshNow(bypass) {
                if (!bypass) throw new Error("Setup must refresh provider discovery");
                refreshes++;
            }
            QtObject {
                id: configuration
                property string commandPath: "codexbar"
                property bool cliAutomaticUpdates: false
            }
            SOURCE_FUNCTION
            Controllers.ManagedCliController { SOURCE_CONTROLLER }
        }
    }
    function create(command) {
        var subject = createTemporaryObject(harness, testCase);
        verify(subject !== null);
        subject.controller.scriptUrl = "FIXTURE_URL";
        subject.config.commandPath = command || "codexbar";
        return subject;
    }
    function test_installAndOfflineReuse_data() {
        return [{tag: "fresh install", command: "codexbar"}, {tag: "reuse", command: "reuse"}];
    }
    function test_installAndOfflineReuse(data) {
        var subject = create(data.command);
        subject.prepareCli();
        verify(subject.cliSetupBusy);
        subject.prepareCli();
        tryCompare(subject, "refreshes", 1);
        compare(subject.config.commandPath, "/home/test/.local/share/codexbar-plasma/cli/current/codexbar");
        compare(subject.accountsController.resets, 1);
        verify(!subject.cliSetupBusy);
        verify(!subject.config.cliAutomaticUpdates);
    }
    function test_repairedSelectedPathRefreshes() {
        var subject = create("/home/test/.local/share/codexbar-plasma/cli/current/codexbar");
        subject.prepareCli();
        tryCompare(subject, "refreshes", 1);
        compare(subject.accountsController.resets, 1);
        verify(!subject.cliSetupBusy);
    }
    function test_failuresPreserveSelectionAndAllowRetry_data() {
        return [{tag: "network", command: "network"}, {tag: "malformed", command: "malformed"},
                {tag: "nonzero exit", command: "failed-exit"}];
    }
    function test_failuresPreserveSelectionAndAllowRetry(data) {
        var subject = create(data.command);
        subject.prepareCli();
        tryCompare(subject, "cliSetupBusy", false);
        compare(subject.config.commandPath, data.command);
        compare(subject.refreshes, 0);
        compare(subject.accountsController.resets, 0);
        verify(subject.cliSetupStatus.length > 0);
        subject.prepareCli();
        verify(subject.cliSetupBusy);
        subject.controller.retire();
    }
    function test_timeoutAndLateReply() {
        var subject = create();
        subject.prepareCli();
        var source = subject.controller.activeSource;
        findChild(subject.controller, "managedCliDeadline").triggered();
        verify(!subject.cliSetupBusy);
        subject.controller.accept(source, {"exit code": 0, stdout: JSON.stringify({
            status: "installed", version: "0.77.0", path: "/home/test/.local/share/codexbar-plasma/cli/current/codexbar"})});
        compare(subject.config.commandPath, "codexbar");
        compare(subject.refreshes, 0);
        subject.prepareCli();
        tryCompare(subject, "refreshes", 1);
    }
    function test_changedCommandRetiresInstall() {
        var subject = create();
        subject.prepareCli();
        subject.config.commandPath = "/usr/bin/another-cli";
        verify(!subject.cliSetupBusy);
        compare(subject.cliSetupStatus, "");
        wait(350);
        compare(subject.config.commandPath, "/usr/bin/another-cli");
        compare(subject.refreshes, 0);
    }
    function test_onlyUnavailableEmptyIdleWidgetCanInstall_data() {
        return [{tag: "working CLI", missing: false, loading: false, providers: []},
                {tag: "refreshing", missing: true, loading: true, providers: []},
                {tag: "retained quotas", missing: true, loading: false, providers: [{provider: "claude"}]}];
    }
    function test_onlyUnavailableEmptyIdleWidgetCanInstall(data) {
        var subject = create();
        subject.commandPathFailed = data.missing;
        subject.loading = data.loading;
        subject.providers = data.providers;
        subject.prepareCli();
        verify(!subject.controller.busy);
        verify(!subject.cliSetupRequested);
    }
}
'''


class PopupCliSetupTests(unittest.TestCase):
    def test_installation_owner(self):
        surface = Surface("applet", ROOT)
        source = (ROOT / "contents/ui/main.qml").read_text()
        signature = re.search(r"function prepareCli\([^)]*\)", source).group(0)
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        properties = re.search(r"property bool cliSetupRequested:.*?onCommandPathChanged:[^\n]+", source, re.S)
        self.assertIsNotNone(properties)
        qml = qml.replace("SOURCE_SETUP_PROPERTIES", properties.group(0))
        qml = qml.replace("SOURCE_FUNCTION", signature + " {" + surface.function_body("prepareCli") + "}")
        qml = qml.replace("SOURCE_CONTROLLER", surface.id_block("managedCli")).replace(
            "Plasmoid.configuration", "configuration")
        with tempfile.TemporaryDirectory(prefix="codexbar-popup-cli-") as directory:
            path = Path(directory)
            script = path / "managed.py"
            script.write_text('''import json, sys, time
time.sleep(0.2)
command = sys.argv[sys.argv.index("--command") + 1]
reply = dict(status="ready" if command == "reuse" else "installed", version="0.77.0",
             path="/home/test/.local/share/codexbar-plasma/cli/current/codexbar")
print("invalid" if command == "malformed" else json.dumps(dict(status="network") if command == "network" else reply))
sys.exit(1 if command == "failed-exit" else 0)
''')
            fixture = path / "tst_setup.qml"
            fixture.write_text(qml.replace("FIXTURE_URL", script.as_uri()))
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            warnings = [line for line in output.splitlines() if "QWARN" in line
                        and "QProcess: Destroyed while process" not in line]
            self.assertEqual(warnings, [], output)
