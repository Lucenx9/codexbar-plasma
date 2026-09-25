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
            property alias missingPlaceholder: missingCommandPlaceholder
            property alias missingMessage: missingCommandMessage
            property alias loadingRow: providerUsageLoadingRow
            property alias errorArt: providerUsageErrorIcon
            SOURCE_MISSING_PROPERTY
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
                property bool commandPathFailed: false
                property string commandPath: "codexbar"
                property bool globalViewSelected: false
                property var providers: []
                property bool providerUsageFeedbackVisible: true
                property real secondaryTextOpacity: 0.7
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
            Item { LOADING_ROW }
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 220
                Components.PlainPlaceholderMessage { EMPTY_MESSAGE }
            }
            Item { MISSING_MESSAGE }
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

    function test_unreachableCommandTakesItsOwnStateAwayFromSetupAndRetry() {
        var subject = createSubject();
        subject.applet.selectedProviderData = null;
        subject.applet.errorText = "sh: 1: codexbar: not found";
        subject.applet.commandPathFailed = true;

        // The widget never reached the CLI, so neither the retryable connection
        // banner nor the "enable a provider" setup message may claim this case.
        verify(subject.missingMessage.visible);
        verify(!subject.globalMessage.visible);
        verify(subject.missingPlaceholder.plainExplanation.indexOf("codexbar") !== -1);
        // Its action opens settings rather than repeating a command that cannot run.
        subject.missingPlaceholder.helpfulAction.trigger();
        compare(subject.settingsOpened, 1);
        compare(subject.applet.refreshes, 0);

        // A reachable command hands the view back to the ordinary states.
        subject.applet.commandPathFailed = false;
        verify(!subject.missingMessage.visible);
        verify(subject.globalMessage.visible);
    }

    function test_unreachableCommandDefersToLoadingAndToRecoveredProviders() {
        var subject = createSubject();
        subject.applet.selectedProviderData = null;
        subject.applet.commandPathFailed = true;
        subject.applet.errorText = "sh: 1: codexbar: not found";
        verify(subject.missingMessage.visible);

        // A refresh in flight must not flash the setup error under the spinner.
        subject.applet.loading = true;
        verify(!subject.missingMessage.visible);
        subject.applet.loading = false;
        verify(subject.missingMessage.visible);

        // Retained providers keep their data on screen; the state is for an
        // empty popup, not for a stale classification over usable quotas.
        subject.applet.providers = [{provider: "codex"}];
        verify(!subject.missingMessage.visible);
    }

    function test_errorStateCentersAStatusGlyphWithoutALoadingIndicator() {
        var subject = createSubject();
        subject.applet.selectedProviderData = null;
        subject.applet.errorText = "Synthetic connection failure";
        verify(subject.loadingRow.visible);
        verify(subject.globalMessage.visible);
        verify(subject.errorArt.visible);
        subject.applet.loading = true;
        verify(!subject.errorArt.visible);
        verify(subject.loadingRow.visible);
        subject.applet.loading = false;
        subject.applet.providers = [{provider: "codex"}];
        verify(!subject.loadingRow.visible);
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
                                  ("EMPTY_MESSAGE", "emptyProvidersPlaceholder"),
                                  ("MISSING_MESSAGE", "missingCommandMessage")):
            # The harness imports the shared components under a namespace, while
            # production resolves them from the same directory.
            qml = qml.replace(placeholder, surface.id_block(name).replace(
                "PlainPlaceholderMessage {", "Components.PlainPlaceholderMessage {"))
        qml = qml.replace("LOADING_ROW", surface.id_block("providerUsageLoadingRow").replace(
            "PlainPlasmaLabel {", "Components.PlainPlasmaLabel {"))
        # The production condition itself, so the test cannot drift from it.
        representation = (ROOT / "contents/ui/components/FullRepresentation.qml").read_text()
        condition = re.search(
            r"readonly property bool commandPathMissing:.*?(?=\n\n)", representation, re.S)
        assert condition, "commandPathMissing must stay a single readonly property"
        qml = qml.replace("SOURCE_MISSING_PROPERTY", condition.group(0))
        # The provider setup state is rendered outside this harness, so assert at
        # the source that it also stands aside for an unreachable command.
        self.assertIn("!fullRoot.commandPathMissing", surface.id_block("emptyProvidersMessage"))
        with tempfile.TemporaryDirectory(prefix="codexbar-recovery-") as temporary:
            fixture = Path(temporary) / "tst_recovery.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_popup_menu_offers_accounts_and_docs(self):
        surface = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = main.read_text()
        surface.texts = {main: source}
        functions = []
        for name in ("actionRows", "providerAccountAction", "providerDocsUrl",
                     "providerLoginUrl", "providerStatusUrl", "safeStatusUrl",
                     "providerKey", "providerMapKey", "accountLoadingForProvider",
                     "performAction"):
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + surface.function_body(name) + "}")
        qml = MENU_QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n        ".join(functions))
        # The status action opens through the host guard; route the external
        # open through a harness recorder the same way the update tests do.
        qml = qml.replace("Qt.openUrlExternally(", "recordOpenedUrl(")
        with tempfile.TemporaryDirectory(prefix="codexbar-popup-menu-") as temporary:
            fixture = Path(temporary) / "tst_popup_menu.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


