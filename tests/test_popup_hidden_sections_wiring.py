"""Exercise the applet's hidden popup section adapters against a stand-in config."""

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

FUNCTIONS = ("popupDetailSections", "hiddenPopupDetailSections", "popupDetailSectionHideable",
             "hidePopupDetailSection", "restorePopupDetailSection")

QML = '''import QtQuick
import QtTest
import "SOURCE_URL/PopupHiddenSections.js" as PopupHiddenSections
TestCase {
    name: "PopupHiddenSectionsWiring"
    QtObject {
        id: hostConfiguration
        property string popupHiddenDetailSections: ""
    }
    QtObject {
        id: applet
        HIDDEN_SECTIONS_BINDING
        SOURCE_FUNCTIONS
    }
    function test_hideRestoreWritesOnlyDisplayPreferences() {
        var section = {title: "Budgets", rows: [{value: "25"}]};
        var codex = {provider: "codex", providerDetails: [section]};
        var claude = {provider: "claude", providerDetails: [section]};
        verify(applet.popupDetailSectionHideable(section));
        verify(!applet.popupDetailSectionHideable({title: ""}));
        applet.hidePopupDetailSection("codex", section);
        verify(hostConfiguration.popupHiddenDetailSections.indexOf("Budgets") < 0);
        compare(applet.popupDetailSections(codex), []);
        compare(applet.hiddenPopupDetailSections(codex), [section]);
        compare(applet.popupDetailSections(claude), [section]);
        compare(codex.providerDetails, [section]);
        applet.restorePopupDetailSection("codex", section);
        compare(hostConfiguration.popupHiddenDetailSections, "");
        compare(applet.popupDetailSections(codex), [section]);
        compare(applet.hiddenPopupDetailSections(null), []);
        hostConfiguration.popupHiddenDetailSections = "not json";
        compare(applet.popupDetailSections(codex), [section]);
    }
}
'''


class PopupHiddenSectionsWiringTests(unittest.TestCase):
    def test_applet_adapters_store_and_filter_hidden_sections(self):
        surface = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = surface.texts[main]
        surface.texts = {main: source}
        binding = re.search(r"^\s*(readonly property var popupHiddenDetailSections:.*)$", source, re.M).group(1)
        functions = []
        for name in FUNCTIONS:
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + surface.function_body(name) + "}")
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("HIDDEN_SECTIONS_BINDING", binding)
        qml = qml.replace("SOURCE_FUNCTIONS", "\n        ".join(functions))
        qml = qml.replace("Plasmoid.configuration", "hostConfiguration")
        with tempfile.TemporaryDirectory(prefix="codexbar-hidden-sections-") as temporary:
            fixture = Path(temporary) / "tst_popup_hidden_sections_wiring.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_popup_filters_presented_sections_and_keeps_restore_accessible(self):
        popup = Surface("applet", ROOT)
        popup.require("applet.popupDetailSections(applet.presentedProviderData)",
                      "filter only privacy-projected popup detail sections")
        popup.require("applet.hiddenPopupDetailSections(applet.presentedProviderData)",
                      "restore titles must come from privacy-projected current sections")
        popup.require("details.length > 0 || hiddenDetails.length > 0",
                      "all-hidden sections must keep the restore disclosure accessible")


if __name__ == "__main__":
    unittest.main()
