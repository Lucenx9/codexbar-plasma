"""Run the AI Insights settings page's helper-process functions with stubs.

The production retire/run/accept/report functions and the endpoint handler are
copied from configAiInsights.qml into a QtTest, with the executable source,
deadline, and model field replaced by recorders, so the page's reply handling
runs without the KDE settings runtime. A second harness mirrors the Clear
button's enabled binding with a stubbed configuration and runs the page's
cache re-arm handler, so the button must enable again when a new insight is
stored after a clear. A third harness instantiates the page's creation path
with stored values as creation properties, the way the KCM dialog injects
them, with a real editable combo, so opening settings must keep the stored
model instead of wiping it through a model-list reset, and must offer it as
the initial picker entry.
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

    // A test reads the wallet, so it corrects a status lookup that failed,
    // while an Ollama listing, which reads no key, leaves the status alone.
    function test_connectionTestUpdatesTheKeyStatus() {
        var replies = [
            [JSON.stringify({status: "ok", key: "valid", models: []}), "present"],
            [JSON.stringify({status: "error", reason: "missing_key"}), "absent"],
            [JSON.stringify({status: "error", reason: "secret_unavailable"}), "unavailable"],
            [JSON.stringify({status: "error", reason: "network"}), "unavailable"],
            [listed, "unavailable"]
        ]
        for (var i = 0; i < replies.length; i++) {
            keyStatus = "unavailable"
            verify(run("models"))
            accept(helperSource.connected[helperSource.connected.length - 1], {stdout: replies[i][0]})
            compare(keyStatus, replies[i][1], replies[i][0])
        }
        keyStatus = ""
    }

    // A listing stopped by the shell bound reports a timeout, not a format error.
    function test_stoppedListingReportsTimeout() {
        verify(run("models"))
        accept(helperSource.connected[0], {stdout: "", "exit code": 124})
        compare(actionText, "error:timeout")
        compare(availableModels, [])
    }
}
'''


CLEAR_QML = '''import QtQuick
import QtTest
TestCase {
    id: page
    name: "AiInsightsClearButton"
    property bool cacheCleared: false
    readonly property bool cacheStored: String(configuration.aiInsightsCache || "").length > 0
    readonly property bool clearEnabled: cacheStored && !cacheCleared
    onCacheStoredChanged: { RESET_HANDLER }

    QtObject {
        id: configuration
        property string aiInsightsCache: ""
    }

    function pressClear() {
        configuration.aiInsightsCache = ""
        cacheCleared = true
    }

    function test_clearRearmsWhenANewInsightArrives() {
        configuration.aiInsightsCache = "insight-1"
        verify(clearEnabled)
        pressClear()
        verify(!clearEnabled)
        configuration.aiInsightsCache = "insight-2"
        verify(clearEnabled, "Clear stays disabled after a new insight arrives")
    }
}
'''


CREATION_QML = '''import QtQuick
import QtQuick.Controls
import QtTest
import "SOURCE_URL/AiInsights.js" as AiInsights
TestCase {
    id: test
    name: "AiInsightsCreationKeepsModel"
    when: windowShown
    // The KCM dialog injects stored values as creation properties, which
    // notifies derived properties such as provider during instantiation,
    // even when the stored value equals the QML default.
    Component {
        id: pageFactory
        Item {
            id: page
            property string cfg_aiInsightsProvider: "ollama"
            property string cfg_aiInsightsModel: ""
            property alias cfg_aiInsightsOllamaEndpoint: endpointField.text
            readonly property string provider: AiInsights.safeProvider(cfg_aiInsightsProvider)
            property var availableModels: []
            property var modelsByProvider: ({})
            property string keyStatus: ""
            property string actionText: ""
            property string activeSource: ""
            property string activeAction: ""
            property alias combo: modelCombo
            onCfg_aiInsightsModelChanged: { MODEL_HANDLER }
            onProviderChanged: { PROVIDER_HANDLER }
            Component.onCompleted: { COMPLETED_HANDLER }

            QtObject {
                id: helperSource
                function disconnectSource(source) {}
            }
            QtObject {
                id: actionDeadline
                function stop() {}
            }
            TextField {
                id: endpointField
            }
            // A real editable combo: resetting its model resets the edit
            // text, which the page must not mistake for a user edit.
            ComboBox {
                id: modelCombo
                editable: true
                model: page.availableModels
                onEditTextChanged: { EDIT_HANDLER }
                onActivated: { ACTIVATED_HANDLER }
            }

            SOURCE_FUNCTIONS
            function refreshKeyStatus() {}
        }
    }

    // Typing with the field focused is user intent and must reach the
    // setting. Runs synchronously: no event-loop pump before the compare,
    // so deferred control polish cannot interleave with the focused edit.
    function test_focusedTypingWritesBack() {
        var page = pageFactory.createObject(test, {
            cfg_aiInsightsProvider: "ollama",
            cfg_aiInsightsModel: "",
            cfg_aiInsightsOllamaEndpoint: "http://localhost:11434"
        })
        verify(page !== null)
        page.combo.forceActiveFocus()
        verify(page.combo.activeFocus)
        page.combo.editText = "llama3.2:3b"
        compare(page.cfg_aiInsightsModel, "llama3.2:3b")
        page.destroy()
    }

    // A control-driven reset without focus must restore the setting
    // instead of adopting the reset.
    function test_unfocusedResetRestores() {
        var page = pageFactory.createObject(test, {
            cfg_aiInsightsProvider: "ollama",
            cfg_aiInsightsModel: "qwen3:4b",
            cfg_aiInsightsOllamaEndpoint: "http://localhost:11434"
        })
        verify(page !== null)
        verify(!page.combo.activeFocus)
        page.combo.editText = ""
        compare(page.combo.editText, "qwen3:4b")
        compare(page.cfg_aiInsightsModel, "qwen3:4b")
        page.destroy()
    }

    // Opening settings with a stored local model must show it, not an empty
    // field that would persist the wipe on Apply. The stored model also seeds
    // the picker menu, which stays settled past deferred control polish.
    function test_openWithStoredLocalModelKeepsIt() {
        var page = pageFactory.createObject(test, {
            cfg_aiInsightsProvider: "ollama",
            cfg_aiInsightsModel: "qwen3:4b",
            cfg_aiInsightsOllamaEndpoint: "http://localhost:11434"
        })
        verify(page !== null)
        compare(page.cfg_aiInsightsModel, "qwen3:4b")
        compare(page.combo.editText, "qwen3:4b")
        compare(page.availableModels, ["qwen3:4b"])
        wait(250)
        compare(page.cfg_aiInsightsModel, "qwen3:4b")
        compare(page.combo.editText, "qwen3:4b")
        compare(page.availableModels, ["qwen3:4b"])
        page.destroy()
    }

    function test_openWithStoredCloudModelKeepsIt() {
        var page = pageFactory.createObject(test, {
            cfg_aiInsightsProvider: "openai",
            cfg_aiInsightsModel: "gpt-4o-mini",
            cfg_aiInsightsOllamaEndpoint: "http://localhost:11434"
        })
        verify(page !== null)
        compare(page.cfg_aiInsightsModel, "gpt-4o-mini")
        compare(page.combo.editText, "gpt-4o-mini")
        compare(page.availableModels, ["gpt-4o-mini"])
        wait(250)
        compare(page.cfg_aiInsightsModel, "gpt-4o-mini")
        compare(page.combo.editText, "gpt-4o-mini")
        compare(page.availableModels, ["gpt-4o-mini"])
        page.destroy()
    }

    // Without a stored model there is nothing to offer: the menu stays
    // empty until a connection test lists the service.
    function test_openWithoutStoredModelLeavesMenuEmpty() {
        var page = pageFactory.createObject(test, {
            cfg_aiInsightsProvider: "ollama",
            cfg_aiInsightsModel: "",
            cfg_aiInsightsOllamaEndpoint: "http://localhost:11434"
        })
        verify(page !== null)
        compare(page.availableModels, [])
        compare(page.combo.editText, "")
        wait(250)
        compare(page.availableModels, [])
        compare(page.cfg_aiInsightsModel, "")
        page.destroy()
    }

    // Picking a listed model with the mouse commits it even though the
    // combo never holds focus, so the unfocused guard restores the text
    // first; the activation must still write the pick back.
    function test_popupSelectionCommitsModel() {
        var page = pageFactory.createObject(test, {
            cfg_aiInsightsProvider: "ollama",
            cfg_aiInsightsModel: "qwen3:4b",
            cfg_aiInsightsOllamaEndpoint: "http://localhost:11434"
        })
        verify(page !== null)
        page.availableModels = ["qwen3:4b", "llama3.2:3b"]
        compare(page.combo.editText, "qwen3:4b")
        verify(!page.combo.activeFocus)
        page.combo.popup.open()
        tryCompare(page.combo.popup, "opened", true)
        var delegate = page.combo.popup.contentItem.itemAtIndex(1)
        verify(delegate !== null)
        mouseClick(delegate)
        compare(page.cfg_aiInsightsModel, "llama3.2:3b")
        compare(page.combo.editText, "llama3.2:3b")
        page.destroy()
    }

    // The provider switch still swaps the pending model: only the creation
    // reset is a bug, not the per-provider model memory. Switching clears
    // the seeded entry, since the other provider's list is untested.
    function test_providerRoundTripKeepsBothModels() {
        var page = pageFactory.createObject(test, {
            cfg_aiInsightsProvider: "ollama",
            cfg_aiInsightsModel: "qwen3:4b",
            cfg_aiInsightsOllamaEndpoint: "http://localhost:11434"
        })
        verify(page !== null)
        page.selectProvider("openrouter")
        compare(page.cfg_aiInsightsModel, "")
        compare(page.availableModels, [])
        page.selectProvider("ollama")
        compare(page.cfg_aiInsightsModel, "qwen3:4b")
        compare(page.combo.editText, "qwen3:4b")
        compare(page.availableModels, [])
        page.destroy()
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
        self.assertIn("Totals: 8 passed, 0 failed", output)

    def test_clear_button_rearms_when_a_new_insight_arrives(self):
        insights = Surface("insights", ROOT)
        source = (ROOT / "contents/ui/configAiInsights.qml").read_text()
        # Pin the production wiring this harness mirrors: the button disables
        # through the sticky flag the moment Clear is pressed.
        self.assertIn("enabled: page.cacheStored && !page.cacheCleared", source)
        self.assertIn('Plasmoid.configuration.aiInsightsCache = ""', source)
        self.assertIn("page.cacheCleared = true", source)
        # An absent handler leaves the harness without one, so the behavior,
        # not the handler's existence, decides the result.
        try:
            handler = insights.handler_body("onCacheStoredChanged")
        except AssertionError:
            handler = ""
        qml = CLEAR_QML.replace("RESET_HANDLER", handler)
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / "tst_ai_insights_clear_button.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("Totals: 3 passed, 0 failed", output)

    def test_opening_settings_keeps_the_stored_model(self):
        insights = Surface("insights", ROOT)
        source = (ROOT / "contents/ui/configAiInsights.qml").read_text()
        # Pin the production wiring this harness mirrors by hand: the combo
        # shows the tested list. The copied handlers carry the rest.
        self.assertIn("model: page.availableModels", insights.id_block("modelCombo"))
        functions = []
        for name in ("retire", "selectProvider"):
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + insights.function_body(name) + "}")
        handlers = {
            "MODEL_HANDLER": insights.handler_body("onCfg_aiInsightsModelChanged"),
            "PROVIDER_HANDLER": insights.handler_body("onProviderChanged"),
            "COMPLETED_HANDLER": insights.handler_body("Component.onCompleted"),
            "EDIT_HANDLER": insights.handler_body("onEditTextChanged"),
        }
        # An absent activation handler leaves the harness without one, so the
        # popup selection test, not the handler's existence, decides the result.
        try:
            handlers["ACTIVATED_HANDLER"] = insights.handler_body("onActivated")
        except AssertionError:
            handlers["ACTIVATED_HANDLER"] = ""
        qml = CREATION_QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        for marker, body in handlers.items():
            qml = qml.replace(marker, body)
        qml = qml.replace("SOURCE_FUNCTIONS", "\n".join(functions))
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / "tst_ai_insights_creation.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("Totals: 9 passed, 0 failed", output)


if __name__ == "__main__":
    unittest.main()
