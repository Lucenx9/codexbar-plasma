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
import QtQuick.Window
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "SOURCE_URL/components" as Components
import "SOURCE_URL/CostPresentation.mjs" as CostPresentation
import "SOURCE_URL/CostAmounts.mjs" as CostAmounts
import "SOURCE_URL/CostChart.mjs" as CostChart
import "SOURCE_URL/CostCurrency.mjs" as CostCurrency
import "SOURCE_URL/CostTrust.mjs" as CostTrust
import "SOURCE_URL/CostResponse.mjs" as CostResponse
import "SOURCE_URL/PrivacyPresentation.js" as Privacy
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
    function i18nc(context) {
        return i18n.apply(testCase, Array.prototype.slice.call(arguments, 1));
    }

    property bool mirrored: false
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
        totals: {cost: 5, tokens: 100, currency: "USD"}, valueMode: "plain",
        historyCoverageEstablished: true,
        projects: { rows: [
            { label: "Priced", cost: 5, tokens: 100, currency: "USD" }
        ], truncated: false }
    }]
    property var presentedCosts: spendCosts.concat([{
        provider: "extra", windowValueLine: "$9.00",
        totals: {cost: 9, tokens: 9, currency: "USD"}, valueMode: "plain",
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
        property bool aiInsightsEnabled: false
        property bool aiInsightsConfigured: false
        property bool aiInsightsBusy: false
        property var aiInsightsCache: null
        property string aiInsightsCacheState: "none"
        property string aiInsightsErrorReason: ""
        property var aiInsightsSnapshot: ({sufficient: false})
        property var presentedProviders: []
        function aiInsightsErrorText(reason) { return reason; }
        property bool costHistoryShowsTokens: false
        property int costHistoryDays: 30
        property string costHistoryPeriod: ""
        property string costHistoryMetric: "cost"
        property bool costLoading: false
        property string costErrorText: ""
        property real secondaryTextOpacity: 0.7
        property real valueTextOpacity: 0.85
        property real compactMeterTrackHeight: 8
        property real roundedSurfaceRadius: 8
        property real nestedSurfaceRadius: 4
        property string metricSet: ""
        property string daysSet: ""
        property string periodSet: ""
        property int refreshCount: 0
        property int usageRefreshCount: 0
        property var costNumberFormat: CostAmounts.numberFormat(",", ".")
        function accountKey(item) { return item.account || ""; }
        function accountLabel(item) { return item.account || ""; }
        function tokenCostHint(provider) { return "hint"; }
        function privateErrorText(text) { return text; }
        property double panelClockMs: 0
        function usageCountText(value) { return String(value) + " tokens"; }
        function amountString(value, currency) { return (currency || "USD") + " " + String(value); }
        function qualifiedCostValue(value, mode) { return costText.qualifiedCostValue(value, mode); }
        function providerDisplayTitle(provider) { return provider; }
        function providerReadableColor(provider) { return "#3aa655"; }
        function readableAccentColor(a, b) { return "#3aa655"; }
        function withAlpha(color, alpha) { return color; }
        function providerIconSource(provider) { return ""; }
        function providerIconIsMask(provider) { return false; }
        function canvasColor(color, alpha) { return "#000000"; }
        function costChartPoints(points, memo) {
            return CostChart.memoizedChartPoints(memo, costNumberFormat, points, costHistoryShowsTokens);
        }
        function spendProviderCosts() {
            return testCase.spendCosts.map(function(item) {
                return Object.assign({}, item, {daily: testCase.spendPoints.map(function(point) {
                    return {label: point.label, cost: point.value, tokens: point.value, currency: "USD"};
                })});
            });
        }
        function presentedSpendProviderCosts(costs) {
            return costs.length > 0 && costs[0].points ? costs : testCase.presentedCosts;
        }
        function spendCurrency(costs) { return "USD"; }
        function spendTotalLine() { return "Total line"; }
        function setCostHistoryMetric(metric) { metricSet = metric; }
        function setCostHistoryDays(days) { daysSet = String(days); costHistoryDays = days; costHistoryPeriod = ""; }
        function setCostHistoryPeriod(period) { periodSet = period; costHistoryPeriod = period; }
        function refreshCost(full) { refreshCount++; }
        function refreshNow(full) { usageRefreshCount++; }
        function updateCostTrustNoticeState(scope, summary, dismiss) {
            return { key: scope, dismissed: dismiss, shouldShow: false };
        }
    }

    Components.CostText {
        id: costText
    }

    Component {
        id: projectFactory
        ColumnLayout {
            function i18n() { return testCase.i18n.apply(testCase, arguments); }
            function i18np(one, many, count) { return testCase.i18np(one, many, count); }
            function i18nc() { return testCase.i18nc.apply(testCase, arguments); }
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
            function i18nc() { return testCase.i18nc.apply(testCase, arguments); }
            Components.ProviderCostSection {
                applet: fakeApplet
                providerData: testCase.providerData
            }
        }
    }
    Component {
        id: providerScrollFactory
        PlasmaComponents.ScrollView {
            id: providerScroll
            LayoutMirroring.enabled: testCase.mirrored
            LayoutMirroring.childrenInherit: true
            width: 580
            height: 500
            contentWidth: availableWidth
            clip: true
            PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff
            ColumnLayout {
                width: providerScroll.availableWidth - Kirigami.Units.smallSpacing
                function i18n() { return testCase.i18n.apply(testCase, arguments); }
                function i18np(one, many, count) { return testCase.i18np(one, many, count); }
                function i18nc() { return testCase.i18nc.apply(testCase, arguments); }
                Components.ProviderCostSection {
                    applet: fakeApplet
                    providerData: testCase.providerData
                }
                Components.DisclosureButton {
                    objectName: "providerActionsToggle"
                    plainText: "Provider actions"
                    onClicked: expanded = !expanded
                }
            }
        }
    }
    Component {
        id: spendFactory
        ColumnLayout {
            property bool mirrored: false
            LayoutMirroring.enabled: mirrored
            LayoutMirroring.childrenInherit: true
            function i18n() { return testCase.i18n.apply(testCase, arguments); }
            function i18np(one, many, count) { return testCase.i18np(one, many, count); }
            function i18nc() { return testCase.i18nc.apply(testCase, arguments); }
            Components.SpendView {
                objectName: "testAnalysis"
                activityExpanded: true
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
    def test_provider_disclosures_keep_focus_inside_viewport(self):
        self.run_fixture('''
    function test_disclosureFocusBounds_data() {
        var cases = [];
        for (var width of [240, 540]) {
            for (var mirrored of [false, true]) {
                for (var name of ["costDetailsToggle", "providerActionsToggle"]) {
                    cases.push({tag: name + "-" + width + "-" + mirrored,
                        width: width, mirrored: mirrored, name: name});
                }
            }
        }
        return cases;
    }
    function test_disclosureFocusBounds(data) {
        testCase.mirrored = data.mirrored;
        var subject = createTemporaryObject(providerScrollFactory, testCase,
            {width: data.width, height: 800});
        verify(subject !== null);
        verify(waitForPolish(testCase.Window.window));
        var toggle = findChild(subject, data.name);
        verify(toggle !== null);
        // Both translated labels must fit with their complete native frame.
        toggle.plainText = data.name === "costDetailsToggle"
            ? "Mostra dettagli" : "Azioni del provider";
        toggle.forceActiveFocus(Qt.TabFocusReason);
        verify(waitForPolish(testCase.Window.window));
        verify(toggle.visualFocus);
        for (var item of [toggle, toggle.background]) {
            verify(item !== null);
            verify(item.mapToItem(subject, 0, 0).x >= 0,
                data.name + " starts outside the clipped viewport");
            verify(item.mapToItem(subject, item.width, 0).x <= subject.availableWidth,
                data.name + " ends outside the clipped viewport");
        }
        keyClick(Qt.Key_Space);
        verify(toggle.expanded);
        keyClick(Qt.Key_Space);
        verify(!toggle.expanded);
        mouseClick(toggle, 1, toggle.height / 2);
        verify(toggle.expanded, "The leading edge must remain clickable");
    }
    ''', style="org.kde.desktop")

    def test_provider_history_has_no_empty_project_tail(self):
        self.run_fixture('''
    function test_noEmptyProjectTail_data() {
        return [
            {tag: "wide-cost", width: 580, tokens: false},
            {tag: "narrow-cost", width: 240, tokens: false},
            {tag: "wide-tokens", width: 580, tokens: true},
            {tag: "narrow-tokens", width: 240, tokens: true}
        ];
    }
    function test_noEmptyProjectTail(options) {
        failOnWarning(/.*/);
        fakeApplet.costHistoryShowsTokens = options.tokens;
        testCase.providerData = {provider: "claude", tokenCost: null};
        var subject = createTemporaryObject(providerScrollFactory, testCase, {width: options.width});
        verify(subject !== null);
        verify(waitForPolish(testCase.Window.window));
        var section = findChild(subject, "providerLocalCostSection");
        var all = [];
        walkTree(section, all);
        var history = all.filter(function(item) {
            return item.peakLine !== undefined && item.rows !== undefined;
        })[0];
        verify(history !== undefined);
        var projectSection = findChild(subject, "projectCostSection");
        var base = testCase.providerTokenCost;
        var projects = {rows: [
            {label: "Example project", cost: 12, tokens: 100, currency: "USD"}
        ], truncated: false};
        for (var data of [
            {provider: "claude", projects: undefined},
            {provider: "codex", projects: projects},
            {provider: "claude", projects: undefined},
            {provider: "antigravity", projects: undefined},
            {provider: "codex", projects: {rows: [], truncated: false}},
            {provider: "future-provider", projects: {rows: [], truncated: true}},
            {provider: "future-provider", projects: projects}
        ]) {
            testCase.providerData = {provider: data.provider,
                tokenCost: Object.assign({}, base, {provider: data.provider, projects: data.projects})};
            verify(waitForPolish(testCase.Window.window));
            verify(!projectSection.visible, "Projects must stay hidden while details are collapsed");
            section.detailsExpanded = true;
            verify(waitForPolish(testCase.Window.window));
            var hasProjects = data.projects !== undefined
                && (data.projects.rows.length > 0 || data.projects.truncated);
            compare(projectSection.visible, hasProjects);
            if (!hasProjects) {
                var tail = section.height - history.mapToItem(section, 0, history.height).y;
                fuzzyCompare(tail, 0, 0.5, "Empty space below cost history");
            } else {
                verify(projectSection.height > 0);
                verify(projectSection.mapToItem(section, 0, 0).y >= history.y + history.height);
            }
            section.detailsExpanded = false;
            verify(waitForPolish(testCase.Window.window));
        }
    }
    ''')

    def test_spend_provider_totals_follow_metric_and_fit(self):
        self.run_fixture('''
    function test_spendProviderTotalsFollowMetricAndFit() {
        failOnWarning(/Binding loop|Detected recursive rearrange/);
        var subject = createTemporaryObject(spendFactory, testCase, {width: 540, height: 800});
        verify(subject !== null);
        var primary = findChild(subject, "spendProviderPrimary");
        var secondary = findChild(subject, "spendProviderSecondary");
        var title = findChild(subject, "spendProviderTitle");
        verify(primary && secondary && title);
        compare(primary.text, "$5.00");
        compare(secondary.text, "100 tokens");
        fakeApplet.costHistoryShowsTokens = true;
        compare(primary.text, "100 tokens");
        compare(secondary.text, "$5.00");
        compare(fakeApplet.refreshCount, 0);

        // Unknown is distinct from measured zero in either metric order.
        testCase.presentedCosts = [{provider: "codex", totals: {
            cost: null, tokens: 0, currency: "EUR"}, valueMode: "plain"}];
        tryVerify(function() {
            primary = findChild(subject, "spendProviderPrimary");
            return primary && primary.text === "0 tokens";
        });
        secondary = findChild(subject, "spendProviderSecondary");
        compare(secondary.text, "Cost unavailable");
        fakeApplet.costHistoryShowsTokens = false;
        compare(primary.text, "Cost unavailable");
        compare(secondary.text, "0 tokens");

        testCase.presentedCosts = [{provider: "Long <provider> & identity ".repeat(5),
            totals: {cost: 123456789, tokens: null, currency: "EUR"}, valueMode: "estimated"}];
        tryVerify(function() {
            primary = findChild(subject, "spendProviderPrimary");
            return primary && primary.text === "EUR 123,456,789.00 (estimated)";
        });
        secondary = findChild(subject, "spendProviderSecondary");
        title = findChild(subject, "spendProviderTitle");
        compare(secondary.text, "Tokens unavailable");
        var card = title.parent.parent;
        compare(card.Accessible.name, title.text);
        compare(card.Accessible.description, primary.text + ". " + secondary.text);
        for (var mirrored of [false, true]) {
            subject.mirrored = mirrored;
            for (var size of [540, 240]) {
                subject.width = size;
                wait(30);
                for (var label of [title, primary, secondary]) {
                    var pos = label.mapToItem(card, 0, 0);
                    verify(label.width > 0);
                    verify(pos.x >= 0 && pos.x + label.width <= card.width + 1);
                }
                var titleLeft = title.mapToItem(card, 0, 0).x;
                var valueLeft = primary.mapToItem(card, 0, 0).x;
                verify(mirrored ? valueLeft + primary.width <= titleLeft
                    : titleLeft + title.width <= valueLeft);
            }
        }
        subject.mirrored = false;
        primary.font.pointSize *= 2;
        secondary.font.pointSize *= 2;
        title.font.pointSize *= 2;
        wait(30);
        verify(primary.y + primary.height <= secondary.y);
        verify(card.height >= primary.height + secondary.height);
        verify(title.truncated && primary.truncated);
        mouseMove(card, card.width / 2, card.height / 2);
        var tree = [];
        walkTree(card, tree);
        var tooltips = tree.filter(function(item) { return item.plainText !== undefined; });
        compare(tooltips.length, 1);
        tryCompare(tooltips[0], "visible", true);
        compare(tooltips[0].plainText, title.text + "\\n" + primary.text + "\\n" + secondary.text);
        verify(tooltips[0].text.indexOf("&lt;provider&gt;") >= 0);
        mouseMove(testCase, testCase.width - 1, testCase.height - 1);
        card.forceActiveFocus(Qt.TabFocusReason);
        tryCompare(card, "visualFocus", true);
        tryCompare(tooltips[0], "visible", true);
        findChild(subject, "analysisProviderFilter").forceActiveFocus(Qt.TabFocusReason);
        tryCompare(tooltips[0], "visible", false);
    }
    ''')

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
        var metricToggles = all.filter(function(item) {
            return item.objectName === "providerCostMetricToggle";
        });
        compare(metricToggles.length, 1);
        compare(metricToggles[0].currentIndex, 0);
        // Both choices stay visible; a click asks the applet, and the checked
        // button follows the applet setting rather than the click.
        var toggleTree = [];
        walkTree(metricToggles[0], toggleTree);
        var metricButtons = toggleTree.filter(function(item) {
            return item.checkable === true;
        });
        compare(metricButtons.length, 2);
        verify(metricButtons[0].checked && !metricButtons[1].checked);
        fakeApplet.metricSet = "";
        mouseClick(metricButtons[1]);
        compare(fakeApplet.metricSet, "tokens");
        verify(metricButtons[0].checked && !metricButtons[1].checked);
        mouseClick(metricButtons[0]);
        compare(fakeApplet.metricSet, "cost");
        verify(metricButtons[0].checked, "clicking the checked metric must not uncheck it");
        compare(charts[0].accessibleTitle, "Daily cost history");
        // A peak figure supplies scale without repeating the axis end date.
        verify(charts[0].showPeak);
        verify(charts[0].peakIndex >= 0);
        charts[0].selectedIndex = 0;
        compare(charts[0].selectedIndex, 0);
        // The day reset is a flat inline action that clears the selection.
        var allDays = all.filter(function(item) {
            return item.objectName === "costAllDaysButton";
        });
        compare(allDays.length, 1);
        tryVerify(function() { return allDays[0].visible; });
        verify(allDays[0].flat);
        mouseClick(allDays[0]);
        tryVerify(function() { return charts[0].selectedIndex === -1; });
        verify(!allDays[0].visible);
        charts[0].selectedIndex = 0;
        fakeApplet.costHistoryShowsTokens = true;
        tryVerify(function() { return metricToggles[0].currentIndex === 1
                && metricButtons[1].checked && !metricButtons[0].checked; });
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
        // Month names and the hour cycle follow the regional format; the
        // catalog stub keeps the English word order.
        function stamp(ms) {
            var date = new Date(ms);
            var locale = Qt.locale();
            var time = locale.toString(date, locale.timeFormat(Locale.ShortFormat).replace(/:?ss/, ""));
            return locale.toString(date, "MMM") + " " + date.getDate() + ", " + time;
        }
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

    def test_quota_weeks_reject_invalid_reset_timestamps(self):
        self.run_fixture('''
    function test_invalidQuotaReset_data() {
        return [
            { tag: "impossible-day", reset: "2026-09-31T12:22:00Z" },
            { tag: "missing-timezone", reset: "2026-09-30T12:22:00" }
        ];
    }
    function test_invalidQuotaReset(data) {
        fakeApplet.panelClockMs = new Date(2026, 8, 28, 12).getTime();
        var tokenCost = Object.assign({}, testCase.providerTokenCost, {
            daily: [{ label: "2026-09-21", cost: 1, tokens: 100 },
                { label: "2026-09-28", cost: 1, tokens: 100 }], currency: "USD"
        });
        testCase.providerData = { provider: "codex", tokenCost: tokenCost,
            rows: [{ lane: "secondary", windowMinutes: 10080, resetsAt: "2026-09-30T12:22:00Z" }] };
        var subject = createTemporaryObject(providerFactory, testCase);
        verify(subject !== null);
        var all = [];
        walkTree(subject, all);
        var section = all.filter(function(item) { return item.objectName === "quotaWindowSection"; })[0];
        verify(section !== undefined);
        verify(section.windows.length > 0);
        testCase.providerData = { provider: "codex", tokenCost: tokenCost,
            rows: [{ lane: "secondary", windowMinutes: 10080, resetsAt: data.reset }] };
        compare(section.windows.length, 0);
        verify(!section.visible);
    }
    ''')

    def test_quota_weeks_keep_currency_in_privacy_mode(self):
        self.run_fixture('''
    function test_privateQuotaCurrency_data() {
        return [
            { tag: "euro", currency: "EUR", expected: "EUR 2" },
            { tag: "dollar", currency: "USD", expected: "USD 2" }
        ];
    }
    function test_privateQuotaCurrency(data) {
        var scan = new Date(2026, 8, 17, 12).getTime();
        var reset = new Date(2026, 8, 24).toISOString();
        var parsed = CostResponse.response(JSON.stringify([{
            provider: "codex", currencyCode: data.currency, historyDays: 1,
            updatedAt: new Date(scan).toISOString(),
            totals: { totalCost: 2, totalTokens: 100 },
            daily: [{ date: "2026-09-17", totalCost: 2, totalTokens: 100 }]
        }]), "", 1, 0);
        compare(parsed.outcome, "success");
        fakeApplet.panelClockMs = scan;
        var subject = createTemporaryObject(providerFactory, testCase);
        verify(subject !== null);
        var all = [];
        walkTree(subject, all);
        var section = all.filter(function(item) { return item.objectName === "quotaWindowSection"; })[0];
        verify(section !== undefined);
        // Exercise the real projection on both transitions. Localized labels
        // are supplied by main.qml after projection and do not affect amounts.
        for (var privacy of [false, true, false]) {
            var cost = Privacy.cost(parsed.costs.codex, privacy);
            cost.windowLabel = "Today";
            cost.hintLine = "";
            testCase.providerData = { provider: "codex", tokenCost: cost,
                rows: [{ lane: "secondary", windowMinutes: 10080, resetsAt: reset }] };
            compare(section.windows.length, 1);
            compare(section.windows[0].cost, 2);
            // The fixture formatter exposes the currency passed by the view.
            compare(section.amountText(section.windows[0]).split(" · ")[0], data.expected);
        }
    }
    ''')

    def test_provider_today_needs_a_scan_from_today(self):
        self.run_fixture('''
    // The CLI's "today" is the total of the day it scanned. A snapshot from
    // 22:00 must not present that day's spend as today's after midnight,
    // whether the new scan is still running or has failed.
    function test_providerTodayNeedsAScanFromToday() {
        var payload = [{ provider: "codex", historyDays: 30, currencyCode: "USD",
            updatedAt: new Date(2026, 8, 23, 22).toISOString(),
            sessionCostUSD: 1.25, sessionTokens: 1200,
            totals: { totalCost: 9, totalTokens: 9000 }, daily: [] }];
        var tokenCost = Object.assign({}, CostResponse.response(JSON.stringify(payload), "", 30, 0).costs.codex,
            { windowLabel: "30d", hintLine: "" });
        fakeApplet.panelClockMs = new Date(2026, 8, 23, 23, 30).getTime();
        testCase.providerData = { provider: "codex", tokenCost: tokenCost };
        var subject = createTemporaryObject(providerFactory, testCase);
        verify(subject !== null);
        tryVerify(function() {
            var texts = textsUnder(subject);
            return texts.indexOf("Today") >= 0 && texts.indexOf("USD 1.25") >= 0
                && texts.indexOf("1200 tokens") >= 0;
        });

        fakeApplet.panelClockMs = new Date(2026, 8, 24, 0, 30).getTime();
        tryVerify(function() {
            var texts = textsUnder(subject);
            return texts.indexOf("Today") >= 0 && texts.indexOf("USD 1.25") < 0
                && texts.indexOf("Cost unavailable") >= 0 && texts.indexOf("Tokens unavailable") >= 0;
        });
        // The selected period still shows the retained snapshot.
        verify(textsUnder(subject).indexOf("USD 9") >= 0);
        fakeApplet.panelClockMs = 0;
    }
    ''')

    def test_calendar_history_growth_preserves_provider_selection(self):
        self.run_fixture('''
    function test_calendarGrowth_data() {
        return [{tag: "month-to-date", period: "month-to-date"},
            {tag: "all", period: "all"}];
    }
    function test_calendarGrowth(data) {
        function snapshot(day) {
            var daily = [];
            for (var i = 1; i <= day; i++)
                daily.push({date: "2026-09-0" + i, totalCost: i, totalTokens: i * 10});
            var payload = [{provider: "codex", reportingPeriod: data.period,
                historyDays: day, updatedAt: "2026-09-0" + day, daily: daily}];
            return Object.assign({}, CostResponse.response(JSON.stringify(payload), "", 30, 0).costs.codex,
                {windowLabel: data.period, hintLine: ""});
        }
        testCase.providerData = {provider: "codex", tokenCost: snapshot(2)};
        var subject = createTemporaryObject(providerFactory, testCase);
        verify(subject !== null);
        var section = findChild(subject, "providerLocalCostSection");
        var chart = findChild(subject, "providerCostChart");
        section.detailsExpanded = true;
        chart.selectedIndex = 1;
        compare(section.selectedDay.label, "2026-09-02");

        testCase.providerData = {provider: "codex", tokenCost: snapshot(3)};
        compare(section.tokenCost.historyDays, 3);
        compare(chart.selectedIndex, 1);
        compare(section.selectedDay.label, "2026-09-02");
        compare(section.detailsExpanded, true);

        // Choosing another range still retires both the pin and disclosure.
        testCase.providerData = {provider: "codex", tokenCost: Object.assign({}, snapshot(3),
            {period: "", historyDays: 3})};
        compare(chart.selectedIndex, -1);
        compare(section.detailsExpanded, false);
        section.detailsExpanded = true;
        chart.selectedIndex = 1;
        testCase.providerData = {provider: "codex", tokenCost: Object.assign({}, snapshot(3),
            {period: "", historyDays: 7})};
        compare(chart.selectedIndex, -1);
        compare(section.detailsExpanded, false);
    }
    ''')

    def test_provider_rows_state_excluded_requests(self):
        self.run_fixture('''
    // Official per-day and per-model incomplete-request counts reach their
    // own rows through the production response and presentation chain, and a
    // selected day states its count beside its amounts.
    function test_providerRowsStateExcludedRequests() {
        var payload = [{ provider: "codex", historyDays: 30, currencyCode: "USD",
            totals: { totalCost: 3, totalTokens: 30 },
            daily: [
                { date: "2026-09-11", totalCost: 1, totalTokens: 10, incompleteRequestCount: 2,
                    modelBreakdowns: [{ modelName: "Partial", cost: 1, totalTokens: 10, incompleteRequestCount: 2 }] },
                { date: "2026-09-12", totalCost: 2, totalTokens: 20,
                    modelBreakdowns: [{ modelName: "Complete", cost: 2, totalTokens: 20 }] }
            ] }];
        var tokenCost = Object.assign({}, CostResponse.response(JSON.stringify(payload), "", 30, 0).costs.codex,
            { windowLabel: "30d", hintLine: "" });
        testCase.providerData = { provider: "codex", tokenCost: tokenCost };
        var subject = createTemporaryObject(providerFactory, testCase);
        verify(subject !== null);
        var all = [];
        walkTree(subject, all);
        var section = all.filter(function(item) { return item.objectName === "providerLocalCostSection"; })[0];
        section.detailsExpanded = true;
        function visibleExcluded(name) {
            var found = [];
            walkTree(subject, found);
            return found.filter(function(item) {
                return item.objectName === name && item.visible;
            }).map(function(item) { return item.text; });
        }
        tryVerify(function() {
            return visibleExcluded("costModelExcludedRequests").join() === "2 incomplete requests excluded"
                && visibleExcluded("costHistoryExcludedRequests").join() === "2 incomplete requests excluded";
        });
        var chart = all.filter(function(item) { return item.objectName === "providerCostChart"; })[0];
        chart.selectedIndex = chart.points.map(function(point) { return point.label; }).indexOf("2026-09-11");
        verify(chart.selectedIndex >= 0);
        tryVerify(function() {
            return textsUnder(subject).some(function(text) {
                return String(text).indexOf(" \u00b7 2 incomplete requests excluded") > 0;
            });
        });
    }
    ''')

    def test_analysis_refresh_only_updates_history(self):
        self.run_fixture('''
    function test_analysisRefresh() {
        var subject = createTemporaryObject(spendFactory, testCase);
        var refresh = findChild(subject, "analysisRefreshButton");
        refresh.requested();
        compare(fakeApplet.usageRefreshCount, 0);
        compare(fakeApplet.refreshCount, 1);
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
            return texts.indexOf("extra") >= 0 && texts.indexOf("codex") >= 0;
        });
        compare(findChild(subject, "projectCostSection"), null);
        var all = [];
        walkTree(subject, all);
        var metricToggles = all.filter(function(item) {
            return item.toString().indexOf("CostMetricToggle") >= 0;
        });
        compare(metricToggles.length, 1);
        metricToggles[0].activated(1);
        compare(fakeApplet.metricSet, "tokens");
        // The range picker offers the day windows and the CLI's calendar
        // periods, and follows a period chosen here or elsewhere.
        var ranges = all.filter(function(item) {
            return typeof item.valueAt === "function" && item.model !== undefined
                && item.model.length === 5;
        });
        compare(ranges.length, 1);
        compare(ranges[0].currentIndex, 1);
        compare(ranges[0].Accessible.name, "History range: 30 days");
        ranges[0].activated(3);
        compare(fakeApplet.periodSet, "month-to-date");
        compare(ranges[0].currentText, "Month to date");
        compare(ranges[0].Accessible.name, "History range: Month to date");
        ranges[0].activated(0);
        compare(fakeApplet.daysSet, "7");
        compare(ranges[0].currentText, "7 days");
        compare(ranges[0].Accessible.name, "History range: 7 days");
        fakeApplet.costHistoryPeriod = "all";
        compare(ranges[0].currentText, "All history");
        compare(ranges[0].Accessible.name, "History range: All history");
        fakeApplet.setCostHistoryDays(30);
        var historyMsgs = all.filter(function(item) {
            return item.plainText !== undefined
                && item.plainText.indexOf("No daily") >= 0;
        });
        compare(historyMsgs.length, 1);
        compare(historyMsgs[0].plainText,
            "No daily cost history for this range. Try Tokens for token history.");
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
        compare(notices.length, 0);
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
        verify(all.some(function(item) { return item.plainText === "Daily activity" && item.visible; }));
        // Every rendered day must sit on the row whose weekday label names it.
        var dayNames = [];
        for (var weekday = 0; weekday < 7; weekday++)
            dayNames.push(Qt.locale().dayName(weekday, Locale.ShortFormat));
        var weekdayLabels = all.filter(function(item) {
            return item.text !== undefined && dayNames.indexOf(item.text) >= 0
                && item.visible && item.height > 0;
        });
        compare(weekdayLabels.length, 7);
        // The grid recreates its cells as it sizes itself and positions them
        // on a later polish, so collect them once seven rows are laid out.
        function heatmapCells() {
            var tree = [];
            walkTree(subject, tree);
            return tree.filter(function(item) {
                return item.measured === true && item.modelData && item.width > 0;
            });
        }
        var cells = [];
        tryVerify(function() {
            cells = heatmapCells();
            var rows = [];
            cells.forEach(function(cell) {
                var y = Math.round(cell.mapToItem(subject, 0, 0).y);
                if (rows.indexOf(y) < 0)
                    rows.push(y);
            });
            return rows.length === 7;
        });
        // A narrow view keeps only the newest weeks; at least one full week
        // must render so every weekday row is checked.
        verify(cells.length >= 7 && cells.length <= spendPoints.length, cells.length);
        for (var c = 0; c < cells.length; c++) {
            var parts = cells[c].modelData.label.split("-");
            var expected = dayNames[new Date(Date.UTC(Number(parts[0]),
                Number(parts[1]) - 1, Number(parts[2]))).getUTCDay()];
            var cellCenter = cells[c].mapToItem(subject, 0, cells[c].height / 2).y;
            var rowLabel = weekdayLabels.filter(function(label) {
                return Math.abs(label.mapToItem(subject, 0, label.height / 2).y - cellCenter) < 1;
            });
            compare(rowLabel.length, 1, cells[c].modelData.label);
            compare(rowLabel[0].text, expected, cells[c].modelData.label);
            fuzzyCompare(cells[c].width, cells[c].height, 0.5, cells[c].modelData.label);
        }
        all = [];
        walkTree(subject, all);
        var tips = all.filter(function(item) {
            return item.toString().indexOf("PlainToolTip") >= 0;
        });
        verify(tips.length >= 1);
    }
    ''')

    def test_activity_layout_breakpoints(self):
        self.run_fixture('''
    function test_analysisLayoutBreakpoints_data() {
        var cases = [];
        for (var expanded of [false, true]) {
            for (var offset of [-1, 0, 1])
                cases.push({tag: expanded + "-width-" + offset, expanded: expanded, offset: offset});
        }
        return cases;
    }
    function test_analysisLayoutBreakpoints(data) {
        var subject = createTemporaryObject(spendFactory, testCase, {
            width: Kirigami.Units.gridUnit * 38 + data.offset, height: 780});
        var view = findChild(subject, "testAnalysis");
        view.expandedView = data.expanded;
        var grid = findChild(subject, "analysisChartProviders");
        verify(grid !== null);
        verify(waitForPolish(subject));
        var columns = data.expanded && data.offset >= 0 ? 2 : 1;
        compare(grid.columns, columns);
        subject.height = 240;
        verify(waitForPolish(subject));
        compare(grid.columns, columns);
    }
    ''')

    def test_small_numeric_fonts_preserve_theme(self):
        self.run_fixture('''
    function test_smallNumericFonts() {
        var themeFont = Kirigami.Theme.smallFont;
        var featuresBefore = JSON.stringify(themeFont.features);
        var spend = createTemporaryObject(spendFactory, testCase, {width: 580, height: 780});
        var provider = createTemporaryObject(providerFactory, testCase, {width: 580});
        verify(waitForPolish(spend));
        verify(waitForPolish(provider));
        var labels = [findChild(spend, "spendProviderSecondary"),
            findChild(spend, "heatmapReadout")];
        var all = [];
        walkTree(provider, all);
        var tokens = all.filter(function(item) {
            return item.text !== undefined && String(item.text).indexOf("tokens") >= 0
                && item.font !== undefined && item.font.features.tnum === 1;
        });
        verify(tokens.length > 0);
        labels = labels.concat(tokens);
        for (var label of labels) {
            verify(label !== null);
            for (var property of ["pixelSize", "pointSize", "family", "weight",
                    "italic", "styleName", "letterSpacing", "wordSpacing", "capitalization"])
                compare(label.font[property], themeFont[property], property);
            compare(label.font.features.tnum, 1);
        }
        compare(JSON.stringify(Kirigami.Theme.smallFont.features), featuresBefore,
            "Numeric labels must not mutate the theme font");
    }
    ''')

    def test_heatmap_keyboard_inspection_and_refresh(self):
        self.run_fixture('''
    function test_heatmapKeyboard_data() {
        return [{tag: "ltr", mirrored: false}, {tag: "rtl", mirrored: true}];
    }
    function test_heatmapKeyboard(data) {
        failOnWarning(/Binding loop|recursive rearrange|TypeError|ReferenceError/);
        var originalPoints = spendPoints;
        var subject = createTemporaryObject(spendFactory, testCase, {
            width: 580, height: 500, mirrored: data.mirrored
        });
        var grid = findChild(subject, "spendHeatmap");
        var readout = findChild(subject, "heatmapReadout");
        verify(grid !== null && readout !== null);
        verify(waitForPolish(subject));
        verify(grid.activeFocusOnTab, "Measured days must be reachable through Tab");
        mouseMove(testCase, 0, 0);
        var scroll = findChild(subject, "spendHistoryScroll");
        var flick = scroll.contentItem;
        flick.contentY = 0;
        verify(readout.mapToItem(flick, 0, readout.height).y > flick.height,
            "The short popup must initially clip the heatmap readout");
        grid.hoveredDay = "2026-09-01";
        grid.forceActiveFocus(Qt.TabFocusReason);
        tryCompare(grid, "visualFocus", true);
        compare(grid.hoveredDay, "");
        verify(grid.mapToItem(flick, 0, 0).y >= -1);
        verify(readout.mapToItem(flick, 0, readout.height).y <= flick.height + 1,
            "Keyboard focus must reveal the heatmap and its readout");
        compare(grid.selectedDay, "2026-09-08");
        // Window reactivation need not carry a Tab focus reason.
        grid.forceActiveFocus(Qt.ActiveWindowFocusReason);
        keyClick(Qt.Key_Home);
        compare(grid.selectedDay, "2026-09-01");
        compare(grid.inspectedCell.label, "2026-09-01");
        verify(grid.Accessible.name.indexOf("$1") >= 0);
        verify(readout.text.indexOf("$1") >= 0);
        var readoutY = readout.y;
        keyClick(data.mirrored ? Qt.Key_Left : Qt.Key_Right);
        compare(grid.selectedDay, "2026-09-08");
        keyClick(data.mirrored ? Qt.Key_Right : Qt.Key_Left);
        compare(grid.selectedDay, "2026-09-01");
        keyClick(Qt.Key_Down);
        compare(grid.selectedDay, "2026-09-02");
        compare(readout.y, readoutY);
        // A refreshed value remains attached to the same date.
        spendPoints = originalPoints.map(function(point) {
            return Object.assign({}, point, {value: 99, displayValue: "$99"});
        });
        tryVerify(function() { return readout.text.indexOf("$99") >= 0; });
        compare(grid.selectedDay, "2026-09-02");
        // Missing dates are not zero and never retain another day's selection.
        spendPoints = spendPoints.filter(point => point.label !== "2026-09-02");
        tryCompare(grid, "selectedDay", "");
        compare(grid.readout, "");
        keyClick(Qt.Key_Home);
        keyClick(Qt.Key_Down);
        compare(grid.selectedDay, "2026-09-03");
        keyClick(Qt.Key_End);
        compare(grid.selectedDay, "2026-09-08");
        fakeApplet.costHistoryMetric = "tokens";
        tryCompare(grid, "selectedDay", "");
        compare(grid.readout, "");
        fakeApplet.costHistoryMetric = "cost";
        keyClick(Qt.Key_End);
        fakeApplet.costHistoryDays = 90;
        tryCompare(grid, "selectedDay", "");
        fakeApplet.costHistoryDays = 30;
        keyClick(Qt.Key_End);
        keyClick(Qt.Key_Tab);
        verify(!grid.activeFocus, "The entire heatmap must occupy only one Tab stop");
        compare(grid.readout, "");
        compare(fakeApplet.refreshCount, 0, "Inspection must not fetch history");
        spendPoints = originalPoints;
    }
    ''')

    def test_heatmap_selects_chart_day_by_pointer_and_keyboard(self):
        self.run_fixture('''
    function test_selectCalendarDay_data() {
        return [{tag: "ltr", mirrored: false}, {tag: "rtl", mirrored: true}];
    }
    function test_selectCalendarDay(data) {
        failOnWarning(/Binding loop|recursive rearrange|TypeError|ReferenceError/);
        var subject = createTemporaryObject(spendFactory, testCase,
            {width: 580, height: 800, mirrored: data.mirrored});
        var view = findChild(subject, "testAnalysis");
        var chart = findChild(subject, "analysisHistoryChart");
        var grid = findChild(subject, "spendHeatmap");
        var readout = findChild(subject, "heatmapReadout");
        grid.forceActiveFocus(Qt.TabFocusReason);
        verify(waitForPolish(subject));
        var cell = findChild(subject, "activityDay-2026-09-03");
        var readoutY = readout.y;
        mouseMove(cell, cell.width / 2, cell.height / 2);
        tryVerify(function() { return readout.text.indexOf("$3") >= 0; });
        compare(chart.selectedIndex, -1, "Hover must not select a day");
        mouseClick(cell, cell.width / 2, cell.height / 2);
        compare(view.selectedDay, "2026-09-03");
        compare(chart.points[chart.selectedIndex].label, view.selectedDay);
        verify(cell.Accessible.selected);
        verify(grid.activeFocus);
        mouseMove(testCase, 0, 0);
        verify(readout.text.indexOf("$3") >= 0);
        compare(readout.y, readoutY);
        keyClick(Qt.Key_Home);
        compare(view.selectedDay, "2026-09-03", "Keyboard inspection must preserve the pin");
        keyClick(Qt.Key_Return);
        compare(view.selectedDay, "2026-09-01");
        keyClick(Qt.Key_End);
        keyClick(Qt.Key_Space);
        compare(view.selectedDay, "2026-09-08");
        keyClick(Qt.Key_Escape);
        compare(view.selectedDay, "");
        verify(grid.activeFocus);
        compare(readout.text.trim(), "");
        cell.Accessible.pressAction();
        compare(view.selectedDay, "2026-09-03");
        // Pinning in the chart also marks the matching calendar cell.
        chart.selectedIndex = 0;
        verify(findChild(subject, "activityDay-2026-09-01").Accessible.selected);
        var original = spendPoints;
        spendPoints = original.filter(function(point) { return point.label !== "2026-09-05"; })
            .map(function(point) { return Object.assign({}, point,
                {value: point.label === "2026-09-04" ? 0 : point.value}); });
        grid.selectDay("2026-09-04", Qt.OtherFocusReason);
        compare(view.selectedDay, "2026-09-04");
        verify(readout.text.indexOf("$0") >= 0, "A measured zero remains selectable");
        grid.selectDay("2026-09-05", Qt.OtherFocusReason);
        compare(view.selectedDay, "2026-09-04", "An unavailable day cannot change selection");
        spendPoints = original;
        var toggle = findChild(subject, "analysisActivityToggle");
        toggle.clicked();
        verify(!grid.visible);
        verify(toggle.activeFocus);
        compare(fakeApplet.refreshCount, 0);
    }
    ''')

    def run_fixture(self, snippet, style=None):
        qml = QML_TEMPLATE.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("/*TESTS*/", snippet)
        with tempfile.TemporaryDirectory(prefix="codexbar-cost-sections-") as temporary:
            fixture = Path(temporary) / "tst_cost_sections.qml"
            fixture.write_text(qml)
            environment = {**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"}
            if style is not None:
                environment["QT_QUICK_CONTROLS_STYLE"] = style
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env=environment,
                capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