MENU_QML = '''import QtQuick
import QtTest
import "SOURCE_URL/ProviderNormalizer.js" as Normalizer
import "SOURCE_URL/ProviderIdentity.js" as ProviderIdentity
TestCase {
    name: "PopupMenuRows"
    QtObject {
        id: root
        property bool showProviderChangelogs: false
        property var selectedProviderData: null
        property var openedUrls: []
        property var accountsController: QtObject {
            function loadingForProvider(key) { return false; }
        }
        SOURCE_FUNCTIONS
        function i18n(text) { return text; }
        function recordOpenedUrl(url) { openedUrls.push(url); }
    }
    function menuItem(provider) {
        return {provider: provider, account: "", dashboardUrl: "",
                statusUrl: "", changelogUrl: ""};
    }
    // The overflow menu always offers account switching first, with a docs
    // entry carrying the identity-table URL whenever one exists.
    function test_menuOffersAccountsAndDocs() {
        var rows = root.actionRows(menuItem("codex"));
        compare(rows[0].action, "accounts");
        var docs = rows.filter(function(row) { return row.action === "docs"; });
        compare(docs.length, 1);
        verify(docs[0].url.indexOf("https://") === 0);
        verify(root.providerDocsUrl("codex").indexOf("https://") === 0);
        compare(root.providerLoginUrl("codex"), "https://chatgpt.com");
    }
    // Unknown providers get no docs entry instead of a guessed URL.
    function test_unknownProviderHasNoDocsRow() {
        var rows = root.actionRows(menuItem("unknown-xyz"));
        compare(rows.filter(function(row) { return row.action === "docs"; }).length, 0);
        compare(root.providerDocsUrl("unknown-xyz"), "");
        compare(root.providerLoginUrl("unknown-xyz"), "");
    }
    // The status action opens the guarded URL, so a payload status URL on a
    // foreign host cannot redirect the click away from the shipped page.
    function test_statusActionOpensGuardedUrl() {
        var item = menuItem("codex");
        item.statusUrl = "https://evil.example/status";
        root.selectedProviderData = item;
        root.openedUrls = [];
        root.performAction({action: "status"});
        compare(root.openedUrls, [root.providerStatusUrl("codex")]);
        item.statusUrl = root.providerStatusUrl("codex") + "incidents/7";
        root.selectedProviderData = item;
        root.openedUrls = [];
        root.performAction({action: "status"});
        compare(root.openedUrls, [item.statusUrl]);
    }
}
'''


if __name__ == "__main__":
    unittest.main()
