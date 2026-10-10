"""Execute main.qml's updater handlers against a fake plasmoid configuration.

The applet persists the updater's last status, error, and check time through
`Plasmoid.configuration`. Nothing else re-reads those keys at runtime, so a
handler that silently stopped writing them would leave the Updates page showing
a stale result forever. These tests run the real handler bodies rather than
asserting their spelling, so reformatting main.qml cannot break them.
"""

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

# Handlers written as `on<Signal>: function (args) { ... }`. `Surface.handler_body`
# only matches the braced `name: {` form, so these are located here instead.
HANDLERS = ("onStatusRecorded", "onCheckSucceeded")

QML = '''import QtQuick
import QtTest
import "UPDATE_LOGIC_URL" as UpdateLogic
TestCase {
    name: "WidgetUpdateWiring"
    Component {
        id: harness
        QtObject {
            id: root
            // Stands in for the applet's `Plasmoid` attached object. The
            // extracted bodies are rewritten to read `plasmoid` because a QML
            // id cannot start with a capital letter.
            property QtObject plasmoid: QtObject {
                property QtObject configuration: QtObject {
                    property string widgetUpdateLastStatus: "stale status"
                    property string widgetUpdateLastError: "stale error"
                    property double autoUpdateLastCheck: -1
                    property string widgetUpdateAvailableVersion: "stale version"
                    property string widgetUpdateRequest: ""
                }
            }
            readonly property string widgetUpdateRequest: plasmoid.configuration.widgetUpdateRequest
            property string installedWidgetVersion: "0.2.47"
            // Stands in for the applet's WidgetUpdateController.
            property QtObject widgetUpdater: QtObject {
                property bool busy: false
                property bool startable: true
                property var runs: []
                function runNow(install) {
                    runs = runs.concat([install]);
                    busy = startable;
                }
            }

            SOURCE_HANDLERS
        }
    }

    function test_recordedStatusReachesThePersistedConfiguration() {
        var applet = createTemporaryObject(harness, this);
        applet.onStatusRecorded("Up to date", "", "");
        compare(applet.plasmoid.configuration.widgetUpdateLastStatus, "Up to date");
        compare(applet.plasmoid.configuration.widgetUpdateLastError, "");
        compare(applet.plasmoid.configuration.widgetUpdateAvailableVersion, "");
    }

    function test_recordedFailureKeepsBothHalvesOfTheResult() {
        var applet = createTemporaryObject(harness, this);
        applet.onStatusRecorded("Update failed", "checksum mismatch", "2.0");
        compare(applet.plasmoid.configuration.widgetUpdateLastStatus, "Update failed");
        compare(applet.plasmoid.configuration.widgetUpdateLastError, "checksum mismatch");
        compare(applet.plasmoid.configuration.widgetUpdateAvailableVersion, "2.0");
    }

    function test_successfulCheckPersistsItsTimestamp() {
        var applet = createTemporaryObject(harness, this);
        applet.onCheckSucceeded(1758547200000);
        compare(applet.plasmoid.configuration.autoUpdateLastCheck, 1758547200000);
    }

    // Settings only write a request; the applet runs it and clears it when done.
    function test_settingsRequestRunsOnceAndClearsWhenFinished() {
        var applet = createTemporaryObject(harness, this);
        var config = applet.plasmoid.configuration;
        config.widgetUpdateRequest = "install";
        applet.serviceWidgetUpdateRequest();
        compare(applet.widgetUpdater.runs, [true]);
        compare(config.widgetUpdateRequest, "running:install");
        applet.serviceWidgetUpdateRequest();
        compare(applet.widgetUpdater.runs.length, 1);
        applet.widgetUpdater.busy = false;
        applet.serviceWidgetUpdateRequest();
        compare(config.widgetUpdateRequest, "");
        compare(applet.widgetUpdater.runs.length, 1);
    }

    function test_requestWaitsForAnAutomaticRun() {
        var applet = createTemporaryObject(harness, this);
        applet.widgetUpdater.busy = true;
        applet.plasmoid.configuration.widgetUpdateRequest = "check";
        applet.serviceWidgetUpdateRequest();
        compare(applet.widgetUpdater.runs.length, 0);
        compare(applet.plasmoid.configuration.widgetUpdateRequest, "check");
        applet.widgetUpdater.busy = false;
        applet.serviceWidgetUpdateRequest();
        compare(applet.widgetUpdater.runs, [false]);
    }

    // Upgrading another way must not leave an Install button for that release.
    function test_startupForgetsAReleaseThatIsAlreadyInstalled_data() {
        return [{tag: "installed", persisted: "0.2.47", expected: ""},
                {tag: "older", persisted: "0.2.46", expected: ""},
                {tag: "newer", persisted: "0.2.48", expected: "0.2.48"},
                {tag: "none", persisted: "", expected: ""}];
    }
    function test_startupForgetsAReleaseThatIsAlreadyInstalled(data) {
        var applet = createTemporaryObject(harness, this);
        applet.plasmoid.configuration.widgetUpdateAvailableVersion = data.persisted;
        applet.forgetInstalledWidgetUpdate();
        compare(applet.plasmoid.configuration.widgetUpdateAvailableVersion, data.expected);
        compare(applet.restoredWidgetUpdateVersion(), data.expected);
    }

    function test_staleOrInvalidRequestsAreClearedWithoutRunning_data() {
        return [{tag: "stale-marker", request: "running:install", startable: true},
                {tag: "junk", request: "rm -rf ~", startable: true},
                {tag: "not-started", request: "install", startable: false}];
    }
    function test_staleOrInvalidRequestsAreClearedWithoutRunning(data) {
        var applet = createTemporaryObject(harness, this);
        applet.widgetUpdater.startable = data.startable;
        applet.plasmoid.configuration.widgetUpdateRequest = data.request;
        applet.serviceWidgetUpdateRequest();
        compare(applet.plasmoid.configuration.widgetUpdateRequest, "");
        verify(!applet.widgetUpdater.busy);
    }
}
'''


