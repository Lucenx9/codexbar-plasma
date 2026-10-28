import QtQuick
import QtTest
import "../contents/ui/CostPresentation.js" as CostPresentation
import "../contents/ui/components" as Components

TestCase {
    id: testCase
    name: "CostLabels"

    property var numberFormat: CostPresentation.numberFormat(",", ".")
    property bool showsTokens: false

    function i18n(source) {
        for (var i = 1; i < arguments.length; i++)
            source = source.replace("%" + i, String(arguments[i]));
        return source;
    }
    function i18np(one, many, count) {
        return i18n(count === 1 ? one : many, count);
    }

    Components.CostText {
        id: costText
        numberFormat: testCase.numberFormat
        function i18n() {
            return testCase.i18n.apply(testCase, arguments);
        }
        function i18np(one, many, count) {
            return testCase.i18np(one, many, count);
        }
    }
    Components.CostLabels {
        id: costLabels
        numberFormat: testCase.numberFormat
        showsTokens: testCase.showsTokens
        tokenCountText: function (tokens) {
            return costText.usageCountText(tokens, "tokens");
        }
        function i18n() {
            return testCase.i18n.apply(testCase, arguments);
        }
    }

    function init() {
        numberFormat = CostPresentation.numberFormat(",", ".");
        showsTokens = false;
    }
    function laneTotals() {
        return {
            totals: {
                tokens: 1500,
                inputTokens: 1000,
                outputTokens: 400,
                cacheReadTokens: 80,
                cacheCreationTokens: 20
            }
        };
    }
    function twoDays() {
        return [
            {
                label: "Mon",
                cost: 5,
                tokens: 900,
                currency: "USD"
            },
            {
                label: "Tue",
                cost: 2,
                tokens: 4000,
                currency: "USD"
            }
        ];
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
        var models = costLabels.costModelRows({
            models: [
                {
                    label: "A",
                    cost: 1,
                    tokens: 1000,
                    currency: "USD"
                },
                {
                    label: "B",
                    cost: null,
                    tokens: 500,
                    currency: "USD"
                }
            ]
        });
        compare(models.length, 2);
        compare(models[1].value, "500 tokens");
        var history = costLabels.costHistoryRows({
            daily: [
                {
                    label: "Mon",
                    cost: 1,
                    tokens: 4000,
                    currency: "USD"
                },
                {
                    label: "Tue",
                    cost: 4,
                    tokens: 1000,
                    currency: "USD"
                }
            ]
        });
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
        compare(costLabels.costPerMillionLine({
            totals: {
                cost: 2,
                tokens: 1000000,
                currency: "USD"
            }
        }), "Average: $2.00 / 1M tokens");
        compare(costLabels.costPeakLine([]), "");
        // All history longer than the chart supplies its whole-range average.
        var average = {
            cost: {
                value: 9,
                currency: "USD"
            },
            tokens: null
        };
        compare(costLabels.costAverageDailyLine(twoDays(), average), "Average/day: $9.00");
        testCase.showsTokens = true;
        compare(costLabels.costAverageDailyLine(twoDays(), average), "");
        testCase.showsTokens = false;
    }

    function test_perMillionLineHandlesLargeFiniteTotals() {
        compare(costLabels.costPerMillionLine({
            totals: {
                cost: 1e308,
                tokens: 1e308,
                currency: "EUR"
            }
        }), "Average: EUR 1,000,000.00 / 1M tokens");
        compare(costLabels.costPerMillionLine({
            totals: {
                cost: Number.MAX_VALUE,
                tokens: 1,
                currency: "USD"
            }
        }), "");
    }

    // A peak older than the seven history rows is neither shown nor
    // highlighted there, so the peak line names the highlighted row instead.
    function test_peakLineNamesTheHighlightedHistoryRow() {
        var daily = [
            {
                label: "D0",
                cost: 50,
                tokens: 1,
                currency: "USD"
            }
        ];
        for (var i = 1; i <= 7; i++)
            daily.push({
                label: "D" + i,
                cost: i === 3 ? 9 : 1,
                tokens: 1,
                currency: "USD"
            });
        var rows = costLabels.costHistoryRows({
            daily: daily
        });
        compare(rows.map(function (row) {
            return row.label;
        }), ["D7", "D6", "D5", "D4", "D3", "D2", "D1"]);
        var highlighted = rows.filter(function (row) {
            return row.isPeak;
        });
        compare(highlighted.map(function (row) {
            return row.label;
        }), ["D3"]);
        compare(costLabels.costPeakLine(daily), "Peak: D3 - $9.00");
    }

    // History rows, the peak line, and the latest-day summary date their
    // days like the chart, in the locale's short format, and keep any other
    // label as the CLI sent it.
    function test_historyTextDatesDaysInTheLocale() {
        var day = function (key) {
            var parts = key.split("-").map(Number);
            return new Date(parts[0], parts[1] - 1, parts[2]).toLocaleDateString(Qt.locale(), Locale.ShortFormat);
        };
        var daily = [
            {
                label: "2026-09-23",
                cost: 1,
                tokens: 1,
                currency: "USD"
            },
            {
                label: "2026-09-24",
                cost: 4,
                tokens: 1,
                currency: "USD"
            },
            {
                label: "2026-09-25",
                cost: 2,
                tokens: 1,
                currency: "USD"
            }
        ];
        compare(costLabels.costHistoryRows({
            daily: daily
        }).map(function (row) {
            return row.label;
        }), [day("2026-09-25"), day("2026-09-24"), day("2026-09-23")]);
        compare(costLabels.costPeakLine(daily), "Peak: " + day("2026-09-24") + " - $4.00");
        compare(costLabels.costSparklineSummary(daily), day("2026-09-25") + ": $2.00");
        compare(costLabels.costDayLabel("2026-09-24"), day("2026-09-24"));
        compare(costLabels.costDayLabel("Week 34"), "Week 34");
        compare(costLabels.costDayLabel("2026-02-30"), "2026-02-30");
        compare(costLabels.costDayLabel(""), "");
    }

    function test_explicitInputsUpdateWithoutAnApplet() {
        showsTokens = true;
        compare(costLabels.costPeakLine(twoDays()), "Peak: Tue - 4K");
        var snapshot = {
            models: [
                {
                    label: "A",
                    cost: null,
                    tokens: 1500,
                    currency: "USD"
                }
            ]
        };
        var before = JSON.stringify(snapshot);
        compare(costLabels.costModelRows(snapshot)[0].value, "1.5K tokens");
        numberFormat = CostPresentation.numberFormat(".", ",");
        compare(costLabels.costModelRows(snapshot)[0].value, "1,5K tokens");
        compare(JSON.stringify(snapshot), before);
    }
}
