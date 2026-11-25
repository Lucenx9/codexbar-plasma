"""Static UI checks for usage meters, credits, provider details and reset text."""

import re
import unittest

from ui_regression_support import (
    Surface,
    code_contains,
    full_representation_qml,
    function_body,
    id_block,
    provider_usage_row_qml,
    root,
)


class UsageRowsTest(unittest.TestCase):
    def setUp(self):
        self.applet = Surface("applet", root)
        self.provider_usage_row_text = provider_usage_row_qml.read_text(encoding="utf-8")
        self.full_representation_text = full_representation_qml.read_text(encoding="utf-8")

    def test_provider_cost_meter_uses_shared_track_height_and_color_animation(self):
        provider_cost_section_body = id_block(self.full_representation_text, "providerCostSection")
        self.assertEqual(
            provider_cost_section_body.count("Layout.preferredHeight: applet.meterTrackHeight"),
            1,
            "the provider-cost meter must consume the shared meterTrackHeight",
        )
        self.assertTrue(
            code_contains(provider_cost_section_body, "Behavior on color"),
            "the provider-cost meter must animate color like the quota meters",
        )

    def test_usage_delegate_receives_explicit_track_height_without_applet_state(self):
        delegate = self.applet.id_block("providerUsageDelegate")
        self.assertIn("meterTrackHeight: fullRoot.applet.meterTrackHeight", delegate)
        self.assertNotIn("applet", self.provider_usage_row_text)
        self.assertNotIn("Plasmoid", self.provider_usage_row_text)
        self.assertEqual(self.applet.text.count("delegate: providerUsageDelegate"), 2)
        self.assertEqual(
            self.provider_usage_row_text.count(
            "Layout.preferredHeight: usageRow.meterTrackHeight"
            ),
            1,
            "the provider-usage meter must consume meterTrackHeight",
        )

    def test_usage_rows_localize_structured_pace(self):
        self.applet.require("row.pace = paceSummaryPartsText(snapshot.paceParts)", "usage rows must localize structured pace fields")

    def test_usage_percentage_leads_bar_and_remains_prominent(self):
        usage_percent_body = id_block(self.provider_usage_row_text, "usagePercentLabel")
        self.assertTrue(
            code_contains(usage_percent_body, "font.weight: Font.DemiBold"),
            "usagePercentLabel must remain a prominent scan target",
        )
        self.assertLessEqual(
            self.provider_usage_row_text.index("id: usagePercentLabel"),
            self.provider_usage_row_text.index("id: usageBar"),
            "usage percentage must appear in the metric header before its bar",
        )

    def test_usage_track_and_markers_share_inset_geometry(self):
        usage_bar_body = id_block(self.provider_usage_row_text, "usageBar")
        self.assertTrue(
            code_contains(usage_bar_body, "usageRow.withAlpha(Kirigami.Theme.textColor, 0.1)"),
            "usageBar must keep its pill track visually restrained",
        )
        # A marker that spans the track edge to edge reads as a gap in the accent fill
        # rather than a threshold, so pace and quota markers share one inset geometry.
        # A background sliver on each side keeps the tick legible over the fill.
        marker_body = (root / "contents/ui/components/MeterMarker.qml").read_text(encoding="utf-8")
        for marker_geometry_fragment in (
            "y: inset",
            "height: Math.max(0, trackHeight - inset * 2)",
            "readonly property real knockout: 1",
            "color: Kirigami.Theme.backgroundColor",
            "anchors.leftMargin: meterMarker.knockout",
            "anchors.rightMargin: meterMarker.knockout",
        ):
            self.assertTrue(
                code_contains(marker_body, marker_geometry_fragment),
                "MeterMarker.qml must define one shared inset meter marker; "
                f"missing {marker_geometry_fragment!r}",
            )
        self.assertEqual(
            usage_bar_body.count("MeterMarker {"),
            2,
            "both the pace marker and the quota markers must share one marker geometry",
        )
        for full_height_marker in ("height: usageBar.height\n", "height: trackHeight\n", "y: 0\n"):
            self.assertFalse(
                full_height_marker in usage_bar_body or full_height_marker in marker_body,
                "quota markers must not span the meter track edge to edge again",
            )

    def test_usage_metadata_keeps_compact_type_scale(self):
        for usage_metadata_id in ("usagePaceLabel", "usageResetLabel"):
            usage_metadata_body = id_block(self.provider_usage_row_text, usage_metadata_id)
            self.assertTrue(
                code_contains(usage_metadata_body, "font: Kirigami.Theme.smallFont"),
                f"{usage_metadata_id} must retain the compact metadata type scale",
            )


