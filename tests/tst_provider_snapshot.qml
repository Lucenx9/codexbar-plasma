import QtQuick
import QtTest
import "../contents/ui/ProviderSnapshot.js" as ProviderSnapshot
import "../contents/ui/ProviderNormalizer.js" as Normalizer
import "../contents/ui/UsageCache.js" as UsageCache

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
