"""Verify first-install confirmation from an actual offline CLI version probe."""

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
    name: "ManagedCliInstallConfirmation"
    when: windowShown
    width: 620
    height: 760
    visible: true

    function i18n(text, first, second) {
        return text.replace("%1", first === undefined ? "%1" : first)
                   .replace("%2", second === undefined ? "%2" : second);
    }
    function i18np(one, many, count) { return (count === 1 ? one : many).replace("%1", count); }

    function create(command) {
        var factory = Qt.createComponent("PAGE_URL");
        if (factory.status === Component.Error && /module "org\\.kde\\.[^"]+" is not installed/.test(factory.errorString())) {
            skip("Managed CLI settings need the optional KDE QML modules");
            return null;
        }
        compare(factory.status, Component.Ready, factory.errorString());
        var page = createTemporaryObject(factory, testCase, {
            width: testCase.width, height: testCase.height, cfg_commandPath: command
        });
        verify(page !== null);
        var managed = findChild(page, "managedCliController");
        // All managed actions are synthetic, including a mistakenly started install.
        managed.scriptUrl = "MANAGED_URL";
        tryVerify(function() { return managed.result.status === "absent" && !managed.busy; });
        tryVerify(function() { return findChild(page, "installManagedCliButton").enabled; });
        return page;
    }
    function test_firstClickConfirmsWithoutCheckingReleases() {
        var page = create("CLI_PATH"); if (!page) return;
        var release = findChild(page, "cliReleaseController");
        verify(!release.checked);
        findChild(page, "installManagedCliButton").clicked();
        verify(page.managedInstallConfirming);
        var label = findChild(page, "managedInstallConfirmLabel");
        verify(label.visible);
        verify(label.text.indexOf("0.73.0") >= 0);
        verify(label.text.indexOf("CLI_PATH") >= 0);
        verify(!findChild(page, "managedCliController").busy);
        verify(!release.checked);
        findChild(page, "cancelManagedInstallButton").clicked();
        verify(!label.visible);
    }
    function test_commandChangeClearsConfirmationAndReprobes() {
        var page = create("CLI_PATH"); if (!page) return;
        var button = findChild(page, "installManagedCliButton");
        button.clicked();
        verify(page.managedInstallConfirming);
        page.cfg_commandPath = "SECOND_CLI_PATH";
        verify(!page.managedInstallConfirming);
        verify(!button.enabled);
        tryVerify(function() { return button.enabled; });
        button.clicked();
        var label = findChild(page, "managedInstallConfirmLabel");
        verify(label.visible);
        verify(label.text.indexOf("0.72.0") >= 0);
        verify(label.text.indexOf("SECOND_CLI_PATH") >= 0);
        verify(!findChild(page, "cliReleaseController").checked);
    }
    function test_missingCliCanInstallAfterOfflineProbe() {
        var page = create("MISSING_CLI_PATH"); if (!page) return;
        findChild(page, "installManagedCliButton").clicked();
        verify(!page.managedInstallConfirming);
        var managed = findChild(page, "managedCliController");
        verify(managed.busy);
        compare(managed.activeAction, "install");
        tryVerify(function() { return !managed.busy; });
    }
}
'''


class ManagedCliInstallConfirmationTests(unittest.TestCase):
    def test_settings_with_offline_cli_fixtures(self):
        with tempfile.TemporaryDirectory(prefix="managed install 'test-") as temporary:
            directory = Path(temporary)
            for name, version in (("external-cli", "0.73.0"), ("second-cli", "0.72.0")):
                cli = directory / name
                cli.write_text('#!/bin/sh\nprintf "CodexBar ' + version + '\\n"\n')
                cli.chmod(0o700)
            helper = directory / "managed.py"
            helper.write_text('''import json, sys
print(json.dumps({"status": "absent" if "status" in sys.argv else "error"}))
''')
            qml = QML.replace("PAGE_URL", (ROOT / "contents/ui/configGeneral.qml").as_uri())
            qml = qml.replace("MANAGED_URL", helper.as_uri())
            qml = qml.replace("SECOND_CLI_PATH", str(directory / "second-cli"))
            qml = qml.replace("MISSING_CLI_PATH", str(directory / "missing-cli"))
            qml = qml.replace("CLI_PATH", str(directory / "external-cli"))
            fixture = directory / "tst_install.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software",
                     "XDG_DATA_HOME": str(directory / "data")},
                capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            if "SKIP" in output:
                if os.environ.get("QML_TEST_REQUIRE_NO_SKIPS") == "1":
                    self.fail(output)
                self.skipTest("Managed CLI settings need the optional KDE QML modules")
            self.assertNotIn("QWARN", output)


if __name__ == "__main__":
    unittest.main()
