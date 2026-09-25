import QtQuick
import QtTest
import "../contents/ui/ProviderCostPresentation.js" as Presentation
import "../contents/ui/ProviderSnapshot.js" as ProviderSnapshot

TestCase {
    name: "ProviderCostPresentation"

    function test_invalidRecords() {
        for (var value of [null, undefined, [], "cost", 42, true]) {
            compare(Presentation.section("codex", value), null);
            compare(Presentation.resetCount("codex", value), null);
        }
        for (var provider of [null, undefined,
            {},
            {
                toString: null
            },
            [], "", "x".repeat(129), "__proto__"]) {
            compare(Presentation.section(provider, {
                used: 12
            }), null);
            compare(Presentation.resetCount(provider, {
                availableCount: 2
            }), null);
        }
    }

    function test_invalidAmounts_data() {
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
                tag: "false",
                value: false
            },
            {
                tag: "true",
                value: true
            },
            {
                tag: "empty",
                value: ""
            },
            {
                tag: "whitespace",
                value: " \t"
            },
            {
                tag: "text",
                value: "unknown"
            },
            {
                tag: "array",
                value: [2]
            },
            {
                tag: "object",
                value: {
                    toString: null
                }
            },
            {
                tag: "nan",
                value: NaN
            },
            {
                tag: "infinity",
                value: Infinity
            }
        ];
    }

    function test_invalidAmounts(data) {
        compare(Presentation.section("claude", {
            used: data.value,
            limit: 100
        }), null);
        var cost = Presentation.section("claude", {
            used: 0,
            limit: data.value,
            personalUsed: data.value
        });
        compare(cost.kind, "spend");
        compare(cost.used, 0);
        compare(cost.limit, null);
        compare(cost.percentUsed, -1);
        compare(cost.personalUsed, null);
        compare(Presentation.resetCount("codex", {
            availableCount: data.value
        }), null);
    }

    function test_allowance_data() {
        return [
            {
                tag: "zero",
                used: 0,
                limit: 100,
                percent: 0
            },
            {
                tag: "numeric-string",
                used: "25",
                limit: "100",
                percent: 25
            },
            {
                tag: "negative",
                used: -1,
                limit: 100,
                percent: 0
            },
            {
                tag: "exhausted",
                used: 100,
                limit: 100,
                percent: 100
            },
            {
                tag: "over-limit",
                used: 150,
                limit: 100,
                percent: 100
            },
            {
                tag: "overflow",
                used: Number.MAX_VALUE,
                limit: Number.MIN_VALUE,
                percent: 100
            }
        ];
    }

    function test_allowance(data) {
        var result = Presentation.section("future-provider", {
            used: data.used,
            limit: data.limit,
            personalUsed: "3"
        });
        compare(result.kind, "allowance");
        compare(result.titleKey, "extraUsage");
        compare(result.percentUsed, data.percent);
        compare(result.limit, Number(data.limit));
        compare(result.personalUsed, 3);
        compare(result.currency, "USD");
        compare(result.period, null);
    }

    function test_balancePrecedesLimit_data() {
        return [
            {
                tag: "factory",
                provider: "factory",
                period: "Extra usage balance",
                kind: "balance",
                title: "extraUsage"
            },
            {
                tag: "factory-case",
                provider: "FACTORY",
                period: "Extra usage balance",
                kind: "balance",
                title: "extraUsage"
            },
            {
                tag: "opencodego",
                provider: "opencodego",
                period: "Zen balance",
                kind: "balance",
                title: "zenBalance"
            },
            {
                tag: "minimax",
                provider: "minimax",
                period: "MiniMax points balance",
                kind: "pointsBalance",
                title: "credits"
            }
        ];
    }

    function test_balancePrecedesLimit(data) {
        var result = Presentation.section(data.provider, {
            used: 12.5,
            limit: 100,
            personalUsed: 5,
            period: data.period
        });
        compare(result.kind, data.kind);
        compare(result.titleKey, data.title);
        compare(result.used, 12.5);
        compare(result.limit, null);
        compare(result.percentUsed, -1);
        compare(result.personalUsed, null);
        compare(Presentation.section("future-provider", {
            used: 12.5,
            limit: 100,
            period: data.period
        }).kind, "allowance");
    }

    function test_providerFallbacksAndMissingLimits() {
        for (var provider of ["manus", "synthetic"])
            compare(Presentation.section(provider, {
                used: 10,
                limit: 100
            }), null);
        for (var limit of [0, -1, null, undefined, false, ""])
            compare(Presentation.section("litellm", {
                used: 10,
                limit: limit
            }), null);
        compare(Presentation.section("litellm", {
            used: 10,
            limit: 100
        }).kind, "allowance");
        for (var provider of ["openai", "claude"])
            compare(Presentation.section(provider, {
                used: 10
            }).titleKey, "apiSpend");
        compare(Presentation.section("future-provider", {
            used: 10
        }).titleKey, "extraUsage");
        compare(Presentation.section("future-provider", {
            used: 10,
            limit: 100,
            currencyCode: "Quota"
        }).titleKey, "quotaUsage");
        compare(Presentation.section("future-provider", {
            used: 10,
            currencyCode: "Quota"
        }).percentUsed, -1);
        for (var personal of [0, -1, null, false])
            compare(Presentation.section("claude", {
                used: 10,
                limit: 100,
                personalUsed: personal
            }).personalUsed, null);
    }

    function test_textBoundsAndInputOwnership() {
        var cost = Object.freeze({
            used: 12,
            currencyCode: "EUR".repeat(100),
            period: "x".repeat(500),
            extra: "private"
        });
        var result = Presentation.section("claude", cost);
        compare(result.currency.length, 12);
        compare(result.period.length, 120);
        compare(result.extra, undefined);
        compare(cost.currencyCode.length, 300);
        compare(Presentation.section("claude", {
            used: 12,
            period: ""
        }).period, "");
        var redacted = Presentation.section("claude", {
            used: 12,
            period: "Authorization: Bearer synthetic-test-token"
        });
        verify(redacted.period.indexOf("synthetic-test-token") < 0);
        var malformed = Presentation.section("claude", {
            used: 12,
            period: {
                toString: null
            },
            currencyCode: {
                toString: null
            }
        });
        verify(malformed !== null);
        verify(malformed.period.length <= 120);
        verify(malformed.currency.length <= 12);
    }

    function test_resetCounts() {
        compare(Presentation.resetCount("claude", {
            availableCount: 2
        }), null);
        compare(Presentation.resetCount("future-provider", {
            availableCount: 2
        }), null);
        compare(Presentation.resetCount("codex", {
            availableCount: 0
        }), null);
        compare(Presentation.resetCount("codex", {
            availableCount: -1
        }), null);
        compare(Presentation.resetCount("codex", {
            availableCount: "2"
        }), 2);
        compare(Presentation.resetCount("codex", {
            availableCount: 1.6
        }), 2);
        // Preserve the existing positive-count gate before display rounding.
        compare(Presentation.resetCount("codex", {
            availableCount: 0.2
        }), 0);
    }

    function test_snapshotKeepsHealthyQuotasWhenCostIsInvalid() {
        var snapshot = ProviderSnapshot.normalize({
            provider: "codex",
            usage: {
                primary: {
                    usedPercent: 25
                },
                providerCost: {
                    used: false,
                    limit: 100
                },
                codexResetCredits: {
                    availableCount: "2"
                }
            },
            credits: {
                remaining: 30
            }
        }, 1234);
        compare(Presentation.section(snapshot.provider, snapshot.providerCost), null);
        compare(Presentation.resetCount(snapshot.provider, snapshot.resetCredits), 2);
        compare(snapshot.rows[0].usedPercent, 25);
        compare(snapshot.credits, 30);
        compare(snapshot.codexCreditLimit, null);
    }

    function test_snapshotDropsUnusableResetCredits() {
        for (var value of [{}, { availableCount: "many" }, { availableCount: 0 },
                { availableCount: -1 }, { availableCount: Infinity }]) {
            var snapshot = ProviderSnapshot.normalize({
                provider: "codex",
                error: { message: "Codex login required" },
                usage: { codexResetCredits: value }
            }, 1234);
            compare(snapshot.resetCredits, null, JSON.stringify(value));
        }
    }
}
