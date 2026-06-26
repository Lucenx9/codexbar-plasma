import QtQuick 2.15
import QtTest 1.0
import "../contents/ui/Logic.js" as Logic

TestCase {
    name: "CostSparklineSummaryTests"

    // Mock i18n
    function mockI18n(text, arg1, arg2) {
        if (arg1 !== undefined && arg2 !== undefined) {
            return arg1 + ": " + arg2;
        }
        return text;
    }

    // Mock amountString
    function mockAmountString(cost, currency) {
        return cost + " " + currency;
    }

    function test_emptyOrNull() {
        compare(Logic.costSparklineSummary(null, mockI18n, mockAmountString), "")
        compare(Logic.costSparklineSummary(undefined, mockI18n, mockAmountString), "")
        compare(Logic.costSparklineSummary([], mockI18n, mockAmountString), "")
    }

    function test_singlePointWithLabelAndCurrency() {
        var points = [
            { label: "Today", cost: 10.5, currency: "EUR" }
        ]
        compare(Logic.costSparklineSummary(points, mockI18n, mockAmountString), "Today: 10.5 EUR")
    }

    function test_singlePointWithoutLabelOrCurrency() {
        var points = [
            { cost: 5.0 }
        ]
        compare(Logic.costSparklineSummary(points, mockI18n, mockAmountString), "Latest: 5 USD")
    }

    function test_multiplePoints() {
        var points = [
            { label: "Yesterday", cost: 8.0, currency: "USD" },
            { label: "Today", cost: 12.0, currency: "USD" }
        ]
        compare(Logic.costSparklineSummary(points, mockI18n, mockAmountString), "Today: 12 USD")
    }
}
