"""Static checks for notification identity, planning, and memo ownership."""

import re
import unittest

from ui_regression_support import (
    Surface,
    code_contains,
    function_body,
    root,
)

# The popup UI rules below belong to the plasmoid surface, not to main.qml
# specifically, so read the surface as one text. Extracting the popup into a
# component keeps these assertions meaningful instead of silently unhooking them.
applet = Surface("applet", root)
main_text = applet.text


class NotificationsTest(unittest.TestCase):
    def test_notification_identity(self):
        pending_setter_body = function_body(main_text, "setNotificationProviderRefreshPending")
        for setter_fragment in (
            "var nextPending = copyObject(notificationRefreshPending)",
            "nextPending[key] = true",
            "delete nextPending[key]",
            "notificationRefreshPending = nextPending",
        ):
            if not code_contains(pending_setter_body, setter_fragment):
                raise AssertionError(
                    "setNotificationProviderRefreshPending must update the copied pending map; "
                    f"missing {setter_fragment!r}"
                )
        if not re.search(
            r"if\s*\(pending\)\s*\{\s*nextPending\[key\]\s*=\s*true;?\s*\}\s*else\s*\{\s*delete\s+nextPending\[key\];?\s*\}",
            pending_setter_body,
            re.S,
        ):
            raise AssertionError("setNotificationProviderRefreshPending must set or clear the provider entry")

        notification_memo_js = (root / "contents/ui/NotificationMemo.js").read_text(encoding="utf-8")

        status_memo_key_body = function_body(notification_memo_js, "statusMemoKey")
        if "providerID" not in status_memo_key_body or "account" in status_memo_key_body:
            raise AssertionError("statusMemoKey must remain exclusively provider-scoped across account switches")

    def test_notification_planner_boundary(self):
        notification_planner_js = (root / "contents/ui/NotificationPlanner.js").read_text(encoding="utf-8")

        # NotificationPlanner owns the opaque memo and every cross-signal transition.
        # The direct QtTest suite pins priming, pending refreshes, account scopes,
        # escalation/reset behavior, and intent ordering; these static assertions keep
        # QML as the thin observation/effect adapter instead of reintroducing policy.
        # Private planner helpers deliberately stay out of this check so a
        # behavior-preserving internal refactor does not have to rewrite the safety net.
        if "function transition(observations, previousMemo, options)" not in notification_planner_js:
            raise AssertionError("NotificationPlanner.js must expose its transition boundary")
        for forbidden_planner_fragment in (
            "sendPlasmaNotification",
            "notify-send",
            "i18n(",
            "Qt.",
            "selectedAccountForProvider",
            "notificationRefreshPending",
        ):
            if forbidden_planner_fragment in notification_planner_js:
                raise AssertionError(
                    "NotificationPlanner must stay pure and independent of QML lifecycle/effects; "
                    f"found {forbidden_planner_fragment!r}"
                )

        # Direct QtTests own projection rules; pin only the QML input wiring.
        observations_body = applet.function_body("notificationObservations")
        self.assertTrue(code_contains(observations_body,
            "NotificationObservations.build(providers, selectedAccounts, notificationRefreshPending, {"))
        for binding in ("warningPercent: quotaWarningPercent", "criticalPercent: quotaCriticalPercent"):
            self.assertTrue(code_contains(observations_body, binding))
        observation_source = (root / "contents/ui/NotificationObservations.js").read_text()
        for forbidden in ("root.", "Plasmoid.", "i18n(", "Qt.", "sendPlasmaNotification"):
            self.assertNotIn(forbidden, observation_source)

        process_notifications_body = applet.function_body("processNotifications")
        for delegation_fragment in (
            "var observations = notificationObservations()",
            "NotificationPlanner.transition(",
            "notificationPlannerOptions(mode)",
            "notificationMemo = result.nextMemo",
            "dispatchNotificationIntents(result.intents, observations)",
        ):
            if not code_contains(process_notifications_body, delegation_fragment):
                raise AssertionError(
                    "processNotifications must delegate the whole transition and apply its result; "
                    f"missing {delegation_fragment!r}"
                )
        memo_commit_index = process_notifications_body.find("notificationMemo = result.nextMemo")
        dispatch_index = process_notifications_body.find("dispatchNotificationIntents")
        if memo_commit_index < 0 or dispatch_index < 0 or memo_commit_index > dispatch_index:
            raise AssertionError("the complete notification memo must commit before any intent side effect")
        for old_policy_fragment in (
            "NotificationMemo.statusDecision(",
            "quotaNotificationKey(",
            "paceNotificationKey(",
            "limitResetNotificationKey(",
        ):
            if old_policy_fragment in process_notifications_body:
                raise AssertionError("processNotifications must not reimplement planner policy in QML")

        dispatch_body = applet.function_body("dispatchNotificationIntents")
        for effect_fragment in ("providers[observation.providerIndex]", "rows[intent.rowIndex]",
                                "providerNotificationText.message(", "sendPlasmaNotification("):
            self.assertIn(effect_fragment, dispatch_body)
        text_path = root / "contents/ui/components/ProviderNotificationText.qml"
        text_source = text_path.read_text()
        text_body = function_body(text_source, "message")
        for kind in ("status", "quota", "pace", "reset"):
            self.assertIn('intent.kind === "' + kind + '"', text_body)
        for forbidden in ("root.", "Plasmoid.", "NotificationPlanner", "sendPlasmaNotification",
                          "connectSource", "Qt.openUrlExternally", "Timer {", "Connections {"):
            self.assertNotIn(forbidden, text_source)
        applet.require("Components.ProviderNotificationText {", "provider notification text owner")

        reset_memo_body = applet.function_body("resetNotificationMemo")
        if not code_contains(reset_memo_body, "NotificationPlanner.transition("):
            raise AssertionError(
                "resetNotificationMemo must reset the opaque memo through NotificationPlanner; "
                "missing 'NotificationPlanner.transition('"
            )
        if not code_contains(reset_memo_body, 'mode: "reset"'):
            raise AssertionError(
                "resetNotificationMemo must request the planner's reset transition; "
                "missing 'mode: \"reset\"'"
            )
        if re.search(r"notificationMemo\s*=\s*\(\{\}\)", reset_memo_body):
            raise AssertionError("resetNotificationMemo must not clear the whole memo, including status state")
        reset_index = reset_memo_body.find('mode: "reset"')
        prime_index = reset_memo_body.find("processNotifications()", reset_index)
        deferred_index = reset_memo_body.find("Qt.callLater(processNotifications)", reset_index)
        if reset_index < 0 or prime_index < 0 or prime_index == deferred_index or deferred_index < 0 or prime_index > deferred_index:
            raise AssertionError(
                "resetNotificationMemo must prime synchronously before the deferred pass, "
                "so an incident starting in between cannot join the baseline silently"
            )

    def test_notification_memo(self):
        notification_memo_js = (root / "contents/ui/NotificationMemo.js").read_text(encoding="utf-8")

        # NotificationMemo remains an internal seam for provider-scoped status rules.
        for memo_function in (
            "function statusMemoKey(providerID)",
            "function statusPrimedMemoKey(providerID)",
            "function isStatusMemoKey(key)",
            "function preservedMemoAfterReset(memo)",
            "function carryStatusMemo(memo, providerID, nextMemo)",
            "function statusDecision(memo, providerID, value, severity)",
            "function applyStatusDecision(nextMemo, providerID, decision)",
            "function severityRank(severity)",
        ):
            if memo_function not in notification_memo_js:
                raise AssertionError(f"NotificationMemo.js must keep {memo_function!r}")
        if "sendPlasmaNotification" in notification_memo_js or "i18n(" in notification_memo_js:
            raise AssertionError("NotificationMemo.js must stay free of side effects and user-facing text")
        status_decision_body = function_body(notification_memo_js, "statusDecision")
        if not code_contains(status_decision_body, 'statusPrimedMemoKey(providerID)] !== "1"'):
            raise AssertionError(
                "statusDecision must silently baseline a provider that was never primed, so an incident "
                "predating the memo cannot be announced as new"
            )
        unprimed_index = status_decision_body.find('statusPrimedMemoKey(providerID)] !== "1"')
        worsened_index = status_decision_body.find("worsened")
        if unprimed_index < 0 or worsened_index < 0 or unprimed_index > worsened_index:
            raise AssertionError("statusDecision must settle the unprimed case before comparing severities")

        # Status notifications must fire on first sight, worsened severity, and changed
        # same-severity stable incident keys so active incident replacements are not
        # missed without letting free-form status text changes spam notifications.
        status_body = function_body(notification_memo_js, "statusDecision")
        if not code_contains(status_body, "worsened"):
            raise AssertionError("statusDecision must gate on severity worsening")
        if (
            "incidentChanged" not in status_body
            or "previousIncidentKey" not in status_body
            or "currentIncidentKey" not in status_body
            or "previousIncidentKey !== currentIncidentKey" not in status_body
        ):
            raise AssertionError(
                "statusDecision must only notify for same-severity changes "
                "when a stable status incident key is present"
            )
        if "previousValue !== text" in status_body:
            raise AssertionError(
                "statusDecision must compare incident keys instead of full "
                "severity-bearing memo values"
            )
        notification_planner_js = (root / "contents/ui/NotificationPlanner.js").read_text(encoding="utf-8")

        status_value_body = function_body(notification_planner_js, "statusValue")
        if not code_contains(status_value_body, "observation.statusIncidentKey"):
            raise AssertionError("NotificationPlanner must prefer stable incident keys when present")
        if not code_contains(status_value_body, "NotificationMemo.statusMemoValue("):
            raise AssertionError("NotificationPlanner must encode severity and stable incident key through NotificationMemo")
        if 'String(severity || "") + "|" + String(incidentKey || "")' not in function_body(
            notification_memo_js, "statusMemoValue"
        ):
            raise AssertionError("statusMemoValue must encode severity and incident key, and nothing else")
        if "statusText" in status_value_body:
            raise AssertionError("NotificationPlanner must not use provider-controlled status text as incident identity")

    def test_fresh_data_clears_suppression(self):
        for fresh_function in ("applyUsageTransition",):
            fresh_body = function_body(main_text, fresh_function)
            fresh_index = fresh_body.find("markNotificationProvidersFresh(result.providers)")
            received_index = fresh_body.find("markUsageSnapshotReceived(result.nowMs)")
            providers_index = fresh_body.find("providers = result.providers")
            if fresh_index < 0 or providers_index < 0 or fresh_index > providers_index:
                raise AssertionError(f"{fresh_function} must mark fresh provider data before publishing it")
            if received_index < 0 or received_index > providers_index:
                raise AssertionError(f"{fresh_function} must timestamp usage before publishing it")
        mark_fresh_body = function_body(main_text, "markNotificationProvidersFresh")
        self.assertTrue(code_contains(mark_fresh_body,
            "notificationRefreshPending = NotificationObservations.freshPending("))
        self.assertTrue(code_contains(mark_fresh_body,
            "items, selectedAccounts, notificationRefreshPending"))

    def test_quota_thresholds(self):
        # Projection tests exercise custom thresholds; the UI must use the same
        # bounded threshold module for its markers.
        if "QuotaThresholds.markers(" not in function_body(main_text, "quotaWarningMarkers"):
            raise AssertionError("quotaWarningMarkers must delegate to QuotaThresholds.markers")
        for retired_literal in ("usageBarsShowUsed ? 80 : 20", "usageBarsShowUsed ? 95 : 5", "used >= 95", "used >= 80"):
            if retired_literal in main_text:
                raise AssertionError(
                    f"quota thresholds must stay configurable; found hardcoded {retired_literal!r}"
                )


if __name__ == "__main__":
    unittest.main()