class CreditRowsTest(unittest.TestCase):
    def setUp(self):
        self.applet = Surface("applet", root)
        self.full_representation_text = full_representation_qml.read_text(encoding="utf-8")

    def test_reset_credits_share_credits_group_and_separator(self):
        credits_section_body = id_block(self.full_representation_text, "creditsSection")
        reset_credits_section_body = id_block(self.full_representation_text, "resetCreditsSection")
        self.assertNotIn(
            "Kirigami.Separator {",
            reset_credits_section_body,
            "reset credits must share the Credits separator instead of drawing their own",
        )
        self.assertIn(
            "resetCreditsSection",
            credits_section_body,
            "reset credits must stay grouped inside the Credits section",
        )

    def test_credit_limit_uses_shared_usage_delegate(self):
        credits_section_body = id_block(self.full_representation_text, "creditsSection")
        for credit_limit_fragment in (
            "readonly property var creditLimit:",
            "applet.presentedProviderData.codexCreditLimit",
            "applet.codexCreditLimitUsageRow(",
            "model: creditsSection.creditLimitRow ? [creditsSection.creditLimitRow] : []",
            "delegate: providerUsageDelegate",
        ):
            self.assertTrue(
                code_contains(credits_section_body, credit_limit_fragment),
                "the Credits section must render the validated Codex monthly limit "
                f"without adding a meter to plain balances; missing {credit_limit_fragment!r}",
            )

    def test_plain_credit_balance_stays_null_safe_with_fallback(self):
        credits_section_body = id_block(self.full_representation_text, "creditsSection")
        self.assertTrue(
            re.search(
                r"visible:\s*applet\.presentedProviderData\s*"
                r"&&\s*applet\.presentedProviderData\.credits\s*!==\s*null",
                credits_section_body,
            ),
            "the plain credits balance must stay null-safe and independent of QML formatting",
        )
        self.assertTrue(
            code_contains(credits_section_body, 'i18n("Remaining: %1",'),
            "the Credits section must keep the plain remaining-balance fallback",
        )

    def test_monthly_credit_limit_presents_all_validated_fields(self):
        credit_limit_row_body = self.applet.function_body("creditLimitRow")
        for credit_limit_row_fragment in (
            'i18n("Monthly credit limit")',
            'i18n("Used: %1, remaining: %2 of %3"',
            "usedPercent: creditLimit.usedPercent",
            "leftPercent: creditLimit.leftPercent",
            "resetsAt: creditLimit.resetsAt",
        ):
            self.assertTrue(
                code_contains(credit_limit_row_body, credit_limit_row_fragment),
                "the Codex monthly-limit row must present every validated field through "
                f"the shared usage-meter component; missing {credit_limit_row_fragment!r}",
            )

    def test_credit_balance_uses_locale_aware_number_adapter(self):
        format_number_body = function_body(self.applet.text, "formatNumber")
        self.assertTrue(
            code_contains(format_number_body, "groupedDecimalString(")
            or code_contains(format_number_body, "CostAmounts.formatCount("),
            "formatNumber must format through groupedDecimalString or CostAmounts.formatCount "
            "so credit balances carry group separators and the locale decimal mark like every "
            "other figure in the popup",
        )
        self.assertNotIn(
            "toFixed(",
            format_number_body,
            "formatNumber must not format digits itself again; toFixed hardcodes the "
            "decimal mark and prints a whole balance as '0.0'",
        )

    def test_reset_credits_use_plural_and_strict_semantic_count(self):
        reset_credits_body = self.applet.function_body("resetSection")
        self.assertTrue(
            code_contains(reset_credits_body, 'i18np("%1 available", "%1 available"'),
            "reset credit counts must use plural-aware translations",
        )
        self.assertTrue(
            code_contains(reset_credits_body, "ProviderCostPresentation.resetCount(providerID, resetCredits)"),
            "reset credits must use the tested semantic count",
        )
        direct_number_call = re.compile(r"(?<![A-Za-z0-9_])Number\(")
        self.assertFalse(
            direct_number_call.search(reset_credits_body),
            "reset credits must not use loose numeric coercion",
        )


