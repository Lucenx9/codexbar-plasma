"""Settings pages follow hidden rows and sections the popup changes while they are open."""

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
import "SOURCE_URL/general/ConfigValueSync.js" as ConfigValueSync
import "SOURCE_URL/PopupHiddenRows.js" as PopupHiddenRows
import "SOURCE_URL/PopupHiddenSections.js" as PopupHiddenSections
TestCase {
    name: "HiddenPopupItemsSync"
    readonly property string rowA: JSON.stringify([{provider: "codex", row: "primary"}])
    readonly property string rowsAB: JSON.stringify([{provider: "codex", row: "primary"},
        {provider: "codex", row: "secondary"}])
    readonly property string rowsABC: JSON.stringify([{provider: "codex", row: "primary"},
        {provider: "codex", row: "secondary"}, {provider: "claude", row: "primary"}])
    readonly property string rowsBC: JSON.stringify([{provider: "codex", row: "secondary"},
        {provider: "claude", row: "primary"}])
    readonly property string sectionA: "v1:" + "a".repeat(32)
    readonly property string sectionB: "v1:" + "b".repeat(32)
    Component { id: harness; QtObject {
        property string cfg_popupHiddenUsageRows: ""
        property string cfg_popupHiddenUsageRowsDefault: ""
        property string cfg_popupHiddenDetailSections: ""
        property string cfg_popupHiddenDetailSectionsDefault: ""
        property string persistedPopupHiddenUsageRows: ""
        property string persistedPopupHiddenDetailSections: ""
        property string hiddenUsageRowsBase: ""
        property string hiddenDetailSectionsBase: ""
        readonly property var hiddenUsageRows: PopupHiddenRows.parse(cfg_popupHiddenUsageRows)
        readonly property var hiddenDetailSections: PopupHiddenSections.parse(cfg_popupHiddenDetailSections)
        SOURCE_HANDLERS
        SOURCE_FUNCTIONS
    }}
    function opened(rows, sections) {
        // Plasma injects the stored values when it builds the page.
        var page = createTemporaryObject(harness, this, {
            cfg_popupHiddenUsageRows: rows, persistedPopupHiddenUsageRows: rows,
            cfg_popupHiddenDetailSections: sections, persistedPopupHiddenDetailSections: sections,
            hiddenUsageRowsBase: rows, hiddenDetailSectionsBase: sections });
        verify(page !== null);
        return page;
    }
    function sections(keys) {
        return JSON.stringify(keys.map(function(key) { return {provider: "codex", section: key}; }));
    }
    function test_applyKeepsRowsThePopupChangedMeanwhile() {
        var page = opened(rowA, "");
        page.persistedPopupHiddenUsageRows = rowsAB;
        compare(page.cfg_popupHiddenUsageRows, rowsAB);
        page.persistedPopupHiddenUsageRows = "";
        compare(page.cfg_popupHiddenUsageRows, "");
    }
    function test_pendingRestoreSurvivesPopupChangesAndApply() {
        var page = opened(rowsAB, "");
        RESTORE_ROW
        page.persistedPopupHiddenUsageRows = rowsABC;
        compare(page.cfg_popupHiddenUsageRows, rowsBC);
        // Plasma writes the page's value on Apply.
        page.persistedPopupHiddenUsageRows = page.cfg_popupHiddenUsageRows;
        compare(page.cfg_popupHiddenUsageRows, rowsBC);
    }
    function test_sectionsFollowThePopupAndKeepPendingRestores() {
        var page = opened("", sections([sectionA]));
        page.persistedPopupHiddenDetailSections = sections([sectionA, sectionB]);
        compare(page.cfg_popupHiddenDetailSections, sections([sectionA, sectionB]));
        RESTORE_SECTIONS
        page.persistedPopupHiddenDetailSections = sections([sectionA, sectionB]);
        compare(page.cfg_popupHiddenDetailSections, "");
    }
}
'''

PAGES = {
    "popup": {
        "file": "contents/ui/configPopup.qml",
        "functions": ("syncHiddenUsageRowsFromPersisted", "syncHiddenDetailSectionsFromPersisted",
                      "restoreHiddenUsageRow", "restoreProviderDetailSections"),
        "restore_row": 'page.restoreHiddenUsageRow({provider: "codex", row: "primary"});',
        "restore_sections": 'page.restoreProviderDetailSections("codex");',
    },
    "general": {
        "file": "contents/ui/configGeneral.qml",
        "functions": ("syncHiddenUsageRowsFromPersisted", "syncHiddenDetailSectionsFromPersisted"),
        # General restores hidden items only through its defaults action.
        "restore_row": ('page.cfg_popupHiddenUsageRows = JSON.stringify('
                        '[{provider: "codex", row: "secondary"}]);'),
        "restore_sections": 'page.cfg_popupHiddenDetailSections = "";',
    },
}


class HiddenPopupItemsSyncTests(unittest.TestCase):
    def run_page(self, name):
        page = PAGES[name]
        source = (ROOT / page["file"]).read_text()
        surface = Surface(name, ROOT)
        functions = []
        for function in page["functions"]:
            signature = re.search(r"function " + function + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + surface.function_body(function) + "}")
        handlers = re.findall(r"^    onPersistedPopupHidden\w+Changed:.*$", source, re.MULTILINE)
        self.assertEqual(len(handlers), 2)
        qml = (QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
               .replace("SOURCE_FUNCTIONS", "\n".join(functions))
               .replace("SOURCE_HANDLERS", "\n".join(handlers))
               .replace("RESTORE_ROW", page["restore_row"])
               .replace("RESTORE_SECTIONS", page["restore_sections"]))
        with tempfile.TemporaryDirectory(prefix="codexbar-hidden-sync-") as temporary:
            fixture = Path(temporary) / "tst_hidden_sync.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("SKIP", output)

    def test_popup_page(self):
        self.run_page("popup")

    def test_general_page(self):
        self.run_page("general")

    def test_pages_start_from_the_values_plasma_injected(self):
        for name in PAGES:
            source = (ROOT / PAGES[name]["file"]).read_text()
            completed = re.search(r"^    Component\.onCompleted: \{\n(.*?)\n    \}", source,
                                  re.MULTILINE | re.DOTALL).group(1)
            with self.subTest(page=name):
                self.assertIn("hiddenUsageRowsBase = persistedPopupHiddenUsageRows", completed)
                self.assertIn("hiddenDetailSectionsBase = persistedPopupHiddenDetailSections", completed)


if __name__ == "__main__":
    unittest.main()
