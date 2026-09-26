"""Exercise the applet's hidden popup row adapters against a stand-in config."""

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

FUNCTIONS = ("popupUsageRows", "popupUsageRowHideable", "hidePopupUsageRow")

QML = '''import QtQuick
import QtTest
import "SOURCE_URL/PopupHiddenRows.js" as PopupHiddenRows
TestCase {
    name: "PopupHiddenRowsWiring"
    QtObject {
        id: hostConfiguration
        property string popupHiddenUsageRows: ""
    }
    QtObject {
        id: applet
        HIDDEN_ROWS_BINDING
        SOURCE_FUNCTIONS
    }
    function labels(rows) {
        return rows.map(function(row) { return row.label; });
    }
    // Hiding writes the stored choice, the binding reparses it, and only the
    // popup adapter for that provider drops the row.
    function test_hideWritesConfigurationAndFiltersOnlyThatProvider() {
        var codex = {provider: "codex", rows: [
            {lane: "primary", label: "Session"},
            {lane: "secondary", label: "Weekly"},
            {lane: "extra", windowId: "", label: "Unidentified"}
        ]};
        var claude = {provider: "claude", rows: [{lane: "secondary", label: "Weekly"}]};
        verify(applet.popupUsageRowHideable(codex.rows[1]));
        verify(!applet.popupUsageRowHideable(codex.rows[2]));
        applet.hidePopupUsageRow("codex", codex.rows[1]);
        applet.hidePopupUsageRow("codex", codex.rows[2]);
        compare(JSON.parse(hostConfiguration.popupHiddenUsageRows), [{provider: "codex", row: "secondary"}]);
        compare(labels(applet.popupUsageRows(codex)), ["Session", "Unidentified"]);
        compare(labels(applet.popupUsageRows(claude)), ["Weekly"]);
        compare(codex.rows.length, 3);
        compare(applet.popupUsageRows(null), []);
        hostConfiguration.popupHiddenUsageRows = "not json";
        compare(labels(applet.popupUsageRows(codex)), ["Session", "Weekly", "Unidentified"]);
    }
}
'''


class PopupHiddenRowsWiringTests(unittest.TestCase):
    def test_applet_adapters_store_and_filter_hidden_rows(self):
        surface = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = surface.texts[main]
        surface.texts = {main: source}
        binding = re.search(r"^\s*(readonly property var popupHiddenUsageRows:.*)$", source, re.M).group(1)
        functions = []
        for name in FUNCTIONS:
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + surface.function_body(name) + "}")
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("HIDDEN_ROWS_BINDING", binding)
        qml = qml.replace("SOURCE_FUNCTIONS", "\n        ".join(functions))
        qml = qml.replace("Plasmoid.configuration", "hostConfiguration")
        with tempfile.TemporaryDirectory(prefix="codexbar-hidden-rows-") as temporary:
            fixture = Path(temporary) / "tst_popup_hidden_rows_wiring.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_popup_provider_tab_renders_the_filtered_rows(self):
        # The provider tab is the only surface that drops hidden rows; the
        # panel, Overview and notifications keep reading the unfiltered rows.
        popup = Surface("applet", ROOT)
        popup.require("model: applet.popupUsageRows(applet.presentedProviderData)",
                      "the provider tab must render the hidden-row filter")
        popup.reject("presentedProviderData.rows : []",
                     "the provider tab must not bypass the hidden-row filter")


if __name__ == "__main__":
    unittest.main()
