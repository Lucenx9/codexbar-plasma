"""Settings provider lists accept only successful CLI processes."""

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
    name: "ProviderRosterExit"
    function i18n(text, value) {
        return value === undefined ? text : text.replace("%1", value);
    }
    function test_processResult_data() {
        return [
            {tag: "success", script: "success", error: "", count: 1},
            {tag: "failed-json", script: "failed-json", error: "codexbar exited with code 7", count: 0},
            {tag: "failed-empty", script: "failed-empty", error: "codexbar exited with code 7", count: 0},
            {tag: "failed-stderr", script: "failed-stderr", error: "Synthetic failure", count: 0},
            {tag: "failed-envelope", script: "failed-envelope", error: "Synthetic structured failure", count: 0}
        ];
    }
    function test_processResult(data) {
        var factory = Qt.createComponent("CONTROLLER_URL");
        if (factory.status === Component.Error && /module "org\\.kde\\.[^"]+" is not installed/.test(factory.errorString()))
            skip("Provider roster exit checks need the optional KDE QML modules");
        compare(factory.status, Component.Ready, factory.errorString());
        var subject = createTemporaryObject(factory, testCase, {
            active: true, commandPath: "FIXTURE_PATH/" + data.script
        });
        verify(subject !== null);
        tryVerify(function() {
            return subject.commandRunSerial > 0 && !subject.providerRosterLoading
                && !subject.hasPendingProviderRosterCommands();
        }, 10000);
        compare(subject.enabledProviderRoster.length, data.count);
        compare(subject.providerRosterError, data.error);
        if (data.count > 0)
            compare(subject.enabledProviderRoster[0].provider, "codex");
    }
}
'''


class ProviderRosterExitTests(unittest.TestCase):
    def test_production_datasource_checks_process_exit(self):
        with tempfile.TemporaryDirectory(prefix="codexbar-roster-exit-") as temporary:
            directory = Path(temporary)
            record = '\'{"provider":"codex","enabled":true}\''
            scripts = {
                "success": f"printf '%s\\n' {record}\nexit 0\n",
                "failed-json": f"printf '%s\\n' {record}\nexit 7\n",
                "failed-empty": "exit 7\n",
                "failed-stderr": f"printf '%s\\n' {record}\nprintf '%s\\n' 'Synthetic failure' >&2\nexit 7\n",
                "failed-envelope": "printf '%s\\n' '{\"error\":{\"message\":\"Synthetic structured failure\"}}'\nexit 7\n",
            }
            for name, body in scripts.items():
                script = directory / name
                script.write_text("#!/bin/sh\n" + body)
                script.chmod(0o700)
            fixture = directory / "tst_roster.qml"
            fixture.write_text(QML.replace("CONTROLLER_URL", (
                ROOT / "contents/ui/controllers/ProviderRosterController.qml").as_uri()
            ).replace("FIXTURE_PATH", str(directory)))
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"),
                 "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=70)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            if "SKIP" in result.stdout:
                if os.environ.get("QML_TEST_REQUIRE_NO_SKIPS") == "1":
                    self.fail("Provider roster exit checks require the KDE QML modules")
                self.skipTest("Provider roster exit checks need the optional KDE QML modules")


if __name__ == "__main__":
    unittest.main()
