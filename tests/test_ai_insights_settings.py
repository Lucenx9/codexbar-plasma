"""Run the AI Insights settings page's helper-process functions with stubs.

The production retire/run/accept/report functions and the endpoint handler are
copied from configAiInsights.qml into a QtTest, with the executable source,
deadline, and model field replaced by recorders, so the page's reply handling
runs without the KDE settings runtime.
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

QML = '''import QtQuick
import QtQuick.Controls
import QtTest
import "SOURCE_URL/AiInsights.js" as AiInsights
import "SOURCE_URL/CommandLedger.js" as CommandLedger
TestCase {
    id: page
    name: "AiInsightsSettings"
    property string cfg_aiInsightsOllamaEndpoint: "http://localhost:11434"
    property string cfg_aiInsightsModel: "qwen3:4b"
    property bool cfg_aiInsightsOpenRouterZdr: true
    readonly property string provider: "ollama"
    readonly property string providerName: "Ollama"
    readonly property url scriptUrl: "file:///opt/codexbar-plasma/scripts/ai-insights.py"
    property var availableModels: []
    property string keyStatus: ""
    property string actionText: ""
    property bool actionFailed: false
    property string activeSource: ""
    property string activeAction: ""
    property int commandSerial: 0
    readonly property bool busy: activeSource.length > 0
    onCfg_aiInsightsOllamaEndpointChanged: { ENDPOINT_HANDLER }

    QtObject {
        id: helperSource
        property var connected: []
        property var disconnected: []
        function connectSource(source) { connected = connected.concat([source]) }
        function disconnectSource(source) { disconnected = disconnected.concat([source]) }
    }
    QtObject {
        id: actionDeadline
        property int interval: 0
        function restart() {}
        function stop() {}
    }
    QtObject {
        id: messages
        function errorText(reason, provider) { return "error:" + reason }
    }
    // A real editable combo: replacing its model resets the edit text, which
    // the page writes back to the model setting, as in the settings dialog.
    ComboBox {
        id: modelCombo
        editable: true
        model: page.availableModels
        onEditTextChanged: {
            var value = editText.trim()
            if (value !== page.cfg_aiInsightsModel) {
                page.cfg_aiInsightsModel = value
            }
        }
    }

    SOURCE_FUNCTIONS
    function refreshKeyStatus() {}
    function i18n(text, first) { return String(text).replace("%1", first) }
    function i18np(singular, plural, count) { return (count === 1 ? singular : plural).replace("%1", count) }

    readonly property string listed: JSON.stringify({status: "ok", key: "none", models: [{id: "qwen3:4b"}]})

    function init() {
        cfg_aiInsightsOllamaEndpoint = "http://localhost:11434"
        retire()
        report("", false)
        availableModels = []
        cfg_aiInsightsModel = "qwen3:4b"
        modelCombo.editText = cfg_aiInsightsModel
        helperSource.connected = []
        helperSource.disconnected = []
    }

    function test_replyReportsTheTestedAddress() {
        verify(run("models"))
        accept(helperSource.connected[0], {stdout: listed})
        verify(actionText.indexOf("Connection works") === 0, actionText)
        compare(availableModels, ["qwen3:4b"])
    }

    // A late listing from the previous address must not claim that the new,
    // untested address works or fill the model list from another server.
    function test_endpointChangeRetiresTheRunningTest() {
        verify(run("models"))
        var source = helperSource.connected[0]
        cfg_aiInsightsOllamaEndpoint = "https://ollama.example.net"
        verify(!busy)
        verify(helperSource.disconnected.indexOf(source) >= 0)
        accept(source, {stdout: listed})
        compare(actionText, "")
        compare(availableModels, [])
    }

    // A finished result describes the address it tested, not an edited one.
    function test_endpointChangeClearsTheFinishedResult() {
        verify(run("models"))
        accept(helperSource.connected[0], {stdout: listed})
        verify(actionText.length > 0)
        compare(availableModels, ["qwen3:4b"])
        compare(modelCombo.editText, "qwen3:4b")
        cfg_aiInsightsOllamaEndpoint = "http://127.0.0.1:11434"
        compare(actionText, "")
        compare(availableModels, [])
        compare(modelCombo.editText, "qwen3:4b")
    }

    // Clearing the listed models resets the editable combo; the chosen model
    // belongs to the settings, not to the tested address, and must survive.
    function test_endpointChangeKeepsTheChosenModel() {
        verify(run("models"))
        accept(helperSource.connected[0], {stdout: listed})
        compare(modelCombo.editText, "qwen3:4b")
        cfg_aiInsightsOllamaEndpoint = "http://127.0.0.1:11434"
        compare(availableModels, [])
        compare(cfg_aiInsightsModel, "qwen3:4b")
        compare(modelCombo.editText, "qwen3:4b")
    }
}
'''


class AiInsightsSettingsTests(unittest.TestCase):
    def test_helper_replies_follow_the_tested_endpoint(self):
        insights = Surface("insights", ROOT)
        source = (ROOT / "contents/ui/configAiInsights.qml").read_text()
        functions = []
        for name in ("retire", "run", "report", "accept"):
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + insights.function_body(name) + "}")
        # An absent handler leaves the harness without one, so the behavior,
        # not the handler's existence, decides the result.
        try:
            handler = insights.handler_body("onCfg_aiInsightsOllamaEndpointChanged")
        except AssertionError:
            handler = ""
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("ENDPOINT_HANDLER", handler)
        qml = qml.replace("SOURCE_FUNCTIONS", "\n".join(functions))
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / "tst_ai_insights_settings.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("Totals: 6 passed, 0 failed", output)


if __name__ == "__main__":
    unittest.main()
