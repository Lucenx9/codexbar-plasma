"""Static UI checks for Usage & Spend controls and the activity heatmap."""

import unittest

from ui_regression_support import (
    Surface,
    code_contains,
    provider_cost_section_qml,
    root,
    spend_view_qml,
)


# Surface checks follow the applet owner across extracted popup components.
class SpendViewTest(unittest.TestCase):
    def setUp(self):
        self.applet = Surface("applet", root)
        self.spend_text = spend_view_qml.read_text(encoding="utf-8")
        self.toggle_text = (root / "contents/ui/components/CostMetricToggle.qml").read_text(encoding="utf-8")
        self.provider_section_text = provider_cost_section_qml.read_text(encoding="utf-8")

    def test_spend_follows_saved_provider_order(self):
        spend_provider_costs_body = self.applet.function_body("spendProviderCosts")
        self.assertNotIn(
            "ProviderOrder.orderedItems(",
            spend_provider_costs_body,
            "saved display order must not change the stable cost aggregation order",
        )
        presented_spend_provider_costs_body = self.applet.function_body("presentedSpendProviderCosts")
        for spend_order_fragment in (
            'providers.map(function(item) { return item.provider }).join(",")',
            'ProviderOrder.orderedItems(costs || spendProviderCosts(), tabOrder + "," + providerOrderRaw)',
        ):
            self.assertTrue(
                code_contains(presented_spend_provider_costs_body, spend_order_fragment),
                "Usage & Spend must follow the saved provider order; "
                f"missing {spend_order_fragment!r}",
            )
        self.assertIn(
            "model: view.presentedProviderCosts",
            self.applet.id_block("spendProviderRepeater"),
            "the visible spend provider list must use presentation order",
        )

    def test_history_controls_leave_room_for_spend_total(self):
        spend_header = self.applet.id_block("spendHeaderRow")
        history_controls = self.applet.id_block("historyControlsRow")
        self.assertFalse(
            "ComboBox" in spend_header or "Components.AnalysisSummary" not in spend_view_qml.read_text(),
            "history filters must leave the full header width available for the spend total",
        )
        for control_id in ("metricToggle", "rangeCombo"):
            self.assertIn(
                f"id: {control_id}",
                history_controls,
                "history filters must remain grouped on their own row",
            )

    def test_spend_range_selector_restores_binding_after_activation(self):
        self.assertTrue(
            code_contains(self.spend_text, "rangeCombo.valueAt(index)"),
            "the cost range selector must use the activated option instead of stale currentValue",
        )
        self.assertTrue(
            code_contains(self.spend_text, "rangeCombo.currentIndex = Qt.binding(function"),
            "SpendView.qml must restore the range combo's currentIndex "
            "binding after an interactive pick severs it",
        )

    def test_history_views_use_shared_metric_toggle(self):
        # Both history views share one metric control; its checked buttons
        # follow the applet setting after a click severs their bindings.
        for metric_source, metric_text in (
            ("SpendView.qml", self.spend_text),
            ("ProviderCostSection.qml", self.provider_section_text),
        ):
            self.assertFalse(
                "Components.CostMetricToggle {" not in metric_text or "PlainComboBox {\n            objectName: \"providerCostMetricCombo\"" in metric_text,
                f"{metric_source} must use the shared Cost/Tokens toggle",
            )

    def test_metric_toggle_restores_bindings_and_owns_button_theme(self):
        for toggle_fragment in (
            "readonly property int currentIndex: applet.costHistoryShowsTokens ? 1 : 0",
            "applet.setCostHistoryMetric(values[index])",
            "checked = Qt.binding(function",
            'Accessible.name: i18n("History metric")',
            # The choices keep their own Button theme: inherited from a view
            # created hidden, their labels stayed black on Breeze Dark.
            "Kirigami.Theme.inherit: false",
        ):
            self.assertTrue(
                code_contains(self.toggle_text, toggle_fragment),
                f"CostMetricToggle.qml is missing {toggle_fragment!r}",
            )

    def test_spend_refresh_bypasses_hourly_throttle(self):
        self.assertTrue(
            code_contains(self.spend_text, "view.applet.refreshCost(true)"),
            "the cost refresh button must explicitly bypass the automatic hourly throttle",
        )

    def test_spend_loading_follows_cost_command_lifecycle(self):
        for cost_loading_fragment in (
            "busy: view.applet.costLoading",
            "visible: view.applet.costLoading && view.providerCosts.length === 0",
            "visible: !view.applet.costLoading",
        ):
            self.assertTrue(
                code_contains(self.spend_text, cost_loading_fragment),
                "SpendView must distinguish a range refresh from an empty result; "
                f"missing {cost_loading_fragment!r}",
            )
        self.assertIn(
            'readonly property bool costLoading: costController.loading',
            self.applet.text,
            "cost loading state must follow the active cost command lifecycle",
        )

    def test_spend_chart_keeps_single_day_history_accessible(self):
        self.assertTrue(
            code_contains(self.spend_text, "InteractiveChart"),
            "SpendView must expose the interactive chart; missing 'InteractiveChart'",
        )
        self.assertTrue(
            code_contains(self.spend_text, "visible: view.dailyPoints.length > 0"),
            "SpendView must keep a one-day history keyboard-inspectable",
        )
        self.assertNotIn(
            "visible: view.dailyPoints.length > 1",
            self.spend_text,
            "SpendView must not hide the accessible chart when one history day is available",
        )

    def test_heatmap_follows_selected_range_and_available_width(self):
        self.assertTrue(
            code_contains(self.spend_text, "Daily activity"),
            "SpendView must expose the bounded activity heatmap; missing 'Daily activity'",
        )
        for heatmap_range_fragment in (
            "Math.ceil( (view.heatmapDays.length + view.heatmapTrailingSlots) / 7)",
            "readonly property int fittingColumns",
            "readonly property real cellHeight",
            "Layout.preferredHeight: 7 * heatmapGrid.cellHeight",
            "+ 6 * heatmapGrid.rowSpacing",
        ):
            self.assertTrue(
                code_contains(self.spend_text, heatmap_range_fragment),
                "the activity heatmap must follow the selected cost range and size cells "
                f"from the available width; missing {heatmap_range_fragment!r}",
            )
        self.assertNotIn(
            "view.dailyPoints.length - 42",
            self.spend_text,
            "the activity heatmap must not pin itself to a fixed 42-day window while the "
            "range selector offers 7/30/90 days",
        )

    def test_heatmap_weekday_labels_follow_locale_and_calendar_alignment(self):
        for heatmap_weekday_fragment in (
            "readonly property int heatmapFirstWeekday: Qt.locale().firstDayOfWeek",
            "CostChart.spendHeatmapRowWeekdays( heatmapDays, heatmapFirstWeekday)",
            "CostChart.spendHeatmapTrailingSlots( heatmapDays, heatmapFirstWeekday)",
            "view.heatmapDays, columnCount * 7, view.heatmapTrailingSlots)",
            "visible: view.heatmapRowWeekdays.length === 7",
            "Qt.locale().dayName(modelData, Locale.ShortFormat)",
        ):
            self.assertTrue(
                code_contains(self.spend_text, heatmap_weekday_fragment),
                "the activity heatmap rows must name their weekday, and stay unlabelled when "
                f"the days are not calendar aligned; missing {heatmap_weekday_fragment!r}",
            )

    def test_heatmap_pads_grid_and_hides_single_week_ranges(self):
        self.assertTrue(
            code_contains(self.spend_text, "CostChart.spendHeatmapCells("),
            "the activity heatmap must pad its grid through the shared cell layout, so a ragged "
            "final column cannot cut a week-wide notch out of the block",
        )
        self.assertTrue(
            code_contains(self.spend_text, "visible: view.heatmapDays.length > 7"),
            "the activity heatmap must stay hidden for ranges that fill a single week column, "
            "which repeat the chart above instead of showing a weekday pattern",
        )

    def test_heatmap_padding_stays_out_of_inspection_and_accessibility(self):
        for heatmap_padding_fragment in (
            "readonly property bool measured: !!heatmapCell.modelData",
            "Accessible.ignored: !heatmapCell.measured",
            "onClicked: if (heatmapCell.measured)",
        ):
            self.assertTrue(
                code_contains(self.spend_text, heatmap_padding_fragment),
                "padded heatmap slots carry no day and must stay out of hover, the readout, and "
                f"the reading order; missing {heatmap_padding_fragment!r}",
            )

    def test_heatmap_legend_shares_cell_tint_scale(self):
        # The legend is the only key to the tint scale; it must paint through the
        # same function as the cells, or it would describe a different scale.
        for heatmap_legend_fragment in (
            'objectName: "heatmapLegend"',
            "color: view.heatmapTint(heatmapCell.fraction)",
            "color: view.heatmapTint(parent.modelData)",
        ):
            self.assertTrue(
                code_contains(self.spend_text, heatmap_legend_fragment),
                "the activity heatmap legend must share the cells' tint scale; "
                f"missing {heatmap_legend_fragment!r}",
            )

    def test_spend_provider_rows_do_not_repeat_range_label(self):
        self.assertNotIn(
            "modelData.monthLine",
            self.spend_text,
            "the Usage & Spend provider rows must not repeat the window label that the "
            "range selector already states; use the windowValueLine figures",
        )

    def test_heatmap_inspection_preserves_cell_fill_geometry(self):
        self.assertNotIn(
            "heatmapMouse.containsMouse ? 0.4 : 0",
            self.spend_text,
            "the heatmap hover outline must not fade a border's own alpha: Qt treats a zero-alpha "
            "pen as invalid and paints a zero-width border, snapping the cell fill out to the edge",
        )
        self.assertTrue(
            code_contains(self.spend_text, "opacity: heatmapCell.pinned || heatmapCell.index === heatmapFocus.inspectedIndex ? 1 : 0"),
            "SpendView activity heatmap cells must use a dedicated inspection outline overlay, so the "
            "painted fill geometry never depends on hover",
        )

    def test_heatmap_readout_stays_in_layout(self):
        self.assertTrue(
            code_contains(self.spend_text, 'objectName: "heatmapReadout"'),
            "daily activity must keep its readout in the layout instead of covering cells with a tooltip",
        )


if __name__ == "__main__":
    unittest.main()
