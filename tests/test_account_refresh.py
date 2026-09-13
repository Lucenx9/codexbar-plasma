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
        // stored selection and the --account argument must keep the original.
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
        verify(applet.refreshes[0].command.indexOf("--account 'Work  Team'") !== -1);
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
        compare(applet.commandSource !== before, data.provider.length > 0);
        tryVerify(function() { return applet.refreshes.length > 0; });
        wait(0);
        compare(applet.refreshes.length, 1);
        compare(applet.refreshes[0].account, "target");
        compare(applet.refreshes[0].command, applet.commandSource);
        verify(applet.refreshes[0].pending);
    }
}
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
            script.write_text("#!/usr/bin/env python3\nimport json, sys\nprint(json.dumps([{'provider': 'codex', 'enabled': True}]))\n")
            script.chmod(0o700)
            fixture.write_text(qml.replace("FIXTURE_PATH", str(script)))
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
