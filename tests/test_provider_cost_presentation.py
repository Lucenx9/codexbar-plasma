"""Exercise the owning cost/credit adapters against every compiled catalog."""

import gettext
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "scripts/lib"))
from compile_translations import compile_catalogs
from qml_surfaces import Surface


class ProviderCostPresentationTests(unittest.TestCase):
    def test_cost_and_reset_adapters_preserve_translated_sections(self):
        applet = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        applet.texts = {main: main.read_text()}
        applet.files = [main]
        signatures = {"providerCostSection": "providerID, cost",
                      "resetCreditsSection": "providerID, resetCredits",
                      "codexCreditLimitUsageRow": "creditLimit"}
        adapters = "\n".join(f"function {name}({args}) {{ {applet.function_body(name)} }}"
                             for name, args in signatures.items())
        with tempfile.TemporaryDirectory(prefix="codexbar-cost-labels-") as temporary:
            directory = Path(temporary)
            compile_catalogs(directory / "locale")
            cases = []
            for language in ("en", "it", "fr", "de", "es", "pt_BR"):
                catalog = gettext.translation("plasma_applet_app.codexbar.plasma", directory / "locale",
                                              languages=[language], fallback=language == "en")
                messages = {key: value for key, value in getattr(catalog, "_catalog", {}).items()
                            if isinstance(key, str)}

                def text(source, *values):
                    result = catalog.gettext(source)
                    for index, value in enumerate(values, 1):
                        result = result.replace("%" + str(index), str(value))
                    return result

                def section(title, percent, spend, percent_line="", personal=""):
                    return {"title": text(title), "percentUsed": percent, "spendLine": spend,
                            "percentLine": percent_line, "personalSpendLine": personal}

                rows = [
                    {"provider": "claude", "cost": {"used": 25, "limit": 100, "personalUsed": 12},
                     "expected": section("Extra usage", 25,
                                         text("%1: %2 / %3", text("This month"), "$25.00", "$100.00"),
                                         text("%1% used", 25), text("Your spend: %1", "$12.00"))},
                    {"provider": "factory", "cost": {"used": 12.5, "limit": 100, "currencyCode": "EUR",
                                                        "period": "Extra usage balance"},
                     "expected": section("Extra usage", -1, text("Balance: %1", "EUR 12.50"))},
                    {"provider": "opencodego", "cost": {"used": 12.5, "limit": 100, "period": "Zen balance"},
                     "expected": section("Zen balance", -1, text("Balance: %1", "$12.50"))},
                    {"provider": "minimax", "cost": {"used": 12.5, "limit": 100, "period": "MiniMax points balance"},
                     "expected": section("Credits", -1, text("Balance: %1", 13))},
                    {"provider": "openai", "cost": {"used": 0, "period": "Billing cycle"},
                     "expected": section("API spend", -1, text("%1: %2", "Billing cycle", "$0.00"))},
                    {"provider": "future-provider", "cost": {"used": 10, "limit": 20, "currencyCode": "Quota",
                                                                "period": "Today"},
                     "expected": section("Quota usage", 50, text("%1: %2 / %3", text("Today"), 10, 20),
                                         text("%1% used", 50))},
                    {"provider": "future-provider", "cost": {"used": 2, "currencyCode": "Quota"},
                     "expected": section("Extra usage", -1, text("%1: %2", text("This month"), 2))},
                    {"provider": "claude", "cost": {"used": -1, "limit": 10, "personalUsed": 0,
                                                       "period": "last 30 days"},
                     "expected": section("Extra usage", 0,
                                         text("%1: %2 / %3", text("Last 30 days"), "-$1.00", "$10.00"),
                                         text("%1% used", 0))},
                    {"provider": "litellm", "cost": {"used": 10, "limit": 0}, "expected": None},
                    {"provider": "manus", "cost": {"used": 10, "limit": 100}, "expected": None},
                    {"provider": "codex", "cost": {"used": False, "limit": 100}, "expected": None},
                ]
                plural_messages = {count: catalog.ngettext("%1 available", "%1 available", count)
                                   for count in (0, 1, 2)}
                counts = [{"input": count, "expected": {"title": text("Reset credits"),
                            "line": plural_messages[rounded].replace("%1", str(rounded))}}
                          for count, rounded in ((1, 1), ("2", 2), (1.6, 2), (0.2, 0))]
                cases.append({"tag": language, "messages": messages, "plurals": plural_messages,
                              "rows": rows, "counts": counts,
                              "monthlyTitle": text("Monthly credit limit"),
                              "monthlySummary": text("Used: %1, remaining: %2 of %3", "0", "1,000", "1,000")})
            qml = '''import QtQuick
import QtTest
import "SOURCE_URL/CostPresentation.js" as CostPresentation
import "SOURCE_URL/components" as Components
TestCase {
    id: testCase
    name: "ProviderCostAdapters"
    Components.ProviderCostDetails {
        id: providerCostDetails
        numberFormat: testCase.costNumberFormat
        function i18n(source) { return testCase.i18n.apply(testCase, arguments); }
        function i18np(one, many, count) { return testCase.i18np(one, many, count); }
    }
    property var messages: ({})
    property var plurals: ({})
    property var costNumberFormat: CostPresentation.numberFormat(",", ".")
    function i18n(source) {
        var text = messages[source] || source;
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, String(arguments[i]));
        return text;
    }
    function i18np(one, many, count) {
        return plurals[count].replace("%1", String(count));
    }
    ADAPTERS
    function test_sections_data() { return CASES; }
    function test_sections(data) {
        messages = data.messages;
        plurals = data.plurals;
        for (var row of data.rows)
            compare(providerCostSection(row.provider, row.cost), row.expected, row.provider);
        for (var count of data.counts)
            compare(resetCreditsSection("codex", {availableCount: count.input}), count.expected);
        compare(resetCreditsSection("claude", {availableCount: 2}), null);
        compare(resetCreditsSection("codex", {availableCount: 0}), null);
        var monthly = codexCreditLimitUsageRow({title: "", used: 0, remaining: 1000,
            limit: 1000, usedPercent: 0, leftPercent: 100, resetsAt: "future-reset"});
        compare(monthly.label, data.monthlyTitle);
        compare(monthly.summaryText, data.monthlySummary);
        compare(monthly.usedPercent, 0);
        compare(monthly.leftPercent, 100);
        compare(monthly.resetsAt, "future-reset");
    }
}
'''
            fixture = directory / "tst_provider_cost_adapters.qml"
            fixture.write_text(qml.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
                               .replace("ADAPTERS", adapters).replace("CASES", json.dumps(cases)))
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("SKIP", output)
            self.assertNotIn("QWARN", output)

    def test_monthly_credit_amounts_remain_visible_without_pace(self):
        applet = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        applet.texts = {main: main.read_text()}
        applet.files = [main]
        adapter = applet.function_body("codexCreditLimitUsageRow")
        qml = r'''import QtQuick
import QtTest
import "SOURCE_URL/components" as Components
import "SOURCE_URL/CostPresentation.js" as CostPresentation
TestCase {
    id: testCase
    name: "CreditUsageRow"
    Components.ProviderCostDetails {
        id: providerCostDetails
        numberFormat: CostPresentation.numberFormat(",", ".")
        function i18n(source) { return applet.i18n.apply(applet, arguments); }
    }
    when: windowShown
    visible: true
    width: 540
    height: 300
    QtObject {
        id: applet
        property bool showPopupPace: true
        property real secondaryTextOpacity: 0.7
        property int meterTrackHeight: 7
        function i18n(source) {
            for (var i = 1; i < arguments.length; i++)
                source = source.replace("%" + i, String(arguments[i]));
            return source;
        }
        function codexCreditLimitUsageRow(creditLimit) { ADAPTER }
        function popupUsageRowHideable() { return false; }
        function providerReadableColor() { return "blue"; }
        function displayPercent(row) { return row.leftPercent; }
        function paceMarkerPercent() { return -1; }
        function resetLabel(value) { return value; }
        function usageResetText(row) { return row.resetsAt || ""; }
        function withAlpha(color, alpha) { return Qt.rgba(0, 0, 1, alpha); }
        function percentSuffix() { return "left"; }
        function quotaMeterColor() { return "blue"; }
        function quotaWarningMarkers() { return []; }
        function usagePaceText(row) { return row.pace; }
    }
    Component {
        id: usageComponent
        Components.ProviderUsageRow {
            function i18n(text) { return text; }
        }
    }
    function hasVisibleText(item, text) {
        if (!item.visible) return false;
        if (item.text === text) return true;
        for (var child of item.children)
            if (hasVisibleText(child, text)) return true;
        return false;
    }
    function test_summaryAndForecastSettingsAreIndependent() {
        var limit = {title: "Monthly credit limit", used: 15, remaining: 85,
            limit: 100, usedPercent: 15, leftPercent: 85, resetsAt: "in 7d"};
        var row = createTemporaryObject(usageComponent, testCase,
            {applet: applet, providerData: {provider: "codex"},
                modelData: applet.codexCreditLimitUsageRow(limit), width: 500});
        verify(row !== null);
        wait(0);
        verify(hasVisibleText(row, "Used: 15, remaining: 85 of 100"));
        applet.showPopupPace = false;
        verify(hasVisibleText(row, "Used: 15, remaining: 85 of 100"));
        verify(hasVisibleText(row, "in 7d"));
        row.modelData = {label: "Session", hasPercent: true, usedPercent: 15,
            leftPercent: 85, pace: "Runs out in 1h", resetsAt: "in 7d"};
        verify(!hasVisibleText(row, "Used: 15, remaining: 85 of 100"));
        verify(!hasVisibleText(row, "Runs out in 1h"));
        verify(hasVisibleText(row, "in 7d"));
        applet.showPopupPace = true;
        verify(hasVisibleText(row, "Runs out in 1h"));
        row.modelData = {label: "Session", hasPercent: true, usedPercent: 15,
            leftPercent: 85, pace: "", resetsAt: ""};
        verify(!hasVisibleText(row, "Runs out in 1h"));
    }
}
'''
        with tempfile.TemporaryDirectory(prefix="codexbar-credit-row-") as temporary:
            fixture = Path(temporary) / "tst_credit_usage_row.qml"
            fixture.write_text(qml.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
                               .replace("ADAPTER", adapter))
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("SKIP", output)
            self.assertNotIn("QWARN", output)

    def test_main_cost_wrappers_delegate_to_presentation(self):
        applet = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        applet.texts = {main: main.read_text()}
        applet.files = [main]
        names = ("costHistoryWindowLabel",
                 "costChartPoints", "spendTotalLine", "spendProviderCosts",
                 "spendHistoryStillBuilding", "costPresentation", "providerTitle",
                 "providerKey", "amountString", "usageCountText", "tokenCountString",
                 "qualifiedCostValue")
        functions = []
        for name in names:
            signature = re.search(r"function " + name + r"\([^)]*\)",
                                  applet.texts[main]).group(0)
            functions.append(signature + " {" + applet.function_body(name) + "}")
        qml = COST_WRAPPER_QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n        ".join(functions))
        with tempfile.TemporaryDirectory(prefix="codexbar-cost-wrappers-") as temporary:
            fixture = Path(temporary) / "tst_main_cost_wrappers.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("SKIP", output)
            self.assertNotIn("QWARN", output)

    def test_cost_metric_helpers_sanitize_before_persisting(self):
        applet = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        applet.texts = {main: main.read_text()}
        applet.files = [main]
        names = ("safeCostHistoryMetric", "setCostHistoryMetric",
                 "setCostHistoryDays", "setCostHistoryPeriod")
        functions = []
        for name in names:
            signature = re.search(r"function " + name + r"\([^)]*\)",
                                  applet.texts[main]).group(0)
            # QML rejects a property named Plasmoid, so the harness rewrites
            # the configuration write; see the substitution below.
            functions.append((signature + " {" + applet.function_body(name) + "}")
                             .replace("Plasmoid.configuration", "costConfiguration"))
        qml = (COST_METRIC_QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
               .replace("SOURCE_FUNCTIONS", "\n        ".join(functions)))
        with tempfile.TemporaryDirectory(prefix="codexbar-cost-metric-") as temporary:
            fixture = Path(temporary) / "tst_main_cost_metric.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("SKIP", output)
            self.assertNotIn("QWARN", output)


