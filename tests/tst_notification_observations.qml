import QtQuick
import QtTest
import "../contents/ui/NotificationObservations.js" as NotificationObservations
import "../contents/ui/NotificationPlanner.js" as NotificationPlanner
import "../contents/ui/UsageCache.js" as UsageCache
import "../contents/ui/ProviderSnapshot.js" as ProviderSnapshot

TestCase {
    name: "NotificationObservations"
    property bool includeStatus: true
    property bool notifyStatusIncidents: true
    property bool notifyQuotaWarnings: true
    property bool notifyPredictivePaceWarnings: false
    property bool notifyLimitResets: true
    property int quotaWarningPercent: 80
    property int quotaCriticalPercent: 95
    property int limitResetArmThreshold: 80
    property int limitResetFloor: 5
    property var selectedAccounts: ({})
    property var notificationRefreshPending: ({})
    property var providers: []

    function observations() {
        return NotificationObservations.build(providers, selectedAccounts, notificationRefreshPending, {
            warningPercent: quotaWarningPercent,
            criticalPercent: quotaCriticalPercent
        });
    }

    function init() {
        includeStatus = true;
        quotaWarningPercent = 80;
        quotaCriticalPercent = 95;
        selectedAccounts = ({});
        notificationRefreshPending = ({});
        providers = [];
    }
    function item(account, severity, error, used, statusEnvelope) {
        var status = statusEnvelope === undefined ? {
            indicator: severity || "none"
        } : statusEnvelope;
        return {
            provider: "codex",
            account: account,
            error: error,
            hasIncident: severity.length > 0,
            statusSeverity: severity,
            statusIncidentKey: severity.length > 0 ? "incident-1" : "",
            status: severity.length > 0 ? "Service degraded" : "",
            statusKnown: status !== null,
            rows: used === undefined ? [] : [
                {
                    lane: "primary",
                    label: "Session",
                    hasPercent: true,
                    usedPercent: used,
                    paceKnown: false
                }
            ]
        };
    }
    function observe(mode, previousMemo) {
        return NotificationPlanner.transition(observations(), previousMemo || ({}), {
            mode: mode,
            statusEnabled: includeStatus && notifyStatusIncidents,
            quotaEnabled: notifyQuotaWarnings,
            paceEnabled: notifyPredictivePaceWarnings,
            resetEnabled: notifyLimitResets,
            resetArmThreshold: limitResetArmThreshold,
            resetFloor: limitResetFloor
        });
    }
    function beginAccountChange() {
        providers = [item("account-a", "", "", 85)];
        var initial = observe("prime");
        selectedAccounts = ({
                codex: "account-b"
            });
        notificationRefreshPending = ({
                codex: true
            });
        return initial.nextMemo;
    }
    function receive(items) {
        notificationRefreshPending = NotificationObservations.freshPending(items, selectedAccounts, notificationRefreshPending);
        providers = items;
    }
    function test_namedWindowReorderDoesNotInventQuotaCrossingsOrResets() {
        var nearLimit = {
            id: "requests",
            title: "Daily",
            window: {
                usedPercent: 85
            }
        };
        var empty = {
            id: "tokens",
            title: "Daily",
            window: {
                usedPercent: 0
            }
        };
        var payload = {
            provider: "codex",
            usage: {
                extraRateWindows: [nearLimit, empty]
            }
        };
        providers = [ProviderSnapshot.normalize(payload, 1000)];
        compare(providers[0].rows[0].windowId, "requests");
        compare(providers[0].rows[0].usedPercent, 85);
        compare(providers[0].rows[1].windowId, "tokens");
        compare(providers[0].rows[1].usedPercent, 0);
        var initial = observe("prime");

        payload.usage.extraRateWindows = [empty, nearLimit];
        providers = [ProviderSnapshot.normalize(payload, 2000)];
        var reordered = observe("observe", initial.nextMemo);
        compare(reordered.intents.map(function (intent) {
            return intent.kind;
        }).join(","), "");

        nearLimit.window.usedPercent = 0;
        providers = [ProviderSnapshot.normalize(payload, 3000)];
        var reset = observe("observe", reordered.nextMemo);
        compare(reset.intents.length, 1);
        compare(reset.intents[0].kind, "reset");
        compare(reset.intents[0].rowIndex, 1);
        compare(observe("observe", reset.nextMemo).intents.length, 0);
    }
    function test_oldSuccessfulQuotaPreservesNotificationBaseline_data() {
        return [
            {
                tag: "unchanged-quota",
                used: 85,
                expectedKinds: []
            },
            {
                tag: "limit-reset",
                used: 2,
                expectedKinds: ["reset"]
            },
            {
                tag: "quota-escalation",
                used: 96,
                expectedKinds: ["quota"]
            }
        ];
    }
    function test_oldSuccessfulQuotaPreservesNotificationBaseline(data) {
        var nowMs = Date.parse("2026-09-12T12:00:00Z");
        var fresh = item("account-a", "", "", 85);
        fresh.updatedAt = new Date(nowMs).toISOString();
        receive(UsageCache.reconcile([], [fresh], nowMs));
        var initial = observe("prime");

        // A successful CLI reply can still carry an expired quota alongside
        // newly fetched status. Exercise the cache's real classification.
        var old = item("account-a", "major", "", 85);
        old.updatedAt = new Date(nowMs - 2 * UsageCache.maximumAgeMs).toISOString();
        receive(UsageCache.reconcile(providers, [old], nowMs + 1000));
        verify(providers[0].usageStale);
        compare(providers[0].error, "");
        compare(observations()[0].rows.length, 0);
        var stale = observe("observe", initial.nextMemo);
        compare(stale.intents.length, 1);
        compare(stale.intents[0].kind, "status");

        var current = item("account-a", "major", "", data.used);
        current.updatedAt = new Date(nowMs + 2000).toISOString();
        receive(UsageCache.reconcile(providers, [current], nowMs + 2000));
        var recovered = observe("observe", stale.nextMemo);
        compare(recovered.intents.map(function (intent) {
            return intent.kind;
        }), data.expectedKinds);
        compare(observe("observe", recovered.nextMemo).intents.length, 0);
    }
    function test_statusFetchingToggleDoesNotInventAnIncidentTransition() {
        providers = [item("account-a", "major", "", 85)];
        var initial = observe("prime");
        includeStatus = false;
        receive([item("account-a", "", "", 96, null)]);
        var withoutStatus = observe("observe", initial.nextMemo);
        compare(withoutStatus.intents.length, 1);
        compare(withoutStatus.intents[0].kind, "quota");
        includeStatus = true;
        quotaWarningPercent = 80;
        quotaCriticalPercent = 95;
        receive([item("account-a", "major", "", 96)]);
        compare(observe("observe", withoutStatus.nextMemo).intents.length, 0);
    }
    function test_matchingAccountErrorStillReportsAFreshProviderIncident() {
        var memo = beginAccountChange();
        receive([item("account-b", "major", "Expired credentials")]);
        var result = observe("observe", memo);
        compare(result.intents.length, 1);
        compare(result.intents[0].kind, "status");
        compare((notificationRefreshPending.codex === true), false);
    }
    function test_knownRecoveryWithoutUsageClearsOnlyTheMatchedAccountStatus_data() {
        return [
            {
                tag: "matched-observe",
                account: "account-b",
                mode: "observe",
                accepted: true
            },
            {
                tag: "matched-prime",
                account: "account-b",
                mode: "prime",
                accepted: true
            },
            {
                tag: "foreign-observe",
                account: "account-a",
                mode: "observe",
                accepted: false
            },
            {
                tag: "foreign-prime",
                account: "account-a",
                mode: "prime",
                accepted: false
            },
            {
                tag: "unidentified-observe",
                account: "",
                mode: "observe",
                accepted: false
            },
            {
                tag: "unidentified-prime",
                account: "",
                mode: "prime",
                accepted: false
            }
        ];
    }
    function test_knownRecoveryWithoutUsageClearsOnlyTheMatchedAccountStatus(data) {
        providers = [item("account-a", "major", "", 85)];
        var initial = observe("prime");
        selectedAccounts = ({
                codex: "account-b"
            });
        notificationRefreshPending = ({
                codex: true
            });
        receive([item(data.account, "", "Expired credentials", undefined, {
                indicator: "none"
            })]);
        var recovered = observe(data.mode, initial.nextMemo);
        compare(recovered.intents.length, 0);
        compare((notificationRefreshPending.codex === true), !data.accepted);
        receive([item("account-b", "major", "", 85)]);
        var recurring = observe("observe", recovered.nextMemo);
        compare(recurring.intents.length, data.accepted ? 1 : 0);
        if (data.accepted)
            compare(recurring.intents[0].kind, "status");
        receive([item("account-b", "major", "", 96)]);
        var escalated = observe("observe", recurring.nextMemo);
        compare(escalated.intents.length, 1);
        compare(escalated.intents[0].kind, "quota");
    }
    function test_foreignAccountErrorKeepsTheSelectionPending_data() {
        return [
            {
                tag: "previous-account",
                account: "account-a"
            },
            {
                tag: "unidentified",
                account: ""
            }
        ];
    }
    function test_foreignAccountErrorKeepsTheSelectionPending(data) {
        var memo = beginAccountChange();
        receive([item(data.account, "major", "Expired credentials")]);
        compare((notificationRefreshPending.codex === true), true);
        compare(observe("observe", memo).intents.length, 0);
    }
    function test_errorOnlyReplyDoesNotPrimeTheSelectedAccountQuota() {
        var memo = beginAccountChange();
        receive([item("account-b", "", "Expired credentials")]);
        var errored = observe("observe", memo);
        compare(errored.intents.length, 0);
        receive([item("account-b", "", "", 85)]);
        var healthy = observe("observe", errored.nextMemo);
        compare(healthy.intents.length, 0);
        receive([item("account-b", "", "", 96)]);
        var escalated = observe("observe", healthy.nextMemo);
        compare(escalated.intents.length, 1);
        compare(escalated.intents[0].kind, "quota");
    }
    // Pending slots and account lookups resolve CLI aliases before mapping,
    // so an alias and its canonical id share one slot instead of leaking a
    // parallel key an allowlist would not recognize.
    function test_providerAliasesShareAccountAndPendingIdentity() {
        selectedAccounts = ({
                elevenlabs: "account-a"
            });
        notificationRefreshPending = ({
                elevenlabs: true
            });
        providers = [
            {
                provider: "11labs",
                account: "account-b"
            }
        ];
        var alias = observations()[0];
        compare(alias.providerID, "elevenlabs");
        compare(alias.scopeID, JSON.stringify(["elevenlabs", "account-a"]));
        verify(alias.pending);
        receive([
            {
                provider: "elevenlabs",
                account: "account-a",
                statusKnown: true
            }
        ]);
        compare(notificationRefreshPending, ({}));
        compare(observations()[0].scopeID, alias.scopeID);
        verify(!observations()[0].pending);
    }
    function test_projectionPreservesDispatchIndexesAndDoesNotMutateInputs() {
        var first = item("account-a", "", "", 85);
        first.rows = [null, first.rows[0]];
        providers = [null, first, item("account-b", "major", "", 96)];
        selectedAccounts = ({
                codex: "selected-account"
            });
        notificationRefreshPending = ({
                codex: true,
                claude: true
            });
        var before = JSON.stringify([providers, selectedAccounts, notificationRefreshPending]);
        var result = observations();
        compare(result.map(function (value) {
            return value.providerIndex;
        }), [1, 2]);
        compare(result[0].rows.length, 2);
        verify(!result[0].rows[0].hasPercent);
        verify(isNaN(result[0].rows[0].usedPercent));
        compare(result[0].rows[1].usedPercent, 85);
        compare(result[1].rows[0].usedPercent, 96);
        result[0].rows[1].usedPercent = 0;
        compare(JSON.stringify([providers, selectedAccounts, notificationRefreshPending]), before);
        var nextPending = NotificationObservations.freshPending([item("selected-account", "", "", 20)], selectedAccounts, notificationRefreshPending);
        compare(nextPending, ({
                claude: true
            }));
        compare(JSON.stringify([providers, selectedAccounts, notificationRefreshPending]), before);
    }

    function test_quotaAndPaceRequireAuthoritativeEvidence_data() {
        return [
            {
                tag: "measured",
                confidence: "",
                level: "major",
                pace: true
            },
            {
                tag: "estimated",
                confidence: "estimated",
                level: "",
                pace: false
            },
            {
                tag: "percent-only",
                confidence: "percentOnly",
                level: "",
                pace: false
            }
        ];
    }
    function test_quotaAndPaceRequireAuthoritativeEvidence(data) {
        var provider = item("account-a", "", "", 75);
        provider.rows[0].dataConfidence = data.confidence;
        provider.rows[0].paceKnown = true;
        provider.rows[0].paceOnTop = false;
        provider.rows[0].paceEtaSeconds = 3600;
        providers = [provider];
        quotaWarningPercent = 50;
        quotaCriticalPercent = 70;
        var row = observations()[0].rows[0];
        compare(row.quotaLevel, data.level);
        compare(row.paceActive, data.pace);
        compare(row.dataConfidence, data.confidence);
        verify(row.paceKnown);
        quotaCriticalPercent = 90;
        compare(observations()[0].rows[0].quotaLevel, data.level ? "minor" : "");
        quotaWarningPercent = 80;
        compare(observations()[0].rows[0].quotaLevel, "");
    }

    function test_stableAccountKeyDoesNotCollapseDisplaySpacing() {
        selectedAccounts = ({
                codex: "team  one"
            });
        notificationRefreshPending = ({
                codex: true
            });
        var provider = item("team one", "", "", 40);
        receive([provider]);
        verify(notificationRefreshPending.codex);
        compare(observations()[0].scopeID, JSON.stringify(["codex", "team  one"]));
        provider.accountKey = "team  one";
        receive([provider]);
        compare(notificationRefreshPending, ({}));
        selectedAccounts = ({});
        compare(observations()[0].scopeID, JSON.stringify(["codex", "team  one"]));
    }

    function test_invalidProviderCannotClearPendingOrNameAProvider_data() {
        return [
            {
                tag: "prototype",
                provider: "__proto__"
            },
            {
                tag: "constructor",
                provider: "constructor"
            },
            {
                tag: "control",
                provider: "bad\nprovider"
            }
        ];
    }
    function test_invalidProviderCannotClearPendingOrNameAProvider(data) {
        notificationRefreshPending = ({
                codex: true
            });
        var provider = item("account-a", "", "", 20);
        provider.provider = data.provider;
        receive([provider]);
        compare(notificationRefreshPending, ({
                codex: true
            }));
        compare(observations()[0].providerID, "");
        compare(observations()[0].scopeID, JSON.stringify(["", "account-a"]));
    }

    function test_staleUsageWithoutStatusDoesNotClearPending() {
        notificationRefreshPending = ({
                codex: true
            });
        var provider = item("account-a", "", "", 85, null);
        provider.usageStale = true;
        receive([null, provider]);
        compare(notificationRefreshPending, ({
                codex: true
            }));
        verify(observations()[0].pending);
        compare(observations()[0].rows, []);
        provider.statusKnown = true;
        receive([provider]);
        compare(notificationRefreshPending, ({}));
        verify(!observations()[0].pending);
        compare(observations()[0].rows, []);
    }
}
