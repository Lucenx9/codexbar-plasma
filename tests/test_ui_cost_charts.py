"""Static UI checks for shared cost chart geometry and inspection."""

import unittest

from ui_regression_support import (
    Surface,
    code_contains,
    function_body,
    interactive_chart_qml,
    root,
    spend_view_qml,
)


# Surface checks follow the applet owner across extracted popup components.
class InteractiveChartTest(unittest.TestCase):
    def setUp(self):
        self.applet = Surface("applet", root)
        self.chart_text = interactive_chart_qml.read_text(encoding="utf-8")
        self.spend_text = spend_view_qml.read_text(encoding="utf-8")

    def test_detail_bars_use_shared_rounded_geometry(self):
        self.assertTrue(
            code_contains(self.chart_text, "CostChart.paintRoundedTopBar("),
            "provider detail bar charts must use rounded top corners",
        )
        for detail_chart_fragment in (
            "chart.barGradient(",
            "CostChart.chartBarGeometry(width, chart.pointCount)",
            "ChartScale.barGeometry(height,",
        ):
            self.assertTrue(
                code_contains(self.chart_text, detail_chart_fragment),
                "provider detail bar charts must retain the polished cost-chart language; "
                f"missing {detail_chart_fragment!r}",
            )

    def test_detail_charts_preserve_signed_values_and_zero_baseline(self):
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
            self.applet.require(signed_chart_fragment, "detail charts must retain signed values and their zero baseline")

    def test_detail_bars_use_restrained_gradient(self):
        chart_gradient_body = function_body(self.chart_text, "barGradient")
        for gradient_fragment in (
            "context.createLinearGradient",
            "gradient.addColorStop(0",
            "gradient.addColorStop(1",
        ):
            self.assertTrue(
                code_contains(chart_gradient_body, gradient_fragment),
                "vertical bar charts must use the shared restrained gradient; "
                f"missing {gradient_fragment!r}",
            )

    def test_provider_sparkline_uses_shared_chart_and_cost_points(self):
        self.assertTrue(
            code_contains(self.applet.text, "Components.InteractiveChart"),
            "the provider cost sparkline must use the interactive shared chart; "
            "missing 'Components.InteractiveChart'",
        )
        self.assertTrue(
            code_contains(self.applet.text, "applet.costChartPoints("),
            "the provider cost sparkline must plot the applet cost chart points; "
            "missing 'applet.costChartPoints('",
        )

    def test_detail_bars_apply_shared_pitch_and_offset(self):
        for label, source_text in (
            ("InteractiveChart.qml", self.chart_text),
        ):
            self.assertTrue(
                code_contains(source_text, "CostChart.chartBarGeometry("),
                f"{label} bar charts must use the shared geometry helper",
            )
            self.assertNotIn(
                "barWidth + gap",
                source_text,
                f"{label} bar charts must not recompute their own bar pitch",
            )
        self.assertTrue(
            code_contains(self.chart_text, "geometry.offset + barIndex * geometry.step"),
            "provider detail bars must apply the shared canvas offset",
        )

    def test_detail_line_markers_use_shared_inset_geometry(self):
        # The active line-chart point grows to a 3.5px radius. Both axes and pointer hit
        # testing must use the shared inset geometry so the visible marker stays inside
        # Canvas and resolves back to its own point.
        for helper_name in ("chartLineX", "chartLineIndexAt", "chartLineY"):
            self.assertTrue(
                code_contains(self.chart_text, f"CostChart.{helper_name}("),
                f"provider detail line charts must use {helper_name}",
            )

    def test_interactive_chart_supports_pointer_and_keyboard(self):
        for chart_interaction_fragment in (
            "activeFocusOnTab: true",
            "Keys.onPressed:",
            "onPositionChanged:",
            "selectedIndex",
        ):
            self.assertTrue(
                code_contains(self.chart_text, chart_interaction_fragment),
                "InteractiveChart must support pointer and keyboard inspection; "
                f"missing {chart_interaction_fragment!r}",
            )
        self.assertTrue(
            code_contains(self.chart_text, "readonly property bool hasActivePoint"),
            "InteractiveChart must expose whether a point is active",
        )

    def test_chart_readout_retains_text_and_space_during_fade(self):
        self.assertNotIn(
            "visible: chart.activeIndex",
            self.chart_text,
            "InteractiveChart must reserve readout space while pointer state changes",
        )
        self.assertTrue(
            code_contains(self.chart_text, "opacity: chart.hasActivePoint || chart.peakIndex >= 0 ? 1 : 0"),
            "the chart readout must fade with the active point instead of blinking",
        )
        self.assertTrue(
            code_contains(self.chart_text, "onActiveIndexChanged: if (activeIndex >= 0 && activeIndex < pointCount)"),
            "the chart readout must retain the last inspected point across the fade-out, and must "
            "bounds-check inline: hasActivePoint is still stale inside an activeIndex change handler",
        )
        self.assertNotIn(
            "chart.hasActivePoint ? chart.pointLabel",
            self.chart_text,
            "the chart readout text must not clear on hasActivePoint: that empties the row "
            "on the same signal that starts the fade, so hover exit blinks instead of fading",
        )

    def test_inactive_chart_readout_leaves_accessibility_tree(self):
        self.assertEqual(
            self.chart_text.count("Accessible.ignored: !chart.hasActivePoint"),
            2,
            "both retained chart readout labels must leave the accessibility tree when no point is "
            "active: the text outlives the fade and a zero opacity does not hide it from a screen reader",
        )

    def test_chart_text_is_localized(self):
        for localized_pair_source, localized_pair_text in (
            ("InteractiveChart.qml", self.chart_text),
            ("SpendView.qml", self.spend_text),
        ):
            self.assertNotIn(
                '+ ": " +',
                localized_pair_text,
                f"{localized_pair_source} must localize label/value separators with placeholders",
            )


if __name__ == "__main__":
    unittest.main()
