"""Exercise account-selection scheduling with the production QML bindings."""

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

FUNCTIONS = (
    "copyObject", "providerMapKey", "accountLabel",
    "accountKey", "selectedAccountForProvider", "accountOptionsForProvider",
    "selectAccount", "scheduleUsageRefresh", "refreshNow",
)

QML = '''import QtQuick
import QtTest
import "SOURCE_URL/ProviderNormalizer.js" as Normalizer
import "SOURCE_URL/Guards.js" as Guards
import "SOURCE_URL/controllers" as Controllers
TestCase {
    name: "AccountRefresh"
    Component {
        id: harness
        QtObject {
            id: root
            property string commandPath: "FIXTURE_PATH"
            property string provider: "codex"
            property string source: ""
            property bool includeStatus: false
            property var selectedAccounts: ({codex: "initial"})
            property var accountOptions: ({})
            readonly property bool usageRefreshScheduled: usageController.refreshScheduled
            property QtObject usageController: Controllers.UsageController {
                function i18n(text, first) { return text.replace("%1", first === undefined ? "%1" : first); }
                commandPath: root.commandPath
                provider: root.provider
                sourceMode: root.source
                selectedAccounts: root.selectedAccounts
                includeStatus: root.includeStatus
                refreshIntervalSec: 0
                onLoadingChanged: {
                    if (loading) root.refreshes = root.refreshes.concat({
                        account: root.selectedAccountForProvider("codex"), command: commandSource, pending: root.pending});
                }
            }
            property var refreshes: []
            property var invalidations: []
            property bool pending: false
            property var cachedSnapshot: null
            property var published: []
            property Connections usageConnections: Connections {
                target: root.usageController
                function onSnapshotReceived(items) { root.published = root.published.concat([items]); }
            }

            SOURCE_BINDINGS
            SOURCE_FUNCTIONS

            function invalidateUsageData(key) {
                invalidations = invalidations.concat(selectedAccountForProvider(key));
            }
            function setNotificationProviderRefreshPending(key, value) {
                pending = value;
            }
            function replaceProviderSnapshot(key, snapshot) {
                cachedSnapshot = snapshot;
            }
        }
    }

    function test_oneRefreshAfterAccountSelection_data() {
        return [
            {tag: "single-uncached", provider: "codex", cached: false},
            {tag: "single-cached", provider: "codex", cached: true},
            {tag: "multi-uncached", provider: "", cached: false},
            {tag: "multi-cached", provider: "", cached: true}
        ];
    }

    function test_accountSelectionKeepsOriginalIdentifierSpacing() {
        // "Work  Team" and "Work Team" collapse to one display label, but the
        // stored selection must keep the original when matching --all-accounts.
        var identity = "Work  Team";
        var snapshot = {provider: "codex", account: "Work Team", accountKey: identity};
        var applet = createTemporaryObject(harness, this, {
            provider: "codex",
            accountOptions: ({codex: [snapshot]})
        });
        verify(applet !== null);
        wait(0);
        tryCompare(applet.usageController, "loading", false);
        applet.refreshes = [];
        applet.selectAccount("codex", identity);
        compare(applet.selectedAccountForProvider("codex"), identity);
        compare(applet.cachedSnapshot, snapshot);
        tryVerify(function() { return applet.refreshes.length > 0; });
        wait(0);
        compare(applet.refreshes.length, 1);
        compare(applet.refreshes[0].account, identity);
        verify(applet.refreshes[0].command.indexOf("--all-accounts") !== -1);
        tryCompare(applet.usageController, "loading", false);
        compare(applet.published[applet.published.length - 1][0].accountKey, identity);
        compare(applet.published[applet.published.length - 1][0].rows[0].usedPercent, 90);
    }

    function test_oneRefreshAfterAccountSelection(data) {
        var snapshot = {provider: "codex", account: "target"};
        var applet = createTemporaryObject(harness, this, {
            provider: data.provider,
            accountOptions: data.cached ? {codex: [snapshot]} : ({})
        });
        verify(applet !== null);
        wait(0);
        tryCompare(applet, "usageRefreshScheduled", false);
        tryCompare(applet.usageController, "loading", false);
        applet.refreshes = [];
        var before = applet.commandSource;
        applet.selectAccount("codex", "target");
        compare(applet.refreshes.length, 0);
        compare(applet.invalidations, ["initial"]);
        compare(applet.cachedSnapshot, data.cached ? snapshot : null);
        // Codex selections share a command; the changed request context must
        // still schedule exactly one refresh and retire the previous reply.
        compare(applet.commandSource, before);
        tryVerify(function() { return applet.refreshes.length > 0; });
        wait(0);
        compare(applet.refreshes.length, 1);
        compare(applet.refreshes[0].account, "target");
        compare(applet.refreshes[0].command, applet.commandSource);
        verify(applet.refreshes[0].pending);
        tryCompare(applet.usageController, "loading", false);
    }

    function test_codexClickRefreshAndDefault_data() {
        return [
            {tag: "scoped-auto", provider: "codex", source: ""},
            {tag: "scoped-oauth", provider: "codex", source: "oauth"},
            {tag: "aggregate-auto", provider: "", source: ""},
            {tag: "aggregate-oauth", provider: "", source: "oauth"}
        ];
    }

    function test_codexClickRefreshAndDefault(data) {
        var applet = createTemporaryObject(harness, this, {
            provider: data.provider, source: data.source, selectedAccounts: ({}),
            accountOptions: {codex: [{provider: "codex", account: "target"}]}
        });
        function latest() { return applet.published[applet.published.length - 1][0]; }
        function completed(count) {
            tryVerify(function() { return applet.published.length === count && !applet.usageController.loading; });
        }
        completed(1);
        compare(latest().rows[0].usedPercent, 15);
        applet.selectAccount("codex", "target");
        completed(2);
        compare(latest().commandFailed, false, latest().error);
        compare(latest().accountKey, "target");
        compare(latest().rows[0].usedPercent, 83);
        applet.usageController.refresh(false);
        completed(3);
        compare(latest().accountKey, "target");
        compare(latest().rows[0].usedPercent, 83);
        applet.selectAccount("codex", "missing");
        completed(4);
        verify(latest().commandFailed);
        compare(latest().rows, []);
        applet.selectAccount("codex", "");
        completed(5);
        compare(latest().commandFailed, false);
        compare(latest().accountKey, "Default");
        compare(latest().rows[0].usedPercent, 15);
    }

    function test_codexSelectionRetiresReplyWithTheSameCommand() {
        var applet = createTemporaryObject(harness, this, {
            commandPath: "SLOW_FIXTURE_PATH", selectedAccounts: {codex: "target"}
        });
        tryCompare(applet.usageController, "loading", true);
        wait(50);
        var previousCommand = applet.commandSource;
        applet.selectAccount("codex", "Work  Team");
        compare(applet.commandSource, previousCommand);
        tryVerify(function() { return applet.published.length === 1 && !applet.usageController.loading; });
        compare(applet.published[0][0].accountKey, "Work  Team");
        compare(applet.published[0][0].rows[0].usedPercent, 90);
        wait(600);
        compare(applet.published.length, 1);
    }
}
'''

