"""Static UI checks for cost sections, Usage & Spend, charts, and cost notices."""

import re
import unittest

from ui_regression_support import (
    Surface,
    code_contains,
    cost_presentation_js,
    cost_trust_notice_qml,
    full_representation_qml,
    function_body,
    id_block,
    interactive_chart_qml,
    provider_cost_section_qml,
    root,
    spend_view_qml,
)

# The popup UI rules below belong to the plasmoid surface, not to main.qml
# specifically, so read the surface as one text. Extracting the popup into a
# component keeps these assertions meaningful instead of silently unhooking them.
applet = Surface("applet", root)
main_text = applet.text
cost_presentation_text = cost_presentation_js.read_text(encoding="utf-8")
provider_cost_section_text = provider_cost_section_qml.read_text(encoding="utf-8")
interactive_chart_text = interactive_chart_qml.read_text(encoding="utf-8")
spend_view_text = spend_view_qml.read_text(encoding="utf-8")
full_representation_text = full_representation_qml.read_text(encoding="utf-8")
cost_trust_notice_text = cost_trust_notice_qml.read_text(encoding="utf-8")


class CostTest(unittest.TestCase):
    def test_cost_controller_localizes_failures(self):
        cost_controller_text = (root / "contents/ui/controllers/CostController.qml").read_text()
        for message in ("codexbar cost did not return JSON.",
                        "codexbar cost returned an unsupported JSON payload.",
                        "Some cost data could not be refreshed."):
            if not code_contains(cost_controller_text, message):
                raise AssertionError("cost controller must localize each failure outcome")
        if not code_contains(main_text, "onTokenCostsChanged: applyTokenCosts()"):
            raise AssertionError("controller snapshots must update provider-local cost sections")

    def test_token_cost_sections(self):
        token_cost_section_body = id_block(main_text, "tokenCostSection")
        if not code_contains(token_cost_section_body, "applet.costErrorText"):
            raise AssertionError("tokenCostSection must surface costErrorText instead of dropping cost errors")
        if not code_contains(token_cost_section_body, "Cost unavailable: %1"):
            raise AssertionError("tokenCostSection must label visible cost errors")
        if not code_contains(token_cost_section_body, "supportsLocalCost"):
            raise AssertionError("tokenCostSection must scope global cost errors to supported providers")
        if "points: tokenCostSection.chartPoints" not in token_cost_section_body \
                or token_cost_section_body.count("tokenCostSection.chartPoints.length > 0") < 2:
            raise AssertionError(
                "provider cost charts must use the points available for the selected metric"
            )

        present_cost_body = function_body(main_text, "presentTokenCosts")
        for fragment in ("copyObject(snapshot)", "costHistoryWindowLabel({ period: snapshot.period }, snapshot.labelDays)",
                         'item.title = i18n("Cost")', "item.monthLine = costLine(windowLabel, snapshot.totals.cost,",
                         "item.windowValueLine = costValueLine(snapshot.totals.cost,"):
            if not code_contains(present_cost_body, fragment):
                raise AssertionError(f"cost presentation must localize normalized snapshots: {fragment!r}")

        if not code_contains(main_text, "function costHistoryWindowLabel(item, requestedHistoryDays)"):
            raise AssertionError("main.qml must define costHistoryWindowLabel")
        cost_history_label_body = function_body(main_text, "costHistoryWindowLabel")
        if not code_contains(cost_history_label_body, "rawDays = Normalizer.strictFiniteNumber(requestedHistoryDays)"):
            raise AssertionError("invalid emitted cost ranges must fall back to the captured request range")
        for cost_number_function in ("costValueLine", "costLine"):
            cost_number_body = function_body(main_text, cost_number_function)
            if cost_number_body.count("Normalizer.strictFiniteNumber(") < 2:
                raise AssertionError(
                    f"{cost_number_function} must reject coercive cost and token values"
                )
        spend_total_body = function_body(main_text, "spendTotalLine")
        for token_only_total_fragment in (
            "Normalizer.strictFiniteNumber(totals.cost)",
            'usageCountText(totals.tokens, "tokens")',
        ):
            if not code_contains(spend_total_body, token_only_total_fragment):
                raise AssertionError(
                    "the global spend summary must not print a fabricated zero-dollar total; "
                    f"missing {token_only_total_fragment!r}"
                )
        token_cost_hint_body = function_body(main_text, "tokenCostHint")
        for antigravity_hint_fragment in (
            'case "antigravity":',
            'i18n("Local Antigravity history includes token totals. Dollar costs are unavailable.")',
        ):
            if not code_contains(token_cost_hint_body, antigravity_hint_fragment):
                raise AssertionError(
                    "Antigravity local history must be described as token-only; "
                    f"missing {antigravity_hint_fragment!r}"
                )

        # The aggregation moved into CostPresentation.js; the rule did not. A snapshot
        # answered for another window must still be excluded from the selected range.
        spend_snapshots_body = function_body(cost_presentation_text, "spendSnapshots")
        if not code_contains(spend_snapshots_body, "snapshotMatchesRange(tokenCost, historyDays, period)"):
            raise AssertionError("global spend aggregates must exclude snapshots from another selected range")
        cost_range_match_body = function_body(cost_presentation_text, "snapshotMatchesRange")
        for range_match_fragment in ("Number(tokenCost.historyDays)", "Number(historyDays)"):
            if not code_contains(cost_range_match_body, range_match_fragment):
                raise AssertionError(
                    "cost snapshot range matching must compare normalized snapshot and selected ranges; "
                    f"missing {range_match_fragment!r}"
                )
        if "CostPresentation.spendSnapshots(" not in function_body(main_text, "spendProviderCosts"):
            raise AssertionError("main.qml must read spend snapshots from CostPresentation.js")

        provider_token_cost_body = function_body(main_text, "providerTokenCost")
        if not code_contains(provider_token_cost_body, "tokenCosts[key]"):
            raise AssertionError("providerTokenCost must read the current token-cost map")
        if (
            "CostPresentation.snapshotMatchesRange(" not in provider_token_cost_body
            or "costHistoryDays" not in provider_token_cost_body
        ):
            raise AssertionError("providerTokenCost must hide snapshots from a stale history range")
        if not code_contains(main_text, "onCostHistoryDaysChanged: applyTokenCosts()"):
            raise AssertionError("changing the cost history range must reproject provider details")
        replace_snapshot_body = function_body(main_text, "replaceProviderSnapshot")
        for snapshot_fragment in ("UsageCache.reconcile([], [snapshot], Date.now())", "providerTokenCost(key)", "replacement"):
            if not code_contains(replace_snapshot_body, snapshot_fragment):
                raise AssertionError(
                    "replaceProviderSnapshot must preserve current token-cost state; "
                    f"missing {snapshot_fragment!r}"
                )

    def test_spend_follows_saved_provider_order(self):
        spend_provider_costs_body = applet.function_body("spendProviderCosts")
        if "ProviderOrder.orderedItems(" in spend_provider_costs_body:
            raise AssertionError(
                "saved display order must not change the stable cost aggregation order"
            )
        presented_spend_provider_costs_body = applet.function_body("presentedSpendProviderCosts")
        for spend_order_fragment in (
            "ProviderOrder.orderedItems(",
            "providerOrderRaw",
        ):
            if not code_contains(presented_spend_provider_costs_body, spend_order_fragment):
                raise AssertionError(
                    "Usage & Spend must follow the saved provider order; "
                    f"missing {spend_order_fragment!r}"
                )
        if "model: view.presentedProviderCosts" not in applet.id_block("spendProviderRepeater"):
            raise AssertionError("the visible spend provider list must use presentation order")

    def test_history_header_and_bars(self):
        spend_header = applet.id_block("spendHeaderRow")
        history_controls = applet.id_block("historyControlsRow")
        if "ComboBox" in spend_header or "spendTotalLine()" not in spend_header:
            raise AssertionError("history filters must leave the full header width available for the spend total")
        for control_id in ("metricCombo", "rangeCombo"):
            if f"id: {control_id}" not in history_controls:
                raise AssertionError("history filters must remain grouped on their own row")

        cost_history_header_body = id_block(main_text, "costHistoryHeaderRow")
        if not code_contains(cost_history_header_body, "costHistoryChartSection.averageLine"):
            raise AssertionError("cost history must keep the average aligned with its heading")
        cost_history_row_body = id_block(main_text, "costHistoryMetricRow")
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
            if not code_contains(cost_history_row_body, history_row_fragment):
                raise AssertionError(
                    "cost history rows must stay compact and scannable; "
                    f"missing {history_row_fragment!r}"
                )

        cost_history_rows_body = function_body(cost_presentation_text, "historyRows")
        if not code_contains(cost_history_rows_body, "sparklineMax(visibleDaily, showsTokens)"):
            raise AssertionError("cost history bars must scale against the seven visible days")
        if "tokenCost.daily.length - 14" in cost_history_rows_body:
            raise AssertionError("cost history must not dominate the popup with fourteen detailed rows")
        if "function costDailyRows(tokenCost)" in main_text:
            raise AssertionError("cost details must not repeat the daily history below the chart")

    def test_detail_charts(self):
        rounded_bar_body = function_body(cost_presentation_text, "paintRoundedTopBar")
        for rounded_bar_fragment in (
            "Math.min(radius, safeWidth / 2, safeHeight)",
            "context.quadraticCurveTo(",
            "context.fill()",
        ):
            if not code_contains(rounded_bar_body, rounded_bar_fragment):
                raise AssertionError(
                    "paintRoundedTopBar must preserve restrained top rounding for Canvas bars; "
                    f"missing {rounded_bar_fragment!r}"
                )

        if not code_contains(interactive_chart_text, "CostPresentation.paintRoundedTopBar("):
            raise AssertionError("provider detail bar charts must use rounded top corners")
        for detail_chart_fragment in (
            "chart.barGradient(",
            "CostPresentation.chartBarGeometry(width, chart.pointCount)",
            "ChartScale.barGeometry(height,",
        ):
            if not code_contains(interactive_chart_text, detail_chart_fragment):
                raise AssertionError(
                    "provider detail bar charts must retain the polished cost-chart language; "
                    f"missing {detail_chart_fragment!r}"
                )

        for signed_chart_fragment in (
            'import "../ChartScale.js" as ChartScale',
            "ChartScale.domain(points)",
            "ChartScale.pointValue(point)",
            "ChartScale.fraction(value, valueDomain)",
            "chart.chartFraction(0), chart.lineMarkerInset)",
            "if (bar.negative)",
            "context.scale(1, -1)",
            "context.restore()",
        ):
            applet.require(signed_chart_fragment, "detail charts must retain signed values and their zero baseline")

        chart_gradient_body = function_body(interactive_chart_text, "barGradient")
        for gradient_fragment in (
            "context.createLinearGradient",
            "gradient.addColorStop(0",
            "gradient.addColorStop(1",
        ):
            if not code_contains(chart_gradient_body, gradient_fragment):
                raise AssertionError(
                    "vertical bar charts must use the shared restrained gradient; "
                    f"missing {gradient_fragment!r}"
                )

        if not code_contains(main_text, "Components.InteractiveChart"):
            raise AssertionError(
                "the provider cost sparkline must use the interactive shared chart; "
                "missing 'Components.InteractiveChart'"
            )
        if not code_contains(main_text, "applet.costChartPoints("):
            raise AssertionError(
                "the provider cost sparkline must plot the applet cost chart points; "
                "missing 'applet.costChartPoints('"
            )

        # Bar charts are painted for up to 365 cost-history days and 120 detail-chart
        # points. Their one-pixel minimum width can exceed a dense point slot, so the
        # shared geometry helper must distribute the drawable bar edges inside the
        # canvas instead of using the nominal slot as the drawing step.
        if not code_contains(cost_presentation_text, "function chartBarGeometry(width, count)"):
            raise AssertionError("CostPresentation.js must expose a shared bar-chart geometry helper")
        chart_geometry_body = function_body(cost_presentation_text, "chartBarGeometry")
        for fragment in (
            "var slotStep = safeWidth / points",
            "var barWidth = Math.max(1, slotStep - gap)",
            "Math.max(0, safeWidth - barWidth) / (points - 1)",
            "offset: Math.max(0, slotStep - barWidth) / 2",
        ):
            if not code_contains(chart_geometry_body, fragment):
                raise AssertionError(
                    f"chartBarGeometry must keep sparse and dense bars inside the canvas: {fragment}"
                )
        for label, source_text in (
            ("InteractiveChart.qml", interactive_chart_text),
        ):
            if not code_contains(source_text, "CostPresentation.chartBarGeometry("):
                raise AssertionError(f"{label} bar charts must use the shared geometry helper")
            if "barWidth + gap" in source_text:
                raise AssertionError(f"{label} bar charts must not recompute their own bar pitch")
        if not code_contains(interactive_chart_text, "geometry.offset + barIndex * geometry.step"):
            raise AssertionError("provider detail bars must apply the shared canvas offset")

        # The active line-chart point grows to a 3.5px radius. Both axes and pointer hit
        # testing must use the shared inset geometry so the visible marker stays inside
        # Canvas and resolves back to its own point.
        for helper_name in ("chartLineX", "chartLineIndexAt", "chartLineY"):
            if not code_contains(cost_presentation_text, f"function {helper_name}("):
                raise AssertionError(f"CostPresentation.js must expose {helper_name} marker geometry")
            if not code_contains(interactive_chart_text, f"CostPresentation.{helper_name}("):
                raise AssertionError(f"provider detail line charts must use {helper_name}")

    def test_cost_hierarchy_and_selection(self):
        for summary_id, summary_fragment in (
            ("costSparklineSummaryLabel", "font: Kirigami.Theme.smallFont"),
        ):
            summary_body = id_block(main_text, summary_id)
            if not code_contains(summary_body, summary_fragment):
                raise AssertionError(f"{summary_id} must preserve the intended cost hierarchy")

        cost_summary_body = applet.id_block("costSummaryGrid")
        for fragment in (
            "columns: 2",
            "amounts: CostPresentation.todayAmounts(tokenCostSection.tokenCost, tokenCostSection.applet.panelClockMs)",
            "amounts: tokenCostSection.tokenCost.totals",
            "tokenCostSection.amountText(modelData.amounts, modelData.valueMode)",
            "tokenCostSection.tokensText(modelData.amounts)",
            "Layout.fillWidth: true",
            "wrapMode: Text.Wrap",
        ):
            if not code_contains(cost_summary_body, fragment):
                raise AssertionError(f"compact cost summary is missing {fragment!r}")
        token_cost_section_body = id_block(main_text, "tokenCostSection")

        for fragment in (
            "property bool detailsExpanded: false",
            "CostPresentation.selectedCostDay(",
            "chartPoints, costChart.selectedIndex)",
            "onPointsChanged: tokenCostSection.reconcileDaySelection()",
            "onSelectedIndexChanged: tokenCostSection.rememberDaySelection()",
            "CostPresentation.costDayIndexAfterRefresh(",
            "onCostHistoryShowsTokensChanged: clearDaySelection()",
            "applet.accountKey(providerData)",
            "accountSelectionKey,",
            "accountSelectionLabel,",
            "applet.accountLabel(providerData)",
            "applet.setCostHistoryMetric(valueAt(index))",
        ):
            if not code_contains(token_cost_section_body, fragment):
                raise AssertionError(f"provider cost selection is missing {fragment!r}")
        if not re.search(r"onSelectionScopeChanged:\s*\{\s*detailsExpanded = false;\s*clearDaySelection\(\);", token_cost_section_body):
            raise AssertionError("provider cost scope changes must clear expanded details and the pinned day")
        for collapsed_id in ("costDrillDownSection", "costHistoryChartSection"):
            if "Components.CostTrustNotice" in applet.id_block(collapsed_id):
                raise AssertionError("cost trust notices must remain outside collapsed details")

    def test_model_details(self):
        cost_drill_down_body = id_block(main_text, "costDrillDownSection")
        for fragment in (
            'i18n("No model breakdown for this period.")',
            "costDrillDownSection.detailData.modelsTruncated === true",
            "modelsTruncated: tokenCostSection.selectedDay.modelsTruncated",
        ):
            if not code_contains(cost_drill_down_body, fragment):
                raise AssertionError(f"period and day details must expose missing or partial models: {fragment!r}")
        if not code_contains(cost_drill_down_body, "readonly property real metricValueColumnWidth: Kirigami.Units.gridUnit * 9"):
            raise AssertionError("costDrillDownSection must define a stable value column width")
        for fragment in ('i18n("Cost details")',
                         'i18n("Details for %1", costLabels.costDayLabel(tokenCostSection.selectedDay.label))'):
            if not code_contains(cost_drill_down_body, fragment):
                raise AssertionError("costDrillDownSection must use a plain, user-facing title with a localized day")
        for value_label in ("costBreakdownValueLabel", "costModelValueLabel"):
            value_label_body = id_block(main_text, value_label)
            if not code_contains(value_label_body, "Layout.preferredWidth: costDrillDownSection.metricValueColumnWidth"):
                raise AssertionError(f"{value_label} must use the shared metric value column width")
            if not code_contains(value_label_body, "Layout.maximumWidth: costDrillDownSection.metricValueColumnWidth"):
                raise AssertionError(f"{value_label} must cap the shared metric value column width")
            if not code_contains(value_label_body, "font.pixelSize: Kirigami.Theme.smallFont.pixelSize"):
                raise AssertionError(f"{value_label} must use the compact numeric type scale")

        cost_models_heading_body = id_block(main_text, "costModelsHeading")
        for heading_fragment in (
            "font.pixelSize: Kirigami.Theme.smallFont.pixelSize",
            "font.weight: Font.DemiBold",
        ):
            if not code_contains(cost_models_heading_body, heading_fragment):
                raise AssertionError("Models must remain distinct without adding another card")
        if "costRecentDaysHeading" in cost_drill_down_body or 'i18n("Recent days")' in cost_drill_down_body:
            raise AssertionError("cost details must not duplicate the daily history after the models")

    def test_interactive_chart(self):
        for chart_interaction_fragment in (
            "activeFocusOnTab: true",
            "Keys.onPressed:",
            "onPositionChanged:",
            "selectedIndex",
        ):
            if not code_contains(interactive_chart_text, chart_interaction_fragment):
                raise AssertionError(
                    "InteractiveChart must support pointer and keyboard inspection; "
                    f"missing {chart_interaction_fragment!r}"
                )
        for stable_chart_fragment in (
            "readonly property bool hasActivePoint",
            "if (chart.hoveredIndex >= chart.pointCount)",
        ):
            if not code_contains(interactive_chart_text, stable_chart_fragment):
                raise AssertionError(
                    "InteractiveChart must keep hover geometry stable and clamp stale state; "
                    f"missing {stable_chart_fragment!r}"
                )
        if "visible: chart.activeIndex" in interactive_chart_text:
            raise AssertionError("InteractiveChart must reserve readout space while pointer state changes")

        if not code_contains(interactive_chart_text, "opacity: chart.hasActivePoint ? 1 : 0"):
            raise AssertionError("the chart readout must fade with the active point instead of blinking")
        if not code_contains(interactive_chart_text, "onActiveIndexChanged: if (activeIndex >= 0 && activeIndex < pointCount)"):
            raise AssertionError(
                "the chart readout must retain the last inspected point across the fade-out, and must "
                "bounds-check inline: hasActivePoint is still stale inside an activeIndex change handler"
            )
        if interactive_chart_text.count("Accessible.ignored: !chart.hasActivePoint") != 2:
            raise AssertionError(
                "both retained chart readout labels must leave the accessibility tree when no point is "
                "active: the text outlives the fade and a zero opacity does not hide it from a screen reader"
            )
        if "chart.hasActivePoint ? chart.pointLabel" in interactive_chart_text:
            raise AssertionError(
                "the chart readout text must not clear on hasActivePoint: that empties the row "
                "on the same signal that starts the fade, so hover exit blinks instead of fading"
            )

    def test_spend_range_and_refresh(self):
        if not code_contains(spend_view_text, "rangeCombo.valueAt(index)"):
            raise AssertionError("the cost range selector must use the activated option instead of stale currentValue")
        for metric_combo_source, metric_combo_text in (
            ("SpendView.qml", spend_view_text),
            ("ProviderCostSection.qml", provider_cost_section_text),
        ):
            if not code_contains(metric_combo_text, "currentIndex = Qt.binding(function"):
                raise AssertionError(
                    f"{metric_combo_source} must restore the metric combo's currentIndex "
                    "binding after an interactive pick severs it"
                )
        if not code_contains(spend_view_text, "view.applet.refreshCost(true)"):
            raise AssertionError("the cost refresh button must explicitly bypass the automatic hourly throttle")
        for cost_loading_fragment in (
            "busy: view.applet.costLoading",
            "visible: view.applet.costLoading && view.providerCosts.length === 0",
            "visible: !view.applet.costLoading",
        ):
            if not code_contains(spend_view_text, cost_loading_fragment):
                raise AssertionError(
                    "SpendView must distinguish a range refresh from an empty result; "
                    f"missing {cost_loading_fragment!r}"
                )
        if ('readonly property bool costLoading: costController.loading'
                not in main_text):
            raise AssertionError("cost loading state must follow the active cost command lifecycle")

    def test_chart_text_is_localized(self):
        for localized_pair_source, localized_pair_text in (
            ("InteractiveChart.qml", interactive_chart_text),
            ("SpendView.qml", spend_view_text),
        ):
            if '+ ": " +' in localized_pair_text:
                raise AssertionError(
                    f"{localized_pair_source} must localize label/value separators with placeholders"
                )

    def test_spend_view_heatmap(self):
        if not code_contains(spend_view_text, "InteractiveChart"):
            raise AssertionError("SpendView must expose the interactive chart; missing 'InteractiveChart'")
        if not code_contains(spend_view_text, "Activity heatmap"):
            raise AssertionError("SpendView must expose the bounded activity heatmap; missing 'Activity heatmap'")
        if not code_contains(spend_view_text, "visible: view.dailyPoints.length > 0"):
            raise AssertionError("SpendView must keep a one-day history keyboard-inspectable")
        if "visible: view.dailyPoints.length > 1" in spend_view_text:
            raise AssertionError("SpendView must not hide the accessible chart when one history day is available")
        for heatmap_range_fragment in (
            "readonly property var heatmapDays: CostPresentation.spendHeatmapDays(dailyPoints, providerCosts)",
            "Math.ceil( (view.heatmapDays.length + view.heatmapTrailingSlots) / 7)",
            "readonly property int fittingColumns",
            "readonly property real cellHeight",
            "Layout.preferredHeight: 7 * heatmapGrid.cellHeight",
            "+ 6 * heatmapGrid.rowSpacing",
        ):
            if not code_contains(spend_view_text, heatmap_range_fragment):
                raise AssertionError(
                    "the activity heatmap must follow the selected cost range and size cells "
                    f"from the available width; missing {heatmap_range_fragment!r}"
                )
        for heatmap_weekday_fragment in (
            "readonly property int heatmapFirstWeekday: Qt.locale().firstDayOfWeek",
            "CostPresentation.spendHeatmapRowWeekdays( heatmapDays, heatmapFirstWeekday)",
            "CostPresentation.spendHeatmapTrailingSlots( heatmapDays, heatmapFirstWeekday)",
            "view.heatmapDays, columnCount * 7, view.heatmapTrailingSlots)",
            "visible: view.heatmapRowWeekdays.length === 7",
            "Qt.locale().dayName(modelData, Locale.ShortFormat)",
        ):
            if not code_contains(spend_view_text, heatmap_weekday_fragment):
                raise AssertionError(
                    "the activity heatmap rows must name their weekday, and stay unlabelled when "
                    f"the days are not calendar aligned; missing {heatmap_weekday_fragment!r}"
                )
        if not code_contains(spend_view_text, "CostPresentation.spendHeatmapCells("):
            raise AssertionError(
                "the activity heatmap must pad its grid through the shared cell layout, so a ragged "
                "final column cannot cut a week-wide notch out of the block"
            )
        if not code_contains(spend_view_text, "visible: view.heatmapDays.length > 7"):
            raise AssertionError(
                "the activity heatmap must stay hidden for ranges that fill a single week column, "
                "which repeat the chart above instead of showing a weekday pattern"
            )
        for heatmap_padding_fragment in (
            "readonly property bool measured: !!heatmapCell.modelData",
            "Accessible.ignored: !heatmapCell.measured",
            "visible: heatmapMouse.containsMouse && heatmapCell.measured",
        ):
            if not code_contains(spend_view_text, heatmap_padding_fragment):
                raise AssertionError(
                    "padded heatmap slots carry no day and must stay out of hover, the readout, and "
                    f"the reading order; missing {heatmap_padding_fragment!r}"
                )
        if "modelData.monthLine" in spend_view_text:
            raise AssertionError(
                "the Usage & Spend provider rows must not repeat the window label that the "
                "range selector already states; use the windowValueLine figures"
            )

        if "view.dailyPoints.length - 42" in spend_view_text:
            raise AssertionError(
                "the activity heatmap must not pin itself to a fixed 42-day window while the "
                "range selector offers 7/30/90 days"
            )

        if "heatmapMouse.containsMouse ? 0.4 : 0" in spend_view_text:
            raise AssertionError(
                "the heatmap hover outline must not fade a border's own alpha: Qt treats a zero-alpha "
                "pen as invalid and paints a zero-width border, snapping the cell fill out to the edge"
            )
        if not code_contains(spend_view_text, "opacity: heatmapMouse.containsMouse ? 1 : 0"):
            raise AssertionError(
                "SpendView activity heatmap cells must fade a dedicated hover outline overlay, so the "
                "painted fill geometry never depends on hover"
            )

        # Two tooltips confirm or read out state instead of labelling a control, and opt
        # out of that delay explicitly. Pin both, so the default cannot silently start
        # holding back feedback that has to be immediate.
        if not code_contains(spend_view_text, "delay: 0"):
            raise AssertionError(
                "the heatmap cell readout must stay instant: it reports the cell under the pointer "
                "while the pointer scans the grid"
            )

    def test_cost_trust_notices(self):
        if not code_contains(main_text, "item.windowValueLine = costValueLine("):
            raise AssertionError(
                "normalized token costs must expose a window-free value line for range-scoped surfaces"
            )
        for mixed_currency_fragment in (
            "CostPresentation.spendHasMixedCostCurrencies(providerCosts)",
            "The cost subtotal and charts use %1.",
            'i18n("%1 subtotal", costValue)',
        ):
            if not code_contains(main_text, mixed_currency_fragment):
                raise AssertionError(
                    "mixed-currency spend must be labelled as a subtotal and explain its scope; "
                    f"missing {mixed_currency_fragment!r}"
                )
        for empty_metric_fragment in (
            "view.providerCosts.length > 0 && view.dailyPoints.length === 0",
            "No daily token history is available for this range.",
            "Try Tokens to check for token-only history.",
        ):
            if not code_contains(spend_view_text, empty_metric_fragment):
                raise AssertionError(
                    "a provider snapshot without the selected daily metric needs a scoped explanation; "
                    f"missing {empty_metric_fragment!r}"
                )
        token_cost_section_body = id_block(main_text, "tokenCostSection")
        for trust_owner_source, trust_owner_text in (
            ("ProviderCostSection.qml", token_cost_section_body),
            ("SpendView.qml", spend_view_text),
        ):
            if not code_contains(trust_owner_text, "Components.CostTrustNotice"):
                raise AssertionError(
                    f"{trust_owner_source} must render the shared cost-trust notice"
                )
            if not code_contains(trust_owner_text, "CostPresentation.costTrustSummary("):
                raise AssertionError(
                    f"{trust_owner_source} must delegate cost-trust policy to CostPresentation"
                )
        for persistent_notice_fragment in (
            "property var costTrustNoticeStates: ({})",
            "function updateCostTrustNoticeState(",
            "CostPresentation.costTrustNoticeStoreTransition(",
        ):
            if not code_contains(main_text, persistent_notice_fragment):
                raise AssertionError(
                    "the applet root must preserve scoped cost-notice dismissals across popup recreation; "
                    f"missing {persistent_notice_fragment!r}"
                )
        for cost_trust_fragment in (
            "PlainNote {",
            "property var summary: null",
            "property var stateOwner: null",
            'property string noticeScope: ""',
            "property bool presentationVisible: false",
            "showCloseButton: true",
            "stateOwner.updateCostTrustNoticeState(",
            "onNoticeScopeChanged:",
            "onStateOwnerChanged:",
            'typeof stateOwner.updateCostTrustNoticeState !== "function"',
            "onSummaryChanged: scheduleRefreshNoticeState()",
            "onNoticeScopeChanged: scheduleRefreshNoticeState()",
            "onStateOwnerChanged: scheduleRefreshNoticeState()",
            "function scheduleRefreshNoticeState()",
            "noticeRefresh.restart()",
            "onTriggered: noticeRoot.refreshNoticeState()",
            "onVisibleChanged: {",
            "&& presentationVisible",
            'i18n("%1 %2"',
            'i18n("The displayed range total',
            'i18np(',
            "lacked final usage",
            "function incompleteText()",
        ):
            if not code_contains(cost_trust_notice_text, cost_trust_fragment):
                raise AssertionError(
                    "CostTrustNotice must own the shared localized message and standard styling; "
                    f"missing {cost_trust_fragment!r}"
                )
        for non_atomic_notice_fragment in (
            "onSummaryChanged: refreshNoticeState()",
            "onNoticeScopeChanged: refreshNoticeState()",
            "onStateOwnerChanged: refreshNoticeState()",
        ):
            if non_atomic_notice_fragment in cost_trust_notice_text:
                raise AssertionError(
                    "cost notice scope and summary changes must be coalesced before mutating shared dismissal state; "
                    f"found {non_atomic_notice_fragment!r}"
                )
        for provider_notice_fragment in (
            'noticeScope: "provider:" +',
            "stateOwner: tokenCostSection.applet",
            "presentationVisible: tokenCostSection.presentationVisible",
        ):
            if not code_contains(token_cost_section_body, provider_notice_fragment):
                raise AssertionError(
                    "provider cost notices must use a persistent provider scope and visible context; "
                    f"missing {provider_notice_fragment!r}"
                )
        if not code_contains(full_representation_text, "presentationVisible: fullRoot.visible && !applet.globalViewSelected"):
            raise AssertionError("the provider cost section must receive the popup visibility context")
        for spend_notice_fragment in (
            'noticeScope: "spend"',
            "stateOwner: view.applet",
            "presentationVisible: view.visible",
        ):
            if not code_contains(spend_view_text, spend_notice_fragment):
                raise AssertionError(
                    "Spend cost notices must use a persistent aggregate scope and visible context; "
                    f"missing {spend_notice_fragment!r}"
                )
        for qualified_value_fragment in (
            'i18n("%1 (estimated)"',
            'i18n("%1 (partial)"',
            'i18n("%1 (approximate)"',
        ):
            if not code_contains(main_text, qualified_value_fragment):
                raise AssertionError(
                    "cost amount lines must carry their trust qualifier in localized text; "
                    f"missing {qualified_value_fragment!r}"
                )
        present_cost_body = function_body(main_text, "presentTokenCosts")
        if not re.search(r'item.sessionLine = costLine\(i18n\("Today"\), snapshot.sessionCost,\s*'
                         r'snapshot.sessionTokens, currency\)', present_cost_body):
            raise AssertionError("Today must not inherit history-level trust qualifiers")

    def test_provider_cost_section(self):
        provider_cost_body = function_body(main_text, "providerCostSection")
        if not code_contains(provider_cost_body, "ProviderCostPresentation.section(providerID, cost)"):
            raise AssertionError("provider cost must use the tested semantic section")
        direct_number_call = re.compile(r"(?<![A-Za-z0-9_])Number\(")
        if direct_number_call.search(provider_cost_body):
            raise AssertionError("provider cost must not use loose numeric coercion")
        provider_cost_presentation = (root / "contents/ui/ProviderCostPresentation.js").read_text()
        for forbidden in ("root.", "Plasmoid.", "i18n(", "i18np(", "Qt."):
            if forbidden in provider_cost_presentation:
                raise AssertionError("provider cost decisions must be pure: " + forbidden)
        reset_credits_body = function_body(main_text, "resetCreditsSection")
        for field in ("cost.used", "cost.limit", "cost.personalUsed", "resetCredits.availableCount"):
            if field in provider_cost_body + reset_credits_body:
                raise AssertionError("numeric cost/credit decisions must stay in the semantic module: " + field)


if __name__ == "__main__":
    unittest.main()
