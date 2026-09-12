"""Malformed optional reset metadata must not discard a valid provider quota."""

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
    "normalizeProvider", "presentProviderSnapshot", "presentUsageWindow", "copyObject", "resetText",
    "isCliRecord", "normalizedProviderID", "providerMapKey", "hasOwnKey",
    "boundedCliMessage", "paceSummaryText", "paceSummaryPartsText", "paceEtaText",
)

QML = '''import QtQuick
import QtTest
import "SOURCE_URL/ProviderNormalizer.js" as Normalizer
import "SOURCE_URL/ProviderSnapshot.js" as ProviderSnapshot
import "SOURCE_URL/UsageResponse.js" as UsageResponse
import "SOURCE_URL/ProviderOrder.js" as ProviderOrder
import "SOURCE_URL/Guards.js" as Guards
import "SOURCE_URL/SafeText.js" as SafeText
import "SOURCE_URL/PacePresentation.js" as PacePresentation
TestCase {
    name: "QuotaResetMetadata"
    Component {
        id: harness
        QtObject {
            id: root
            property var providers: []
            property var providerDisplayNames: ({})
            property string providerOrderRaw: ""
            property bool loading: true
            property double panelClockMs: Date.UTC(2026, 8, 11, 12)
            property int maximumProviderSnapshots: Normalizer.maximumProviderSnapshots

            SOURCE_FUNCTIONS

            function parseOutput(stdout, stderr) {
                var result = UsageResponse.response(stdout, stderr, "", panelClockMs);
                compare(result.outcome, "success");
                commitUsageSnapshot(result.items.map(function(item) { return root.presentProviderSnapshot(item); }));
                loading = false;
            }

            function i18n(text) {
                for (var i = 1; i < arguments.length; i++) {
                    text = text.replace("%" + i, String(arguments[i]));
                }
                return text;
            }
            function i18np(one, many, count) { return i18n(count === 1 ? one : many, count); }
            // Observe the parser's publication boundary. Quota parsing,
            // bounded normalization and reset formatting above are production.
            function commitUsageSnapshot(items) { providers = items; }
            function rateWindowLabel() { return "Quota"; }
            function providerTitle(providerID) { return providerID; }
            function providerCostSection() { return null; }
            function resetCreditsSection() { return null; }
            function providerTokenCost() { return null; }
            function planText() { return ""; }
            function providerDashboardUrl() { return ""; }
            function safeStatusUrl() { return ""; }
            function providerChangelogUrl() { return ""; }
            function statusText() { return ""; }
        }
    }

    function test_optionalResetKeepsQuota_data() {
        return [
            {tag: "structured-reset", used: 72, extra: false,
                window: {usedPercent: 72, resetsAt: {toString: null}}, reset: ""},
            {tag: "structured-extra-reset-zero", used: 0, extra: true,
                window: {usedPercent: 0, resetsAt: [{toString: null}]}, reset: ""},
            {tag: "valid-iso-reset", used: 72, extra: false,
                window: {usedPercent: 72, resetsAt: "2026-09-11T13:00:00Z"}, reset: "1h"},
            {tag: "description-only", used: 72, extra: false,
                window: {usedPercent: 72, resetDescription: "Synthetic reset"}, reset: "Synthetic reset"},
            {tag: "null-reset-zero", used: 0, extra: false,
                window: {usedPercent: 0, resetsAt: null}, reset: ""}
        ];
    }

    function test_optionalResetKeepsQuota(data) {
        var applet = createTemporaryObject(harness, this, {});
        verify(applet !== null);
        var usage = data.extra
            ? {extraRateWindows: [{id: "extra", title: "Extra", window: data.window}]}
            : {primary: data.window};
        // Round-trip ordinary JSON through the real aggregate parser. No
        // functions or getters cross the CLI boundary in either failing case.
        applet.parseOutput(JSON.stringify([
            {provider: "codex", usage: usage},
            {provider: "claude", usage: {primary: {usedPercent: 12}}}
        ]), "");
        compare(applet.providers.length, 2, "optional reset metadata discarded a provider");
        var item = applet.providers.filter(function(provider) { return provider.provider === "codex"; })[0];
        verify(item !== undefined);
        compare(item.error, "");
        compare(item.rows.length, 1);
        compare(item.rows[0].hasPercent, true);
        compare(item.rows[0].usedPercent, data.used);
        compare(item.rows[0].leftPercent, 100 - data.used);
        compare(item.rows[0].lane, data.extra ? "extra" : "primary");
        compare(item.rows[0].reset, data.reset);
        compare(item.rows[0].resetsAt, typeof data.window.resetsAt === "string" ? data.window.resetsAt : "");
        verify(!applet.loading);
    }
}
'''


class QuotaResetMetadataTests(unittest.TestCase):
    def test_optional_reset_metadata_preserves_valid_quotas(self):
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
        with tempfile.TemporaryDirectory(prefix="codexbar-quota-reset-") as temporary:
            fixture = Path(temporary) / "tst_quota_reset.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