class ProviderDetailsTest(unittest.TestCase):
    def setUp(self):
        self.applet = Surface("applet", root)

    def test_provider_actions_separate_widget_actions_and_group_menu_rows(self):
        action_rows_body = function_body(self.applet.text, "actionRows")
        self.assertTrue(
            code_contains(action_rows_body, 'action: "refresh", enabled: true, separatorBefore: true'),
            "actionRows must separate provider actions from widget-level actions",
        )
        provider_action_rows_body = id_block(self.applet.text, "providerActionRows")
        for action_fragment in (
            "id: providerActionGroupSeparator",
            "visible: modelData.separatorBefore === true",
        ):
            self.assertTrue(
                code_contains(provider_action_rows_body, action_fragment),
                f"providerActionRows must expose {action_fragment} for grouped menu actions",
            )

    def test_generic_details_take_priority_over_legacy_dashboard(self):
        snapshot_text = (root / "contents/ui/ProviderSnapshot.js").read_text()
        normalize_provider_body = function_body(snapshot_text, "normalize")
        # Parsing and fallback behavior are covered directly by
        # tst_legacy_usage_dashboard.qml; keep localization and generic-detail priority
        # wired through the applet without pinning the module's private helpers.
        self.assertTrue(
            code_contains(normalize_provider_body, "providerDetails.length > 0 ? null : LegacyUsageDashboard.normalize(usage, item)"),
            "generic details must take precedence over bounded legacy dashboards",
        )

    def test_legacy_dashboard_rows_use_localized_adapter(self):
        present_provider_body = function_body(self.applet.text, "presentProviderSnapshot")
        for field in ("kpis", "rows"):
            self.assertTrue(
                code_contains(present_provider_body, f"{field}: dashboard.{field}.map(dashboardDisplayRow)"),
                "legacy dashboard rows must use the localized adapter",
            )

    def test_dashboard_adapter_localizes_and_bounds_named_rows(self):
        # The applet surface contains the same method on the root wrapper and
        # CostText. Read the component for the formatting rules.
        cost_text = (root / "contents/ui/components/CostText.qml").read_text(encoding="utf-8")
        dashboard_display_body = function_body(cost_text, "dashboardDisplayRow")
        self.assertTrue(
            code_contains(dashboard_display_body, "row.parts.map(root.dashboardPartText)"),
            "dashboard number formatting must remain in the QML adapter",
        )
        self.assertTrue(
            code_contains(dashboard_display_body, "dashboardLabelText(row.labelKey)"),
            "semantic dashboard labels must be localized in QML",
        )
        self.assertTrue(
            code_contains(dashboard_display_body, 'i18n("%1 (%2)", row.name, parts[0])'),
            "a named dashboard row must show its name with the first part",
        )
        self.assertTrue(
            code_contains(dashboard_display_body, 'Normalizer.boundedDisplayText(parts.join(" · "), 500)'),
            "dashboard row text must stay bounded in the QML adapter",
        )

    def test_root_dashboard_wrapper_delegates_to_cost_text(self):
        main_qml_text = (root / "contents/ui/main.qml").read_text(encoding="utf-8")
        root_surface = Surface("applet", root)
        main = root / "contents/ui/main.qml"
        root_surface.texts = {main: main_qml_text}
        root_surface.files = [main]
        self.assertTrue(
            code_contains(root_surface.function_body("dashboardDisplayRow"),
            "return costText.dashboardDisplayRow(row)"),
            "the root dashboard row wrapper must delegate to CostText",
        )

    def test_provider_counts_use_plural_aware_helper(self):
        self.assertTrue(
            code_contains(self.applet.text, "function providerCountText(count)"),
            "overview provider counts must use a plural-aware helper",
        )
        provider_count_body = function_body(self.applet.text, "providerCountText")
        self.assertTrue(
            code_contains(provider_count_body, 'i18np("%1 provider", "%1 providers", total)'),
            "providerCountText must select the correct singular form",
        )


class ResetTextTest(unittest.TestCase):
    def setUp(self):
        self.applet = Surface("applet", root)

    def test_popup_detail_lines_keep_middle_dot_separator(self):
        # Popup header and detail lines share the Sessions and Usage & Spend separator.
        for popup_file in ("FullRepresentation.qml", "OverviewProviderRow.qml", "AnalysisAssistant.qml"):
            self.assertNotIn(
                'i18n("%1 - %2"',
                (root / "contents/ui/components" / popup_file).read_text(),
                f"{popup_file} must join popup detail lines with the middle dot separator",
            )

    def test_reset_text_receives_live_clock_and_regional_formatter(self):
        reset_text_body = function_body(self.applet.text, "resetText")
        # The root supplies the live clock and the shared regional date formatter.
        self.assertTrue(
            code_contains(reset_text_body, "usageWindowText.resetText(window, panelClockMs, absolute)"),
            "reset presentation must receive the live panel clock",
        )
        self.applet.require("dateLabels: timeLabels", "reset presentation must use the shared regional formatter")

    def test_usage_text_leaves_state_and_effects_in_applet(self):
        usage_text = (root / "contents/ui/components/UsageWindowText.qml").read_text()
        for forbidden in ("Plasmoid.", "applet.", "Date.now(", "Timer {", "DataSource"):
            self.assertNotIn(forbidden, usage_text, "usage text must not own applet state or effects: " + forbidden)

    def test_qml_times_use_shared_regional_formatter(self):
        # A literal Qt.formatDateTime pattern writes English day and month names and a
        # fixed hour cycle whatever the user's regional format; TimeLabels owns them.
        for path in sorted((root / "contents/ui").rglob("*.qml")):
            self.assertNotIn(
                "Qt.formatDateTime(",
                path.read_text(),
                f"{path.relative_to(root)} must format times through TimeLabels",
            )

    def test_reset_decisions_remain_pure_and_use_callers_clock(self):
        reset_presentation = (root / "contents/ui/ResetPresentation.js").read_text()
        for forbidden in ("root.", "Plasmoid.", "Qt.", "i18n(", "i18np(", "Date.now("):
            self.assertNotIn(
                forbidden,
                reset_presentation,
                "reset decisions must be pure and use the caller's clock: " + forbidden,
            )


if __name__ == "__main__":
    unittest.main()
