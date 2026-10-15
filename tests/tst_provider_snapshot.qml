import QtQuick
import QtTest
import "../contents/ui/ProviderSnapshot.js" as ProviderSnapshot
import "../contents/ui/ProviderNormalizer.js" as Normalizer
import "../contents/ui/UsageCache.js" as UsageCache
import "../contents/ui/ResetPresentation.js" as ResetPresentation

TestCase {
    name: "ProviderSnapshot"

    function test_resetCreditInventoryOverridesLegacyAggregate_data() {
        return [
            {tag: "usable", summary: {available: 2, nextExpiresAt: "2026-10-16T00:00:00Z"}, expected: {availableCount: 2}},
            {tag: "empty", summary: {available: 0}, expected: null},
            {tag: "expired", summary: {available: 0}, legacy: 1, expected: null},
            {tag: "null", summary: null, expected: null},
            {tag: "undefined", summary: undefined, expected: null},
            {tag: "missing-count", summary: {}, expected: null},
            {tag: "array", summary: [{available: 2}], expected: null},
            {tag: "string", summary: {available: "2"}, expected: null},
            {tag: "boolean", summary: {available: true}, expected: null},
            {tag: "negative", summary: {available: -1}, expected: null},
            {tag: "fraction", summary: {available: 1.5}, expected: null},
            {tag: "infinite", summary: {available: Infinity}, expected: null},
            {tag: "nan", summary: {available: NaN}, expected: null},
            {tag: "unsafe", summary: {available: Number.MAX_SAFE_INTEGER + 1}, expected: null},
            {tag: "object-count", summary: {available: {toString: null}}, expected: null},
            {tag: "inherited-count", summary: Object.create({available: 2}), expected: null}
        ];
    }
    function test_resetCreditInventoryOverridesLegacyAggregate(data) {
        var item = {provider: "codex", resetCredits: data.summary, usage: {
            primary: {usedPercent: 25},
            codexResetCredits: {availableCount: data.legacy === undefined ? 99 : data.legacy}
        }};
        var before = JSON.stringify(item);
        var snapshot = ProviderSnapshot.normalize(item, 1000);
        compare(snapshot.resetCredits, data.expected);
        compare(snapshot.rows[0].usedPercent, 25);
        compare(JSON.stringify(item), before);
        if (snapshot.resetCredits) {
            verify(JSON.stringify(snapshot.resetCredits).indexOf("nextExpiresAt") < 0);
            snapshot.resetCredits.availableCount = 3;
            compare(item.resetCredits.available, 2);
        }
    }
    function test_resetCreditsKeepAbsentSummaryFallback() {
        var item = {provider: "codex", usage: {primary: {usedPercent: 25},
            codexResetCredits: {availableCount: 2}}};
        compare(ProviderSnapshot.normalize(item, 1000).resetCredits, {availableCount: 2});
        item.usage.codexResetCredits.availableCount = "2";
        compare(ProviderSnapshot.normalize(item, 1000).resetCredits, {availableCount: 2});
        item.usage.codexResetCredits.availableCount = 0;
        compare(ProviderSnapshot.normalize(item, 1000).resetCredits, null);
        delete item.usage.codexResetCredits;
        compare(ProviderSnapshot.normalize(item, 1000).resetCredits, null);
        // An inherited summary is not an emitted CLI field.
        item = Object.create({resetCredits: {available: 99}});
        item.provider = "codex";
        item.usage = {codexResetCredits: {availableCount: 2}};
        compare(ProviderSnapshot.normalize(item, 1000).resetCredits, {availableCount: 2});
    }
    function test_topLevelOnlyResetCreditsPreserveHealthyQuotas() {
        var item = {provider: "codex", resetCredits: {available: 2},
            usage: {primary: {usedPercent: 25}}};
        compare(ProviderSnapshot.normalize(item, 1000).resetCredits, {availableCount: 2});
        delete item.resetCredits;
        var failedEnrichment = ProviderSnapshot.normalize(item, 1000);
        compare(failedEnrichment.resetCredits, null);
        compare(failedEnrichment.rows[0].usedPercent, 25);
        verify(!failedEnrichment.commandFailed);
        item.provider = "claude";
        item.resetCredits = {available: 2};
        compare(ProviderSnapshot.normalize(item, 1000).resetCredits, null);
    }
    function test_confidenceSurvivesWithoutPromotingEstimates_data() {
        return [
            {tag: "estimated", confidence: "estimated", expected: "estimated", authoritative: false},
            {tag: "percent-only", confidence: "percentOnly", expected: "percentOnly", authoritative: false},
            {tag: "exact", confidence: "exact", expected: "exact", authoritative: true},
            {tag: "missing", confidence: undefined, expected: "", authoritative: true},
            {tag: "empty", confidence: "", expected: "unknown", authoritative: false},
            {tag: "explicit-undefined", confidence: undefined, explicit: true, expected: "unknown", authoritative: false},
            {tag: "null", confidence: null, expected: "unknown", authoritative: false},
            {tag: "boolean", confidence: false, expected: "unknown", authoritative: false},
            {tag: "array", confidence: ["exact"], expected: "unknown", authoritative: false},
            {tag: "future", confidence: "futureConfidence", expected: "unknown", authoritative: false},
            {tag: "malformed", confidence: {toString: null}, expected: "unknown", authoritative: false},
            {tag: "oversized", confidence: "x".repeat(10000), expected: "unknown", authoritative: false}
        ];
    }
    function test_confidenceSurvivesWithoutPromotingEstimates(data) {
        var input = {provider: "unknown-provider", usage: {
            dataConfidence: data.confidence,
            primary: {usedPercent: 95, resetsAt: "2026-10-14T14:00:00Z", windowMinutes: 300},
            extraRateWindows: [{id: "extra", window: {usedPercent: 20}}]
        }, pace: {primary: {expectedUsedPercent: 50, willLastToReset: false, etaSeconds: 60}}};
        if (data.confidence === undefined && data.explicit !== true) {
            delete input.usage.dataConfidence;
        }
        var before = JSON.stringify(input);
        var result = ProviderSnapshot.normalize(input, 1000);
        compare(result.dataConfidence, data.expected);
        compare(result.rows[0].dataConfidence, data.expected);
        compare(result.rows[1].dataConfidence, data.expected);
        compare(result.rows[0].usedPercent, 95);
        compare(result.rows[0].leftPercent, 5);
        compare(result.rows[0].paceKnown, data.authoritative || data.confidence === "percentOnly");
        compare(result.rows[0].resetsAt.length > 0, data.authoritative || data.confidence === "percentOnly");
        compare(result.rows[0].paceParts.length > 0, data.authoritative || data.confidence === "percentOnly");
        compare(JSON.stringify(input), before);
    }
    function test_receiptTimeAndForecastAreExplicit() {
        var result = ProviderSnapshot.normalize({
            provider: "codex",
            account: "Work  Team",
            usage: {
                primary: {
                    usedPercent: 0
                }
            },
            pace: {
                primary: {
                    expectedUsedPercent: 30,
                    willLastToReset: false,
                    etaSeconds: 1800
                }
            }
        }, 123456);
        compare(result.usageReceivedAtMs, 123456);
        compare(result.rows[0].paceObservedAtMs, 123456);
        compare(result.accountKey, "Work  Team");
        compare(result.account, "Work Team");
        compare(result.rows[0].usedPercent, 0);
        compare(result.rows[0].paceEtaSeconds, 1800);
        compare(result.rows[0].paceParts[1].kind, "runsOut");
        verify(!result.commandFailed);
    }
    function test_metadataDoesNotExposeUnknownFields() {
        var result = ProviderSnapshot.normalize({
            provider: "codex",
            secret: "private-token",
            account: {
                toString: null
            },
            usage: {
                identity: {
                    accountEmail: "demo@example.com",
                    loginMethod: ["bad"]
                },
                primary: {
                    usedPercent: 120,
                    resetsAt: {
                        toString: null
                    }
                },
                extraRateWindows: Array(1000).fill({
                    title: "x".repeat(500),
                    window: {
                        usedPercent: 5
                    }
                })
            },
            status: {
                indicator: {},
                description: {
                    toString: null
                }
            },
            credits: {
                remaining: false
            }
        }, 1000);
        compare(result.accountKey, "demo@example.com");
        compare(result.loginMethod, "");
        compare(result.secret, undefined);
        compare(result.rows.length, Normalizer.maximumExtraRateWindows + 1);
        compare(result.rows[0].usedPercent, 100);
        compare(result.rows[0].resetValue, "");
        compare(result.rows[1].label.length, 120);
        compare(result.credits, null);
        compare(result.statusRecord.indicator, "");
        verify(JSON.stringify(result).indexOf("private-token") < 0);
    }
    function test_confidenceMustBeAnOwnContractField() {
        function InheritedUsage() {}
        InheritedUsage.prototype.dataConfidence = "estimated";
        var usage = new InheritedUsage();
        usage.primary = {usedPercent: 50};
        var result = ProviderSnapshot.normalize({provider: "unknown-provider", usage: usage}, 1000);
        compare(result.dataConfidence, "");
        compare(result.rows[0].dataConfidence, "");
        compare(result.rows[0].usedPercent, 50);
    }
    // A numeric CLI reset date has to survive as a parsable date: the live
    // countdown, the panel "resets within" rule and absolute formatting all
    // read the stored string, and epoch digits are not a date Date.parse knows.
    function test_numericResetDateStaysParsable() {
        var epochMs = Date.UTC(2026, 8, 13, 13);
        var result = ProviderSnapshot.normalize({
            provider: "codex",
            usage: {
                primary: {
                    usedPercent: 50,
                    resetsAt: epochMs
                }
            }
        }, 1000);
        compare(result.rows[0].resetValue, epochMs);
        compare(Date.parse(result.rows[0].resetsAt), epochMs);
        compare(ResetPresentation.parts({resetsAt: result.rows[0].resetsAt},
            epochMs - 3600000, false), {kind: "hours", hours: 1, minutes: 0});
        // Unusable numbers keep the empty reset instead of throwing or
        // printing raw digits in the quota row.
        for (var value of [NaN, Infinity, 8640000000000001]) {
            var broken = ProviderSnapshot.normalize({
                provider: "codex",
                usage: {primary: {usedPercent: 50, resetsAt: value}}
            }, 1000).rows[0];
            compare(broken.resetsAt, "");
            compare(broken.resetValue, "");
            compare(ResetPresentation.parts({resetsAt: broken.resetValue,
                resetDescription: broken.resetDescription}, 1000, false).text, "");
        }
    }
    function test_errorsAndEmptyPlaceholdersRemainDistinct() {
        compare(ProviderSnapshot.normalize({
            provider: "codex"
        }, 1000).placeholder, "noUsage");
        compare(ProviderSnapshot.normalize({
            provider: "codex",
            account: "named"
        }, 1000).placeholder, "limitsUnavailable");
        var failed = ProviderSnapshot.normalize({
            provider: "codex",
            error: {
                message: {
                    toString: null
                }
            }
        }, 1000);
        verify(failed.commandFailed);
        compare(failed.error, "");
        compare(failed.placeholder, "");
        compare(ProviderSnapshot.normalize({
            provider: "codex"
        }, 1000).statusRecord, null);
        compare(ProviderSnapshot.normalize({
            provider: "codex",
            status: {
                indicator: "major",
                incidentId: "outage"
            }
        }, 1000).statusIncidentKey, "outage");
    }
    function test_placeholderUsesValidatedIdentity() {
        var malformed = ProviderSnapshot.normalize({
            provider: "codex",
            account: ["invalid"],
            usage: {identity: {accountOrganization: ["invalid"], loginMethod: ["invalid"]}}
        }, 1000);
        compare(malformed.account, "");
        compare(malformed.organization, "");
        compare(malformed.loginMethod, "");
        compare(malformed.placeholder, "noUsage");

        var legacy = ProviderSnapshot.normalize({
            provider: "codex",
            usage: {accountEmail: "demo@example.com"}
        }, 1000);
        compare(legacy.account, "demo@example.com");
        compare(legacy.placeholder, "limitsUnavailable");
    }
    // New-style detail sections flow through to the popup and suppress the
    // legacy dashboard: both must never render at once.
    function test_detailsSectionsSuppressTheLegacyDashboard() {
        var detailed = ProviderSnapshot.normalize({
            provider: "codex",
            usage: {
                details: [{title: "API usage", rows: [{label: "Requests", value: "1,240"}]}]
            },
            openaiDashboard: {creditsRemaining: 8}
        }, 1000);
        compare(detailed.providerDetails.length, 1);
        compare(detailed.providerDetails[0].rows[0].value, "1,240");
        compare(detailed.usageDashboard, null);
    }
    // Without detail sections the legacy dashboard still feeds the popup, and
    // either supplemental source suppresses the empty placeholder.
    function test_legacyDashboardFeedsThePopupWithoutDetails() {
        var legacy = ProviderSnapshot.normalize({
            provider: "codex",
            usage: {},
            openaiDashboard: {creditsRemaining: 8}
        }, 1000);
        compare(legacy.providerDetails.length, 0);
        verify(legacy.usageDashboard !== null);
        compare(legacy.placeholder, "");
    }
    // Official Linux output carries lane titles beside `usage` on the provider
    // record (`{"primary": "Memory"}` for llmman at 0.67.0). Only a bounded,
    // non-empty string for a lane that produced a row survives.
    function test_cliLaneLabelsAreBoundedPerLane() {
        var labels = Object.create({secondary: "Inherited"});
        labels.primary = "  Memory  ";
        labels.tertiary = 42;
        labels.extra = "Ignored";
        var result = ProviderSnapshot.normalize({
            provider: "llmman",
            rateWindowLabels: labels,
            usage: {
                primary: {usedPercent: 40},
                secondary: {usedPercent: 10},
                tertiary: {usedPercent: 5},
                extraRateWindows: [{title: "Pool", window: {usedPercent: 1}}]
            }
        }, 1000);
        compare(result.rows.length, 4);
        compare(result.rows[0].cliLabel, "Memory");
        compare(result.rows[1].cliLabel, null);
        compare(result.rows[2].cliLabel, null);
        compare(result.rows[3].cliLabel, undefined);
        compare(result.rows[3].label, "Pool");

        var bounded = ProviderSnapshot.normalize({
            provider: "future",
            rateWindowLabels: {primary: "x".repeat(500), secondary: "   "},
            usage: {primary: {usedPercent: 1}, secondary: {usedPercent: 2}}
        }, 1000);
        compare(bounded.rows[0].cliLabel.length, 60);
        compare(bounded.rows[1].cliLabel, null);

        for (var malformed of [null, "Memory", ["Memory"], 7]) {
            var plain = ProviderSnapshot.normalize({
                provider: "future", rateWindowLabels: malformed,
                usage: {primary: {usedPercent: 1}}
            }, 1000);
            compare(plain.rows[0].cliLabel, null);
        }
    }

    // The official extra-window ID survives only in identifier shape; it lets
    // the popup hide that window, and it is never rendered.
    function test_extraWindowIDsAreIdentifierShaped() {
        var result = ProviderSnapshot.normalize({
            provider: "claude",
            usage: {
                primary: {usedPercent: 1},
                extraRateWindows: [
                    {id: "opus-weekly", title: "Opus", window: {usedPercent: 2}},
                    {id: "has space", title: "Spaced", window: {usedPercent: 3}},
                    {id: 7, title: "Numeric", window: {usedPercent: 4}},
                    {title: "Missing", window: {usedPercent: 5}}
                ]
            }
        }, 1000);
        compare(result.rows.map(function(row) { return row.windowId; }),
            [undefined, "opus-weekly", "", "", ""]);
    }

    function test_blankDisplayNameFallsBackToTitleOrNull() {
        var withTitle = ProviderSnapshot.normalize({
            provider: "codex",
            displayName: "   \t  \n ",
            title: "Custom Title"
        }, 1000);
        compare(withTitle.displayName, "Custom Title");

        var withoutTitle = ProviderSnapshot.normalize({
            provider: "codex",
            displayName: "   "
        }, 1000);
        compare(withoutTitle.displayName, null);
    }
    function test_invalidRecords_data() {
        return [
            {
                tag: "null",
                value: null
            },
            {
                tag: "array",
                value: []
            },
            {
                tag: "string",
                value: "bad"
            }
        ];
    }
    function test_invalidRecords(data) {
        compare(ProviderSnapshot.normalize(data.value, 1000), null);
    }
}
