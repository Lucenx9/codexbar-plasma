"""Static UI checks for cost projection, provider details and localized text."""

import re
import unittest

from ui_regression_support import (
    Surface,
    code_contains,
    function_body,
    id_block,
    root,
)


# Surface checks follow the applet owner across extracted popup components.
class CostProjectionTest(unittest.TestCase):
    def setUp(self):
        self.applet = Surface("applet", root)

    def test_cost_controller_localizes_failures(self):
        cost_controller_text = (root / "contents/ui/controllers/CostController.qml").read_text()
        for message in ("codexbar cost did not return JSON.",
                        "codexbar cost returned an unsupported JSON payload.",
                        "Some cost data could not be refreshed."):
            self.assertTrue(
                code_contains(cost_controller_text, message),
                "cost controller must localize each failure outcome",
            )

    def test_controller_snapshots_update_cost_sections(self):
        self.assertTrue(
            code_contains(self.applet.text, "onTokenCostsChanged: applyTokenCosts()"),
            "controller snapshots must update provider-local cost sections",
        )

    def test_spend_costs_project_the_selected_range(self):
        spend_provider_costs_body = function_body(self.applet.text, "spendProviderCosts")
        for fragment in (
            "CostPresentation.spendSnapshots(tokenCosts, costHistoryDays, function(providerID)",
            "return providerTitle(providerID)",
            "}, costHistoryPeriod)",
            "return snapshots.map(function(item) { return root.costPresentation(item) })",
        ):
            self.assertTrue(code_contains(spend_provider_costs_body, fragment), fragment)

    def test_provider_costs_hide_stale_ranges(self):
        provider_token_cost_body = function_body(self.applet.text, "providerTokenCost")
        self.assertTrue(
            code_contains(provider_token_cost_body, "tokenCosts[key]"),
            "providerTokenCost must read the current token-cost map",
        )
        self.assertFalse(
            "CostPresentation.snapshotMatchesRange(" not in provider_token_cost_body
            or "costHistoryDays" not in provider_token_cost_body,
            "providerTokenCost must hide snapshots from a stale history range",
        )
        self.assertTrue(
            code_contains(self.applet.text, "onCostHistoryDaysChanged: applyTokenCosts()"),
            "changing the cost history range must reproject provider details",
        )

    def test_snapshot_replacement_preserves_current_costs(self):
        replace_snapshot_body = function_body(self.applet.text, "replaceProviderSnapshot")
        for snapshot_fragment in ("UsageCache.reconcile([], [snapshot], Date.now())", "providerTokenCost(key)", "replacement"):
            self.assertTrue(
                code_contains(replace_snapshot_body, snapshot_fragment),
                "replaceProviderSnapshot must preserve current token-cost state; "
                f"missing {snapshot_fragment!r}",
            )