def handler_source(text, name):
    """Return `function name(args) { body }` for a function-form QML handler.

    The signature is matched with tolerant whitespace so a reformat that writes
    `function (args)` instead of `function(args)` still resolves.
    """
    match = re.search(name + r":\s*function\s*\(([^)]*)\)\s*\{", text)
    assert match, f"no function-form handler named {name} in main.qml"
    depth = 1
    index = match.end()
    while index < len(text) and depth > 0:
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
        index += 1
    assert depth == 0, f"unterminated handler body for {name}"
    body = text[match.end():index - 1]
    return f"function {name}({match.group(1)}) {{{body}}}"


class WidgetUpdateWiringTests(unittest.TestCase):
    def test_notification_owner_is_wired_to_configuration_privacy_and_url_opening(self):
        surface = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = surface.texts[main]
        surface.texts = {main: source}
        block = surface.id_block("updateNotifications")
        for binding in ("configuration: Plasmoid.configuration",
                        "enableNotifications: root.enableNotifications",
                        "privacyMode: root.privacyMode", "Qt.openUrlExternally(url)"):
            self.assertIn(binding, block)
        self.assertIn("updateNotifications.notifyAvailableUpdate(version, url, releaseUrl)",
                      surface.function_body("notifyAvailableUpdate"))
        self.assertIn("updateNotifications.notifyInstalledUpdate(version)",
                      surface.function_body("notifyInstalledUpdate"))
        self.assertNotIn("property var pendingUpdateReleaseUrls", source)
        owner = (ROOT / "contents/ui/controllers/UpdateNotificationsController.qml").read_text()
        for forbidden in ("root.", "Plasmoid.", "Qt.openUrlExternally", "connectSource("):
            self.assertNotIn(forbidden, owner)
        logic = (ROOT / "contents/ui/UpdateNotificationState.js").read_text()
        for forbidden in ("i18n(", "Qt.", "configuration.", "dispatcher."):
            self.assertNotIn(forbidden, logic)

    def test_updater_results_reach_the_persisted_configuration(self):
        applet = Surface("applet", ROOT)
        source = applet.texts[ROOT / "contents/ui/main.qml"]
        handlers = []
        for name in HANDLERS:
            # Only the attached-object name is rewritten; the writes themselves
            # run exactly as main.qml declares them.
            handlers.append(handler_source(source, name).replace("Plasmoid.", "plasmoid."))
        handlers.append("function serviceWidgetUpdateRequest() {"
                        + applet.function_body("serviceWidgetUpdateRequest").replace("Plasmoid.", "plasmoid.")
                        + "}")
        for name in ("restoredWidgetUpdateVersion", "forgetInstalledWidgetUpdate"):
            handlers.append(f"function {name}() {{"
                            + applet.function_body(name).replace("Plasmoid.", "plasmoid.")
                            + "}")
        qml = (QML.replace("SOURCE_HANDLERS", "\n            ".join(handlers))
               .replace("UPDATE_LOGIC_URL", (ROOT / "contents/ui/UpdateLogic.js").as_uri()))
        with tempfile.TemporaryDirectory(prefix="codexbar-update-wiring-") as temporary:
            fixture = Path(temporary) / "tst_widget_update_wiring.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
