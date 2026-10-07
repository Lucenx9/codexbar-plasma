"""Exercise update policy through the real dispatcher with synthetic notifications."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
QML = '''import QtQuick
import QtTest
import "SOURCE_URL/controllers" as Controllers
TestCase {
    id: testCase
    name: "UpdateNotificationTransport"
    property var opened: []
    function i18n(text) {
        for (var i = 1; i < arguments.length; i++) text = text.replace("%" + i, arguments[i]);
        return text;
    }
    QtObject {
        id: configuration
        property bool updateNotificationsEnabled: true
        property bool cliUpdateNotificationsEnabled: true
        property string lastNotifiedUpdateVersion: ""
        property string cliUpdateLastNotifiedVersion: ""
    }
    Controllers.UpdateNotificationsController {
        id: subject
        configuration: configuration
        onReleasePageRequested: function(url) {
            testCase.opened = testCase.opened.concat([url]);
        }
    }
    function test_mixedUpdatesActivateThroughTheProductionTransport() {
        subject.notifyAvailableUpdate("v1", "", "https://github.com/Lucenx9/codexbar-plasma/releases/tag/v1");
        subject.privacyMode = true;
        subject.notifyAvailableCliUpdate("v2", "https://github.com/steipete/CodexBar/releases/tag/v2");
        compare(configuration.lastNotifiedUpdateVersion, "v1");
        compare(configuration.cliUpdateLastNotifiedVersion, "v2");
        tryCompare(testCase, "opened", [
            "https://github.com/Lucenx9/codexbar-plasma/releases/tag/v1",
            "https://github.com/steipete/CodexBar/releases/tag/v2"
        ].sort(), 5000);
        compare(subject.pendingUpdateReleaseUrls, ({}));
        subject.notifyAvailableUpdate("v1", "", "");
        subject.notifyAvailableCliUpdate("v2", "");
        wait(200);
        compare(opened.length, 2);
    }
}
'''


class UpdateNotificationTransportTests(unittest.TestCase):
    def test_mixed_updates_use_real_dispatch_and_privacy(self):
        with tempfile.TemporaryDirectory(prefix="codexbar-update-transport-") as directory:
            temporary = Path(directory)
            executable = temporary / "notify-send"
            executable.write_text('''#!/bin/sh
if [ "$1" = --help ]; then
    printf '%s\\n' --action
    exit 0
fi
printf '%s\\n' "$@" >> "$UPDATE_NOTIFICATION_TEST_LOG"
sleep 0.2
printf '%s\\n' default
''')
            executable.chmod(0o700)
            fixture = temporary / "tst_update_notification_transport.qml"
            # Separate processes may complete in either order.
            qml = QML.replace("testCase.opened.concat([url])", "testCase.opened.concat([url]).sort()")
            fixture.write_text(qml.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri()))
            log = temporary / "arguments"
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"),
                 "-input", str(fixture)],
                env={**os.environ, "PATH": str(temporary) + os.pathsep + os.environ["PATH"],
                     "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software",
                     "UPDATE_NOTIFICATION_TEST_LOG": str(log)},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            arguments = log.read_text()
            self.assertIn("CodexBar widget update available", arguments)
            self.assertIn("Version v1 is available.", arguments)
            self.assertIn("Usage or status changed. Open CodexBar for details.", arguments)
            self.assertNotIn("Upstream CLI v2", arguments)
            self.assertEqual(arguments.count("default=Open release page"), 2)
