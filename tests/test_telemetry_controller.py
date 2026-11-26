"""Exercise the telemetry controller with a recording curl and an isolated configuration."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

QML = '''import QtQuick
import QtTest

TestCase {
    name: "TelemetryController"

    Component {
        id: settingsComponent
        QtObject { property string telemetrySubmittedVersion: "" }
    }

    function test_onlyEligibleRefreshesSendBoundedReports() {
        const factory = Qt.createComponent("CONTROLLER_URL");
        if (factory.status === Component.Error && /module "org\\.kde\\.[^"]+" is not installed/.test(factory.errorString()))
            skip("TelemetryController needs the KDE plasma5support QML module");
        compare(factory.status, Component.Ready, factory.errorString());
        const settings = createTemporaryObject(settingsComponent, this);
        const subject = createTemporaryObject(factory, this, {
            configuration: settings,
            endpoint: "https://telemetry.example.test/v1/telemetry",
            widgetVersion: "0.2.58"
        });
        verify(subject !== null);
        verify(subject.available);

        subject.startAttempt(1);
        subject.consented = true;
        subject.finishAttempt(1, "success");
        subject.startAttempt(2);
        subject.consented = false;
        subject.consented = true;
        subject.finishAttempt(2, "success");

        subject.startAttempt(3);
        subject.startAttempt(4);
        subject.finishAttempt(3, "success");
        compare(settings.telemetrySubmittedVersion, "");
        subject.finishAttempt(4, "provider-specific error");
        subject.finishAttempt(4, "success");

        subject.endpoint = "https://telemetry.example.test/v1/telemetry?provider=example";
        verify(!subject.available);
        subject.startAttempt(5);
        subject.finishAttempt(5, "success");
        subject.endpoint = "https://telemetry.example.test/v1/telemetry";
        compare(settings.telemetrySubmittedVersion, "");

        subject.startAttempt(6);
        subject.finishAttempt(6, "success");
        compare(settings.telemetrySubmittedVersion, "0.2.58");
        tryCompare(subject, "sending", false);
        subject.startAttempt(7);
        subject.finishAttempt(7, "timeout");

        subject.widgetVersion = "0.2.59";
        subject.startAttempt(8);
        subject.finishAttempt(8, "timeout");
        compare(settings.telemetrySubmittedVersion, "0.2.59");
        tryCompare(subject, "sending", false);

        subject.widgetVersion = "0.2.58";
        subject.startAttempt(9);
        subject.finishAttempt(9, "success");
        compare(settings.telemetrySubmittedVersion, "0.2.59");
    }
}
'''

RECORDING_CURL = '''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

with Path(os.environ["CODEXBAR_TELEMETRY_TEST_CALLS"]).open("a") as calls:
    calls.write(json.dumps(sys.argv[1:]) + "\\n")
sys.exit(22)
'''


class TelemetryControllerTests(unittest.TestCase):
    def test_recording_curl_receives_only_the_approved_fields(self):
        with tempfile.TemporaryDirectory(prefix="codexbar-telemetry-") as temporary:
            directory = Path(temporary)
            curl = directory / "curl"
            curl.write_text(RECORDING_CURL)
            curl.chmod(0o700)
            calls = directory / "calls.jsonl"
            fixture = directory / "tst_telemetry.qml"
            controller = ROOT / "contents/ui/controllers/TelemetryController.qml"
            fixture.write_text(QML.replace("CONTROLLER_URL", controller.as_uri()))
            test = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={
                    **os.environ,
                    "CODEXBAR_TELEMETRY_TEST_CALLS": str(calls),
                    "PATH": f"{directory}{os.pathsep}{os.environ['PATH']}",
                    "QT_QPA_PLATFORM": "offscreen",
                    "QT_QUICK_BACKEND": "software",
                },
                capture_output=True, text=True, timeout=30,
            )
            output = test.stdout + test.stderr
            self.assertEqual(test.returncode, 0, output)
            if "SKIP" in output:
                self.assertNotEqual(os.environ.get("QML_TEST_REQUIRE_NO_SKIPS"), "1", output)
                self.skipTest("TelemetryController needs the KDE plasma5support QML module")
            self.assertNotIn("QWARN", output)
            self.assertTrue(calls.is_file(), output)
            requests = [json.loads(line) for line in calls.read_text().splitlines()]

        self.assertEqual(len(requests), 2)
        payloads = []
        for args in requests:
            self.assertEqual(args[:12], [
                "--disable", "--proto", "=https", "--no-location", "--max-time", "5", "--silent",
                "--output", "/dev/null", "--header", "Content-Type: application/json", "--data-raw",
            ])
            self.assertEqual(args[13:], ["--", "https://telemetry.example.test/v1/telemetry"])
            payloads.append(json.loads(args[12]))
        self.assertEqual(payloads, [
            {"schema": 1, "widget_version": "0.2.58", "outcome": "success"},
            {"schema": 1, "widget_version": "0.2.59", "outcome": "timeout"},
        ])


if __name__ == "__main__":
    unittest.main()
