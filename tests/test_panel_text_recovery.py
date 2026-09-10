"""Run the production panel-text surfaces in Qt's event loop.

A crowded panel surrenders whole content items, so the two facts that keep a
surrendered item recoverable have to hold in the shipped functions, not in a
test stub: the tooltip carries the credit balance the panel had no room for,
and a provider the widget has no bundled icon for keeps its name longer than
its balance, because the fallback icon identifies nothing.
"""

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
import QtTest
import "SOURCE_URL/PanelProviders.js" as PanelProviders
import "SOURCE_URL/PanelRules.js" as PanelRules
import "SOURCE_URL/PanelTextFit.js" as PanelTextFit
import "SOURCE_URL/ProviderIdentity.js" as ProviderIdentity
TestCase {
    name: "PanelTextRecovery"
    QtObject {
        id: applet
        property string panelProviderIDsRaw: ""
        property bool loading: false
        property bool showCreditsInPanel: true
        property string menuBarDisplayMode: "percent"
        property var panelVisibilityRules: PanelRules.normalizedRules("{}")
        property real panelClockMs: Date.now()
        property var selected: null
        // QML rejects a property named Plasmoid, so the harness rewrites the
        // configuration reads; see the substitution below.
        readonly property var panelConfiguration: ({
            showProviderInPanel: true, showPercentInPanel: true,
            showCreditsInPanel: applet.showCreditsInPanel
        })
        function selectedCompactProvider() { return selected; }
        function providerPresentation(item) { return item; }
        function panelDisplayRow(item, mode) { return item ? {hasPercent: true} : null; }
        function panelMeterDescription(item) { return "Primary: 43% used"; }
        function menuBarDisplayText(item) { return "43% used"; }
        function formatNumber(value) { return String(value); }
        function i18n(text, a, b) {
            return text.replace("%1", a === undefined ? "" : a).replace("%2", b === undefined ? "" : b);
        }
        SOURCE_FUNCTIONS
    }

    function provider(id, credits) {
        return {provider: id, title: "Example " + id, credits: credits,
                hasIncident: false, statusKnown: true, status: ""};
    }

    // A surrendered balance is on no meter, so the tooltip is the only place a
    // pointer user can still read it.
    function test_tooltipCarriesTheCreditBalanceThePanelSurrenders() {
        var line = applet.panelProviderToolTipText(provider("codex", 125));
        verify(line.indexOf("43% used") >= 0, line);
        verify(line.indexOf("125cr") >= 0, line);

        // Providers without a balance, and users who never asked the panel for
        // one, keep the previous tooltip.
        compare(applet.panelProviderToolTipText(provider("codex", null)),
                "Example codex: Primary: 43% used");
        applet.showCreditsInPanel = false;
        compare(applet.panelProviderToolTipText(provider("codex", 125)),
                "Example codex: Primary: 43% used");
        applet.showCreditsInPanel = true;
    }

    function test_unidentifiedProvidersKeepTheirNameLongerThanTheirBalance() {
        // Bundled icons and brand colors cover the same providers, so this is
        // the same test the renderer's icon fallback applies.
        verify(ProviderIdentity.providerBrandColorChannels("codex").length === 3);
        verify(ProviderIdentity.providerBrandColorChannels("an-unbundled-provider").length !== 3);

        applet.selected = provider("codex", 125);
        var known = applet.compactTextSegments();
        compare(known[0].id, "name");
        compare(known[0].identifying, false);
        compare(PanelTextFit.segmentTexts(known)[1], "43% used 125cr");

        applet.selected = provider("an-unbundled-provider", 125);
        var unknown = applet.compactTextSegments();
        compare(unknown[0].identifying, true);
        compare(PanelTextFit.segmentTexts(unknown)[1], "Example an-unbundled-provider 43% used");
    }
}
'''


class PanelTextRecoveryTests(unittest.TestCase):
    def test_production_panel_text_keeps_surrendered_content_recoverable(self):
        surface = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = surface.texts[main]
        surface.texts = {main: source}
        functions = []
        for name in ("compactTextSegments", "providerIconIdentifies", "panelProviderToolTipText"):
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            body = surface.function_body(name)
            # A property named Plasmoid is not addressable in QML, so the stub
            # exposes the same keys under a name the harness can declare.
            functions.append((signature + " {" + body + "}")
                             .replace("Plasmoid.configuration", "panelConfiguration"))
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n        ".join(functions))
        with tempfile.TemporaryDirectory(prefix="codexbar-panel-text-") as temporary:
            fixture = Path(temporary) / "tst_panel_text_recovery.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
