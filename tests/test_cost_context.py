"""Exercise cost-context isolation with the production QML bindings."""

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
    "buildCostCommand", "shellQuote", "copyObject", "providerMapKey",
    "isCliRecord", "parseCostOutput",
    "providerTokenCost", "applyTokenCosts", "retireUsageCommandKind",
)

QML = '''import QtQuick
import QtTest
import "SOURCE_URL/ProviderNormalizer.js" as Normalizer
import "SOURCE_URL/Guards.js" as Guards
import "SOURCE_URL/CommandLedger.js" as CommandLedger
import "SOURCE_URL/CostPresentation.js" as CostPresentation
TestCase {
    name: "CostContext"
    Component {
        id: harness
        QtObject {
            id: root
            property string commandPath: "codexbar-a"
            property string provider: ""
            property bool costUsageEnabled: true
            property int costHistoryDays: 30
            property bool costLifecycleInitialized: true
            property var tokenCosts: ({})
            property string tokenCostsContext: ""
            property string costErrorText: ""
            property var activeCommandDescriptors: ({})
            property var providers: []
            property var finishedSources: []
            property var refreshCalls: []

            SOURCE_BINDINGS
            SOURCE_FUNCTIONS
            SOURCE_HANDLERS

            function i18n(text) { return text; }
            function boundedCliMessage(value) { return String(value); }
            function normalizeTokenCost(item, requestedHistoryDays) {
                return {provider: item.provider, historyDays: requestedHistoryDays};
            }
            function finishUsageCommandSource(sourceName) {
                finishedSources = finishedSources.concat(sourceName);
            }
            function refreshCost(force) {
                refreshCalls = refreshCalls.concat(force === true);
                return true;
            }
        }
    }

    function test_staleContextSnapshotsStayDetached() {
        var applet = createTemporaryObject(harness, this, {});
        verify(applet !== null);
        wait(0);
        var key = applet.providerMapKey("codex");
        var snapshot = {provider: "codex", historyDays: 30, total: 47};
        var costs = ({});
        costs[key] = snapshot;
        applet.tokenCosts = costs;
        applet.tokenCostsContext = applet.costCommandSource;
        // Move to a new executable: the retained map must not attach, even
        // when the history range still matches.
        applet.commandPath = "codexbar-b";
        compare(Object.keys(applet.tokenCosts).length, 1);
        compare(applet.providerTokenCost("codex"), null);
        applet.providers = [{provider: "codex"}];
        applet.applyTokenCosts();
        compare(applet.providers.length, 1);
        compare(applet.providers[0].tokenCost, null);
        // Control: the same snapshot serves the context that produced it.
        applet.commandPath = "codexbar-a";
        compare(applet.providerTokenCost("codex"), snapshot);
    }

    function test_rangeToggleReattachesRetainedSnapshots() {
        // Mirrors the usage-retention smoke run: two synchronous range changes
        // must reattach the retained map without waiting for a refetch.
        var applet = createTemporaryObject(harness, this, {});
        verify(applet !== null);
        wait(0);
        var key = applet.providerMapKey("codex");
        var snapshot = {provider: "codex", historyDays: 30, total: 47};
        var costs = ({});
        costs[key] = snapshot;
        applet.tokenCosts = costs;
        applet.tokenCostsContext = applet.costCommandSource;
        applet.providers = [{provider: "codex"}];
        applet.applyTokenCosts();
        compare(applet.providers[0].tokenCost, snapshot);
        applet.costHistoryDays = 7;
        applet.costHistoryDays = 30;
        compare(applet.providers[0].tokenCost, snapshot);
    }

    function test_costSourceChangeRetiresRunsWhileSnapshotsStayDetached() {
        var applet = createTemporaryObject(harness, this, {});
        verify(applet !== null);
        wait(0);
        var key = applet.providerMapKey("codex");
        var costs = ({});
        costs[key] = {provider: "codex", historyDays: 30, total: 47};
        applet.tokenCosts = costs;
        applet.tokenCostsContext = applet.costCommandSource;
        applet.activeCommandDescriptors = CommandLedger.opened({}, "cost#1", {kind: "cost"});
        applet.finishedSources = [];
        applet.refreshCalls = [];
        applet.commandPath = "codexbar-b";
        // The previous context's map is retained for a way back, but detached:
        // neither surface may render it beside the new context's quotas.
        compare(Object.keys(applet.tokenCosts).length, 1);
        compare(applet.tokenCostsContext !== applet.costCommandSource, true);
        compare(applet.providerTokenCost("codex"), null);
        compare(applet.finishedSources, ["cost#1"]);
        tryVerify(function() { return applet.refreshCalls.length > 0; });
        wait(0);
        compare(applet.refreshCalls, [true]);
    }

    function test_partialRefreshAfterSourceChangeDropsOldSnapshots() {
        // A partial reply from the new source must retain only failed
        // providers from the same source: merging the retained map would
        // re-tag the previous executable's costs with the new source.
        var applet = createTemporaryObject(harness, this, {});
        verify(applet !== null);
        wait(0);
        var oldCosts = ({});
        oldCosts[applet.providerMapKey("codex")] = {provider: "codex", historyDays: 30, total: 1};
        oldCosts[applet.providerMapKey("claude")] = {provider: "claude", historyDays: 30, total: 2};
        applet.tokenCosts = oldCosts;
        applet.tokenCostsContext = applet.costCommandSource;
        applet.commandPath = "codexbar-b";
        var partial = JSON.stringify([
            {provider: "codex"},
            {provider: "claude", error: {message: "cost failed"}}
        ]);
        applet.parseCostOutput(partial, "", 30);
        compare(applet.tokenCostsContext, applet.costCommandSource);
        verify(applet.tokenCosts[applet.providerMapKey("codex")] !== undefined);
        compare(applet.tokenCosts[applet.providerMapKey("codex")].historyDays, 30);
        // The failed provider has no fresh snapshot and no same-source
        // snapshot to retain, so it must stay absent instead of resurfacing
        // the previous executable's costs.
        verify(applet.tokenCosts[applet.providerMapKey("claude")] === undefined);
        compare(applet.providerTokenCost("claude"), null);
        // Control: the same partial reply in the producing context retains
        // the failed provider from that context's map.
        var sameCosts = ({});
        sameCosts[applet.providerMapKey("claude")] = {provider: "claude", historyDays: 30, total: 9};
        applet.tokenCosts = sameCosts;
        applet.tokenCostsContext = applet.costCommandSource;
        applet.parseCostOutput(partial, "", 30);
        compare(applet.tokenCosts[applet.providerMapKey("claude")].total, 9);
        compare(applet.providerTokenCost("claude").total, 9);
    }
}
'''


