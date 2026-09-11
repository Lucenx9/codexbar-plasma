"""A malformed account record must not discard healthy options in its reply."""

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
    "parseProviderAccountsOutput", "normalizeProvider", "planText", "capitalize",
    "isCliRecord", "hasOwnKey", "copyObject", "accountLabel", "providerMapKey",
    "providerKey", "boundedCliMessage", "setAccountOptions", "setAccountError",
    "accountLoadingForProvider", "finishUsageCommandSource",
)

QML = '''import QtQuick
import QtTest
import "SOURCE_URL/ProviderNormalizer.js" as Normalizer
import "SOURCE_URL/ProviderIdentity.js" as ProviderIdentity
import "SOURCE_URL/Guards.js" as Guards
import "SOURCE_URL/SafeText.js" as SafeText
import "SOURCE_URL/AccountRequests.js" as AccountRequests
import "SOURCE_URL/CommandLedger.js" as CommandLedger
import "SOURCE_URL/UsageDetails.js" as UsageDetails
TestCase {
    name: "AccountParseContainment"
    Component {
        id: harness
        QtObject {
            id: root
            property var activeCommandDescriptors: ({})
            property var accountOptions: ({})
            property var accountErrors: ({})
            property var providerDisplayNames: ({})
            property int maximumAccountSnapshots: Normalizer.maximumAccountSnapshots
            property int maximumExtraRateWindows: Normalizer.maximumExtraRateWindows
            property string currentCommand: "accounts-context"
            property QtObject usageSource: QtObject {
                function disconnectSource(sourceName) {}
            }

            SOURCE_FUNCTIONS

            function i18n(text) { return text; }
            function buildProviderAccountsCommand(providerID) { return currentCommand; }
            // Keep presentation unrelated to this account parser test empty.
            // normalizeProvider, its identity reads, planText and capitalize
            // above are the actual production functions, not a throwing stub.
            function addWindow() { return null; }
            function rateWindowLabel() { return ""; }
            function usageDashboard() { return null; }
            function providerPlaceholder() { return ""; }
            function providerTitle(providerID) { return providerID; }
            function providerCostSection() { return null; }
            function resetCreditsSection() { return null; }
            function providerTokenCost() { return null; }
            function providerDashboardUrl() { return ""; }
            function safeStatusUrl() { return ""; }
            function providerChangelogUrl() { return ""; }
            function statusText() { return ""; }
        }
    }

    function malformedAccount() {
        // Ordinary JSON: the structured login method passes no functions or
        // getters into QML, but its string coercion throws in planText.
        return {
            provider: "codex", account: "broken",
            usage: {identity: {loginMethod: [{toString: null}]}}
        };
    }

    function deliver(applet, payload) {
        var descriptor = CommandLedger.descriptor("account", "codex", 1000, 60000, 60000);
        descriptor.commandSignature = applet.currentCommand;
        applet.activeCommandDescriptors = CommandLedger.opened(
            applet.activeCommandDescriptors, "accounts-run", descriptor);
        verify(applet.accountLoadingForProvider("codex"));
        applet.parseProviderAccountsOutput("accounts-run", descriptor, JSON.stringify(payload), "");
        verify(!applet.accountLoadingForProvider("codex"));
        compare(CommandLedger.find(applet.activeCommandDescriptors, "accounts-run"), null);
    }

    function test_malformedAccountKeepsHealthyOptionsBeforeAndAfterIt() {
        var applet = createTemporaryObject(harness, this, {});
        verify(applet !== null);
        deliver(applet, [
            {provider: "codex", account: "valid-before"},
            malformedAccount(),
            {provider: "codex", account: "valid-after"}
        ]);
        var options = applet.accountOptions.codex || [];
        compare(options.length, 2);
        compare(options[0].accountKey, "valid-before");
        compare(options[1].accountKey, "valid-after");
        compare(applet.accountErrors.codex || "", "");
    }

    function test_allMalformedAccountsKeepPreviousOptionsAndReportAnError() {
        var applet = createTemporaryObject(harness, this, {});
        verify(applet !== null);
        var previous = [{provider: "codex", account: "previous", accountKey: "previous"}];
        applet.accountOptions = {codex: previous};
        deliver(applet, [malformedAccount()]);
        compare(applet.accountOptions.codex, previous);
        verify((applet.accountErrors.codex || "").length > 0);
    }
}
'''


class AccountParseContainmentTests(unittest.TestCase):
    def test_account_record_failures_are_contained(self):
        applet = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = applet.texts[main]
        applet.texts = {main: source}
        functions = []
        for name in FUNCTIONS:
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + applet.function_body(name) + "}")
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n".join(functions))
        with tempfile.TemporaryDirectory(prefix="codexbar-account-parse-") as temporary:
            fixture = Path(temporary) / "tst_account_parse.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
