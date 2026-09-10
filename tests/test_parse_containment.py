"""A malformed provider must not abort the usage refresh or stall loading."""

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
    "parseOutput", "canUseProviderFallback", "hasSelectedAccountOverrides",
    "hasOwnKey", "isCliRecord", "normalizedProviderID", "boundedCliMessage",
)

QML = '''import QtQuick
import QtTest
import "SOURCE_URL/ProviderNormalizer.js" as Normalizer
import "SOURCE_URL/ProviderOrder.js" as ProviderOrder
import "SOURCE_URL/Guards.js" as Guards
import "SOURCE_URL/SafeText.js" as SafeText
TestCase {
    name: "ParseContainment"
    Component {
        id: harness
        QtObject {
            id: root
            property string source: ""
            property var selectedAccounts: ({})
            property var providers: []
            property string errorText: ""
            property bool loading: false
            property int maximumProviderSnapshots: 256
            property string providerOrderRaw: ""
            property string explodingProvider: ""
            property var committed: null
            property var failCalls: []
            property var fallbackCalls: []

            SOURCE_FUNCTIONS

            function i18n(text) { return text; }
            function normalizeProvider(item) {
                if (item.provider === explodingProvider) {
                    throw new Error("synthetic normalization failure");
                }
                return {provider: item.provider};
            }
            function commitUsageSnapshot(items) {
                committed = items;
            }
            function failUsageRefresh(message) {
                failCalls = failCalls.concat(message);
                loading = false;
            }
            function startProviderFallback() {
                fallbackCalls = fallbackCalls.concat(true);
            }
        }
    }

    function test_malformedProviderKeepsHealthyProvidersAndSettlesLoading() {
        var applet = createTemporaryObject(harness, this, {explodingProvider: "evil"});
        verify(applet !== null);
        wait(0);
        applet.loading = true;
        applet.parseOutput('[{"provider": "codex"}, {"provider": "evil"}]', "");
        compare(applet.fallbackCalls.length, 0);
        compare(applet.failCalls.length, 0);
        verify(applet.committed !== null);
        compare(applet.committed.length, 1);
        compare(applet.committed[0].provider, "codex");
        compare(applet.errorText, "");
        compare(applet.loading, false);
    }

    function test_allProvidersMalformedFailsTheRefresh() {
        var applet = createTemporaryObject(harness, this, {explodingProvider: "codex"});
        verify(applet !== null);
        wait(0);
        applet.loading = true;
        applet.parseOutput('[{"provider": "codex"}]', "");
        compare(applet.committed, null);
        compare(applet.failCalls.length, 1);
        verify(String(applet.failCalls[0]).indexOf("did not return provider data") !== -1);
        compare(applet.loading, false);
    }

    function test_unparseablePayloadFailsTheRefresh() {
        var applet = createTemporaryObject(harness, this, {});
        verify(applet !== null);
        wait(0);
        applet.loading = true;
        applet.parseOutput("{oops", "");
        compare(applet.committed, null);
        compare(applet.failCalls.length, 1);
        verify(String(applet.failCalls[0]).indexOf("Could not parse codexbar JSON") !== -1);
        compare(applet.loading, false);
    }
}
'''


class ParseContainmentTests(unittest.TestCase):
    def test_normalization_failures_stay_per_provider(self):
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
        with tempfile.TemporaryDirectory(prefix="codexbar-parse-containment-") as temporary:
            fixture = Path(temporary) / "tst_parse_containment.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
