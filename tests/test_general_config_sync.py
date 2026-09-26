"""General keeps the pending history range intact across runtime changes."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/lib"))
from qml_surfaces import Surface

QML = '''import QtQuick
import QtTest
import "SOURCE_URL/general/ConfigValueSync.js" as ConfigValueSync
TestCase {
    name: "GeneralHistoryRange"
    Component { id: harness; QtObject {
        CONFIG_PROPERTIES
        property int persistedCostHistoryDays: 30
        property string persistedCostHistoryPeriod: ""
        property string persistedCostHistoryMetric: "cost"
        property bool costHistoryRangeEditPending: false
        property bool costHistoryMetricEditPending: false
        property bool defaultsActionRequested: false
        SOURCE_HANDLERS
        SOURCE_FUNCTIONS
    }}
    function test_pendingRangeSurvivesExternalChangesAndApply() {
        var page = createTemporaryObject(harness, this);
        page.editCostHistoryDays(90);
        page.persistedCostHistoryPeriod = "month-to-date";
        compare(page.cfg_costHistoryDays, 90);
        compare(page.cfg_costHistoryPeriod, "");
        page.persistedCostHistoryDays = 90;
        verify(page.costHistoryRangeEditPending);
        compare(page.cfg_costHistoryPeriod, "");
        page.persistedCostHistoryPeriod = "";
        verify(!page.costHistoryRangeEditPending);
        page.saveConfig();
        page.persistedCostHistoryPeriod = "all";
        compare(page.cfg_costHistoryPeriod, "all");
        page.persistedCostHistoryDays = 7;
        compare(page.cfg_costHistoryDays, 7);
    }
    function test_defaultsKeepBothRangeFieldsPending() {
        var page = createTemporaryObject(harness, this);
        page.persistedCostHistoryDays = 90;
        page.persistedCostHistoryPeriod = "all";
        page.restoreUserDefaults();
        compare(page.cfg_costHistoryDays, 30);
        compare(page.cfg_costHistoryPeriod, "");
        verify(page.costHistoryRangeEditPending);
        page.persistedCostHistoryPeriod = "month-to-date";
        compare(page.cfg_costHistoryDays, 30);
        compare(page.cfg_costHistoryPeriod, "");
    }
}
'''


class GeneralConfigSyncTests(unittest.TestCase):
    def test_pending_history_range(self):
        source = (ROOT / "contents/ui/configGeneral.qml").read_text()
        surface = Surface("general", ROOT)
        functions = []
        for name in ("applyCostHistoryRangeTransition", "applyCostHistoryMetricTransition",
                     "editCostHistoryDays", "editCostHistoryMetric",
                     "syncCostHistoryRangeFromPersisted", "syncCostHistoryMetricFromPersisted",
                     "restoreUserDefaults", "saveConfig"):
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + surface.function_body(name) + "}")
        properties = []
        namespace = {"k": "http://www.kde.org/standards/kcfg/1.0"}
        for entry in ET.parse(ROOT / "contents/config/main.xml").findall(".//k:entry", namespace):
            name, kind = entry.get("name"), entry.get("type")
            if not re.search(r"\bproperty (?:alias|string|int|bool) cfg_" + name + r"\b", source):
                continue
            value = entry.findtext("k:default", default="", namespaces=namespace)
            literal = json.dumps(value) if kind == "String" else value.lower()
            qml_type = {"String": "string", "Int": "int", "Bool": "bool"}[kind]
            for suffix in ("", "Default"):
                properties.append(f"property {qml_type} cfg_{name}{suffix}: {literal}")
        handlers = re.findall(r"^    onPersistedCostHistory\w+Changed:.*$", source, re.MULTILINE)
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n".join(functions))
        qml = qml.replace("SOURCE_HANDLERS", "\n".join(handlers))
        qml = qml.replace("CONFIG_PROPERTIES", "\n".join(properties))
        with tempfile.TemporaryDirectory(prefix="codexbar-general-sync-") as temporary:
            fixture = Path(temporary) / "tst_general.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
