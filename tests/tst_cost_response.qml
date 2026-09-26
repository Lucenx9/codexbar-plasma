import QtQuick
import QtTest
import "../contents/ui/CostResponse.js" as CostResponse
import "../contents/ui/ProviderNormalizer.js" as Normalizer
import "../contents/ui/SafeText.js" as SafeText

TestCase {
    name: "CostResponse"

    function parse(payload, days) {
        return CostResponse.response(JSON.stringify(payload), "", days === undefined ? 30 : days);
    }
    function test_failuresNeverSupplyReplacementData_data() {
        return [
            {
                tag: "missing",
                text: undefined,
                outcome: "empty"
            },
            {
                tag: "empty",
                text: " ",
                outcome: "empty"
            },
            {
                tag: "broken",
                text: "{",
                outcome: "invalidJson"
            },
            {
                tag: "null",
                text: "null",
                outcome: "unsupported"
            },
            {
                tag: "object",
                text: "{}",
                outcome: "unsupported"
            },
            {
                tag: "wrong-provider",
                text: '[{"provider":{},"error":{}}]',
                outcome: "unsupported"
            },
            {
                tag: "too-large",
                text: " ".repeat(SafeText.maximumCliJsonLength + 1),
                outcome: "tooLarge"
            }
        ];
    }
    function test_failuresNeverSupplyReplacementData(data) {
        var result = CostResponse.response(data.text, "synthetic failure", 7);
        compare(result.outcome, data.outcome);
        compare(result.costs, undefined);
        verify(result.message.length <= SafeText.maximumCliMessageLength);
    }
    function test_emptySnapshotIsSuccess() {
        compare(parse([]), {
            outcome: "success",
            costs: {},
            failedProviders: [],
            message: "",
            argumentsRejected: false
        });
    }
    function test_errorMessages_data() {
        return [
            {
                tag: "object",
                message: {}
            },
            {
                tag: "array",
                message: ["bad"]
            },
            {
                tag: "shadowed-conversion",
                message: {
                    toString: null
                }
            },
            {
                tag: "null",
                message: null
            },
            {
                tag: "empty",
                message: ""
            }
        ];
    }
    function test_errorMessages(data) {
        var result = parse([
            {
                provider: "codex",
                error: {
                    message: data.message
                }
            },
            {
                provider: "claude",
                totals: {
                    totalCost: 4
                }
            }
        ]);
        compare(result.outcome, "partial");
        compare(result.failedProviders, ["codex"]);
        compare(result.message, "");
        compare(result.costs.codex, undefined);
        compare(result.costs.claude.totals.cost, 4);
    }
    function test_errorsWithoutMessagesStillFail_data() {
        return [
            {
                tag: "object",
                error: {}
            },
            {
                tag: "string",
                error: "failed"
            }
        ];
    }
    function test_errorsWithoutMessagesStillFail(data) {
        var result = parse([
            {
                provider: "codex",
                error: data.error,
                sessionCostUSD: 99
            }
        ]);
        compare(result.outcome, "partial");
        compare(result.failedProviders, ["codex"]);
        compare(result.costs, {});
    }
    function test_falsyErrorFlagsKeepHealthyCosts_data() {
        return [
            {
                tag: "false",
                error: false
            },
            {
                tag: "zero",
                error: 0
            },
            {
                tag: "empty",
                error: ""
            },
            {
                tag: "blank",
                error: "   "
            }
        ];
    }
    function test_falsyErrorFlagsKeepHealthyCosts(data) {
        var result = parse([
            {
                provider: "codex",
                totals: {
                    totalCost: 5,
                    totalTokens: 10
                },
                error: data.error
            }
        ]);
        compare(result.outcome, "success");
        compare(result.failedProviders, []);
        compare(result.costs.codex.totals.cost, 5);
        compare(result.costs.codex.totals.tokens, 10);
    }
    function test_nullErrorIsHealthyAndMessageIsBounded() {
        var result = parse([
            {
                provider: "codex",
                error: null,
                totals: {
                    totalCost: 4
                }
            },
            {
                provider: "claude",
                error: {
                    message: "x".repeat(5000)
                }
            }
        ]);
        compare(result.costs.codex.totals.cost, 4);
        verify(result.message.length <= SafeText.maximumCliMessageLength);
        compare(result.failedProviders, ["claude"]);
    }
    function test_rangeNormalization_data() {
        return [
            {
                tag: "captured",
                emitted: undefined,
                requested: 7,
                expected: 7,
                label: 7
            },
            {
                tag: "emitted",
                emitted: 90,
                requested: 7,
                expected: 90,
                label: 90
            },
            {
                tag: "bounded",
                emitted: 999,
                requested: 7,
                expected: 365,
                label: 999
            },
            {
                tag: "bad-emitted",
                emitted: {},
                requested: 7,
                expected: 7,
                label: 7
            },
            {
                tag: "invalid",
                emitted: -1,
                requested: null,
                expected: 30,
                label: 30
            }
        ];
    }
    function test_rangeNormalization(data) {
        var cost = parse({
            provider: "codex",
            historyDays: data.emitted
        }, data.requested).costs.codex;
        compare(cost.historyDays, data.expected);
        compare(cost.labelDays, data.label);
        compare(cost.historyLabel, null);
        compare(cost.historyCoverageEstablished, true);
    }
    function test_rollingPeriodLabelIsLeftToTheLocalizedWidgetLabel_data() {
        // CLI 0.67.0 labels every record in English, including the ranges
        // the widget requests and titles itself in the locale.
        return [
            { tag: "rolling", period: "rolling:30", label: "Last 30 days", expected: null },
            { tag: "today", period: "rolling:1", label: "Today", expected: null },
            { tag: "month-to-date", period: "month-to-date", label: "Month to date", expected: null },
            { tag: "all", period: "all", label: "All", expected: null },
            { tag: "unknown period", period: "quarter", label: "Quarter", expected: "Quarter" },
            { tag: "malformed period", period: "rolling:", label: "Custom", expected: "Custom" },
            { tag: "non-string period", period: 30, label: "Custom", expected: "Custom" },
            { tag: "no period", period: undefined, label: "Custom", expected: "Custom" }
        ];
    }
    function test_rollingPeriodLabelIsLeftToTheLocalizedWidgetLabel(data) {
        var cost = parse({
            provider: "codex",
            historyDays: 30,
            historyLabel: data.label,
            reportingPeriod: data.period
        }).costs.codex;
        compare(cost.historyLabel, data.expected);
        compare(cost.labelDays, 30);
    }
    function test_reportingPeriodIsKeptOnlyForCalendarPeriods_data() {
        return [
            { tag: "month-to-date", period: "month-to-date", expected: "month-to-date" },
            { tag: "all", period: "all", expected: "all" },
            { tag: "rolling", period: "rolling:30", expected: "" },
            { tag: "absent", period: undefined, expected: "" },
            { tag: "unknown", period: "quarter", expected: "" },
            { tag: "non-string", period: 7, expected: "" }
        ];
    }
    function test_reportingPeriodIsKeptOnlyForCalendarPeriods(data) {
        var cost = parse({ provider: "codex", historyDays: 26, reportingPeriod: data.period }).costs.codex;
        compare(cost.period, data.expected);
    }
    function test_allHistorySpansTheRecordedDaysWithinTheChartBound_data() {
        // `--period all` reports the days since year 1. The window runs from
        // the oldest recorded day to the scan day instead, within 365 days.
        return [
            { tag: "recorded span", first: "2026-03-02", last: "2026-09-19",
                updatedAt: "2026-09-19T12:00:00Z", expected: 202 },
            { tag: "scan after last day", first: "2026-09-10", last: "2026-09-12",
                updatedAt: "2026-09-19T12:00:00Z", expected: 10 },
            { tag: "no scan time", first: "2026-09-10", last: "2026-09-12",
                updatedAt: undefined, expected: 3 },
            { tag: "longer than the bound", first: "2024-01-01", last: "2026-09-19",
                updatedAt: "2026-09-19T12:00:00Z", expected: 365 },
            { tag: "no recorded day", first: null, last: null,
                updatedAt: "2026-09-19T12:00:00Z", expected: 365 }
        ];
    }
    function test_allHistorySpansTheRecordedDaysWithinTheChartBound(data) {
        var daily = [];
        if (data.first) {
            daily.push({ date: "not a day", totalCost: 1 });
            daily.push({ date: data.last, totalCost: 1 });
            daily.push({ date: data.first, totalCost: 1 });
        }
        var cost = parse({ provider: "codex", historyDays: 739887, reportingPeriod: "all",
            updatedAt: data.updatedAt, daily: daily }).costs.codex;
        compare(cost.period, "all");
        compare(cost.historyDays, data.expected);
    }
    function test_rejectedArgumentsAreReportedApartFromProviderFailures() {
        // CLI 0.66.0 rejects `--period` with an args error record.
        var rejected = parse([{ provider: "cli", source: "cli",
            error: { kind: "args", code: 1, message: "Unknown option --period" } }]);
        compare(rejected.outcome, "partial");
        compare(rejected.argumentsRejected, true);
        var failed = parse([{ provider: "codex", error: { kind: "provider", message: "failed" } }]);
        compare(failed.argumentsRejected, false);
        compare(parse([{ provider: "codex", historyDays: 30 }]).argumentsRejected, false);
    }
    function test_snapshotKeepsOnlyBoundedNormalizedFields() {
        var cost = parse({
            provider: "codex",
            historyLabel: "x".repeat(1000),
            historyDays: 7,
            currencyCode: "USD",
            historyCoverageIsEstablished: false,
            sessionCostUSD: -2,
            sessionTokens: -3,
            totals: {
                totalCost: 4,
                totalTokens: 123
            },
            projects: [
                {
                    name: "example",
                    path: "/private/path",
                    totalCost: 4
                }
            ],
            updatedAt: "2026-09-12T10:00:00Z",
            daily: [
                {
                    date: "2026-09-12",
                    totalCost: 4,
                    totalTokens: 123,
                    modelBreakdowns: [
                        {
                            modelName: "Example",
                            cost: 4,
                            totalTokens: 123
                        }
                    ]
                }
            ],
            unknownSecret: "not retained"
        }).costs.codex;
        compare(cost.historyLabel.length, 120);
        compare(cost.historyCoverageEstablished, false);
        compare(cost.sessionCost, -2);
        compare(cost.sessionTokens, -3);
        compare(cost.today.cost, 0);
        compare(cost.today.tokens, 0);
        compare(cost.totals.cost, 4);
        compare(cost.models.length, 1);
        compare(cost.models[0].label, "Example");
        compare(cost.daily.length, 7);
        compare(cost.unknownSecret, undefined);
        verify(JSON.stringify(cost).indexOf("/private/path") < 0);
        compare(cost.title, undefined);
    }
    function test_unavailableCostsAndTrustRemainIndependent() {
        var cost = parse({
            provider: "antigravity",
            sessionCostUSD: 0,
            sessionTokens: 50,
            totals: {
                totalCost: 0,
                totalTokens: 100
            }
        }).costs.antigravity;
        compare(cost.sessionCost, null);
        compare(cost.today.cost, null);
        compare(cost.totals.cost, null);
        compare(cost.totals.tokens, 100);
        var estimated = parse({
            provider: "codex",
            provenance: "listPriceEstimate",
            totals: {
                totalCost: 5
            },
            sessionCostUSD: 2
        }).costs.codex;
        compare(estimated.valueMode, "estimated");
        compare(estimated.sessionCost, 2);
    }
    // Snapshot projects are normalized display rows, never raw CLI records.
    function test_snapshotExposesNormalizedProjects() {
        var cost = parse({
            provider: "codex",
            projects: [
                {
                    name: "example",
                    path: "/private/path",
                    totalCost: 4
                }
            ]
        }).costs.codex;
        compare(cost.projects.rows.length, 1);
        compare(cost.projects.rows[0].label, "example");
        compare(cost.projects.rows[0].cost, 4);
        compare(cost.projects.truncated, false);
        verify(JSON.stringify(cost.projects).indexOf("/private/path") < 0);
    }
    // Snapshot model truncation follows the normalized model summary.
    function test_snapshotPropagatesModelTruncation() {
        var breakdowns = [];
        for (var i = 0; i < 7; i++) {
            breakdowns.push({
                modelName: "model-" + i,
                cost: i + 1,
                totalTokens: 10
            });
        }
        var few = parse({
            provider: "codex",
            daily: [
                {
                    date: "2026-09-12",
                    totalCost: 4,
                    totalTokens: 123,
                    modelBreakdowns: [
                        {
                            modelName: "Example",
                            cost: 4,
                            totalTokens: 123
                        }
                    ]
                }
            ]
        }).costs.codex;
        compare(few.modelsTruncated, false);
        var many = parse({
            provider: "codex",
            daily: [
                {
                    date: "2026-09-12",
                    modelBreakdowns: breakdowns
                }
            ]
        }).costs.codex;
        compare(many.models.length, 6);
        compare(many.modelsTruncated, true);
    }
    // Official 0.60.5 output counts requests the CLI excluded per day and per
    // model breakdown. A model's row sums its days, including a day whose
    // breakdown has no measured amounts; malformed counts mean none reported.
    function test_rowsCarryExcludedRequestCounts() {
        var codex = parse({
            provider: "codex",
            daily: [
                {
                    date: "2026-09-11",
                    totalCost: 1,
                    totalTokens: 10,
                    incompleteRequestCount: 2,
                    modelBreakdowns: [
                        {modelName: "Measured", cost: 1, totalTokens: 10, incompleteRequestCount: 2},
                        {modelName: "OnlyIncomplete", incompleteRequestCount: 7},
                        {modelName: "Clean", cost: 0.5, totalTokens: 4, incompleteRequestCount: -3}
                    ]
                },
                {
                    date: "2026-09-12",
                    totalCost: 2,
                    totalTokens: 20,
                    incompleteRequestCount: "4",
                    modelBreakdowns: [
                        {modelName: "Measured", cost: 2, totalTokens: 20, incompleteRequestCount: 3},
                        {modelName: "Clean", cost: 0.5, totalTokens: 4, incompleteRequestCount: 1.5},
                        {modelName: "Saturated", cost: 0.1, totalTokens: 1, incompleteRequestCount: 1000000000},
                        {modelName: "Saturated", cost: 0.1, totalTokens: 1, incompleteRequestCount: 1000000000}
                    ]
                }
            ]
        }).costs.codex;
        compare(codex.daily.map(function(day) { return day.incompleteRequests; }), [2, 0]);
        var byLabel = ({});
        codex.models.forEach(function(model) { byLabel[model.label] = model.incompleteRequests; });
        compare(byLabel, {Measured: 5, Clean: 0, Saturated: 1000000000});
        compare(codex.daily[0].models.map(function(model) { return model.label + ":" + model.incompleteRequests; }),
            ["Measured:2", "Clean:0"]);
    }
    function test_partialMergeRetainsOnlyExplicitFailures() {
        var old = parse([
            {
                provider: "codex",
                totals: {
                    totalCost: 1
                }
            },
            {
                provider: "claude",
                totals: {
                    totalCost: 2
                }
            },
            {
                provider: "gemini",
                totals: {
                    totalCost: 3
                }
            }
        ]).costs;
        var result = parse([
            {
                provider: "codex",
                error: {}
            },
            {
                provider: "claude",
                totals: {
                    totalCost: 4
                }
            }
        ]);
        var merged = Normalizer.mergeCostSnapshotsAfterPartialFailure(old, result.costs, result.failedProviders);
        compare(merged.codex, old.codex);
        compare(merged.claude.totals.cost, 4);
        compare(merged.gemini, undefined);
    }
}