COST_METRIC_QML = '''import QtQuick
import QtTest
import "SOURCE_URL/CostPresentation.js" as CostPresentation
TestCase {
    name: "MainCostMetric"
    // QML rejects a property named Plasmoid, so the harness rewrites the
    // configuration write; see the substitution above.
    property var costConfiguration: ({})
    property int maximumCostHistoryPoints: 365
    SOURCE_FUNCTIONS
    // A calendar period persists only under the CLI's names, and choosing a
    // day count returns to the day window even when the count is unchanged.
    function test_periodPersistsOnlyKnownNamesAndDaysClearIt() {
        setCostHistoryPeriod("month-to-date");
        compare(costConfiguration.costHistoryPeriod, "month-to-date");
        setCostHistoryPeriod("bogus");
        compare(costConfiguration.costHistoryPeriod, "");
        setCostHistoryPeriod("all");
        setCostHistoryDays(30);
        compare(costConfiguration.costHistoryDays, 30);
        compare(costConfiguration.costHistoryPeriod, "");
        costConfiguration = ({});
    }
    // Only the two known metrics survive: anything else persists as cost,
    // so the chart and the summary lines can never disagree.
    function test_unknownMetricsPersistAsCost() {
        compare(safeCostHistoryMetric("tokens"), "tokens");
        compare(safeCostHistoryMetric("cost"), "cost");
        compare(safeCostHistoryMetric("bogus"), "cost");
        compare(safeCostHistoryMetric(""), "cost");
        setCostHistoryMetric("tokens");
        compare(costConfiguration.costHistoryMetric, "tokens");
        setCostHistoryMetric("bogus");
        compare(costConfiguration.costHistoryMetric, "cost");
        costConfiguration = ({});
    }
}
'''


