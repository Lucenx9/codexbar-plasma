import QtQuick
import QtTest
import "../contents/ui/ProviderSnapshot.js" as ProviderSnapshot
import "../contents/ui/ProviderNormalizer.js" as Normalizer
import "../contents/ui/UsageCache.js" as UsageCache
import "../contents/ui/ResetPresentation.js" as ResetPresentation

TestCase {
    name: "ProviderSnapshot"
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
