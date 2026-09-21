"""Exercise the production panel text fallback in Qt's event loop."""

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
TestCase {
    name: "PanelSelectionText"
    QtObject {
        id: applet
        property string panelProviderIDsRaw: ""
        property bool loading: false
        property string menuBarDisplayMode: "percent"
        property var panelVisibilityRules: PanelRules.normalizedRules("{}")
        property real panelClockMs: Date.now()
        function selectedCompactProvider() { return null; }
        function providerPresentation(item) { return item; }
        function panelDisplayRow(item, mode) { return null; }
        function i18n(text) { return text; }
        SOURCE_FUNCTIONS
    }
    function test_emptyRosterText_data() {
        return [
            {tag: "automatic-idle", selection: "", loading: false, expected: "CodexBar"},
            {tag: "automatic-loading", selection: "", loading: true, expected: "Loading"},
            {tag: "none-idle", selection: "__none__", loading: false, expected: ""},
            {tag: "none-loading", selection: "__none__", loading: true, expected: ""},
            {tag: "unavailable-idle", selection: "unknown-provider", loading: false, expected: ""},
            {tag: "unavailable-loading", selection: "unknown-provider", loading: true, expected: ""}
        ];
    }
    function test_emptyRosterText(data) {
        applet.panelProviderIDsRaw = data.selection;
        applet.loading = data.loading;
        compare(applet.compactText(), data.expected);
    }
}
'''


class PanelSelectionTests(unittest.TestCase):
    def test_production_text_distinguishes_automatic_and_explicit_empty_rosters(self):
        surface = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = surface.texts[main]
        surface.texts = {main: source}
        # The fallback lives in the segment builder now; compactText() only
        # joins what survives, so the surface needs both halves.
        functions = []
        for name in ("compactTextSegments", "compactText"):
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + surface.function_body(name) + "}")
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n        ".join(functions))
        with tempfile.TemporaryDirectory(prefix="codexbar-panel-selection-") as temporary:
            fixture = Path(temporary) / "tst_panel_selection.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class CompactProvidersTests(unittest.TestCase):
    # Only compact rendering narrows to the panel-filtered roster, and only
    # to the meters the visibility rules still allow: a hidden meter drops
    # its provider instead of printing a row the user asked to hide.
    COMPACT_FUNCTIONS = (
        "compactProviders", "panelProviderItems", "panelMeterRows",
        "switcherCandidateRows", "usageRowForLane", "appendUniqueUsageRow",
        "providerKey", "clamp",
    )

    COMPACT_QML = '''import QtQuick
import QtTest
import "SOURCE_URL/PanelProviders.js" as PanelProviders
import "SOURCE_URL/PanelRules.js" as PanelRules
import "SOURCE_URL/PanelDisplay.js" as PanelDisplay
import "SOURCE_URL/ProviderIdentity.js" as ProviderIdentity
import "SOURCE_URL/ProviderNormalizer.js" as Normalizer
TestCase {
    name: "CompactProviders"
    property var providers: []
    property string panelProviderIDsRaw: ""
    property string panelQuotaLane: "primary"
    property var panelVisibilityRules: PanelRules.normalizedRules("{}")
    property real panelClockMs: Date.now()
    // QML rejects a property named Plasmoid, so the harness rewrites the
    // configuration read; see the substitution below.
    property var hostConfiguration: ({showMultiProviderInPanel: true})
    function providerPresentation(item) { return item; }
    SOURCE_FUNCTIONS
    function meterItem(used) {
        return {provider: "codex", rows: [{lane: "primary", hasPercent: true,
            usedPercent: used, leftPercent: 100 - used}]};
    }
    function test_allowedMetersKeepTheProvider() {
        providers = [meterItem(43)];
        compare(compactProviders().length, 1);
        providers = [];
    }
    function test_hiddenMetersDropTheProvider() {
        providers = [meterItem(43)];
        panelVisibilityRules = PanelRules.normalizedRules(
            JSON.stringify({meters: {condition: "usageAtLeast", usedPercent: 99}}));
        compare(compactProviders().length, 0);
        panelVisibilityRules = PanelRules.normalizedRules("{}");
        providers = [];
    }
    function test_disabledMultiProviderShowsNothing() {
        providers = [meterItem(43)];
        hostConfiguration = ({showMultiProviderInPanel: false});
        compare(compactProviders().length, 0);
        hostConfiguration = ({showMultiProviderInPanel: true});
        providers = [];
    }
}
'''

    def test_production_compact_providers_honor_visibility_rules(self):
        surface = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = surface.texts[main]
        surface.texts = {main: source}
        functions = []
        for name in self.COMPACT_FUNCTIONS:
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append((signature + " {" + surface.function_body(name) + "}")
                             .replace("Plasmoid.configuration", "hostConfiguration"))
        qml = self.COMPACT_QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n    ".join(functions))
        with tempfile.TemporaryDirectory(prefix="codexbar-compact-providers-") as temporary:
            fixture = Path(temporary) / "tst_compact_providers.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class ProviderSelectionTests(unittest.TestCase):
    # The roster selectors behind the panel, popup and overview: index
    # lookup, ID filtering, automatic ranking and selection reconciliation
    # have no other executed pin.
    SELECT_FUNCTIONS = (
        "providerIndexForID", "overviewProviders", "panelProviderItems",
        "autoSelectedProviderIndex", "updateSelectedProvider",
        "selectedCompactProvider", "globalViewAvailability",
        "boundedConfigRevision",
    )

    SELECT_QML = '''import QtQuick