class CostContextTests(unittest.TestCase):
    def test_cost_snapshots_stay_with_their_command_source(self):
        applet = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = applet.texts[main]
        applet.texts = {main: source}
        # Successful cost parses must stamp the source they came from, so a
        # later source change can tell them apart from current data.
        applet.require("tokenCostsContext = costCommandSource",
                       "cost snapshots must record the source that produced them")
        # Both cost surfaces must refuse foreign snapshots; the spend tab reads
        # the map directly instead of going through providerTokenCost.
        applet.require("if (tokenCostsContext !== costCommandSource) {\n            return []",
                       "the spend tab must not total costs from another command source")
        functions = []
        for name in FUNCTIONS:
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + applet.function_body(name) + "}")
        bindings = [re.search(pattern, source, re.MULTILINE).group(0) for pattern in (
            r"^    property string costCommandSource: .+$",
            r"^    onCostHistoryDaysChanged: .+$",
        )]
        handlers = ["onCostCommandSourceChanged: {" + applet.handler_body("onCostCommandSourceChanged") + "}"]
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n".join(functions))
        qml = qml.replace("SOURCE_BINDINGS", "\n".join(bindings))
        qml = qml.replace("SOURCE_HANDLERS", "\n".join(handlers))
        with tempfile.TemporaryDirectory(prefix="codexbar-cost-context-") as temporary:
            fixture = Path(temporary) / "tst_cost_context.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
