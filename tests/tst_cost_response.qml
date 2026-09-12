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
            message: ""
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
            },
            {
                tag: "false",
                error: false
            },
            {
                tag: "zero",
                error: 0
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
