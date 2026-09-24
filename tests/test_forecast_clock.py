"""Keep cached account forecasts tied to the time their rows were received."""

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
    "presentUsageWindow", "replaceProviderSnapshot", "runOutTextForRow", "paceEtaText",
    "paceWarningActive", "selectAccount", "providerMapKey", "copyObject",
    "accountKey", "accountOptionsForProvider", "markUsageSnapshotReceived",
)

QML = '''import QtQuick
import QtTest
import "SOURCE_URL/ProviderNormalizer.js" as Normalizer
import "SOURCE_URL/ProviderSnapshot.js" as ProviderSnapshot
import "SOURCE_URL/AccountResponse.js" as AccountResponse
import "SOURCE_URL/Guards.js" as Guards
import "SOURCE_URL/PanelDisplay.js" as PanelDisplay
import "SOURCE_URL/ProviderOrder.js" as ProviderOrder
import "SOURCE_URL/UsageCache.js" as UsageCache
import "SOURCE_URL/PrivacyPresentation.js" as PrivacyPresentation
TestCase {
    name: "ForecastClock"
    Component {
        id: harness
        QtObject {
            id: root
            property var providers: []
            property var selectedAccounts: ({})
            property var accountOptions: ({})
            property string providerOrderRaw: ""
            property double testNowMs: Date.UTC(2026, 8, 12, 12)
            property double panelClockMs: testNowMs
            property double usageLastCompletedAtMs: -1
            // Allows the same behavioral test to run against the old adapter.
            property double usageSnapshotReceivedAtMs: panelClockMs

            SOURCE_FUNCTIONS

            function i18n(text, value) {
                return value === undefined ? text : text.replace("%1", value);
            }
            function i18np(one, many, count) { return i18n(count === 1 ? one : many, count); }
            function resetText() { return ""; }
            function paceSummaryPartsText() { return ""; }
            function providerTokenCost() { return null; }
            function invalidateUsageData() { providers = []; }
            function setNotificationProviderRefreshPending() {}
            function scheduleUsageRefresh() {}
        }
    }

    function test_cachedAccountKeepsItsForecastClock_data() {
        return [
            {tag: "cached-account", elapsedMinutes: 15, privateMode: false, expected: "15 minutes"},
            {tag: "private-account", elapsedMinutes: 15, privateMode: true, expected: "15 minutes"},
            {tag: "expired-forecast", elapsedMinutes: 35, privateMode: false, expected: "now"},
            {tag: "fresh-account", elapsedMinutes: 0, privateMode: false, expected: "30 minutes"}
        ];
    }

    function test_cachedAccountKeepsItsForecastClock(data) {
        var applet = createTemporaryObject(harness, this);
        var rows = [];
        // Account discovery normalizes rows before storing the picker options.
        var row = applet.presentUsageWindow(ProviderSnapshot.windowSnapshot({usedPercent: 85}, {
            expectedUsedPercent: 60, willLastToReset: false, etaSeconds: 1800
        }, true, "primary", "Session", applet.testNowMs), "codex");
        rows.push(row);
        applet.accountOptions = {codex: [{
            provider: "codex", account: "Synthetic account", accountKey: "Synthetic account",
            rows: rows, primaryRow: row, updatedAt: "", error: ""
        }]};
        // A newer usage refresh belongs to another account; it cannot restart
        // the forecast stored by the earlier account-discovery response.
        applet.testNowMs += data.elapsedMinutes * 60000;
        applet.markUsageSnapshotReceived();
        applet.selectAccount("codex", "Synthetic account");
        compare(applet.providers.length, 1);
        compare(applet.providers[0].accountKey, "Synthetic account");
        var selectedRow = applet.providers[0].rows[0];
        compare(selectedRow.usedPercent, 85);
        compare(selectedRow.paceEtaSeconds, 1800);
        var presented = PrivacyPresentation.quota(selectedRow, data.privateMode, "Usage");
        compare(applet.runOutTextForRow(presented), data.expected);
        // Further updates elsewhere must not restart the same row's timer.
        applet.testNowMs += 60000;
        applet.markUsageSnapshotReceived();
        compare(applet.runOutTextForRow(presented), data.elapsedMinutes >= 30
            ? "now" : (29 - data.elapsedMinutes) + " minutes");
    }
}
'''

