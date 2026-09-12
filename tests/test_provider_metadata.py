"""Malformed provider metadata must preserve healthy and last-known quotas."""

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
    "parseOutput", "normalizeProvider", "presentProviderSnapshot", "presentUsageWindow", "copyObject", "resetText",
    "isCliRecord", "normalizedProviderID", "providerMapKey", "hasOwnKey",
    "boundedCliMessage", "paceSummaryText", "paceSummaryPartsText", "paceEtaText", "providerTitle",
    "providerKey", "statusText",
    "planText", "capitalize",
)

QML = '''import QtQuick
import QtTest
import "SOURCE_URL/ProviderNormalizer.js" as Normalizer
import "SOURCE_URL/ProviderSnapshot.js" as ProviderSnapshot
import "SOURCE_URL/ProviderIdentity.js" as ProviderIdentity
import "SOURCE_URL/ProviderOrder.js" as ProviderOrder
import "SOURCE_URL/Guards.js" as Guards
import "SOURCE_URL/SafeText.js" as SafeText
import "SOURCE_URL/PacePresentation.js" as PacePresentation
import "SOURCE_URL/UsageCache.js" as UsageCache
TestCase {
    name: "ProviderMetadata"
    Component {
        id: harness
        QtObject {
            id: root
            property var providers: []
            property var providerDisplayNames: ({})
            property string providerOrderRaw: ""
            property string errorText: ""
            property bool loading: true
            property double panelClockMs: Date.UTC(2026, 8, 11, 12)
            property int maximumProviderSnapshots: Normalizer.maximumProviderSnapshots

            SOURCE_FUNCTIONS

            function i18n(text) {
                for (var i = 1; i < arguments.length; i++) {
                    text = text.replace("%" + i, String(arguments[i]));
                }
                return text;
            }
            function i18np(one, many, count) { return i18n(count === 1 ? one : many, count); }
            // Observe publication without running processes or persisting data.
            // Parsing, normalization and quota retention are production.
            function commitUsageSnapshot(items) {
                providers = UsageCache.reconcile(providers, items, panelClockMs);
            }
            function failUsageRefresh(message) { errorText = message; loading = false; }
            function canUseProviderFallback() { return false; }
            function rateWindowLabel() { return "Quota"; }
            function providerCostSection() { return null; }
            function resetCreditsSection() { return null; }
            function providerTokenCost() { return null; }
            function providerDashboardUrl() { return ""; }
            function safeStatusUrl() { return ""; }
            function providerChangelogUrl() { return ""; }
        }
    }

    function test_optionalNameKeepsQuota_data() {
        return [
            {tag: "structured-display-name", field: "displayName", value: {toString: null}, used: 72, title: "Codex"},
            {tag: "structured-title-zero", field: "title", value: {toString: null}, used: 0, title: "Codex"},
            {tag: "structured-array-name", field: "displayName", value: [{toString: null}], used: 72, title: "Codex"},
            {tag: "valid-display-name", field: "displayName", value: "  Custom Codex  ", used: 72, title: "Custom Codex"},
            {tag: "valid-title", field: "title", value: "Custom Codex", used: 72, title: "Custom Codex"},
            {tag: "missing-name", field: "displayName", value: null, used: 0, title: "Codex"},
            {tag: "numeric-name", field: "displayName", value: 42, used: 72, title: "42"},
            {tag: "boolean-name", field: "displayName", value: true, used: 72, title: "true"},
            {tag: "zero-name", field: "displayName", value: 0, used: 72, title: "Codex"},
            {tag: "bounded-name", field: "displayName", value: "x".repeat(200), used: 72, title: "x".repeat(120)}
        ];
    }

    function test_optionalNameKeepsQuota(data) {
        var applet = createTemporaryObject(harness, this, {});
        verify(applet !== null);
        var payload = {
            provider: "codex",
            account: "Synthetic  Account",
            usage: {primary: {usedPercent: data.used}},
            credits: {remaining: 7},
            status: {indicator: "minor", incidentId: "synthetic-incident"}
        };
        payload[data.field] = data.value;
        var encoded = JSON.stringify([
            payload,
            {provider: "claude", usage: {primary: {usedPercent: 12}}}
        ]);
        // These are ordinary JSON values, not executable getters/functions.
        applet.parseOutput(encoded, "");
        compare(applet.providers.length, 2, "optional provider name discarded valid usage");
        var item = applet.providers.filter(function(provider) { return provider.provider === "codex"; })[0];
        verify(item !== undefined);
        compare(item.title, data.title);
        compare(item.error, "");
        compare(item.rows.length, 1);
        compare(item.rows[0].hasPercent, true);
        compare(item.rows[0].usedPercent, data.used);
        compare(item.rows[0].leftPercent, 100 - data.used);
        compare(item.accountKey, "Synthetic  Account");
        compare(item.credits, 7);
        compare(item.statusKnown, true);
        compare(item.statusSeverity, "minor");
        compare(item.statusIncidentKey, "synthetic-incident");
        compare(applet.providers.filter(function(provider) { return provider.provider === "claude"; })[0].rows[0].usedPercent, 12);
        compare(applet.errorText, "");
        verify(!applet.loading);
    }

    function test_errorWithoutDisplayableMessageRetainsQuota_data() {
        return [
            {tag: "missing-message", error: {code: 1, kind: "provider"}},
            {tag: "empty-message", error: {code: 1, message: ""}},
            {tag: "blank-message", error: {code: 1, message: "   "}},
            {tag: "null-message", error: {code: 1, message: null}},
            {tag: "object-message", error: {code: 1, message: {detail: "Synthetic failure"}}},
            {tag: "structured-message", error: {code: 1, message: {toString: null}}},
            {tag: "array-message", error: {code: 1, message: [{toString: null}]}},
            {tag: "valid-message", error: {code: 1, message: "Synthetic failure"}}
        ];
    }

    function test_errorWithoutDisplayableMessageRetainsQuota(data) {
        var applet = createTemporaryObject(harness, this, {});
        verify(applet !== null);
        applet.parseOutput(JSON.stringify([
            {provider: "codex", usage: {primary: {usedPercent: 72}}},
            {provider: "claude", usage: {primary: {usedPercent: 12}}}
        ]), "");
        var measuredAt = applet.providers[0].lastGoodAtMs;
        applet.panelClockMs += 60000;
        applet.loading = true;
        applet.parseOutput(JSON.stringify([
            {provider: "codex", error: data.error,
                status: {indicator: "major", incidentId: "synthetic-incident"}},
            {provider: "claude", usage: {primary: {usedPercent: 45}}}
        ]), "");
        compare(applet.providers.length, 2);
        var retained = applet.providers[0];
        verify(retained.error.length > 0, "An error envelope must not become a successful empty snapshot");
        compare(retained.rows.length, 1);
        compare(retained.rows[0].usedPercent, 72);
        compare(retained.lastGoodAtMs, measuredAt);
        verify(retained.usageStale);
        compare(retained.statusKnown, true);
        compare(retained.statusSeverity, "major");
        compare(retained.error, data.tag === "valid-message" ? "Synthetic failure" : "codexbar command failed.");
        compare(applet.providers[1].rows[0].usedPercent, 45);
        verify(!applet.providers[1].usageStale);
        verify(!applet.loading);
    }

    function test_successWithoutQuotaClearsPreviousMeasurement_data() {
        return [{tag: "absent-error"}, {tag: "null-error", error: null}];
    }

    function test_successWithoutQuotaClearsPreviousMeasurement(data) {
        var applet = createTemporaryObject(harness, this, {});
        applet.parseOutput(JSON.stringify({
            provider: "codex", usage: {primary: {usedPercent: 72}}
        }), "");
        applet.parseOutput(JSON.stringify({provider: "codex", error: data.error}), "");
        compare(applet.providers.length, 1);
        compare(applet.providers[0].error, "");
        compare(applet.providers[0].rows.length, 0);
        verify(!applet.providers[0].usageStale);
    }

    function test_optionalLoginMethodKeepsQuota_data() {
        return [
            {tag: "structured-array", method: [{toString: null}], fallback: undefined, expected: ""},
            {tag: "structured-array-fallback", method: [{toString: null}], fallback: "pro", expected: "Pro"},
            {tag: "structured-object-fallback", method: {toString: null}, fallback: "plus", expected: "Plus"},
            {tag: "blank-fallback", method: "  ", fallback: "pro", expected: "Pro"},
            {tag: "oversized-fallback", method: "x".repeat(257), fallback: "pro", expected: "Pro"},
            {tag: "valid-preferred", method: "plus", fallback: "pro", expected: "Plus"},
            {tag: "valid-fallback", method: undefined, fallback: "pro", expected: "Pro"}
        ];
    }

    function test_optionalLoginMethodKeepsQuota(data) {
        var applet = createTemporaryObject(harness, this, {});
        verify(applet !== null);
        applet.parseOutput(JSON.stringify([
            {provider: "codex", account: "Synthetic  Account", usage: {
                identity: {loginMethod: data.method}, loginMethod: data.fallback,
                primary: {usedPercent: 72}
            }},
            {provider: "claude", usage: {primary: {usedPercent: 12}}}
        ]), "");
        compare(applet.providers.length, 2, "optional login method discarded valid usage");
        var item = applet.providers[0];
        compare(item.provider, "codex");
        compare(item.planText, data.expected);
        compare(item.loginMethod, data.expected.toLowerCase());
        compare(item.accountKey, "Synthetic  Account");
        compare(item.rows.length, 1);
        compare(item.rows[0].usedPercent, 72);
        compare(applet.providers[1].rows[0].usedPercent, 12);
        compare(item.error, "");
        compare(applet.errorText, "");
        verify(!applet.loading);
    }
}
'''


class ProviderMetadataTests(unittest.TestCase):
    def test_provider_metadata_preserves_valid_quotas(self):
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
        with tempfile.TemporaryDirectory(prefix="codexbar-provider-metadata-") as temporary:
            fixture = Path(temporary) / "tst_provider_metadata.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
