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
import "SOURCE_URL/ResetPresentation.js" as ResetPresentation
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


class QuotaMarkerTests(unittest.TestCase):
    # The threshold markers on the usage bars and the severity colours on
    # badges and meter fills share one bounded threshold source; the flag
    # that hides the markers also quiets the colours.
    MARK_FUNCTIONS = (
        "quotaWarningMarkers", "quotaSeverity", "quotaMeterColor", "statusBadgeColor",
    )

    MARK_QML = '''import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "SOURCE_URL/QuotaThresholds.js" as QuotaThresholds
TestCase {
    name: "QuotaMarkers"
    property bool showQuotaWarningMarkers: true
    property bool usageBarsShowUsed: true
    property int quotaWarningPercent: 80
    property int quotaCriticalPercent: 95

    SOURCE_FUNCTIONS

    function init() {
        showQuotaWarningMarkers = true;
        usageBarsShowUsed = true;
    }
    function test_markersFollowTheVisibilityFlag() {
        var row = {hasPercent: true, usedPercent: 96};
        compare(quotaWarningMarkers(row),
            QuotaThresholds.markers(quotaWarningPercent, quotaCriticalPercent, usageBarsShowUsed));
        verify(quotaWarningMarkers(row).length > 0);
        showQuotaWarningMarkers = false;
        compare(quotaWarningMarkers(row), []);
    }
    function test_badgeColoursFollowSeverity() {
        // Compared against the real Theme singleton, so the test pins the
        // production mapping without hardcoding any theme palette.
        compare(statusBadgeColor("critical"), Kirigami.Theme.negativeTextColor);
        compare(statusBadgeColor("major"), Kirigami.Theme.negativeTextColor);
        compare(statusBadgeColor("minor"), Kirigami.Theme.neutralTextColor);
        compare(statusBadgeColor("maintenance"), Kirigami.Theme.neutralTextColor);
        compare(statusBadgeColor("unknown"), Kirigami.Theme.textColor);
        compare(statusBadgeColor(""), "transparent");
    }
    function test_meterFillUsesTheBadgeColourPastTheWarningStep() {
        compare(quotaMeterColor({hasPercent: true, usedPercent: 96}, "ACC"),
            Kirigami.Theme.negativeTextColor);
        compare(quotaMeterColor({hasPercent: true, usedPercent: 10}, "ACC"), "ACC");
        showQuotaWarningMarkers = false;
        compare(quotaMeterColor({hasPercent: true, usedPercent: 96}, "ACC"), "ACC");
    }
}
'''

    def test_production_markers_and_badge_colours_follow_thresholds(self):
        applet = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = applet.texts[main]
        applet.texts = {main: source}
        functions = []
        for name in self.MARK_FUNCTIONS:
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + applet.function_body(name) + "}")
        qml = self.MARK_QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n".join(functions))
        with tempfile.TemporaryDirectory(prefix="codexbar-quota-markers-") as temporary:
            fixture = Path(temporary) / "tst_quota_markers.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class ProviderColorTests(unittest.TestCase):
    # Provider swatches come from the shared brand table and stay readable on
    # the theme background; unknown providers fall back to the theme
    # highlight instead of inventing a color.
    COLOR_FUNCTIONS = (
        "providerColor", "readableAccentColor", "providerReadableColor",
    )

    COLOR_QML = '''import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "SOURCE_URL/ProviderIdentity.js" as ProviderIdentity
import "SOURCE_URL/ThemeContrast.js" as ThemeContrast
TestCase {
    name: "ProviderColors"

    SOURCE_FUNCTIONS

    function test_brandColorsSurviveAndUnknownFallsBackToHighlight() {
        // Compared against the live Theme singleton, so the test pins the
        // production mapping without hardcoding any theme palette.
        compare(providerColor("unknown-xyz"), Kirigami.Theme.highlightColor);
        verify(providerColor("codex") !== Kirigami.Theme.highlightColor);
        verify(providerColor("claude") !== Kirigami.Theme.highlightColor);
    }
    function test_readableColorKeepsContrastOnThemeBackground() {
        var background = Kirigami.Theme.backgroundColor;
        var readable = providerReadableColor("codex", background);
        verify(ThemeContrast.contrastRatio(readable, background)
            >= ThemeContrast.minimumNonTextContrastRatio);
        compare(providerReadableColor("codex"), providerReadableColor("codex", background));
        compare(providerReadableColor("unknown-xyz", background),
            readableAccentColor(Kirigami.Theme.highlightColor, background));
    }
}
'''

    def test_production_provider_colors_follow_brand_and_theme(self):
        applet = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = applet.texts[main]
        applet.texts = {main: source}
        functions = []
        for name in self.COLOR_FUNCTIONS:
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + applet.function_body(name) + "}")
        qml = self.COLOR_QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n".join(functions))
        with tempfile.TemporaryDirectory(prefix="codexbar-provider-colors-") as temporary:
            fixture = Path(temporary) / "tst_provider_colors.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