class ProviderCostTest(unittest.TestCase):
    def setUp(self):
        self.applet = Surface("applet", root)
        self.presentation = (root / "contents/ui/ProviderCostPresentation.js").read_text()

    def test_cost_errors_and_summary_precede_trust_notice(self):
        token_cost_section_body = id_block(self.applet.text, "tokenCostSection")
        self.assertLess(token_cost_section_body.index("visible: tokenCostSection.costErrorText.length > 0"),
                        token_cost_section_body.index("Components.CostTrustNotice {"))
        self.assertLess(token_cost_section_body.index("id: costSummaryGrid"),
                        token_cost_section_body.index("Components.CostTrustNotice {"))

    def test_provider_cost_errors_are_visible_and_scoped(self):
        token_cost_section_body = id_block(self.applet.text, "tokenCostSection")
        self.assertTrue(
            code_contains(token_cost_section_body, "applet.costErrorText"),
            "tokenCostSection must surface costErrorText instead of dropping cost errors",
        )
        self.assertTrue(
            code_contains(token_cost_section_body, "Cost unavailable: %1"),
            "tokenCostSection must label visible cost errors",
        )
        self.assertTrue(
            code_contains(token_cost_section_body, "supportsLocalCost"),
            "tokenCostSection must scope global cost errors to supported providers",
        )

    def test_provider_chart_uses_selected_metric_points(self):
        token_cost_section_body = id_block(self.applet.text, "tokenCostSection")
        self.assertFalse(
            "points: tokenCostSection.chartPoints" not in token_cost_section_body
            or token_cost_section_body.count("tokenCostSection.chartPoints.length > 0") < 1,
            "provider cost charts must use the points available for the selected metric",
        )

    def test_cost_history_heading_keeps_average_aligned(self):
        cost_history_header_body = id_block(self.applet.text, "costHistoryHeaderRow")
        self.assertTrue(
            code_contains(cost_history_header_body, "costHistoryChartSection.averageLine"),
            "cost history must keep the average aligned with its heading",
        )

    def test_cost_history_rows_stay_compact(self):
        cost_history_row_body = id_block(self.applet.text, "costHistoryMetricRow")
        for history_row_fragment in (
            "id: costHistoryDateLabel",
            "id: costHistoryBarTrack",
            "Layout.preferredHeight: applet.compactMeterTrackHeight",
            "applet.withAlpha(Kirigami.Theme.textColor, 0.055)",
            "gradient: Gradient",
            "orientation: Gradient.Horizontal",
            "antialiasing: true",
            "id: costHistoryValueLabel",
            "font.pixelSize: Kirigami.Theme.smallFont.pixelSize",
        ):
            self.assertTrue(
                code_contains(cost_history_row_body, history_row_fragment),
                "cost history rows must stay compact and scannable; "
                f"missing {history_row_fragment!r}",
            )

    def test_cost_details_do_not_repeat_daily_history(self):
        self.assertNotIn(
            "function costDailyRows(tokenCost)",
            self.applet.text,
            "cost details must not repeat the daily history below the chart",
        )

    def test_cost_summary_keeps_today_and_period_amounts_scannable(self):
        cost_summary_body = self.applet.id_block("costSummaryGrid")
        for fragment in (
            "columns: 2",
            "amounts: CostAmounts.todayAmounts(tokenCostSection.tokenCost, tokenCostSection.applet.panelClockMs)",
            "amounts: tokenCostSection.tokenCost.totals",
            "tokenCostSection.amountText(modelData.amounts, modelData.valueMode)",
            "tokenCostSection.tokensText(modelData.amounts, modelData.partialTokens)",
            "Layout.fillWidth: true",
            "wrapMode: Text.Wrap",
        ):
            self.assertTrue(
                code_contains(cost_summary_body, fragment),
                f"compact cost summary is missing {fragment!r}",
            )

    def test_provider_cost_selection_tracks_day_metric_and_account(self):
        token_cost_section_body = id_block(self.applet.text, "tokenCostSection")
        for fragment in (
            "property bool detailsExpanded: false",
            "CostChart.selectedCostDay(",
            "chartPoints, costChart.selectedIndex)",
            "onPointsChanged: tokenCostSection.reconcileDaySelection()",
            "onSelectedIndexChanged: tokenCostSection.rememberDaySelection()",
            "CostChart.costDayIndexAfterRefresh(",
            "onCostHistoryShowsTokensChanged: clearDaySelection()",
            "applet.accountKey(providerData)",
            "accountSelectionKey,",
            "accountSelectionLabel,",
            "applet.accountLabel(providerData)",
            "Components.CostMetricToggle {",
            "applet: tokenCostSection.applet",
        ):
            self.assertTrue(
                code_contains(token_cost_section_body, fragment),
                f"provider cost selection is missing {fragment!r}",
            )
        self.assertTrue(
            re.search(r"onSelectionScopeChanged:\s*\{\s*detailsExpanded = false;\s*clearDaySelection\(\);", token_cost_section_body),
            "provider cost scope changes must clear expanded details and the pinned day",
        )

    def test_cost_trust_notices_stay_outside_collapsed_details(self):
        for collapsed_id in ("costDrillDownSection", "costHistoryChartSection"):
            self.assertNotIn(
                "Components.CostTrustNotice",
                self.applet.id_block(collapsed_id),
                "cost trust notices must remain outside collapsed details",
            )

    def test_model_details_expose_missing_and_partial_models(self):
        cost_drill_down_body = id_block(self.applet.text, "costDrillDownSection")
        for fragment in (
            'i18n("No model data for this period.")',
            "costDrillDownSection.detailData.modelsTruncated === true",
            "modelsTruncated: tokenCostSection.selectedDay.modelsTruncated",
        ):
            self.assertTrue(
                code_contains(cost_drill_down_body, fragment),
                f"period and day details must expose missing or partial models: {fragment!r}",
            )

    def test_model_details_titles_are_localized(self):
        cost_drill_down_body = id_block(self.applet.text, "costDrillDownSection")
        for fragment in ('i18n("Cost details")',
                         'i18n("Details for %1", costLabels.costDayLabel(tokenCostSection.selectedDay.label))'):
            self.assertTrue(
                code_contains(cost_drill_down_body, fragment),
                "costDrillDownSection must use a plain, user-facing title with a localized day",
            )

    def test_model_value_columns_keep_consistent_width_and_type_scale(self):
        cost_drill_down_body = id_block(self.applet.text, "costDrillDownSection")
        self.assertTrue(
            code_contains(cost_drill_down_body, "readonly property real metricValueColumnWidth: Kirigami.Units.gridUnit * 9"),
            "costDrillDownSection must define a stable value column width",
        )
        for value_label in ("costBreakdownValueLabel", "costModelValueLabel"):
            value_label_body = id_block(self.applet.text, value_label)
            self.assertTrue(
                code_contains(value_label_body, "Layout.preferredWidth: costDrillDownSection.metricValueColumnWidth"),
                f"{value_label} must use the shared metric value column width",
            )
            self.assertTrue(
                code_contains(value_label_body, "Layout.maximumWidth: costDrillDownSection.metricValueColumnWidth"),
                f"{value_label} must cap the shared metric value column width",
            )
            self.assertTrue(
                code_contains(
                    value_label_body,
                    'font: Qt.font(Object.assign({}, Kirigami.Theme.smallFont, { weight: Font.Medium, features: { "tnum": 1 } }))',
                ),
                f"{value_label} must use the compact numeric type scale with tabular numerals",
            )

    def test_models_heading_stays_distinct_without_repeating_history(self):
        cost_drill_down_body = id_block(self.applet.text, "costDrillDownSection")
        cost_models_heading_body = id_block(self.applet.text, "costModelsHeading")
        for heading_fragment in (
            "font.pixelSize: Kirigami.Theme.smallFont.pixelSize",
            "font.weight: Font.DemiBold",
        ):
            self.assertTrue(
                code_contains(cost_models_heading_body, heading_fragment),
                "Models must remain distinct without adding another card",
            )
        self.assertFalse(
            "costRecentDaysHeading" in cost_drill_down_body or 'i18n("Recent days")' in cost_drill_down_body,
            "cost details must not duplicate the daily history after the models",
        )

    def test_provider_cost_details_receive_explicit_inputs(self):
        source = (root / "contents/ui/main.qml").read_text()
        for name, call in (("providerCostSection", "providerCostDetails.costSection(providerID, cost)"),
                           ("resetCreditsSection", "providerCostDetails.resetSection(providerID, resetCredits)"),
                           ("codexCreditLimitUsageRow", "providerCostDetails.creditLimitRow(creditLimit)")):
            self.assertIn(call, function_body(source, name))
        self.assertIn("numberFormat: root.costNumberFormat", self.applet.id_block("providerCostDetails"))

    def test_provider_cost_details_leave_effects_in_applet(self):
        details = (root / "contents/ui/components/ProviderCostDetails.qml").read_text()
        for forbidden in ("Plasmoid.configuration", "property var applet", "DataSource", "Timer {",
                          "Connections {", "Qt.openUrlExternally"):
            self.assertFalse(code_contains(details, forbidden), forbidden)

    def test_provider_cost_section_uses_semantic_decisions(self):
        provider_cost_body = self.applet.function_body("costSection")
        self.assertTrue(
            code_contains(provider_cost_body, "ProviderCostPresentation.section(providerID, cost)"),
            "provider cost must use the tested semantic section",
        )
        direct_number_call = re.compile(r"(?<![A-Za-z0-9_])Number\(")
        self.assertFalse(
            direct_number_call.search(provider_cost_body),
            "provider cost must not use loose numeric coercion",
        )

    def test_provider_cost_decisions_remain_pure(self):
        for forbidden in ("root.", "Plasmoid.", "i18n(", "i18np(", "Qt."):
            self.assertNotIn(
                forbidden,
                self.presentation,
                "provider cost decisions must be pure: " + forbidden,
            )

    def test_numeric_cost_and_credit_decisions_stay_in_semantic_module(self):
        provider_cost_body = self.applet.function_body("costSection")
        reset_credits_body = self.applet.function_body("resetSection")
        for field in ("cost.used", "cost.limit", "cost.personalUsed", "resetCredits.availableCount"):
            self.assertNotIn(
                field,
                provider_cost_body + reset_credits_body,
                "numeric cost/credit decisions must stay in the semantic module: " + field,
            )


