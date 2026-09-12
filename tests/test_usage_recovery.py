"""Exercise popup recovery actions with the production QML and effect handlers."""

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
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import "SOURCE_URL/components" as Components
TestCase {
    id: testCase
    name: "UsageRecovery"
    when: windowShown
    width: 600
    height: 550
    visible: true
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    function i18n(text) { return text; }

    Component {
        id: harness
        ColumnLayout {
            id: fullRoot
            width: 560
            property alias applet: root
            property alias message: providerErrorMessage
            property alias globalMessage: globalErrorMessage
            property alias placeholder: emptyProvidersPlaceholder
            property int settingsOpened: 0
            readonly property string usageRecoveryHint: "Diagnostics in widget settings"

            Controls.Action {
                id: configureAction
                onTriggered: fullRoot.settingsOpened++
            }
            QtObject {
                id: nativeHost
                function internalAction(name) {
                    if (name !== "configure") throw new Error("Unexpected native action");
                    return configureAction;
                }
            }
            QtObject {
                id: root
                property bool loading: false
                property int refreshes: 0
                property bool bypassRoster: false
                property string errorText: ""
                property bool providerUsageFeedbackVisible: true
                property var selectedProviderData: ({error: "Synthetic provider failure", rows: [{percent: 43}],
                    usageStale: true, lastGoodAtMs: 1000})
                readonly property var presentedProviderData: selectedProviderData
                function privateErrorText(text) { return text; }
                function refreshNow(bypass) {
                    refreshes++;
                    bypassRoster = bypass;
                    loading = true;
                }
                SOURCE_FUNCTIONS
            }
            SOURCE_ACTIONS
            Components.PlainInlineMessage { GLOBAL_MESSAGE }
            Components.PlainInlineMessage { PROVIDER_MESSAGE }
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 220
                Components.PlainPlaceholderMessage { EMPTY_MESSAGE }
            }
        }
    }

    function createSubject() {
        failOnWarning(/.*/);
        var subject = createTemporaryObject(harness, testCase);
        verify(subject !== null);
        return subject;
    }

    function buttonWithText(item, text) {
        if (item.text === text && typeof item.clicked === "function" && item.visible)
            return item;
        for (var child of item.children || []) {
            var found = buttonWithText(child, text);
            if (found) return found;
        }
        return null;
    }

    function test_retryKeepsRetainedQuotasAndRejectsRepeatedActivation() {
        var subject = createSubject();
        var previous = subject.applet.selectedProviderData;
        tryVerify(function() { return buttonWithText(subject.message, "Retry") !== null; });
        var button = buttonWithText(subject.message, "Retry");
        button.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(subject.applet.refreshes, 1);
        verify(subject.applet.bypassRoster);
        verify(!subject.message.actions[0].enabled);
        subject.message.actions[0].trigger();
        subject.applet.retryUsage();
        keyClick(Qt.Key_Space);
        compare(subject.applet.refreshes, 1);
        compare(subject.applet.selectedProviderData, previous);
        compare(previous.rows[0].percent, 43);
        compare(previous.lastGoodAtMs, 1000);
        verify(previous.usageStale);
        subject.applet.loading = false;
        verify(subject.message.actions[0].enabled);
        subject.message.actions[0].trigger();
        compare(subject.applet.refreshes, 2);
    }

    function test_globalErrorSharesRetryAndDoesNotLeakIntoOtherViews() {
        var subject = createSubject();
        subject.applet.selectedProviderData = null;
        subject.applet.errorText = "Synthetic connection failure";
        verify(subject.globalMessage.visible);
        verify(!subject.message.visible);
        subject.globalMessage.actions[0].trigger();
        compare(subject.applet.refreshes, 1);
        verify(!subject.globalMessage.actions[0].enabled);
        subject.applet.providerUsageFeedbackVisible = false;
        verify(!subject.globalMessage.visible);
    }

    function test_emptyStateAndErrorsOpenNativeSettingsWithoutRefreshing() {
        var subject = createSubject();
        subject.placeholder.helpfulAction.trigger();
        compare(subject.settingsOpened, 1);
        subject.message.actions[1].trigger();
        compare(subject.settingsOpened, 2);
        subject.applet.selectedProviderData = null;
        subject.applet.errorText = "Synthetic connection failure";
        subject.globalMessage.actions[1].trigger();
        compare(subject.settingsOpened, 3);
        compare(subject.applet.refreshes, 0);
    }

    function test_globalAndProviderErrorsShareOneSetOfActions() {
        var subject = createSubject();
        subject.applet.errorText = "Synthetic connection failure";
        verify(subject.globalMessage.visible && subject.message.visible);
        compare(subject.globalMessage.actions.length, 2);
        compare(subject.message.actions.length, 0);
        compare(subject.message.plainText, "Synthetic provider failure");
        subject.applet.errorText = subject.applet.selectedProviderData.error;
        verify(!subject.globalMessage.visible && subject.message.visible);
        compare(subject.message.actions.length, 2);
    }
}
'''


class UsageRecoveryTests(unittest.TestCase):
    def test_popup_actions_and_owner_guards(self):
        surface = Surface("applet", ROOT)
        source = (ROOT / "contents/ui/main.qml").read_text()
        functions = []
        for name in ("retryUsage", "performAction"):
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + surface.function_body(name) + "}")
        # Only the native configuration action and refresh effect are observed.
        functions = "\n".join(functions).replace("Plasmoid.internalAction", "nativeHost.internalAction")
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", functions)
        qml = qml.replace("SOURCE_ACTIONS", "\n".join(
            "Controls.Action {" + surface.id_block(name) + "}"
            for name in ("retryUsageAction", "usageSettingsAction", "configureProvidersAction")))
        for placeholder, name in (("GLOBAL_MESSAGE", "globalErrorMessage"),
                                  ("PROVIDER_MESSAGE", "providerErrorMessage"),
                                  ("EMPTY_MESSAGE", "emptyProvidersPlaceholder")):
            qml = qml.replace(placeholder, surface.id_block(name))
        with tempfile.TemporaryDirectory(prefix="codexbar-recovery-") as temporary:
            fixture = Path(temporary) / "tst_recovery.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
