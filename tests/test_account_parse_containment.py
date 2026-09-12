"""Malformed records must not discard healthy account or usage siblings."""

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
    "normalizeProvider", "presentProviderSnapshot", "presentUsageWindow", "planText", "capitalize",
    "isCliRecord", "hasOwnKey", "copyObject", "accountLabel", "providerMapKey",
    "providerKey", "boundedCliMessage", "normalizedProviderID", "providerErrorPayload",
    "replaceProviderSnapshot",
)

QML = '''import QtQuick
import QtTest
import "SOURCE_URL/ProviderNormalizer.js" as Normalizer
import "SOURCE_URL/ProviderSnapshot.js" as ProviderSnapshot
import "SOURCE_URL/AccountResponse.js" as AccountResponse
import "SOURCE_URL/ProviderIdentity.js" as ProviderIdentity
import "SOURCE_URL/Guards.js" as Guards
import "SOURCE_URL/SafeText.js" as SafeText
import "SOURCE_URL/CommandLedger.js" as CommandLedger
import "SOURCE_URL/UsageDetails.js" as UsageDetails
import "SOURCE_URL/UsageCache.js" as UsageCache
import "SOURCE_URL/ProviderOrder.js" as ProviderOrder
TestCase {
    name: "AccountParseContainment"
    Component {
        id: harness
        QtObject {
            id: root
            property var activeCommandDescriptors: ({})
            property var accountOptions: ({})
            property var providers: []
            property string providerOrderRaw: ""
            property double testNowMs: Date.UTC(2026, 8, 12, 12)
            property var providerDisplayNames: ({})
            property string source: ""
            SOURCE_FUNCTIONS

            function i18n(text) { return text; }
            // Keep presentation unrelated to this parser/selection test empty.
            // normalizeProvider, its identity reads, planText and capitalize
            // above are the actual production functions, not a throwing stub.
            function resetText() { return ""; }
            function paceSummaryPartsText() { return ""; }
            function rateWindowLabel() { return ""; }
            function providerTitle(providerID) { return providerID; }
            function providerCostSection(providerID, cost) {
                return null;
            }
            function resetCreditsSection() { return null; }
            function providerTokenCost() { return null; }
            function providerDashboardUrl() { return ""; }
            function safeStatusUrl() { return ""; }
            function providerChangelogUrl() { return ""; }
            function statusText() { return ""; }
        }
    }

    function deliver(applet, payload) {
        var result = AccountResponse.response(JSON.stringify(payload), "", "codex", applet.testNowMs);
        compare(result.outcome, "success");
        applet.accountOptions = {codex: result.options.map(function(item) { return applet.presentProviderSnapshot(item); })};
    }

    function test_cachedAccountSelectionKeepsMeasurementAge_data() {
        var cases = [];
        for (var timestamp of ["", "invalid", "2026-09-12T12:01:00Z"])
            for (var age of [900000, UsageCache.maximumAgeMs + 1])
                cases.push({tag: timestamp + "-" + age, timestamp: timestamp, age: age});
        return cases;
    }

    function test_cachedAccountSelectionKeepsMeasurementAge(data) {
        var applet = createTemporaryObject(harness, this, {});
        var receivedAtMs = applet.testNowMs;
        deliver(applet, [{provider: "codex", account: "Synthetic account",
            usage: {updatedAt: data.timestamp, primary: {usedPercent: 0}}}]);
        var option = applet.accountOptions.codex[0];
        var original = JSON.stringify(option);
        applet.testNowMs += data.age;
        applet.replaceProviderSnapshot("codex", option);
        var selected = applet.providers[0];
        compare(selected.lastGoodAtMs, receivedAtMs);
        compare(selected.rows[0].usedPercent, 0);
        compare(selected.usageStale, data.age > UsageCache.maximumAgeMs);
        compare(JSON.stringify(option), original);
        var deadline = receivedAtMs + UsageCache.maximumAgeMs;
        if (data.age > UsageCache.maximumAgeMs) {
            compare(UsageCache.expiredProviderIDs([selected], applet.testNowMs), ["codex"]);
            return;
        }
        var retained = UsageCache.reconcile([selected], [{provider: "codex",
            error: "Synthetic failure", account: "", rows: []}], deadline);
        compare(retained[0].lastGoodAtMs, receivedAtMs);
        compare(UsageCache.expiredProviderIDs(retained, deadline + 1), ["codex"]);
    }

    function test_malformedOptionalLoginMethodKeepsTheAccount() {
        var applet = createTemporaryObject(harness, this, {});
        verify(applet !== null);
        deliver(applet, [{
            provider: "codex", account: "retained",
            usage: {identity: {loginMethod: [{toString: null}]}}
        }]);
        var options = applet.accountOptions.codex || [];
        compare(options.length, 1);
        compare(options[0].accountKey, "retained");
        compare(options[0].planText, "");
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
            body = applet.function_body(name).replace("Date.now()", "testNowMs")
            functions.append(signature + " {" + body + "}")
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
