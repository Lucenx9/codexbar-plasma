"""Exercise the applet's notification adapters with the production planner."""

import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/lib"))
from qml_surfaces import Surface

FUNCTIONS = (
    "copyObject", "providerMapKey", "accountLabel", "accountKey",
    "selectedAccountForProvider",
    "markNotificationProvidersFresh", "notificationProviderRefreshPending",
    "notificationScopeKey", "notificationObservationRows", "notificationObservations",
    "quotaNotificationLevel", "paceWarningActive", "notificationPlannerOptions",
    "applyTokenCosts", "providerTokenCost", "primaryIncidentProvider",
)

QML = '''import QtQuick
import QtTest
import "SOURCE_URL/NotificationPlanner.js" as NotificationPlanner
import "SOURCE_URL/ProviderNormalizer.js" as Normalizer
import "SOURCE_URL/Guards.js" as Guards
import "SOURCE_URL/QuotaThresholds.js" as QuotaThresholds
import "SOURCE_URL/CostPresentation.js" as CostPresentation
import "SOURCE_URL/UsageCache.js" as UsageCache
TestCase {
    name: "NotificationWiring"
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
    property var tokenCosts: ({})
    property int costHistoryDays: 30

    SOURCE_FUNCTIONS

    function init() {
        includeStatus = true;
        selectedAccounts = ({});
        notificationRefreshPending = ({});
        providers = [];
    }
    function item(account, severity, error, used, statusEnvelope) {
        var status = statusEnvelope === undefined ? {indicator: severity || "none"} : statusEnvelope;
        return {
            provider: "codex", account: account, error: error,
            hasIncident: severity.length > 0, statusSeverity: severity,
            statusIncidentKey: severity.length > 0 ? "incident-1" : "",
            status: severity.length > 0 ? "Service degraded" : "",
            statusKnown: status !== null,
            rows: used === undefined ? [] : [{
                lane: "primary", label: "Session", hasPercent: true,
                usedPercent: used, paceKnown: false
            }]
        };
    }
    function observe(mode, previousMemo) {
        return NotificationPlanner.transition(notificationObservations(), previousMemo || ({}),
            notificationPlannerOptions(mode));
    }
    function beginAccountChange() {
        providers = [item("account-a", "", "", 85)];
        var initial = observe("prime");
        selectedAccounts = ({codex: "account-b"});
        notificationRefreshPending = ({codex: true});
        return initial.nextMemo;
    }
    function receive(items) {
        markNotificationProvidersFresh(items);
        providers = items;
    }
    function test_oldSuccessfulQuotaPreservesNotificationBaseline_data() {
        return [
            {tag: "unchanged-quota", used: 85, expectedKinds: []},
            {tag: "limit-reset", used: 2, expectedKinds: ["reset"]},
            {tag: "quota-escalation", used: 96, expectedKinds: ["quota"]}
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
        compare(notificationObservationRows(providers[0]).length, 0);
        var stale = observe("observe", initial.nextMemo);
        compare(stale.intents.length, 1);
        compare(stale.intents[0].kind, "status");

        var current = item("account-a", "major", "", data.used);
        current.updatedAt = new Date(nowMs + 2000).toISOString();
        receive(UsageCache.reconcile(providers, [current], nowMs + 2000));
        var recovered = observe("observe", stale.nextMemo);
        compare(recovered.intents.map(function(intent) { return intent.kind; }), data.expectedKinds);
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
        receive([item("account-a", "major", "", 96)]);
        compare(observe("observe", withoutStatus.nextMemo).intents.length, 0);
    }
    function test_costRepublishBeforeFreshStatusDoesNotClearTheIncident() {
        providers = [item("account-a", "major", "", 85)];
        var initial = observe("prime");
        includeStatus = false;
        receive([item("account-a", "", "", 85, null)]);
        var withoutStatus = observe("observe", initial.nextMemo);
        includeStatus = true;
        applyTokenCosts();
        var republished = observe("observe", withoutStatus.nextMemo);
        compare(republished.intents.length, 0);
        receive([item("account-a", "major", "", 85)]);
        compare(observe("observe", republished.nextMemo).intents.length, 0);
    }
    function test_matchingAccountErrorStillReportsAFreshProviderIncident() {
        var memo = beginAccountChange();
        receive([item("account-b", "major", "Expired credentials")]);
        var result = observe("observe", memo);
        compare(result.intents.length, 1);
        compare(result.intents[0].kind, "status");
        compare(notificationProviderRefreshPending("codex"), false);
    }
    function test_knownRecoveryWithoutUsageClearsOnlyTheMatchedAccountStatus_data() {
        return [
            {tag: "matched-observe", account: "account-b", mode: "observe", accepted: true},
            {tag: "matched-prime", account: "account-b", mode: "prime", accepted: true},
            {tag: "foreign-observe", account: "account-a", mode: "observe", accepted: false},
            {tag: "foreign-prime", account: "account-a", mode: "prime", accepted: false},
            {tag: "unidentified-observe", account: "", mode: "observe", accepted: false},
            {tag: "unidentified-prime", account: "", mode: "prime", accepted: false}
        ];
    }
    function test_knownRecoveryWithoutUsageClearsOnlyTheMatchedAccountStatus(data) {
        providers = [item("account-a", "major", "", 85)];
        var initial = observe("prime");
        selectedAccounts = ({codex: "account-b"});
        notificationRefreshPending = ({codex: true});
        receive([item(data.account, "", "Expired credentials", undefined, {indicator: "none"})]);
        var recovered = observe(data.mode, initial.nextMemo);
        compare(recovered.intents.length, 0);
        compare(notificationProviderRefreshPending("codex"), !data.accepted);
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
        return [{tag: "previous-account", account: "account-a"}, {tag: "unidentified", account: ""}];
    }
    function test_foreignAccountErrorKeepsTheSelectionPending(data) {
        var memo = beginAccountChange();
        receive([item(data.account, "major", "Expired credentials")]);
        compare(notificationProviderRefreshPending("codex"), true);
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
    function test_primaryIncidentProviderIgnoresUnknownOrInactiveStatus() {
        providers = [
            {
                provider: "codex",
                statusKnown: false,
                hasIncident: true,
                statusSeverity: "critical"
            },
            {
                provider: "claude",
                statusKnown: true,
                hasIncident: true,
                statusSeverity: "major"
            }
        ];
        var best = primaryIncidentProvider();
        verify(best !== null);
        compare(best.provider, "claude");

        providers = [
            {
                provider: "codex",
                statusKnown: false,
                hasIncident: true,
                statusSeverity: "critical"
            }
        ];
        compare(primaryIncidentProvider(), null);

        providers = [
            {
                provider: "codex",
                statusKnown: true,
                hasIncident: false,
                statusSeverity: "unknown"
            }
        ];
        compare(primaryIncidentProvider(), null);
    }
}
'''


class NotificationWiringTests(unittest.TestCase):
    def test_notification_adapters_preserve_real_transitions(self):
        applet = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = applet.texts[main]
        # These adapters belong to the composition root; several JS modules
        # declare helpers with the same names in their own isolated scopes.
        applet.texts = {main: source}
        functions = []
        for name in FUNCTIONS:
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + applet.function_body(name) + "}")
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n".join(functions))
        with tempfile.TemporaryDirectory(prefix="codexbar-notification-test-") as temporary:
            fixture = Path(temporary) / "tst_notifications.qml"
            fixture.write_text(qml, encoding="utf-8")
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
