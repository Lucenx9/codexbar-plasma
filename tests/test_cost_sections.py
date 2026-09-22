"""Exercise the production cost sections with the real QML components."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/lib"))

QML_TEMPLATE = '''import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "SOURCE_URL/components" as Components
import "SOURCE_URL/CostPresentation.js" as CostPresentation
TestCase {
    id: testCase
    name: "CostSections"
    when: windowShown
    width: 600
    height: 800
    visible: true
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    function i18n(source) {
        var text = source;
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, String(arguments[i]));
        return text;
    }
    function i18np(one, many, count) {
        return String(count === 1 ? one : many).replace("%1", String(count));
    }

    property bool stillBuilding: true
    property var projectCosts: [{
        provider: "codex",
        projects: { rows: [
            { label: "Cost heavy", cost: 8, tokens: 100, currency: "USD" },
            { label: "Token heavy", cost: 1, tokens: 9000, currency: "USD" },
            { label: "Unpriced", cost: null, tokens: 50, currency: "USD" }
        ], truncated: false }
    }]
    property var providerTokenCost: ({
        today: { tokens: 10, cost: 1, currency: "USD" },
        totals: { tokens: 100, cost: null, currency: "USD",
            inputTokens: 60, outputTokens: 30,
            cacheReadTokens: 5, cacheCreationTokens: 5 },
        daily: [
            { label: "D1", cost: 1, tokens: 50, currency: "USD" },
            { label: "D2", cost: 2, tokens: 60, currency: "USD" }
        ],
        models: [{ label: "M1", cost: 3, tokens: 70, currency: "USD" }],
        modelsTruncated: false, hintLine: "",
        windowLabel: "30d", valueMode: "plain", historyDays: 30
    })
    property var providerData: ({ provider: "codex", tokenCost: providerTokenCost })
    property var spendCosts: [{
        provider: "codex", windowValueLine: "$5.00",
        historyCoverageEstablished: true,
        projects: { rows: [
            { label: "Priced", cost: 5, tokens: 100, currency: "USD" }
        ], truncated: false }
    }]
    property var presentedCosts: spendCosts.concat([{
        provider: "extra", windowValueLine: "$9.00",
        historyCoverageEstablished: true,
        projects: { rows: [
            { label: "Extra", cost: 9, tokens: 9, currency: "USD" }
        ], truncated: false }
    }])
    property var spendPoints: [
        { label: "2026-09-01", value: 1, displayValue: "$1" },
        { label: "2026-09-02", value: 2, displayValue: "$2" },
        { label: "2026-09-03", value: 3, displayValue: "$3" },
        { label: "2026-09-04", value: 4, displayValue: "$4" },
        { label: "2026-09-05", value: 5, displayValue: "$5" },
        { label: "2026-09-06", value: 6, displayValue: "$6" },
        { label: "2026-09-07", value: 7, displayValue: "$7" },
        { label: "2026-09-08", value: 8, displayValue: "$8" }
    ]

    QtObject {
        id: fakeApplet
        property bool costHistoryShowsTokens: false
        property int costHistoryDays: 30
        property string costHistoryMetric: "cost"
        property bool costLoading: false
        property string costErrorText: ""
        property real secondaryTextOpacity: 0.7
        property real valueTextOpacity: 0.85
        property real compactMeterTrackHeight: 8
        property real nestedSurfaceRadius: 4
        property string metricSet: ""
        property string daysSet: ""
        property int refreshCount: 0
        property var costNumberFormat: CostPresentation.numberFormat(",", ".")
        function accountKey(item) { return item.account || ""; }
        function accountLabel(item) { return item.account || ""; }
        function tokenCostHint(provider) { return "hint"; }
        function privateErrorText(text) { return text; }
        property double panelClockMs: 0
        function usageCountText(value) { return String(value) + " tokens"; }
        function amountString(value, currency) { return (currency || "USD") + " " + String(value); }
        function qualifiedCostValue(value) { return value; }
        function providerDisplayTitle(provider) { return provider; }
        function providerReadableColor(provider) { return "#3aa655"; }
        function readableAccentColor(a, b) { return "#3aa655"; }
        function withAlpha(color, alpha) { return color; }
        function providerIconSource(provider) { return ""; }
        function providerIconIsMask(provider) { return false; }
        function canvasColor(color, alpha) { return "#000000"; }
        function chartLineIndexAt(w, n, x, inset) { return 0; }
        function chartLineX(w, n, i, inset) { return i * 10; }
        function chartLineY(h, f, inset) { return h * (1 - f); }
        function chartBarGeometry(w, n) { return { offset: 0, step: 10, barWidth: 8 }; }
        function buildChartBarGradient(ctx, accent, base, a, b) { return "#000000"; }
        function paintRoundedTopBar(ctx, x, y, w, h, r) {}
        function costChartPoints(points) {
            return CostPresentation.chartPoints(costNumberFormat, points, costHistoryShowsTokens);
        }
        function costBreakdownRows(tokenCost) {
            if (!tokenCost || !tokenCost.totals)
                return [];
            var totals = tokenCost.totals;
            return CostPresentation.breakdownRows([
                { label: "Total tokens", tokens: totals.tokens },
                { label: "Input", tokens: totals.inputTokens },
                { label: "Output", tokens: totals.outputTokens },
                { label: "Cache read", tokens: totals.cacheReadTokens },
                { label: "Cache write", tokens: totals.cacheCreationTokens }
            ]);
        }
        function costModelRows(tokenCost) {
            return CostPresentation.modelRows(costNumberFormat, tokenCost, function(t) {
                return usageCountText(t);
            });
        }
        function costHistoryRows(tokenCost) {
            return CostPresentation.historyRows(costNumberFormat, tokenCost,
                costHistoryShowsTokens, "Latest");
        }
        function costPeakLine(points) { return points.length > 0 ? "Peak" : ""; }
        function costAverageDailyLine(points) { return points.length > 0 ? "Average" : ""; }
        function costPerMillionLine(tokenCost) { return ""; }
        function costSparklineSummary(daily) { return "summary"; }
        function spendDailyPoints() { return testCase.spendPoints; }
        function spendProviderCosts() { return testCase.spendCosts; }
        function presentedSpendProviderCosts(costs) { return testCase.presentedCosts; }
        function spendCurrency(costs) { return "USD"; }
        function spendTotalLine() { return "Total line"; }
        function spendHistoryStillBuilding() { return testCase.stillBuilding; }
        function setCostHistoryMetric(metric) { metricSet = metric; }
        function setCostHistoryDays(days) { daysSet = String(days); }
        function refreshCost(full) { refreshCount++; }
        function updateCostTrustNoticeState(scope, summary, dismiss) {
            return { key: scope, dismissed: dismiss, shouldShow: false };
        }
    }

    Component {
        id: projectFactory
        ColumnLayout {
            function i18n() { return testCase.i18n.apply(testCase, arguments); }
            function i18np(one, many, count) { return testCase.i18np(one, many, count); }
            Components.ProjectCostSection {
                applet: fakeApplet
                providerCosts: testCase.projectCosts
            }
        }
    }
    Component {
        id: providerFactory
        ColumnLayout {
            function i18n() { return testCase.i18n.apply(testCase, arguments); }
            function i18np(one, many, count) { return testCase.i18np(one, many, count); }
            Components.ProviderCostSection {
                applet: fakeApplet
                providerData: testCase.providerData
            }
        }
    }
    Component {
        id: spendFactory
        ColumnLayout {
            function i18n() { return testCase.i18n.apply(testCase, arguments); }
            function i18np(one, many, count) { return testCase.i18np(one, many, count); }
            Components.SpendView {
                applet: fakeApplet
            }
        }
    }

    function walkTree(item, out) {
        if (item === null || item === undefined || out.indexOf(item) >= 0)
            return;
        out.push(item);
        var groups = [item.children, item.resources, item.data];
        for (var g = 0; g < groups.length; g++) {
            var kids = groups[g];
            if (kids === undefined || kids === null)
                continue;
            for (var i = 0; i < kids.length; i++)
                walkTree(kids[i], out);
        }
    }

    function textsUnder(item) {
        var all = [];
        walkTree(item, all);
        return all.filter(function(child) {
            return child.text !== undefined;
        }).map(function(child) { return child.text; });
    }

/*TESTS*/
}
'''


class CostSectionTests(unittest.TestCase):
    def test_project_section_follows_metric_and_reports_unavailable(self):
        self.run_fixture('''
    // Project rows come from the shared presentation module and word the
    // selected metric; rows without a value name the missing metric.
    function test_projectSectionFollowsMetricAndReportsUnavailable() {
        var subject = createTemporaryObject(projectFactory, testCase);
        verify(subject !== null);
        var texts = textsUnder(subject);
        verify(texts.indexOf("Cost heavy") < texts.indexOf("Token heavy"));
        verify(texts.indexOf("USD 8") >= 0);
        verify(texts.indexOf("Cost unavailable") >= 0);
        fakeApplet.costHistoryShowsTokens = true;
        tryVerify(function() {
            var now = textsUnder(subject);
            return now.indexOf("Token heavy") < now.indexOf("Cost heavy")
                && now.indexOf("9000 tokens") >= 0
                && now.indexOf("100 tokens") >= 0
                && now.indexOf("50 tokens") >= 0
                && now.indexOf("Cost unavailable") === -1;
        });
        fakeApplet.costHistoryShowsTokens = false;
    }
    ''')

    def test_provider_section_binds_chart_and_drilldown(self):
        self.run_fixture('''
    // The provider section owns its chart and drill-down blocks: the chart
    // plots the daily points and the detail/history models follow the
    // applet row adapters, newest day first.
    function test_providerSectionBindsChartAndDrilldown() {
        var subject = createTemporaryObject(providerFactory, testCase);
        verify(subject !== null);
        var all = [];
        walkTree(subject, all);
        var charts = all.filter(function(item) {
            return item.toString().indexOf("InteractiveChart") >= 0;
        });
        compare(charts.length, 1);
        verify(charts[0].visible);
        var sections = all.filter(function(item) {
            return item.objectName === "providerLocalCostSection";
        });
        compare(sections.length, 1);
        var drill = all.filter(function(item) {
            return item.objectName === "costDrillDownSection";
        });
        compare(drill.length, 1);
        var history = all.filter(function(item) {
            return item.peakLine !== undefined && item.rows !== undefined;
        });
        compare(history.length, 1);
        compare(history[0].rows.length, 2);
        compare(history[0].rows[0].label, "D2");
        sections[0].detailsExpanded = true;
        tryVerify(function() {
            var texts = textsUnder(subject);
            return texts.indexOf("Total tokens") >= 0
                && texts.indexOf("M1") >= 0
                && texts.indexOf("Cost unavailable") >= 0
                && texts.indexOf("$2.00 \u00b7 60") >= 0;
        });
        var metricCombos = all.filter(function(item) {
            return item.objectName === "providerCostMetricCombo";
        });
        compare(metricCombos.length, 1);
        compare(metricCombos[0].currentIndex, 0);
        compare(charts[0].accessibleTitle, "Daily cost history");
        charts[0].selectedIndex = 0;
        compare(charts[0].selectedIndex, 0);
        fakeApplet.costHistoryShowsTokens = true;
        tryVerify(function() { return metricCombos[0].currentIndex === 1; });
        compare(charts[0].accessibleTitle, "Daily token history");
        tryVerify(function() { return charts[0].selectedIndex === -1; });
        fakeApplet.costHistoryShowsTokens = false;
    }
    ''')

    def test_provider_section_splits_cost_by_weekly_quota_window(self):
        self.run_fixture('''
    // The weekly usage row supplies the boundaries and the daily history the
    // amounts. Dates are built in local time so the check holds in any time
    // zone, and expected labels use the same formatter as the component.
    function test_providerSectionSplitsCostByWeeklyQuotaWindow() {
        function local(year, month, day, hour, minute) {
            return new Date(year, month - 1, day, hour || 0, minute || 0).getTime();
        }
        var daily = [];
        for (var i = 0; i < 14; i++) {
            var date = new Date(2026, 8, 9 + i);
            daily.push({ label: date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0")
                + "-" + String(date.getDate()).padStart(2, "0"), cost: i + 1, tokens: (i + 1) * 100 });
        }
        var reset = local(2026, 9, 24, 12, 22);
        fakeApplet.panelClockMs = local(2026, 9, 22, 12);
        var tokenCost = Object.assign({}, testCase.providerTokenCost, { daily: daily, currency: "USD" });
        testCase.providerData = { provider: "codex", tokenCost: tokenCost,
            rows: [{ lane: "secondary", windowMinutes: 10080, resetsAt: new Date(reset).toISOString() }] };
        var subject = createTemporaryObject(providerFactory, testCase);
        verify(subject !== null);
        var all = [];
        walkTree(subject, all);
        var section = all.filter(function(item) { return item.objectName === "quotaWindowSection"; })[0];
        verify(section !== undefined);
        compare(section.windows.length, 2);
        // Collapsed details keep the list out of the summary view.
        verify(!section.visible);
        all.filter(function(item) { return item.objectName === "providerLocalCostSection"; })[0].detailsExpanded = true;
        tryVerify(function() { return section.visible; });
        function stamp(ms) { return Qt.formatDateTime(new Date(ms), "MMM d, hh:mm"); }
        var texts = textsUnder(subject);
        verify(texts.indexOf("Quota weeks") >= 0);
        verify(texts.indexOf(stamp(reset - 7 * 86400000) + " - " + stamp(reset)) >= 0, texts.join(" | "));
        verify(texts.indexOf(stamp(reset - 14 * 86400000) + " - " + stamp(reset - 7 * 86400000)) >= 0);
        // A 12:22 reset splits days, so both totals are marked as estimated.
        verify(texts.indexOf("≈ USD 60 · 6000 tokens") >= 0, texts.join(" | "));
        verify(texts.indexOf("≈ USD 42 · 4200 tokens") >= 0);
        verify(texts.some(function(text) { return text.indexOf("≈ The history is kept per day") === 0; }));

        // Finite daily rows are still incomplete when the CLI says its local
        // history scan has not established coverage for the range.
        testCase.providerData = { provider: "codex",
            tokenCost: Object.assign({}, tokenCost, { historyCoverageEstablished: false }),
            rows: [{ lane: "secondary", windowMinutes: 10080, resetsAt: new Date(reset).toISOString() }] };
        tryVerify(function() {
            var updated = textsUnder(subject);
            return updated.indexOf("≈ at least USD 60 · at least 6000 tokens") >= 0
                && updated.indexOf("≈ at least USD 42 · at least 4200 tokens") >= 0;
        });

        // Without a weekly row there is nothing honest to split.
        testCase.providerData = { provider: "codex", tokenCost: tokenCost,
            rows: [{ lane: "primary", windowMinutes: 300, resetsAt: new Date(reset).toISOString() }] };
        tryVerify(function() { return section.windows.length === 0 && !section.visible; });
    }
    ''')

    def test_spend_view_presents_costs_and_controls(self):
        self.run_fixture('''
    // The spend view presents the ordered provider costs with its metric
    // controls, still-building notice, chart and heatmap readout.
    function test_spendViewPresentsCostsAndControls() {
        var subject = createTemporaryObject(spendFactory, testCase);
        verify(subject !== null);
        tryVerify(function() {
            var texts = textsUnder(subject);
            return texts.indexOf("Extra") >= 0 && texts.indexOf("Priced") >= 0;
        });
        var all = [];
        walkTree(subject, all);
        var combos = all.filter(function(item) {
            return typeof item.valueAt === "function" && item.model !== undefined
                && item.model.length === 2;
        });
        compare(combos.length, 1);
        combos[0].activated(1);
        compare(fakeApplet.metricSet, "tokens");
        var historyMsgs = all.filter(function(item) {
            return item.plainText !== undefined
                && item.plainText.indexOf("No daily") >= 0;
        });
        compare(historyMsgs.length, 1);
        compare(historyMsgs[0].plainText,
            "No daily cost history is available for this range. Try Tokens to check for token-only history.");
        fakeApplet.costHistoryShowsTokens = true;
        tryVerify(function() {
            return historyMsgs[0].plainText
                === "No daily token history is available for this range.";
        });
        fakeApplet.costHistoryShowsTokens = false;
        var notices = all.filter(function(item) {
            return item.plainText !== undefined
                && item.plainText.indexOf("still being collected") >= 0;
        });
        compare(notices.length, 1);
        verify(notices[0].visible);
        var texts = textsUnder(subject);
        var charts = all.filter(function(item) {
            return item.toString().indexOf("InteractiveChart") >= 0;
        });
        verify(charts.length >= 1);
        compare(charts[0].accessibleTitle, "Daily cost history");
        fakeApplet.costHistoryShowsTokens = true;
        tryVerify(function() {
            return charts[0].accessibleTitle === "Daily token history";
        });
        fakeApplet.costHistoryShowsTokens = false;
        verify(texts.indexOf("Activity heatmap") >= 0);
        var tips = all.filter(function(item) {
            return item.toString().indexOf("PlainToolTip") >= 0;
        });
        verify(tips.length >= 1);
    }
    ''')

    def run_fixture(self, snippet):
        qml = QML_TEMPLATE.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("/*TESTS*/", snippet)
        with tempfile.TemporaryDirectory(prefix="codexbar-cost-sections-") as temporary:
            fixture = Path(temporary) / "tst_cost_sections.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