POPUP_PACE_QML = '''import QtQuick
import QtTest
import "SOURCE_URL/ProviderNormalizer.js" as Normalizer
import "SOURCE_URL/ProviderSnapshot.js" as ProviderSnapshot
import "SOURCE_URL/PacePresentation.js" as PacePresentation
import "SOURCE_URL/Guards.js" as Guards
TestCase {
    name: "PopupPaceClock"
    Component {
        id: harness
        QtObject {
            id: root
            property double receivedAtMs: Date.UTC(2026, 8, 24, 12)
            property double panelClockMs: receivedAtMs

            SOURCE_FUNCTIONS

            function i18n(text, value) {
                return value === undefined ? text : text.replace("%1", value);
            }
            function i18np(one, many, count) { return i18n(count === 1 ? one : many, count); }
            function resetText() { return ""; }
        }
    }

    function test_popupRunOutFollowsTheClock_data() {
        return [
            {tag: "at receipt", elapsedMinutes: 0, expected: "Expected 40% used | Runs out in 2 hours"},
            {tag: "later", elapsedMinutes: 90, expected: "Expected 40% used | Runs out in 30 minutes"},
            {tag: "passed", elapsedMinutes: 150, expected: "Expected 40% used | Runs out now"}
        ];
    }

    // No periodic refresh (or a long interval) keeps one snapshot on screen.
    // Its reset line counts down, so the run-out line beside it must as well.
    function test_popupRunOutFollowsTheClock(data) {
        var applet = createTemporaryObject(harness, this);
        var row = applet.presentUsageWindow(ProviderSnapshot.windowSnapshot({usedPercent: 70}, {
            expectedUsedPercent: 40, willLastToReset: false, etaSeconds: 7200
        }, true, "primary", "Session", applet.receivedAtMs), "codex");
        applet.panelClockMs = applet.receivedAtMs + data.elapsedMinutes * 60000;
        var usageRow = {applet: applet, rowData: row, showPace: true};
        compare((function() { return PACE_LABEL_TEXT; })(), data.expected);
    }
}
'''


def run_qml(test, qml, name):
    with tempfile.TemporaryDirectory(prefix="codexbar-forecast-clock-") as temporary:
        fixture = Path(temporary) / name
        fixture.write_text(qml)
        result = subprocess.run(
            [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
            env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
            capture_output=True, text=True, timeout=30)
        test.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class ForecastClockTests(unittest.TestCase):
    def test_cached_account_forecast_uses_its_own_receipt_time(self):
        applet = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = applet.texts[main]
        applet.texts = {main: source}
        functions = []
        for name in FUNCTIONS:
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            # Replace only the wall-clock read so every case has a fixed time.
            body = applet.function_body(name).replace("Date.now()", "testNowMs")
            functions.append(signature + " {" + body + "}")
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n".join(functions))
        run_qml(self, qml, "tst_forecast_clock.qml")

    def test_popup_pace_line_counts_down_like_the_panel(self):
        applet = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = applet.texts[main]
        row_file = ROOT / "contents/ui/components/ProviderUsageRow.qml"
        # Evaluate the popup label's own text binding, not a copy of it.
        label = Surface("applet", ROOT)
        label.texts = {row_file: label.texts[row_file]}
        binding = re.search(r"^\s*text:\s*(.+)$", label.id_block("usagePaceLabel"), re.M).group(1)
        applet.texts = {main: source}
        functions = []
        for name in ("presentUsageWindow", "paceSummaryPartsText", "paceEtaText", "copyObject", "usagePaceText"):
            match = re.search(r"function " + name + r"\([^)]*\)", source)
            if match:
                functions.append(match.group(0) + " {" + applet.function_body(name) + "}")
        qml = POPUP_PACE_QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n".join(functions)).replace("PACE_LABEL_TEXT", binding)
        run_qml(self, qml, "tst_popup_pace_clock.qml")


if __name__ == "__main__":
    unittest.main()
