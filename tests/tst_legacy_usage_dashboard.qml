import QtQuick
import QtTest
import "../contents/ui/LegacyUsageDashboard.js" as LegacyUsageDashboard

TestCase {
    name: "LegacyUsageDashboard"

    function normalizeSource(source) {
        return LegacyUsageDashboard.normalize({}, {
            openaiDashboard: source
        });
    }

    function test_missingAndMalformedEnvelopes_data() {
        return [
            {
                tag: "missing",
                value: undefined
            },
            {
                tag: "null",
                value: null
            },
            {
                tag: "empty",
                value: {}
            },
            {
                tag: "array",
                value: []
            },
            {
                tag: "number",
                value: 4
            },
            {
                tag: "boolean",
                value: true
            },
            {
                tag: "string",
                value: "invalid"
            }
        ];
    }

    function test_missingAndMalformedEnvelopes(data) {
        compare(LegacyUsageDashboard.normalize(data.value, data.value), null);
        compare(normalizeSource(data.value), null);
        var healthyItem = LegacyUsageDashboard.normalize(data.value, {
            openaiDashboard: {
                creditsRemaining: 8
            }
        });
        compare(healthyItem.rows[0].parts[0].value, 8);
    }

    function test_preservesMetricZeroesAndScalarText() {
        var dashboard = normalizeSource({
            codeReviewRemainingPercent: 0,
            creditsRemaining: "0",
            accountPlan: false,
            signedInEmail: 0
        });
        compare(dashboard.rows, [
            {
                labelKey: "codeReviewRemaining",
                label: "",
                name: "",
                parts: [
                    {
                        kind: "percent",
                        value: 0
                    }
                ]
            },
            {
                labelKey: "creditsRemaining",
                label: "",
                name: "",
                parts: [
                    {
                        kind: "number",
                        value: 0
                    }
                ]
            },
            {
                labelKey: "plan",
                label: "",
                name: "",
                parts: [
                    {
                        kind: "text",
                        value: "false"
                    }
                ]
            },
            {
                labelKey: "signedIn",
                label: "",
                name: "",
                parts: [
                    {
                        kind: "text",
                        value: "0"
                    }
                ]
            }
        ]);
        compare(dashboard.kpis[0].labelKey, "codexDashboard");
        compare(dashboard.kpis[0].parts, dashboard.rows[0].parts);
    }

    function test_numericMetricsRejectCoerciveValues_data() {
        return [
            {
                tag: "null",
                value: null
            },
            {
                tag: "missing",
                value: undefined
            },
            {
                tag: "boolean",
                value: false
            },
            {
                tag: "array",
                value: []
            },
            {
                tag: "object",
                value: {}
            },
            {
                tag: "blank",
                value: "  "
            },
            {
                tag: "infinity",
                value: Infinity
            },
            {
                tag: "nan",
                value: NaN
            }
        ];
    }

    function test_numericMetricsRejectCoerciveValues(data) {
        compare(normalizeSource({
            codeReviewRemainingPercent: data.value,
            creditsRemaining: data.value
        }), null);
        var dashboard = normalizeSource({
            currentDay: {
                costUSD: data.value,
                cost: 0
            }
        });
        compare(dashboard.rows[0].parts, [
            {
                kind: "currency",
                value: 0,
                currency: "USD"
            }
        ]);
    }

    function test_preservesPeriodAliasesAndPartOrder() {
        var dashboard = normalizeSource({
            currentDay: {
                costUSD: {},
                cost: "2.5",
                totalCost: 99,
                totalTokens: null,
                tokens: "1200",
                requests: false,
                requestCount: 3,
                points: [],
                totalPoints: 4,
                currencyCode: "EUR"
            }
        });
        compare(dashboard.rows[0].labelKey, "today");
        compare(dashboard.rows[0].parts, [
            {
                kind: "currency",
                value: 2.5,
                currency: "EUR"
            },
            {
                kind: "tokens",
                value: 1200
            },
            {
                kind: "requests",
                value: 3
            },
            {
                kind: "points",
                value: 4
            }
        ]);
    }

    function test_periodZeroCostWinsOverAliasesAndCountsStayHidden() {
        var dashboard = normalizeSource({
            today: {
                costUSD: 0,
                cost: 9,
                totalCost: 10,
                totalTokens: 0,
                requests: 0,
                points: 0
            },
            last7Days: {
                totalTokens: 0,
                tokens: 100,
                requests: -1,
                points: 0
            },
            last30Days: {
                totalTokens: 0,
                value: 0,
                total: 100
            }
        });
        compare(dashboard.rows.length, 2);
        compare(dashboard.rows[0].parts, [
            {
                kind: "currency",
                value: 0,
                currency: "USD"
            }
        ]);
        compare(dashboard.rows[1].labelKey, "last30Days");
        compare(dashboard.rows[1].parts, [
            {
                kind: "number",
                value: 0
            }
        ]);
    }

    function test_periodGenericFallback_data() {
        return [
            {
                tag: "preferred-zero",
                source: {
                    value: 0,
                    total: 4
                },
                kind: "number",
                value: 0
            },
            {
                tag: "total-zero",
                source: {
                    value: {},
                    total: "0",
                    used: 8
                },
                kind: "number",
                value: 0
            },
            {
                tag: "used-number",
                source: {
                    value: false,
                    total: [],
                    used: 2
                },
                kind: "number",
                value: 2
            },
            {
                tag: "number-before-text",
                source: {
                    value: "Pending",
                    total: 2
                },
                kind: "number",
                value: 2
            },
            {
                tag: "value-text",
                source: {
                    value: "Pending",
                    total: "Unused"
                },
                kind: "text",
                value: "Pending"
            },
            {
                tag: "total-text",
                source: {
                    value: "  ",
                    total: "Pending"
                },
                kind: "text",
                value: "Pending"
            },
            {
                tag: "used-text",
                source: {
                    value: {},
                    total: "",
                    used: "Pending"
                },
                kind: "text",
                value: "Pending"
            }
        ];
    }

    function test_periodGenericFallback(data) {
        var dashboard = normalizeSource({
            currentDay: data.source
        });
        compare(dashboard.rows[0].parts, [
            {
                kind: data.kind,
                value: data.value
            }
        ]);
    }

    function test_periodFallbackRejectsMissingAndStructuredValues() {
        compare(normalizeSource({
            today: {
                value: false,
                total: [],
                used: {}
            },
            last7Days: {
                value: null,
                total: undefined
            },
            last30Days: {
                value: " ",
                total: "",
                used: NaN
            },
            month: [1, 2]
        }), null);
    }

    function test_periodSourceAndCurrencyFallbackPrecedence() {
        var dashboard = normalizeSource({
            currentDay: {
                totalCost: 2,
                currency: "EUR",
                currencyCode: "GBP"
            },
            today: {
                cost: 99
            },
            currentMonth: {
                value: 3
            },
            month: {
                value: 4
            },
            billingSummary: {
                value: 5
            }
        });
        compare(dashboard.rows[0].parts, [
            {
                kind: "currency",
                value: 2,
                currency: "EUR"
            }
        ]);
        compare(dashboard.rows[1].parts[0].value, 3);
        compare(normalizeSource({
            currentDay: {},
            today: {
                cost: 9
            }
        }), null);
        compare(normalizeSource({
            month: {
                value: 4
            },
            billingSummary: {
                value: 5
            }
        }).rows[0].parts[0].value, 4);
        compare(normalizeSource({
            billingSummary: {
                value: 5
            }
        }).rows[0].parts[0].value, 5);
    }

    function test_topSuffixPrecedenceAndZeroes() {
        var dashboard = normalizeSource({
            topModels: [
                {
                    name: "Model A",
                    costUSD: 0,
                    points: 1,
                    totalTokens: 2,
                    requests: 3
                }
            ],
            topUsageTypes: [
                {
                    type: "Chat",
                    costUSD: null,
                    points: 0,
                    totalTokens: 2
                }
            ]
        });
        compare(dashboard.rows[0].name, "Model A");
        compare(dashboard.rows[0].parts, [
            {
                kind: "currency",
                value: 0,
                currency: "USD"
            }
        ]);
        compare(dashboard.rows[1].name, "Chat");
        compare(dashboard.rows[1].parts, [
            {
                kind: "points",
                value: 0
            }
        ]);
        dashboard = normalizeSource({
            topModels: [
                {
                    model: "Model B",
                    costUSD: [],
                    points: false,
                    totalTokens: "0",
                    requests: 3
                }
            ],
            topUsageTypes: [
                {
                    label: "Chat",
                    requests: 0
                }
            ]
        });
        compare(dashboard.rows[0].parts, [
            {
                kind: "tokens",
                value: 0
            }
        ]);
        compare(dashboard.rows[1].parts, [
            {
                kind: "requests",
                value: 0
            }
        ]);
    }

    function test_topRowsKeepNamesWithoutInventingAmounts() {
        var dashboard = normalizeSource({
            topModels: [
                {
                    name: "Model A",
                    costUSD: false
                }
            ]
        });
        compare(dashboard.rows[0].name, "Model A");
        compare(dashboard.rows[0].parts, []);
        compare(normalizeSource({
            topModels: [null,
                {
                    name: "Do not scan later items"
                }
            ]
        }), null);
        compare(normalizeSource({
            topModels: [
                {
                    name: {},
                    model: "Shadowed",
                    costUSD: 1
                }
            ]
        }), null);
        compare(normalizeSource({
            topModels: [
                {
                    totalTokens: 20
                }
            ]
        }), null);
    }

    function test_latestDailyAndBreakdownUseOnlyLastRecords() {
        var dashboard = normalizeSource({
            daily: [
                {
                    value: 100
                },
                {
                    label: "Daily label",
                    day: "Day",
                    value: 2
                }
            ],
            usageBreakdown: [
                {
                    totalCreditsUsed: 100
                },
                {
                    day: "Breakdown day",
                    label: "Label",
                    totalCreditsUsed: 0
                }
            ],
            dailyBreakdown: [
                {
                    totalCreditsUsed: 90
                }
            ]
        });
        compare(dashboard.rows[0].label, "Daily label");
        compare(dashboard.rows[0].labelKey, "");
        compare(dashboard.rows[0].parts[0].value, 2);
        compare(dashboard.rows[1].label, "Breakdown day");
        compare(dashboard.rows[1].parts[0].value, 0);
        compare(normalizeSource({
            daily: [
                {
                    cost: 1
                },
                null],
            usageBreakdown: []
        }), null);
        dashboard = normalizeSource({
            daily: [
                {
                    cost: 1
                }
            ],
            dailyBreakdown: [
                {
                    points: 2
                }
            ]
        });
        compare(dashboard.rows[0].labelKey, "latest");
        compare(dashboard.rows[1].labelKey, "latestDashboardDay");
    }

    function test_preservesAllLegacySourcesAndKpiLimit() {
        var usage = {
            openAIAPIUsage: {
                creditsRemaining: 1
            },
            openRouterUsage: {
                creditsRemaining: 2
            },
            claudeAdminAPIUsage: {
                creditsRemaining: 3
            },
            poeUsage: {
                creditsRemaining: 4
            },
            deepseekUsage: {
                creditsRemaining: 5
            },
            minimaxUsage: {
                creditsRemaining: 6
            },
            zaiUsage: {
                creditsRemaining: 7
            }
        };
        var dashboard = LegacyUsageDashboard.normalize(usage, {
            openaiDashboard: {
                creditsRemaining: 0
            }
        });
        compare(dashboard.rows.length, 8);
        compare(dashboard.kpis.length, 4);
        compare(dashboard.kpis.map(function (kpi) {
            return kpi.labelKey;
        }), ["codexDashboard", "openaiApi", "openRouter", "claudeAdmin"]);
        for (var i = 0; i < dashboard.rows.length; i++) {
            compare(dashboard.rows[i].parts[0].value, i);
        }
        compare(LegacyUsageDashboard.normalize({
            zaiUsage: usage.zaiUsage
        }, {}).kpis[0].labelKey, "zai");
    }

    function test_rowLimitPreservesPriorityAndLaterSourceKpis() {
        var dashboard = LegacyUsageDashboard.normalize({
            openAIAPIUsage: {
                creditsRemaining: 20
            },
            openRouterUsage: {
                creditsRemaining: 30
            },
            claudeAdminAPIUsage: {
                creditsRemaining: 40
            }
        }, {
            openaiDashboard: {
                codeReviewRemainingPercent: 1,
                creditsRemaining: 2,
                accountPlan: "Plan",
                signedInEmail: "Name",
                today: {
                    value: 5
                },
                last7Days: {
                    value: 6
                },
                last30Days: {
                    value: 7
                },
                month: {
                    value: 8
                },
                topModels: [
                    {
                        name: "Model"
                    }
                ],
                topUsageTypes: [
                    {
                        name: "Chat"
                    }
                ],
                daily: [
                    {
                        value: 11
                    }
                ],
                modelUsage: {
                    creditsRemaining: 12
                }
            }
        });
        compare(dashboard.rows.length, 10);
        compare(dashboard.rows[9].labelKey, "usageMix");
        compare(dashboard.kpis.length, 4);
        compare(dashboard.kpis[3].parts[0].value, 40);
    }

    function test_modelDepthLimitAndCycleHandling() {
        var source = {
            creditsRemaining: 0
        };
        var nested = source;
        for (var i = 1; i < 8; i++) {
            nested.modelUsage = {
                creditsRemaining: i
            };
            nested = nested.modelUsage;
        }
        var dashboard = normalizeSource(source);
        compare(dashboard.rows.length, 5);
        compare(dashboard.rows[4].parts[0].value, 4);
        source = {
            creditsRemaining: 9
        };
        source.modelUsage = source;
        dashboard = normalizeSource(source);
        compare(dashboard.rows.length, 1);
    }

    function test_boundsDisplayFieldsAndDiscardsUnrelatedData() {
        var longText = "x".repeat(200);
        var source = {
            accountPlan: longText,
            historyWindowLabel: longText,
            last30Days: {
                cost: 1,
                currency: longText,
                extra: "ignored"
            },
            topModels: [
                {
                    name: longText,
                    rawRecord: {
                        value: "ignored"
                    }
                }
            ],
            daily: [
                {
                    label: longText,
                    value: longText
                }
            ],
            rawRecord: {
                value: "ignored"
            }
        };
        var before = JSON.stringify(source);
        var dashboard = normalizeSource(source);
        compare(dashboard.rows[0].parts[0].value.length, 120);
        compare(dashboard.rows[1].label.length, 120);
        compare(dashboard.rows[1].parts[0].currency.length, 12);
        compare(dashboard.rows[2].name.length, 120);
        compare(dashboard.rows[3].label.length, 120);
        compare(dashboard.rows[3].parts[0].value.length, 120);
        verify(JSON.stringify(dashboard).indexOf("ignored") === -1);
        compare(JSON.stringify(source), before);
    }
}