CLI = '''#!/usr/bin/env python3
import json, os, sys, time
args = sys.argv[1:]
if sys.argv[0].endswith('slow-cli') and os.environ['CODEXBAR_PLASMA_RUN'] == '1':
    time.sleep(0.4)
if args[0] == 'config':
    print(json.dumps([{'provider': 'codex', 'enabled': True}]))
elif '--account' in args:
    print(json.dumps([{'provider': 'cli', 'source': 'cli', 'error': {
        'kind': 'args', 'code': 1, 'message': 'Error: codex does not support token accounts.'}}]))
    sys.exit(1)
else:
    accounts = [('Default', 15), ('target', 83), ('Work Team', 10), ('Work  Team', 90)]
    if '--all-accounts' not in args:
        accounts = accounts[:1]
    print(json.dumps([{'provider': 'codex', 'account': account,
        'usage': {'primary': {'usedPercent': used}}} for account, used in accounts]))
'''


class AccountRefreshTests(unittest.TestCase):
    def test_account_selection_coalesces_real_qml_callbacks(self):
        applet = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = applet.texts[main]
        applet.texts = {main: source}
        functions = []
        for name in FUNCTIONS:
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + applet.function_body(name) + "}")
        bindings = [re.search(pattern, source, re.MULTILINE).group(0) for pattern in (
            r"^    readonly property string commandSource: .+$",
        )]
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n".join(functions))
        qml = qml.replace("SOURCE_BINDINGS", "\n".join(bindings))
        with tempfile.TemporaryDirectory(prefix="codexbar-account-refresh-") as temporary:
            fixture = Path(temporary) / "tst_account_refresh.qml"
            script = Path(temporary) / "codexbar-fixture"
            script.write_text(CLI)
            script.chmod(0o700)
            slow_script = Path(temporary) / "slow-cli"
            slow_script.write_text(CLI)
            slow_script.chmod(0o700)
            fixture.write_text(qml.replace("SLOW_FIXTURE_PATH", str(slow_script)).replace("FIXTURE_PATH", str(script)))
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