class CostTextTest(unittest.TestCase):
    def setUp(self):
        self.applet = Surface("applet", root)
        self.main_text = self.applet.texts[root / "contents/ui/main.qml"]
        self.cost_text = (root / "contents/ui/components/CostText.qml").read_text(encoding="utf-8")

    def test_cost_presentation_localizes_normalized_snapshots(self):
        present_cost_body = function_body(self.cost_text, "presentTokenCosts")
        for fragment in ("Guards.copyObject(snapshot)", "costHistoryWindowLabel({ period: snapshot.period }, snapshot.labelDays)",
                         'item.title = i18n("Cost")', "item.monthLine = costLine(windowLabel, snapshot.totals.cost,",
                         "item.windowValueLine = costValueLine(snapshot.totals.cost,"):
            self.assertTrue(
                code_contains(present_cost_body, fragment),
                f"cost presentation must localize normalized snapshots: {fragment!r}",
            )

    def test_history_label_falls_back_to_requested_range(self):
        self.assertTrue(
            code_contains(self.main_text, "function costHistoryWindowLabel(item, requestedHistoryDays)"),
            "main.qml must define costHistoryWindowLabel",
        )
        cost_history_label_body = function_body(self.cost_text, "costHistoryWindowLabel")
        self.assertTrue(
            code_contains(cost_history_label_body, "rawDays = Normalizer.strictFiniteNumber(requestedHistoryDays)"),
            "invalid emitted cost ranges must fall back to the captured request range",
        )

    def test_cost_and_token_values_reject_numeric_coercion(self):
        for cost_number_function in ("costValueLine", "costLine"):
            cost_number_body = function_body(self.cost_text, cost_number_function)
            self.assertGreaterEqual(
                cost_number_body.count("Normalizer.strictFiniteNumber("),
                2,
                f"{cost_number_function} must reject coercive cost and token values",
            )

    def test_spend_total_preserves_token_only_costs(self):
        spend_total_body = function_body(self.cost_text, "spendTotalLine")
        for token_only_total_fragment in (
            "Normalizer.strictFiniteNumber(totals.cost)",
            'usageCountText(totals.tokens, "tokens")',
        ):
            self.assertTrue(
                code_contains(spend_total_body, token_only_total_fragment),
                "the global spend summary must not print a fabricated zero-dollar total; "
                f"missing {token_only_total_fragment!r}",
            )
        self.assertTrue(
            code_contains(function_body(self.main_text, "spendTotalLine"),
            "return costText.spendTotalLine(spendProviderCosts())"),
            "the root spend total must pass already filtered provider costs to CostText",
        )

    def test_token_cost_hints_resolve_aliases_and_explain_antigravity_estimates(self):
        token_cost_hint_body = function_body(self.cost_text, "tokenCostHint")
        self.assertIn(
            "ProviderIdentity.resolveProviderKey(",
            token_cost_hint_body,
            "token cost hints must resolve provider identity aliases",
        )
        for antigravity_hint_fragment in (
            'case "antigravity":',
            'i18n("Antigravity cost estimates use public API prices for known models.")',
        ):
            self.assertTrue(
                code_contains(token_cost_hint_body, antigravity_hint_fragment),
                "Antigravity cost estimates must identify the source of prices; "
                f"missing {antigravity_hint_fragment!r}",
            )

    def test_range_scoped_cost_values_omit_window_label(self):
        self.assertTrue(
            code_contains(function_body(self.cost_text, "presentTokenCosts"), "item.windowValueLine = costValueLine("),
            "normalized token costs must expose a window-free value line for range-scoped surfaces",
        )

    def test_mixed_currency_spend_labels_subtotal_and_scope(self):
        self.assertTrue(
            code_contains(function_body(self.cost_text, "spendTotalLine"), 'i18n("%1 subtotal", costValue)'),
            "mixed-currency spend text must label the selected currency as a subtotal",
        )
        for mixed_currency_fragment in (
            "CostCurrency.spendHasMixedCostCurrencies(providerCosts)",
            "Costs and charts use %1.",
        ):
            self.assertTrue(
                code_contains(self.applet.text, mixed_currency_fragment),
                "mixed-currency spend must be labelled as a subtotal and explain its scope; "
                f"missing {mixed_currency_fragment!r}",
            )

    def test_cost_amounts_localize_trust_qualifiers(self):
        qualified_value_body = function_body(self.cost_text, "qualifiedCostValue")
        for qualified_value_fragment in (
            'i18n("%1 (estimated)"',
            'i18n("%1 (partial)"',
            'i18n("%1 (approximate)"',
        ):
            self.assertTrue(
                code_contains(qualified_value_body, qualified_value_fragment),
                "cost amount lines must carry their trust qualifier in localized text; "
                f"missing {qualified_value_fragment!r}",
            )

    def test_cost_presentation_adapters_forward_current_inputs(self):
        source = (root / "contents/ui/main.qml").read_text()
        for name, call in (
            ("costHistoryWindowLabel", "return costText.costHistoryWindowLabel(item, requestedHistoryDays)"),
            ("costChartPoints", "return CostChart.memoizedChartPoints(memo, costNumberFormat, points, costHistoryShowsTokens)"),
        ):
            self.assertTrue(code_contains(function_body(source, name), call), name)

    def test_root_cost_text_receives_number_format(self):
        binding = id_block(self.main_text, "costText")
        self.assertTrue(
            code_contains(binding, "numberFormat: root.costNumberFormat"),
            "CostText must receive the applet number format explicitly",
        )

    def test_root_cost_text_wrappers_delegate_filtered_costs(self):
        delegations = (
            ("presentTokenCosts", "return costText.presentTokenCosts(snapshots)"),
            ("costHistoryWindowLabel", "return costText.costHistoryWindowLabel(item, requestedHistoryDays)"),
            ("spendTotalLine", "return costText.spendTotalLine(spendProviderCosts())"),
            ("dashboardPartText", "return costText.dashboardPartText(part)"),
            ("dashboardDisplayRow", "return costText.dashboardDisplayRow(row)"),
            ("qualifiedCostValue", "return costText.qualifiedCostValue(value, valueMode)"),
            ("costValueLine", "return costText.costValueLine(cost, tokens, currency, valueMode)"),
            ("costLine", "return costText.costLine(label, cost, tokens, currency, valueMode)"),
            ("usageCountText", "return costText.usageCountText(value, unit)"),
            ("tokenCostHint", "return costText.tokenCostHint(providerID)"),
        )
        for name, fragment in delegations:
            self.assertTrue(
                code_contains(function_body(self.main_text, name), fragment),
                f"{name} must delegate to CostText: {fragment}",
            )

    def test_cost_text_leaves_state_and_effects_in_applet(self):
        for forbidden in ("Plasmoid.", "privacyMode", "Date.now(", "Timer {", "DataSource",
                          "Connections {", "Qt.openUrlExternally"):
            self.assertNotIn(forbidden, self.cost_text, "CostText must not own applet state or effects: " + forbidden)


if __name__ == "__main__":
    unittest.main()
