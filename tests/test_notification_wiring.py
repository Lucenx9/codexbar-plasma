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


class NotificationPipelineTests(unittest.TestCase):
    # processNotifications and dispatchNotificationIntents are the composition
    # root: the guard, the prime/observe mode, the commit-before-effect order,
    # and the intent routing have no other executed pin.
    PIPELINE_FUNCTIONS = (
        "notificationObservations", "notificationPlannerOptions",
        "markNotificationProvidersFresh", "applyTokenCosts", "providerTokenCost",
        "providerMapKey", "primaryIncidentProvider", "copyObject",
        "processNotifications", "dispatchNotificationIntents",
        "sendPlasmaNotification",
        "resetLabel", "usageResetText", "paceEtaText", "resetText",
    )

    PIPELINE_QML = '''import QtQuick
import QtTest
import "SOURCE_URL/NotificationPlanner.js" as NotificationPlanner
import "SOURCE_URL/NotificationObservations.js" as NotificationObservations
import "SOURCE_URL/NotificationMemo.js" as NotificationMemo
import "SOURCE_URL/ProviderNormalizer.js" as Normalizer
import "SOURCE_URL/Guards.js" as Guards
import "SOURCE_URL/CostPresentation.js" as CostPresentation
import "SOURCE_URL/PrivacyPresentation.js" as PrivacyPresentation
import "SOURCE_URL/controllers" as Controllers
import "SOURCE_URL/components" as Components
TestCase {
    id: testCase
    name: "NotificationPipeline"
    property bool enableNotifications: true
    property bool includeStatus: true
    property bool notifyStatusIncidents: true
    property bool notifyQuotaWarnings: true
    property bool notifyPredictivePaceWarnings: false
    property bool notifyLimitResets: true
    property int quotaWarningPercent: 80
    property int quotaCriticalPercent: 95
    property int limitResetArmThreshold: 80
    property int limitResetFloor: 5
    property bool privacyMode: false
    property bool resetTimesShowAbsolute: false
    property double panelClockMs: Date.UTC(2026, 8, 12)
    property var selectedAccounts: ({})
    property var notificationRefreshPending: ({})
    property var providers: []
    property var tokenCosts: ({})
    property int costHistoryDays: 30
    property string costHistoryPeriod: ""
    property bool notificationsPrimed: false
    property var notificationMemo: ({})
    property var sentNotifications: []
    property var notificationDispatcher: ({
        send: function(title, body, urgency, actionLabel) {
            sentNotifications = sentNotifications.concat([{
                title: title, body: body, urgency: urgency, actionLabel: actionLabel
            }]);
            return "source-" + sentNotifications.length;
        }
    })

    Components.UsageWindowText {
        id: usageWindowText
        function i18n() { return testCase.i18n.apply(testCase, arguments); }
        function i18np(one, many, count) { return testCase.i18np(one, many, count); }
    }

    Components.ProviderNotificationText {
        id: providerNotificationText
    }

    Controllers.UpdateNotificationsController {
        id: updateNotifications
        configuration: ({})
        privacyMode: parent.privacyMode
        dispatcher: parent.notificationDispatcher
    }

    SOURCE_FUNCTIONS

    function i18n(text) {
        var out = String(text);
        for (var i = 1; i < arguments.length; i++) {
            out = out.replace("%" + i, String(arguments[i]));
        }
        return out;
    }
    function i18np(one, many, count) { return i18n(count === 1 ? one : many, count); }

    function init() {
        enableNotifications = true;
        selectedAccounts = ({});
        notificationRefreshPending = ({});
        providers = [];
        notificationsPrimed = false;
        notificationMemo = ({});
        sentNotifications = [];
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
    function receive(items) {
        markNotificationProvidersFresh(items);
        providers = items;
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
    function quotaItem(used, severity) {
        return {
            provider: "codex", title: "Codex",
            hasIncident: severity.length > 0, statusSeverity: severity,
            statusIncidentKey: severity.length > 0 ? "incident-1" : "",
            status: severity.length > 0 ? "Service degraded" : "",
            statusKnown: true, error: "",
            rows: [{
                lane: "primary", label: "Session", hasPercent: true,
                usedPercent: used, paceKnown: false
            }]
        };
    }
    function test_disabledNotificationsSkipPrimingAndDispatch() {
        enableNotifications = false;
        providers = [quotaItem(96, "major")];
        processNotifications();
        compare(sentNotifications.length, 0);
        verify(!notificationsPrimed);
    }
    function test_emptyRosterStaysUnprimed() {
        providers = [];
        processNotifications();
        compare(sentNotifications.length, 0);
        verify(!notificationsPrimed);
    }
    function test_primeThenEscalationDispatchesOneCriticalQuotaNotification() {
        providers = [quotaItem(85, "")];
        processNotifications();
        verify(notificationsPrimed);
        compare(sentNotifications.length, 0);
        providers = [quotaItem(96, "")];
        processNotifications();
        compare(sentNotifications.length, 1);
        compare(sentNotifications[0].urgency, "critical");
        compare(sentNotifications[0].title, "Codex quota critical");
        verify(sentNotifications[0].body.indexOf("96") >= 0);
        // The committed memo absorbs the escalation; a repeat stays silent.
        processNotifications();
        compare(sentNotifications.length, 1);
    }
    function test_quotaNotificationBodyCarriesTheResetLine() {
        var prime = quotaItem(85, "");
        prime.rows[0].resetsAt = new Date(panelClockMs + 2 * 3600 * 1000).toISOString();
        providers = [prime];
        processNotifications();
        compare(sentNotifications.length, 0);
        var escalated = quotaItem(96, "");
        escalated.rows[0].resetsAt = new Date(panelClockMs + 2 * 3600 * 1000).toISOString();
        providers = [escalated];
        processNotifications();
        compare(sentNotifications.length, 1);
        // The quota body keeps the localized reset countdown alongside the
        // percentage; the label wrapper owns the "Resets" prefix.
        verify(sentNotifications[0].body.indexOf("96") >= 0);
        verify(sentNotifications[0].body.indexOf("Resets") >= 0);
    }
    function test_allIntentKindsRouteInOrderWithTheirOriginalText() {
        var item = quotaItem(95.6, "major");
        item.rows[0].paceEtaSeconds = 3600;
        providers = [item];
        dispatchNotificationIntents([
            {kind: "status", severity: "unknown", observationIndex: 0},
            {kind: "quota", severity: "major", observationIndex: 0, rowIndex: 0},
            {kind: "pace", observationIndex: 0, rowIndex: 0},
            {kind: "reset", observationIndex: 0, rowIndex: 0},
            {kind: "future", observationIndex: 0, rowIndex: 0},
            {kind: "quota", observationIndex: 0, rowIndex: 4},
            {kind: "status", observationIndex: 9}
        ], [{providerIndex: 0}]);
        compare(sentNotifications.map(function(value) { return value.title; }), [
            "Codex status issue", "Codex quota critical", "Codex pace warning", "Codex limit reset"
        ]);
        compare(sentNotifications.map(function(value) { return value.urgency; }), [
            "low", "critical", "normal", "low"
        ]);
        compare(sentNotifications[1].body, "Session is 96% used");
        compare(sentNotifications[2].body, "Session may run out in 1 hour");
        compare(sentNotifications[3].body, "Session is back to 96% used");
    }
    function test_statusWithoutUsageRowsAndPrivacyStaySupported() {
        var item = quotaItem(85, "major");
        item.rows = [];
        providers = [item];
        dispatchNotificationIntents([{kind: "status", severity: "major", observationIndex: 0}],
            [{providerIndex: 0}]);
        compare(sentNotifications[0].body, "Service degraded");
        privacyMode = true;
        dispatchNotificationIntents([{kind: "status", severity: "major", observationIndex: 0}],
            [{providerIndex: 0}]);
        compare(sentNotifications[1].title, "CodexBar");
        compare(sentNotifications[1].body, "Usage or status changed. Open CodexBar for details.");
        privacyMode = false;
    }
    function test_statusIncidentDispatchesWithMappedUrgency() {
        providers = [quotaItem(40, "")];
        processNotifications();
        compare(sentNotifications.length, 0);
        providers = [quotaItem(40, "major")];
        processNotifications();
        compare(sentNotifications.length, 1);
        compare(sentNotifications[0].title, "Codex status issue");
        compare(sentNotifications[0].urgency, "critical");
        processNotifications();
        compare(sentNotifications.length, 1);
    }
}
'''

    def test_notification_pipeline_guards_primes_and_dispatches(self):
        applet = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = applet.texts[main]
        # These adapters belong to the composition root; several JS modules
        # declare helpers with the same names in their own isolated scopes.
        applet.texts = {main: source}
        functions = []
        for name in self.PIPELINE_FUNCTIONS:
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + applet.function_body(name) + "}")
        qml = self.PIPELINE_QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("SOURCE_FUNCTIONS", "\n".join(functions))
        with tempfile.TemporaryDirectory(prefix="codexbar-notification-pipeline-") as temporary:
            fixture = Path(temporary) / "tst_notification_pipeline.qml"
            fixture.write_text(qml, encoding="utf-8")
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class UpdateNotificationWiringTests(unittest.TestCase):
    UPDATE_QML = '''import QtQuick
import QtTest
import "SOURCE_URL/controllers" as Controllers
TestCase {
    id: testCase
    name: "UpdateNotificationWiring"
    property bool enableNotifications: true
    property bool privacyMode: false
    property alias lastNotifiedUpdateVersion: updateNotifications.lastNotifiedUpdateVersion
    property alias pendingUpdateReleaseUrls: updateNotifications.pendingUpdateReleaseUrls
    property QtObject notificationPlasmoidConfiguration: QtObject {
        property bool updateNotificationsEnabled: true
        property bool cliUpdateNotificationsEnabled: true
        property string lastNotifiedUpdateVersion: ""
        property string cliUpdateLastNotifiedVersion: ""
    }
    property var sentNotifications: []
    property int sentSerial: 0
    property var openedReleaseUrls: []
    property var notificationDispatcher: ({
        send: function(title, body, urgency, actionLabel) {
            sentSerial += 1;
            sentNotifications = sentNotifications.concat([{
                title: title, body: body, urgency: urgency, actionLabel: actionLabel
            }]);
            return "source-" + sentSerial;
        }
    })

    function i18n(text, first) {
        return text.replace("%1", first === undefined ? "%1" : first);
    }

    function recordOpenedReleaseUrl(url) {
        openedReleaseUrls = openedReleaseUrls.concat([url]);
    }

    Controllers.UpdateNotificationsController {
        id: updateNotifications
        configuration: testCase.notificationPlasmoidConfiguration
        enableNotifications: testCase.enableNotifications
        privacyMode: testCase.privacyMode
        dispatcher: testCase.notificationDispatcher
        onReleasePageRequested: function(url) { testCase.recordOpenedReleaseUrl(url); }
    }
    function notifyAvailableUpdate(version, url, releaseUrl) {
        updateNotifications.notifyAvailableUpdate(version, url, releaseUrl);
    }
    function notifyInstalledUpdate(version) { updateNotifications.notifyInstalledUpdate(version); }
    function handleUpdateNotificationActivated(sourceName) {
        updateNotifications.handleUpdateNotificationActivated(sourceName);
    }


    function init() {
        enableNotifications = true;
        privacyMode = false;
        lastNotifiedUpdateVersion = "";
        pendingUpdateReleaseUrls = ({});
        notificationPlasmoidConfiguration.lastNotifiedUpdateVersion = "";
        notificationPlasmoidConfiguration.updateNotificationsEnabled = true;
        sentNotifications = [];
        sentSerial = 0;
        openedReleaseUrls = [];
    }

    function releaseUrl(version) {
        return "https://github.com/Lucenx9/codexbar-plasma/releases/tag/" + version;
    }

    function announce(version) {
        notifyAvailableUpdate(version, "", releaseUrl(version));
    }

    function test_queuedActionableUpdatesOpenTheirOwnReleasePage() {
        announce("v0.2.40");
        announce("v0.2.41");
        compare(sentNotifications.length, 2);
        // The action label is the production wording; a relabelled button
        // still opens the page but no longer reads as the release action.
        compare(sentNotifications[0].actionLabel, "Open release page");
        compare(sentNotifications[1].actionLabel, "Open release page");
        compare(Object.keys(pendingUpdateReleaseUrls).length, 2);

        // The later notification activating must not retire the earlier one.
        handleUpdateNotificationActivated("source-2");
        compare(openedReleaseUrls, [releaseUrl("v0.2.41")]);
        handleUpdateNotificationActivated("source-1");
        compare(openedReleaseUrls, [releaseUrl("v0.2.41"), releaseUrl("v0.2.40")]);
        compare(pendingUpdateReleaseUrls, ({}));

        // Replays of retired sources open nothing.
        handleUpdateNotificationActivated("source-1");
        handleUpdateNotificationActivated("unknown-source");
        compare(openedReleaseUrls.length, 2);
    }

    function test_updatesWithoutATrustedReleaseUrlStayNonActionable() {
        announce("v0.2.40");
        compare(sentNotifications.length, 1);
        verify(sentNotifications[0].actionLabel.length > 0);

        notifyAvailableUpdate("v0.2.41", "", "");
        compare(sentNotifications.length, 2);
        compare(sentNotifications[1].actionLabel, "");
        compare(Object.keys(pendingUpdateReleaseUrls).length, 1);

        notifyAvailableUpdate("v0.2.42", "", "https://example.dev/releases/tag/v0.2.42");
        compare(sentNotifications.length, 3);
        compare(sentNotifications[2].actionLabel, "");
        compare(Object.keys(pendingUpdateReleaseUrls).length, 1);

        // Only the trusted first announcement is actionable; the non-actionable
        // sources were never registered, and unknown sources open nothing.
        handleUpdateNotificationActivated("source-2");
        handleUpdateNotificationActivated("source-3");
        compare(openedReleaseUrls, []);
        handleUpdateNotificationActivated("source-1");
        compare(openedReleaseUrls, [releaseUrl("v0.2.40")]);
        compare(pendingUpdateReleaseUrls, ({}));
    }

    function test_disabledNotificationsNeverReachTheDispatcher() {
        enableNotifications = false;
        announce("v0.2.40");
        compare(sentNotifications.length, 0);
        enableNotifications = true;
        notificationPlasmoidConfiguration.updateNotificationsEnabled = false;
        announce("v0.2.41");
        compare(sentNotifications.length, 0);
        compare(pendingUpdateReleaseUrls, ({}));
    }

    // The notified version persists, so the same update is not re-announced
    // on every plasmashell restart.
    function test_availableUpdatePersistsMemoVersion() {
        announce("v0.2.40");
        compare(lastNotifiedUpdateVersion, "v0.2.40");
        compare(notificationPlasmoidConfiguration.lastNotifiedUpdateVersion, "v0.2.40");
        announce("v0.2.40");
        compare(sentNotifications.length, 1);
    }

    // An installed update notifies once with its version, and stays silent
    // while notifications are disabled.
    function test_installedUpdateNotifiesOnceWithVersion() {
        notifyInstalledUpdate("v0.2.42");
        compare(sentNotifications.length, 1);
        compare(sentNotifications[0].title, "CodexBar widget update installed");
        verify(sentNotifications[0].body.indexOf("v0.2.42") >= 0);
        enableNotifications = false;
        notifyInstalledUpdate("v0.2.43");
        compare(sentNotifications.length, 1);
    }
}
'''

    def test_update_notification_adapters_keep_activations_source_scoped(self):
        qml = self.UPDATE_QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        with tempfile.TemporaryDirectory(prefix="codexbar-update-notification-") as temporary:
            fixture = Path(temporary) / "tst_update_notifications.qml"
            fixture.write_text(qml, encoding="utf-8")
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class UpdateInstalledForwardingTests(unittest.TestCase):
    # The onUpdateInstalled handler is the only pin on the call site: the
    # controller emits updateInstalled and the applet must forward the
    # version to root.notifyInstalledUpdate. The handler body is extracted
    # and executed against a recording stub, never grepped, so deleting the
    # forward (or its argument) reddens the QML compare instead of a
    # source-text assertion.
    FORWARD_QML = '''import QtQuick
import QtTest
TestCase {
    name: "UpdateInstalledForwarding"
    QtObject {
        id: root
        property var forwardedVersions: []
        function notifyInstalledUpdate(version) {
            forwardedVersions = forwardedVersions.concat([version]);
        }
        SOURCE_HANDLER
    }
    function test_updateInstalledForwardsVersionToNotifier() {
        root.forwardedVersions = [];
        root.forwardUpdateInstalled("v9.9.9");
        compare(root.forwardedVersions, ["v9.9.9"]);
    }
}
'''

    def test_applet_forwards_update_installed_version_to_notifier(self):
        applet = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = applet.texts[main]
        start = source.find("onUpdateInstalled")
        self.assertNotEqual(start, -1)
        open_brace = source.index("{", start)
        depth = 1
        index = open_brace + 1
        while index < len(source) and depth > 0:
            if source[index] == "{":
                depth += 1
            elif source[index] == "}":
                depth -= 1
            index += 1
        body = source[open_brace + 1:index - 1]
        qml = self.FORWARD_QML.replace(
            "SOURCE_HANDLER",
            "function forwardUpdateInstalled(version) {" + body + "}")
        with tempfile.TemporaryDirectory(prefix="codexbar-update-installed-forward-") as temporary:
            fixture = Path(temporary) / "tst_update_installed_forward.qml"
            fixture.write_text(qml, encoding="utf-8")
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