import QtTest
import "SOURCE_URL/OverviewProviders.js" as OverviewProviders
import "SOURCE_URL/PanelProviders.js" as PanelProviders
import "SOURCE_URL/ProviderAutoSelect.js" as ProviderAutoSelect
import "SOURCE_URL/PopupSelection.js" as PopupSelection
TestCase {
    name: "ProviderSelection"
    property var providers: []
    property string selectedProviderID: ""
    property string selectedGlobalView: "overview"
    property bool selectionInitialized: false
    property bool autoSelectProvider: false
    property string panelProviderIDsRaw: ""
    property string overviewProviderIDsRaw: ""
    property bool overviewAvailable: true
    property bool spendAvailable: true
    property bool sessionsAvailable: true
    property int selectedProviderIndex: providerIndexForID(selectedProviderID)

    SOURCE_FUNCTIONS

    function init() {
        providers = [];
        selectedProviderID = "";
        selectedGlobalView = "overview";
        selectionInitialized = false;
        autoSelectProvider = false;
        panelProviderIDsRaw = "";
        overviewProviderIDsRaw = "";
    }
    function roster() {
        return [{provider: "codex"}, {provider: "claude"}];
    }
    function test_indexLookupFindsKnownProvidersOnly() {
        providers = roster();
        compare(providerIndexForID("codex"), 0);
        compare(providerIndexForID("claude"), 1);
        compare(providerIndexForID("unknown"), -1);
        compare(providerIndexForID(""), -1);
    }
    function test_overviewAndPanelFiltersFollowTheirStoredIDs() {
        providers = roster();
        compare(overviewProviders().length, 2);
        compare(panelProviderItems().length, 2);
        overviewProviderIDsRaw = "claude";
        panelProviderIDsRaw = "codex";
        compare(overviewProviders().map(function(item) { return item.provider; }), ["claude"]);
        compare(panelProviderItems().map(function(item) { return item.provider; }), ["codex"]);
    }
    function test_automaticIndexDelegatesToTheRankedBest() {
        var items = roster();
        compare(autoSelectedProviderIndex(items), ProviderAutoSelect.bestIndex(items));
    }
    function test_reconciliationKeepsAStoredProviderAndStartsEmpty() {
        providers = roster();
        selectedProviderID = "claude";
        selectionInitialized = true;
        updateSelectedProvider();
        compare(selectedProviderID, "claude");
        verify(selectionInitialized);
        // An uninitialized applet with an available overview lands on the
        // global view instead of inheriting the first roster entry.
        selectedProviderID = "";
        selectionInitialized = false;
        updateSelectedProvider();
        compare(selectedProviderID, "");
        compare(selectedGlobalView, "overview");
        verify(selectionInitialized);
        // A stored provider that left the roster falls back to first entry.
        selectedProviderID = "unknown";
        updateSelectedProvider();
        compare(selectedProviderID, "codex");
        providers = [];
        selectedProviderID = "";
        selectionInitialized = false;
        updateSelectedProvider();
        compare(selectedProviderID, "");
        verify(!selectionInitialized);
    }
    function test_compactProviderFallsBackToTheFirstPanelItem() {
        compare(selectedCompactProvider(), null);
        providers = roster();
        compare(selectedCompactProvider().provider, "codex");
        panelProviderIDsRaw = "claude";
        compare(selectedCompactProvider().provider, "claude");
    }
    function test_configRevisionBoundingRejectsGarbage() {
        compare(boundedConfigRevision("3"), 3);
        compare(boundedConfigRevision("2.9"), 2);
        compare(boundedConfigRevision("bogus"), 0);
        compare(boundedConfigRevision("-4"), 0);
        compare(boundedConfigRevision("9999999999"), 2147480000);
    }
}
'''

    def test_production_selectors_resolve_panels_popups_and_overview(self):
        surface = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = surface.texts[main]
        surface.texts = {main: source}
        functions = []
        for name in self.SELECT_FUNCTIONS:
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + surface.function_body(name) + "}")
        qml = self.SELECT_QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n".join(functions))
        with tempfile.TemporaryDirectory(prefix="codexbar-provider-selection-") as temporary:
            fixture = Path(temporary) / "tst_provider_selection.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
