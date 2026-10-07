import QtQuick
import QtTest
import "../contents/ui/components" as Components
import "../contents/ui/CostPresentation.js" as CostPresentation
import "../contents/ui/ProviderNormalizer.js" as Normalizer

TestCase {
    id: testCase
    name: "ProviderCostDetails"

    property var currentCost: null
    readonly property var liveSection: details.costSection("future-provider", currentCost)

    Components.ProviderCostDetails {
        id: details
        numberFormat: CostPresentation.numberFormat(",", ".")
        function i18n(source) {
            var text = source;
            for (var i = 1; i < arguments.length; i++) {
                text = text.replace("%" + i, String(arguments[i]));
            }
            return text;
        }
        function i18np(one, many, count) {
            return i18n(count === 1 ? one : many, count);
        }
    }

    function init() {
        failOnWarning(/.*/);
        currentCost = null;
        details.numberFormat = CostPresentation.numberFormat(",", ".");
    }

    function test_zeroAndMissingAmountsKeepDistinctMeaning() {
        compare(details.costSection("future-provider", {}), null);
        var zero = details.costSection("future-provider", {used: 0});
        compare(zero.spendLine, "This month: $0.00");
        compare(zero.percentUsed, -1);
        compare(zero.percentLine, "");
        compare(zero.personalSpendLine, "");
        // Codex's empty placeholder remains hidden; it is not the purchased
        // balance or the monthly allowance.
        compare(details.costSection("codex", {used: 0, currencyCode: "Credits"}), null);
        var allowance = details.costSection("future-provider", {used: 0, limit: 100, personalUsed: 0});
        compare(allowance.spendLine, "This month: $0.00 / $100.00");
        compare(allowance.percentLine, "0% used");
        compare(allowance.personalSpendLine, "");
    }

    function test_invalidCostAndResetRecords_data() {
        return [
            {tag: "null", value: null}, {tag: "undefined", value: undefined},
            {tag: "array", value: []}, {tag: "text", value: "cost"},
            {tag: "boolean", value: true}, {tag: "number", value: 42},
            {tag: "object-value", value: {used: {}, availableCount: {}}},
            {tag: "boolean-value", value: {used: false, availableCount: false}},
            {tag: "infinite-value", value: {used: Infinity, availableCount: Infinity}}
        ];
    }

    function test_invalidCostAndResetRecords(data) {
        compare(details.costSection("future-provider", data.value), null);
        compare(details.resetSection("codex", data.value), null);
    }

    function test_unknownProvidersAndPeriodsRetainBoundedText() {
        var cost = {used: 12.5, limit: 100, period: " Provider billing window ", currencyCode: "EUR"};
        var before = JSON.stringify(cost);
        var section = details.costSection("future-provider", cost);
        compare(section.title, "Extra usage");
        compare(section.spendLine, "Provider billing window: EUR 12.50 / EUR 100.00");
        compare(section.percentLine, "13% used");
        compare(JSON.stringify(cost), before);
        cost.period = "x".repeat(200);
        section = details.costSection("future-provider", cost);
        verify(section.spendLine.length < 160, section.spendLine);
        compare(details.costSection("__proto__", cost), null);
        compare(details.resetSection("future-provider", {availableCount: 2}), null);
    }

    function test_numberFormatChangesRecomputeBoundDisplay() {
        currentCost = {used: 1234.5, limit: 2000, currencyCode: "EUR", personalUsed: 1000};
        compare(liveSection.spendLine, "This month: EUR 1,234.50 / EUR 2,000.00");
        compare(liveSection.personalSpendLine, "Your spend: EUR 1,000.00");
        details.numberFormat = CostPresentation.numberFormat(".", ",");
        compare(liveSection.spendLine, "This month: EUR 1.234,50 / EUR 2.000,00");
        compare(liveSection.personalSpendLine, "Your spend: EUR 1.000,00");
    }

    function test_resetCreditsKeepPluralAndOptionalSemantics() {
        compare(details.resetSection("codex", {availableCount: 0}), null);
        compare(details.resetSection("codex", {}), null);
        compare(details.resetSection("codex", {availableCount: 1}).line, "1 available");
        compare(details.resetSection("codex", {availableCount: "2"}).line, "2 available");
        compare(details.resetSection("codex", {availableCount: 0.2}).line, "0 available");
    }

    function test_normalizedMonthlyLimitRetainsAmountsAndResetWithoutPace() {
        var normalized = Normalizer.normalizeCodexCreditLimit("codex", {
            title: "", used: 0, remaining: 1234.5, limit: 1234.5, remainingPercent: 100,
            resetsAt: "2026-10-14T12:00:00Z"});
        var before = JSON.stringify(normalized);
        var row = details.creditLimitRow(normalized);
        compare(row.label, "Monthly credit limit");
        compare(row.summaryText, "Used: 0, remaining: 1,235 of 1,235");
        compare(row.usedPercent, 0);
        compare(row.leftPercent, 100);
        compare(row.resetsAt, normalized.resetsAt);
        compare(row.pace, "");
        compare(row.pacePercent, -1);
        compare(JSON.stringify(normalized), before);
        normalized.title = "Provider's monthly title";
        compare(details.creditLimitRow(normalized).label, "Provider's monthly title");
        compare(details.creditLimitRow(null), null);
        compare(details.creditLimitRow(Normalizer.normalizeCodexCreditLimit("codex", {})), null);
        compare(details.creditLimitRow(Normalizer.normalizeCodexCreditLimit("claude", {
            used: 0, remaining: 100, limit: 100, remainingPercent: 100})), null);
    }
}
