import QtQuick
import QtTest
import "../contents/ui/CostPresentation.js" as CostPresentation
import "../contents/ui/components" as Components

TestCase {
    name: "CostText"

    property var regionalFormat: CostPresentation.numberFormat(",", ".")

    Components.CostText {
        id: subject
        numberFormat: regionalFormat
        function i18n(text) {
            for (var i = 1; i < arguments.length; i++)
                text = text.replace("%" + i, String(arguments[i]));
            return text;
        }
        function i18np(one, many, count) {
            return i18n(count === 1 ? one : many, count);
        }
    }

    function snapshot(overrides) {
        var item = {
            provider: "codex",
            currency: "USD",
            period: "",
            historyDays: 30,
            historyLabel: null,
            labelDays: 30,
            sessionCost: 1,
            sessionTokens: 2,
            valueMode: "plain",
            totals: { cost: 3, tokens: 4 },
            note: "keep"
        };
        var extra = overrides || ({});
        var keys = Object.keys(extra);
        for (var i = 0; i < keys.length; i++)
            item[keys[i]] = extra[keys[i]];
        return item;
    }

    function trustedCost(currency, coverage, sourceKind, cost, tokens) {
        return {
            totals: {
                cost: cost === undefined ? 1 : cost,
                tokens: tokens === undefined ? 10 : tokens,
                currency: currency || "USD"
            },
            trust: {
                coverage: coverage || null,
                sourceKind: sourceKind || ""
            }
        };
    }

    function test_historyLabelPrecedence_data() {
        return [
            { tag: "month-over-days", item: { period: "month-to-date", historyDays: 7 }, requested: 26, expected: "Month to date" },
            { tag: "all-over-days", item: { period: "all" }, requested: 365, expected: "All history" },
            { tag: "unknown-period", item: { period: "quarter" }, requested: 30, expected: "Last 30 days" },
            { tag: "item-days", item: { historyDays: 7 }, requested: 30, expected: "Last 7 days" },
            { tag: "string-days", item: { historyDays: "14" }, requested: 30, expected: "Last 14 days" },
            { tag: "blank-days", item: { historyDays: "  " }, requested: 4, expected: "Last 4 days" },
            { tag: "bool-days", item: { historyDays: true }, requested: 9, expected: "Last 9 days" },
            { tag: "object-days", item: { historyDays: {} }, requested: 2, expected: "Last 2 days" },
            { tag: "array-days", item: { historyDays: [6] }, requested: 2, expected: "Last 2 days" },
            { tag: "null-days", item: { historyDays: null }, requested: 5, expected: "Last 5 days" },
            { tag: "zero-days", item: { historyDays: 0 }, requested: 1, expected: "Today" },
            { tag: "fractional-day", item: { historyDays: 1.9 }, requested: 30, expected: "Today" },
            { tag: "null-item", item: null, requested: 7, expected: "Last 7 days" },
            { tag: "missing-request", item: null, requested: null, expected: "Last 30 days" },
            { tag: "string-request", item: null, requested: "8", expected: "Last 8 days" },
            { tag: "infinite-request", item: null, requested: Infinity, expected: "Last 30 days" },
            { tag: "negative-range", item: { historyDays: -3 }, requested: -1, expected: "Last 30 days" }
        ];
    }

    function test_historyLabelPrecedence(data) {
        compare(subject.costHistoryWindowLabel(data.item, data.requested), data.expected);
    }

    function test_presentTokenCostsPreservesSnapshotAndLabelPrecedence() {
        var month = snapshot({
            period: "month-to-date",
            labelDays: 26,
            valueMode: "estimated",
            historyLabel: null
        });
        var before = JSON.stringify(month);
        var presented = subject.presentTokenCosts({ codex: month });
        compare(JSON.stringify(month), before);
        verify(presented.codex !== month);
        verify(month.title === undefined);
        verify(month.windowLabel === undefined);
        compare(presented.codex.note, "keep");
        compare(presented.codex.provider, "codex");
        compare(presented.codex.title, "Cost");
        compare(presented.codex.windowLabel, "Month to date");
        compare(presented.codex.sessionLine, "Today: $1.00 \u00b7 2 tokens");
        compare(presented.codex.monthLine, "Month to date: $3.00 (estimated) \u00b7 4 tokens");
        compare(presented.codex.windowValueLine, "$3.00 (estimated) \u00b7 4 tokens");
        compare(presented.codex.hintLine, "Estimated from local Codex logs for the selected account.");

        var labelled = snapshot({
            period: "month-to-date",
            historyLabel: "Quarter",
            labelDays: 26
        });
        var labelledBefore = JSON.stringify(labelled);
        compare(subject.presentTokenCosts({ codex: labelled }).codex.windowLabel, "Quarter");
        compare(JSON.stringify(labelled), labelledBefore);

        var blank = snapshot({ historyLabel: "", period: "all", labelDays: 3 });
        compare(subject.presentTokenCosts({ codex: blank }).codex.windowLabel, "");

        // Only generated labels are bounded here. Preserve the existing
        // distinction between a null label and an omitted compatibility field.
        var longLabel = snapshot({ historyLabel: "x".repeat(200), period: "all" });
        compare(subject.presentTokenCosts({ codex: longLabel }).codex.windowLabel, "x".repeat(200));
        var missingLabel = snapshot({ period: "all" });
        delete missingLabel.historyLabel;
        var missingPresented = subject.presentTokenCosts({ codex: missingLabel }).codex;
        verify(missingPresented.windowLabel === undefined);
        compare(missingPresented.monthLine, "undefined: $3.00 \u00b7 4 tokens");

        var week = snapshot({ historyLabel: null, period: "", labelDays: 7 });
        compare(subject.presentTokenCosts({ codex: week }).codex.windowLabel, "Last 7 days");

        var coercive = snapshot({
            sessionCost: "nope",
            sessionTokens: {},
            totals: { cost: "5", tokens: "10" }
        });
        var coerciveBefore = JSON.stringify(coercive);
        var coercivePresented = subject.presentTokenCosts({ codex: coercive }).codex;
        compare(JSON.stringify(coercive), coerciveBefore);
        compare(coercivePresented.sessionLine, "Today: -");
        compare(coercivePresented.monthLine, "Last 30 days: $5.00 \u00b7 10 tokens");

        var nonfinite = snapshot({
            sessionCost: Infinity,
            sessionTokens: NaN,
            totals: { cost: NaN, tokens: Infinity }
        });
        var nonfinitePresented = subject.presentTokenCosts({ codex: nonfinite }).codex;
        compare(nonfinitePresented.sessionLine, "Today: -");
        compare(nonfinitePresented.monthLine, "Last 30 days: -");

        var claude = snapshot({
            provider: "claude",
            sessionCost: 8,
            sessionTokens: 9,
            historyLabel: null,
            period: "all"
        });
        var both = subject.presentTokenCosts({ codex: month, claude: claude });
        compare(both.codex.sessionLine, "Today: $1.00 \u00b7 2 tokens");
        compare(both.claude.windowLabel, "All history");
        compare(both.claude.sessionLine, "Today: $8.00 \u00b7 9 tokens");
        compare(both.claude.hintLine, "Estimated from local Claude logs.");
        compare(Object.keys(subject.presentTokenCosts({})).length, 0);
    }

    function test_costLinesRejectCoerciveValuesAndQualifyFiniteCosts_data() {
        return [
            { tag: "plain", call: "line", args: ["Today", 5, 100, "USD", "plain"], expected: "Today: $5.00 \u00b7 100 tokens" },
            { tag: "estimated", call: "line", args: ["Today", "5", "10", "USD", "estimated"], expected: "Today: $5.00 (estimated) \u00b7 10 tokens" },
            { tag: "partial-value", call: "value", args: [5, null, "USD", "partial"], expected: "$5.00 (partial)" },
            { tag: "approximate-negative", call: "line", args: ["Range", -2.5, 1, "EUR", "approximate"], expected: "Range: -EUR 2.50 (approximate) \u00b7 1 token" },
            { tag: "qualifier-skipped", call: "value", args: [null, 100, "USD", "estimated"], expected: "- \u00b7 100 tokens" },
            { tag: "nonfinite", call: "line", args: ["Today", Infinity, NaN, "USD", "approximate"], expected: "Today: -" },
            { tag: "bool", call: "line", args: ["Today", true, false, "USD", "partial"], expected: "Today: -" },
            { tag: "blank", call: "line", args: ["Today", "  ", "nope", "USD", "estimated"], expected: "Today: -" },
            { tag: "broken-decimal", call: "value", args: ["1.2.3", 1, "USD", "plain"], expected: "- \u00b7 1 token" },
            { tag: "padded", call: "value", args: [" 1 ", " 10 ", "USD", "plain"], expected: "$1.00 \u00b7 10 tokens" },
            { tag: "bool-token", call: "value", args: [1, true, "USD", "plain"], expected: "$1.00" },
            { tag: "object-token", call: "value", args: [1, {}, "USD", "plain"], expected: "$1.00" },
            { tag: "quota", call: "value", args: [12.6, null, "Quota", "estimated"], expected: "13 (estimated)" },
            { tag: "blank-currency", call: "value", args: [2, null, "", "future-mode"], expected: "2.00" },
            { tag: "unknown-mode", call: "value", args: [5, null, "USD", "future-mode"], expected: "$5.00" }
        ];
    }

    function test_costLinesRejectCoerciveValuesAndQualifyFiniteCosts(data) {
        var value = data.call === "line"
            ? subject.costLine(data.args[0], data.args[1], data.args[2], data.args[3], data.args[4])
            : subject.costValueLine(data.args[0], data.args[1], data.args[2], data.args[3]);
        compare(value, data.expected);
    }

    function test_usageCountsKeepCompactTextAndLooseNumbers_data() {
        return [
            { tag: "one", value: 1, unit: "tokens", expected: "1 token" },
            { tag: "zero", value: 0, unit: "requests", expected: "0 requests" },
            { tag: "true", value: true, unit: "tokens", expected: "1 token" },
            { tag: "false", value: false, unit: "points", expected: "0 points" },
            { tag: "null", value: null, unit: "tokens", expected: "0 tokens" },
            { tag: "empty", value: "", unit: "tokens", expected: "0 tokens" },
            { tag: "array", value: [], unit: "tokens", expected: "0 tokens" },
            { tag: "boxed", value: [2], unit: "requests", expected: "2 requests" },
            { tag: "object", value: {}, unit: "tokens", expected: "- tokens" },
            { tag: "nan", value: NaN, unit: "points", expected: "- points" },
            { tag: "infinite", value: Infinity, unit: "tokens", expected: "- tokens" },
            { tag: "thousands", value: 1500, unit: "tokens", expected: "1.5K tokens" },
            { tag: "billions", value: 4294967297, unit: "tokens", expected: "4.3B tokens" },
            { tag: "negative", value: -5, unit: "tokens", expected: "-5 tokens" },
            { tag: "unknown-unit", value: 1500, unit: "future", expected: "1.5K" }
        ];
    }

    function test_usageCountsKeepCompactTextAndLooseNumbers(data) {
        compare(subject.usageCountText(data.value, data.unit), data.expected);
        if (data.tag === "thousands")
            compare(subject.tokenCountString(data.value), "1.5K");
        if (data.tag === "nan")
            compare(subject.tokenCountString(data.value), "-");
    }

    function test_spendTotalUsesSuppliedCostsOnly() {
        var single = [{ totals: { cost: 5, tokens: 100, currency: "USD" } }];
        var singleBefore = JSON.stringify(single);
        compare(subject.spendTotalLine(single), "$5.00 total \u00b7 100 tokens");
        compare(JSON.stringify(single), singleBefore);

        compare(subject.spendTotalLine([
            { totals: { cost: null, tokens: 250, currency: "USD" } }
        ]), "250 tokens");
        compare(subject.spendTotalLine([
            { totals: { cost: null, tokens: null, currency: "USD" } }
        ]), "Tokens unavailable");
        compare(subject.spendTotalLine([
            { totals: { cost: NaN, tokens: Infinity, currency: "USD" } }
        ]), "Tokens unavailable");
        compare(subject.spendTotalLine([
            { totals: { cost: "5", tokens: 10, currency: "USD" } }
        ]), "10 tokens");
        compare(subject.spendTotalLine([
            { totals: { cost: 2, tokens: 100, currency: "USD" } },
            { totals: { cost: 9, tokens: 400, currency: "EUR" } }
        ]), "$2.00 subtotal \u00b7 500 tokens");
        compare(subject.spendTotalLine([
            { totals: { cost: null, tokens: 100, currency: "USD" } },
            { totals: { cost: 9, tokens: 400, currency: "EUR" } }
        ]), "EUR 9.00 total \u00b7 500 tokens");
        compare(subject.spendTotalLine([
            { totals: { cost: 2, tokens: null, currency: "USD" } },
            { totals: { cost: 9, tokens: null, currency: "EUR" } }
        ]), "$2.00 subtotal");
        compare(subject.spendTotalLine([
            { totals: { cost: 0, tokens: 0, currency: "USD" } }
        ]), "$0.00 total \u00b7 0 tokens");
        compare(subject.spendTotalLine([]), "");
        compare(subject.spendTotalLine(null), "");
        compare(subject.spendTotalLine({}), "");

        compare(subject.spendTotalLine([trustedCost("USD", {
            priced: 4, unpriced: 0, unmetered: 0, estimated: 1
        }, "listPrice")]), "$1.00 (estimated) total \u00b7 10 tokens");
        compare(subject.spendTotalLine([trustedCost("USD", {
            priced: 5, unpriced: 2, unmetered: 1, estimated: 0
        }, "vendor")]), "$1.00 (partial) total \u00b7 10 tokens");
        compare(subject.spendTotalLine([trustedCost("USD", {
            priced: 1, unpriced: 0, unmetered: 0, estimated: 0
        }, "unknown")]), "$1.00 (approximate) total \u00b7 10 tokens");
        compare(subject.spendTotalLine([trustedCost("USD", {
            priced: 1, unpriced: 0, unmetered: 0, estimated: 0
        }, "vendor")]), "$1.00 total \u00b7 10 tokens");
        compare(subject.spendTotalLine([
            {
                totals: { cost: 2, tokens: 100, currency: "USD" },
                trust: { coverage: null, sourceKind: "listPrice" }
            },
            { totals: { cost: 9, tokens: 400, currency: "EUR" } }
        ]), "$2.00 (estimated) subtotal \u00b7 500 tokens");
    }

    function test_dashboardRowsPreferNameFirstPartAndBoundText() {
        var named = subject.dashboardDisplayRow({
            labelKey: "today",
            label: "Ignored",
            name: "Named",
            parts: [
                { kind: "percent", value: 42.4 },
                { kind: "text", value: "extra" }
            ]
        });
        compare(named.label, "Today");
        compare(named.value, "Named (42%)");

        var nameOnly = subject.dashboardDisplayRow({
            labelKey: "",
            label: "Spend",
            name: "Only",
            parts: []
        });
        compare(nameOnly.label, "Spend");
        compare(nameOnly.value, "Only");

        var unknownKey = subject.dashboardDisplayRow({
            labelKey: "futureKey",
            label: "Fallback",
            name: "",
            parts: [{ kind: "text", value: "kept" }]
        });
        compare(unknownKey.label, "");
        compare(unknownKey.value, "kept");

        var fallback = subject.dashboardDisplayRow({
            labelKey: "",
            label: "Fallback",
            name: "",
            parts: [{ kind: "text", value: "Future <label>" }]
        });
        compare(fallback.label, "Fallback");
        compare(fallback.value, "Future <label>");

        var bounded = subject.dashboardDisplayRow({
            labelKey: "",
            label: "Spend",
            name: "",
            parts: [{ kind: "text", value: "x".repeat(600) }]
        });
        compare(bounded.label, "Spend");
        compare(bounded.value.length, 500);
        compare(bounded.value, "x".repeat(500));

        compare(subject.dashboardLabelText("codexDashboard"), "Codex dashboard");
        compare(subject.dashboardLabelText(""), "");
        compare(subject.dashboardLabelText("futureKey"), "");
        compare(subject.dashboardPartText({ kind: "percent", value: 42.6 }), "43%");
        compare(subject.dashboardPartText({ kind: "percent", value: "42" }), "42%");
        compare(subject.dashboardPartText({ kind: "percent", value: null }), "0%");
        compare(subject.dashboardPartText({ kind: "currency", value: 1234.5, currency: "USD" }), "$1,234.50");
        compare(subject.dashboardPartText({ kind: "currency", value: "1234.5", currency: "USD" }), "-");
        compare(subject.dashboardPartText({ kind: "tokens", value: 1 }), "1 token");
        compare(subject.dashboardPartText({ kind: "number", value: 1500 }), "1.5K");
        compare(subject.dashboardPartText({ kind: "text", value: "Future <label>" }), "Future <label>");
    }

    function test_tokenCostHintsResolveProviderIdentity() {
        var antigravity = "Local Antigravity history includes token totals. Dollar costs are unavailable.";
        var codex = "Estimated from local Codex logs for the selected account.";
        compare(subject.tokenCostHint("antigravity"), antigravity);
        compare(subject.tokenCostHint("agy"), antigravity);
        compare(subject.tokenCostHint("CODEX"), codex);
        compare(subject.tokenCostHint(null), codex);
        compare(subject.tokenCostHint(""), codex);
        compare(subject.tokenCostHint(false), codex);
        compare(subject.tokenCostHint("claude"), "Estimated from local Claude logs.");
        compare(subject.tokenCostHint("openai"), "");
        compare(subject.tokenCostHint("future-provider"), "");
    }

    function test_numberFormatIsExplicitAndReactive() {
        regionalFormat = CostPresentation.numberFormat(",", ".");
        compare(subject.amountString(1234.5, "USD"), "$1,234.50");
        regionalFormat = CostPresentation.numberFormat(".", ",");
        compare(subject.amountString(1234.5, "USD"), "$1.234,50");
        compare(subject.costLine("Today", 1234.5, null, "USD", "plain"), "Today: $1.234,50");
        compare(subject.dashboardPartText({ kind: "currency", value: 1234.5, currency: "EUR" }), "EUR 1.234,50");
        compare(subject.spendTotalLine([
            { totals: { cost: 1234.5, tokens: null, currency: "USD" } }
        ]), "$1.234,50 total");
        regionalFormat = ({});
        compare(subject.amountString(1234.5, "USD"), "$1,234.50");
        regionalFormat = CostPresentation.numberFormat(",", ".");
        compare(subject.amountString(-12, "USD"), "-$12.00");
        compare(subject.amountString(12.6, "Quota"), "13");
        compare(subject.amountString("12.6", "USD"), "-");
        compare(subject.amountString(NaN, "USD"), "-");
        compare(subject.amountString(Infinity, "USD"), "-");
        compare(subject.amountString(true, "USD"), "-");
        compare(subject.amountString(null, "EUR"), "-");
    }
}