COST_WRAPPER_QML = '''import QtQuick
import QtTest
import "SOURCE_URL/components" as Components
import "SOURCE_URL/ProviderNormalizer.js" as Normalizer
import "SOURCE_URL/ProviderIdentity.js" as ProviderIdentity
import "SOURCE_URL/CostPresentation.js" as CostPresentation
import "SOURCE_URL/PrivacyPresentation.js" as PrivacyPresentation
TestCase {
    name: "MainCostWrappers"
    Components.ProviderNames {
        id: providerNames
        function i18n(text) { return text }
    }
    Components.CostLabels {
        id: costLabels
        applet: root
        function i18n(source) { return root.i18n.apply(root, arguments) }
    }
    QtObject {
        id: root
        property var costNumberFormat: CostPresentation.numberFormat(",", ".")
        property bool costHistoryShowsTokens: false
        property int costHistoryDays: 30
        property string costHistoryPeriod: ""
        property var tokenCosts: ({})
        property bool privacyMode: false
        SOURCE_FUNCTIONS
        function i18n(source) {
            var text = source;
            for (var i = 1; i < arguments.length; i++)
                text = text.replace("%" + i, String(arguments[i]));
            return text;
        }
        function i18np(one, many, count) {
            return String(count === 1 ? one : many).replace("%1", String(count));
        }
    }
    function laneTotals() {
        return {totals: {tokens: 1500, inputTokens: 1000, outputTokens: 400,
            cacheReadTokens: 80, cacheCreationTokens: 20}};
    }
    function twoDays() {
        return [{label: "Mon", cost: 5, tokens: 900, currency: "USD"},
                {label: "Tue", cost: 2, tokens: 4000, currency: "USD"}];
    }
    // Every token lane survives the breakdown; a zeroed lane drops out.
    function test_breakdownRowsKeepEveryLane() {
        var rows = costLabels.costBreakdownRows(laneTotals());
        compare(rows.length, 5);
        compare(rows[0].label, "Total tokens");
        compare(rows[0].value, "1.5K");
    }
    // Model and history rows follow the shared presentation module, newest
    // day first with the peak of the selected metric flagged.
    function test_modelAndHistoryRowsFollowPresentation() {
        var models = costLabels.costModelRows({models: [
            {label: "A", cost: 1, tokens: 1000, currency: "USD"},
            {label: "B", cost: null, tokens: 500, currency: "USD"}]});
        compare(models.length, 2);
        compare(models[1].value, "500 tokens");
        var history = costLabels.costHistoryRows({daily: [
            {label: "Mon", cost: 1, tokens: 4000, currency: "USD"},
            {label: "Tue", cost: 4, tokens: 1000, currency: "USD"}]});
        compare(history[0].label, "Tue");
        verify(history[0].value.indexOf("$4.00") === 0);
        compare(history[0].isPeak, true);
        compare(history[1].isPeak, false);
    }
    // The peak, average and per-million lines word the selected metric; an
    // empty selection stays empty instead of printing a zero.
    function test_summaryLinesWordTheSelectedMetric() {
        compare(costLabels.costPeakLine(twoDays()), "Peak: Mon - $5.00");
        compare(costLabels.costAverageDailyLine(twoDays()), "Average/day: $3.50");
        compare(costLabels.costPerMillionLine(
            {totals: {cost: 2, tokens: 1000000, currency: "USD"}}),
            "Average: $2.00 / 1M tokens");
        compare(costLabels.costPeakLine([]), "");
        // All history longer than the chart supplies its whole-range average.
        var average = {cost: {value: 9, currency: "USD"}, tokens: null};
        compare(costLabels.costAverageDailyLine(twoDays(), average), "Average/day: $9.00");
        root.costHistoryShowsTokens = true;
        compare(costLabels.costAverageDailyLine(twoDays(), average), "");
        root.costHistoryShowsTokens = false;
    }
    // A peak older than the seven history rows is neither shown nor
    // highlighted there, so the peak line names the highlighted row instead.
    function test_peakLineNamesTheHighlightedHistoryRow() {
        var daily = [{label: "D0", cost: 50, tokens: 1, currency: "USD"}];
        for (var i = 1; i <= 7; i++)
            daily.push({label: "D" + i, cost: i === 3 ? 9 : 1, tokens: 1, currency: "USD"});
        var rows = costLabels.costHistoryRows({daily: daily});
        compare(rows.map(function(row) { return row.label; }),
            ["D7", "D6", "D5", "D4", "D3", "D2", "D1"]);
        var highlighted = rows.filter(function(row) { return row.isPeak; });
        compare(highlighted.map(function(row) { return row.label; }), ["D3"]);
        compare(costLabels.costPeakLine(daily), "Peak: D3 - $9.00");
    }
    // History rows, the peak line, and the latest-day summary date their
    // days like the chart, in the locale's short format, and keep any other
    // label as the CLI sent it.
    function test_historyTextDatesDaysInTheLocale() {
        var day = function(key) {
            var parts = key.split("-").map(Number);
            return new Date(parts[0], parts[1] - 1, parts[2])
                .toLocaleDateString(Qt.locale(), Locale.ShortFormat);
        };
        var daily = [
            {label: "2026-09-23", cost: 1, tokens: 1, currency: "USD"},
            {label: "2026-09-24", cost: 4, tokens: 1, currency: "USD"},
            {label: "2026-09-25", cost: 2, tokens: 1, currency: "USD"}];
        compare(costLabels.costHistoryRows({daily: daily}).map(function(row) { return row.label; }),
            [day("2026-09-25"), day("2026-09-24"), day("2026-09-23")]);
        compare(costLabels.costPeakLine(daily), "Peak: " + day("2026-09-24") + " - $4.00");
        compare(costLabels.costSparklineSummary(daily), day("2026-09-25") + ": $2.00");
        compare(costLabels.costDayLabel("2026-09-24"), day("2026-09-24"));
        compare(costLabels.costDayLabel("Week 34"), "Week 34");
        compare(costLabels.costDayLabel("2026-02-30"), "2026-02-30");
        compare(costLabels.costDayLabel(""), "");
    }
    // Calendar periods title themselves in the locale, never from the CLI's
    // English label or a day count that changes through the month.
    function test_windowLabelNamesCalendarPeriods() {
        compare(root.costHistoryWindowLabel({period: "month-to-date"}, 26), "Month to date");
        compare(root.costHistoryWindowLabel({period: "all"}, 365), "All history");
        compare(root.costHistoryWindowLabel({period: "quarter"}, 30), "Last 30 days");
        compare(root.costHistoryWindowLabel(null, 7), "Last 7 days");
    }
    // Chart points hide cost-unavailable days but keep their tokens.
    function test_chartPointsFollowTheSelectedMetric() {
        var points = [{label: "Mon", cost: null, tokens: 250, currency: "USD"}];
        root.costHistoryShowsTokens = false;
        compare(root.costChartPoints(points).length, 0);
        root.costHistoryShowsTokens = true;
        compare(root.costChartPoints(points).length, 1);
        root.costHistoryShowsTokens = false;
    }
    // The total line prints the spend subtotal with its token count, and the
    // unavailable wording only when neither metric survived.
    function test_spendTotalLinePrintsSubtotalOrUnavailable() {
        root.tokenCosts = {codex: {provider: "codex", historyDays: 30,
            totals: {cost: 5, tokens: 100, currency: "USD"}}};
        compare(root.spendTotalLine(), "$5.00 total \u00b7 100 tokens");
        root.tokenCosts = {codex: {provider: "codex", historyDays: 30,
            totals: {cost: null, tokens: null, currency: "USD"}}};
        compare(root.spendTotalLine(), "Tokens unavailable");
        root.tokenCosts = ({});
        compare(root.spendTotalLine(), "");
    }
    // Spend snapshots sort by provider title, so the totals follow the same
    // order the Usage & Spend tab prints.
    function test_spendSnapshotsSortByProviderTitle() {
        root.tokenCosts = {zai: {provider: "zai", historyDays: 30},
                           codex: {provider: "codex", historyDays: 30}};
        var costs = root.spendProviderCosts();
        compare(costs.length, 2);
        compare(costs[0].provider, "codex");
        compare(costs[1].provider, "zai");
        root.tokenCosts = ({});
    }
    // The still-building flag mirrors the CLI scan coverage, not the spend.
    function test_stillBuildingMirrorsScanCoverage() {
        root.tokenCosts = {codex: {provider: "codex", historyDays: 30,
            historyCoverageEstablished: false}};
        compare(root.spendHistoryStillBuilding(), true);
        root.tokenCosts = ({});
        compare(root.spendHistoryStillBuilding(), false);
    }
}
'''


if __name__ == "__main__":
    unittest.main()
