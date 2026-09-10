"""Exercise the production panel text fallback in Qt's event loop."""

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
import "SOURCE_URL/PanelProviders.js" as PanelProviders
import "SOURCE_URL/PanelRules.js" as PanelRules
import "SOURCE_URL/PanelTextFit.js" as PanelTextFit
TestCase {
    name: "PanelSelectionText"
    QtObject {
        id: applet
        property string panelProviderIDsRaw: ""
        property bool loading: false
        property string menuBarDisplayMode: "percent"
        property var panelVisibilityRules: PanelRules.normalizedRules("{}")
        property real panelClockMs: Date.now()
        function selectedCompactProvider() { return null; }
        function providerPresentation(item) { return item; }
        function panelDisplayRow(item, mode) { return null; }
        function i18n(text) { return text; }
        SOURCE_FUNCTIONS
    }
    function test_emptyRosterText_data() {
        return [
            {tag: "automatic-idle", selection: "", loading: false, expected: "CodexBar"},
            {tag: "automatic-loading", selection: "", loading: true, expected: "Loading"},
            {tag: "none-idle", selection: "__none__", loading: false, expected: ""},
            {tag: "none-loading", selection: "__none__", loading: true, expected: ""},
            {tag: "unavailable-idle", selection: "unknown-provider", loading: false, expected: ""},
            {tag: "unavailable-loading", selection: "unknown-provider", loading: true, expected: ""}
        ];
    }
    function test_emptyRosterText(data) {
        applet.panelProviderIDsRaw = data.selection;
        applet.loading = data.loading;
        compare(applet.compactText(), data.expected);
    }
}
'''


class PanelSelectionTests(unittest.TestCase):
    def test_production_text_distinguishes_automatic_and_explicit_empty_rosters(self):
        surface = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = surface.texts[main]
        surface.texts = {main: source}
        # The fallback lives in the segment builder now; compactText() only
        # joins what survives, so the surface needs both halves.
        functions = []
        for name in ("compactTextSegments", "compactText"):
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + surface.function_body(name) + "}")
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n        ".join(functions))
        with tempfile.TemporaryDirectory(prefix="codexbar-panel-selection-") as temporary:
            fixture = Path(temporary) / "tst_panel_selection.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
