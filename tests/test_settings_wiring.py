"""Keep settings effects in their owners; pure policies have direct QtTests."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts/lib"))
from qml_surfaces import Surface


class SettingsWiringTests(unittest.TestCase):
    def test_popup_open_refreshes_only_usage_through_the_existing_lifecycle(self):
        applet = Surface("applet")
        applet.require("Qt.callLater(refreshUsageOnOpen)", "popup opening must consult the freshness policy")
        body = applet.function_body("refreshUsageOnOpen")
        for fragment in ("PopupRefreshPolicy.shouldRefresh", "enabled: refreshOnOpen",
                         "visible: expanded", "loading: loading", "scheduled: usageRefreshScheduled",
                         "lastAttemptAtMs: usageLastRefreshAttemptAtMs",
                         "lastCompletedAtMs: usageLastCompletedAtMs", "refreshNow(false)"):
            self.assertIn(fragment, body)
        self.assertNotIn("refreshCost", body)
        self.assertNotIn("connectSource", body)
        self.assertIn("usageLastRefreshAttemptAtMs = Date.now()", applet.function_body("refreshNow"))
        self.assertIn("usageLastCompletedAtMs = nowMs", applet.function_body("markUsageSnapshotReceived"))

    def test_privacy_masks_notification_text_before_the_external_effect(self):
        body = Surface("applet").function_body("sendPlasmaNotification")
        self.assertIn('cleanTitle = privacyMode ? "CodexBar"', body)
        self.assertIn('cleanBody = privacyMode ? i18n(', body)
        self.assertIn("shellQuote(cleanTitle)", body)
        self.assertIn("shellQuote(cleanBody)", body)
        self.assertLess(body.index("cleanBody ="), body.index("connectNotificationCommand("))

    def test_privacy_stops_session_copy_before_touching_the_clipboard(self):
        applet = Surface("applet")
        body = applet.function_body("copySessionValue")
        self.assertLess(body.index("view.applet.privacyMode"), body.index("clipboardBuffer.text ="))
        applet.require("copyEnabled: !view.applet.privacyMode", "private sessions must hide copy actions")

    def test_optional_sections_keep_their_visibility_in_the_popup(self):
        applet = Surface("applet")
        for name, option in (("creditsSection", "showPopupCredits"),
                             ("resetCreditsSection", "showPopupCredits"),
                             ("providerCostSection", "showPopupProviderDetails"),
                             ("providerDetailsSection", "showPopupProviderDetails"),
                             ("usageDashboardSection", "showPopupProviderDetails")):
            self.assertIn("visible: applet." + option, applet.id_block(name))
        applet.require("readonly property bool showPace: applet.showPopupPace !== false", "pace visibility must follow its popup setting")


if __name__ == "__main__":
    unittest.main()
