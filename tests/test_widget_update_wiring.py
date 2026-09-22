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
                }
            }

            SOURCE_HANDLERS
        }
    }

    function test_recordedStatusReachesThePersistedConfiguration() {
        var applet = createTemporaryObject(harness, this);
        applet.onStatusRecorded("Up to date", "");
        compare(applet.plasmoid.configuration.widgetUpdateLastStatus, "Up to date");
        compare(applet.plasmoid.configuration.widgetUpdateLastError, "");
    }

    function test_recordedFailureKeepsBothHalvesOfTheResult() {
        var applet = createTemporaryObject(harness, this);
        applet.onStatusRecorded("Update failed", "checksum mismatch");
        compare(applet.plasmoid.configuration.widgetUpdateLastStatus, "Update failed");
        compare(applet.plasmoid.configuration.widgetUpdateLastError, "checksum mismatch");
    }

    function test_successfulCheckPersistsItsTimestamp() {
        var applet = createTemporaryObject(harness, this);
        applet.onCheckSucceeded(1758547200000);
        compare(applet.plasmoid.configuration.autoUpdateLastCheck, 1758547200000);
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
    def test_updater_results_reach_the_persisted_configuration(self):
        applet = Surface("applet", ROOT)
        source = applet.texts[ROOT / "contents/ui/main.qml"]
        handlers = []
        for name in HANDLERS:
            # Only the attached-object name is rewritten; the writes themselves
            # run exactly as main.qml declares them.
            handlers.append(handler_source(source, name).replace("Plasmoid.", "plasmoid."))
        qml = QML.replace("SOURCE_HANDLERS", "\n            ".join(handlers))
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
