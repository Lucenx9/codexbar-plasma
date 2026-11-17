"""Static UI checks for popup loading, incidents, empty states and setup guidance."""

import re
import unittest

from ui_regression_support import (
    Surface,
    code_contains,
    full_representation_qml,
    id_block,
    provider_header_qml,
    root,
    sessions_view_qml,
    spend_view_qml,
)


class PopupStatesTest(unittest.TestCase):
    def setUp(self):
        self.applet = Surface("applet", root)
        self.provider_header_text = provider_header_qml.read_text(encoding="utf-8")
        self.sessions_view_text = sessions_view_qml.read_text(encoding="utf-8")
        self.spend_view_text = spend_view_qml.read_text(encoding="utf-8")
        self.full_representation_text = full_representation_qml.read_text(encoding="utf-8")

    def test_loading_feedback_stays_scoped_and_hidden_for_errors(self):
        # Error/warning message types are exercised on the production blocks
        # by test_usage_recovery.py.
        provider_usage_loading_body = id_block(self.applet.text, "providerUsageLoadingRow")
        self.assertTrue(
            code_contains(provider_usage_loading_body, "visible: applet.loading && applet.errorText.length === 0"),
            "an error-only popup must not display a loading indicator",
        )
        for scoped_feedback_body, feedback_name in (
            (id_block(self.applet.text, "emptyErrorScroll"), "emptyErrorScroll"),
            (provider_usage_loading_body, "providerUsageLoadingRow"),
        ):
            self.assertTrue(
                code_contains(scoped_feedback_body, "applet.providerUsageFeedbackVisible"),
                f"{feedback_name} must stay hidden on the independent Spend and Sessions tabs",
            )

    def test_usage_loading_filler_preserves_top_pinned_tabs(self):
        # A RowLayout inherits its children's maximum height, so it cannot absorb the
        # leftover popup height: the layout engine then spreads the slack across every
        # row and drops the tab bar into the middle of an otherwise empty popup.
        self.assertTrue(
            re.search(r"Item \{\s*\n\s*id: providerUsageLoadingRow", self.applet.text),
            "providerUsageLoadingRow must be a plain Item so it absorbs the leftover "
            "popup height and keeps the tab bar pinned to the top while usage loads",
        )

    def test_history_views_center_busy_indicators_in_filler(self):
        for filler_owner_source, filler_owner_text in (
            ("SessionsView.qml", self.sessions_view_text),
            ("SpendView.qml", self.spend_view_text),
        ):
            self.assertTrue(
                re.search(r"Controls\.BusyIndicator\s*\{\s*(?:id:\s*\w+\s*)?anchors\.centerIn:\s*parent", filler_owner_text),
                f"{filler_owner_source} must center its busy indicator inside a filler item "
                "so the heading stays pinned to the top while loading",
            )

    def test_incident_banner_and_pill_use_active_status_and_severity(self):
        provider_status_body = id_block(self.applet.text, "providerStatusMessage")
        self.assertTrue(
            code_contains(provider_status_body, "applet.presentedProviderData.hasIncident"),
            "healthy provider status must not occupy a permanent inline banner",
        )
        self.assertTrue(
            code_contains(provider_status_body, "applet.statusBadgeColor(applet.presentedProviderData.statusSeverity)"),
            "incident pills must reflect the provider status severity",
        )

    def test_status_message_and_badge_hide_unknown_or_inactive_status(self):
        for block_id, source, data in (
            ("providerStatusMessage", self.applet.text, "applet.presentedProviderData"),
            ("providerStatusBadge", self.provider_header_text, "providerHeaderRow.providerData"),
        ):
            visible = re.search(r"visible:\s*([^\n]*(?:\n\s*&&[^\n]*)*)", id_block(source, block_id))
            self.assertFalse(
                not visible or not re.search(
                    rf"{re.escape(data)}\.hasIncident\s*&&\s*{re.escape(data)}\.statusKnown\s*!==\s*false",
                    visible.group(1),
                ),
                f"{block_id} must hide inactive and unknown provider status",
            )

    def test_provider_placeholder_uses_native_informational_state(self):
        placeholder_body = id_block(self.applet.text, "providerPlaceholderMessage")
        self.assertTrue(
            code_contains(placeholder_body, "Kirigami.PlaceholderMessage.Type.Informational"),
            "providerPlaceholderMessage must use the native informational empty state",
        )

    def test_empty_providers_offer_native_settings_action(self):
        empty_providers_body = id_block(self.applet.text, "emptyProvidersMessage")
        for fragment in ("Kirigami.PlaceholderMessage.Type.Actionable", "helpfulAction: configureProvidersAction",
                         "plainExplanation:"):
            self.assertTrue(
                code_contains(empty_providers_body, fragment),
                "the empty provider state must explain and open native widget settings",
            )

    def test_missing_cli_guidance_takes_priority_on_global_tabs(self):
        missing = id_block(self.applet.text, "missingCommandMessage")
        self.assertIn("visible: fullRoot.commandPathMissing", missing)
        self.assertNotIn("!applet.globalViewSelected", missing)
        self.assertIn("helpfulAction: prepareCliAction", missing)
        self.assertIn("action: usageSettingsAction", missing)
        self.assertNotIn('objectName: "popupSessionsView"', self.full_representation_text)
        for view in ("SpendView", "SessionsView"):
            self.assertIn("visible: applet." + ("spendSelected" if view == "SpendView" else "sessionsSelected")
                          + " && !fullRoot.commandPathMissing", self.full_representation_text)

    def test_ai_insights_integrated_analysis(self):
        self.assertNotIn("AiInsightsView", self.full_representation_text)
        self.assertNotIn("AiInsightsCard", self.full_representation_text)
        self.assertIn("Components.SpendView", self.full_representation_text)
        spend = (root / "contents/ui/components/SpendView.qml").read_text()
        self.assertIn("Components.AnalysisAssistant", spend)
        self.assertNotIn("generateAiInsight", spend)


if __name__ == "__main__":
    unittest.main()
