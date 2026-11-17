"""Static UI checks for Overview selection, provider identity and interaction."""

import unittest

from ui_regression_support import (
    Surface,
    code_contains,
    function_body,
    id_block,
    overview_provider_row_qml,
    root,
)


class OverviewSelectionTest(unittest.TestCase):
    def setUp(self):
        self.applet = Surface("applet", root)

    def test_overview_selection_shares_alias_filtering(self):
        # Overview selection stores canonical provider IDs (legacy raw CLI spellings,
        # e.g. groqcloud, alibaba-coding-plan, still resolve) matched at runtime
        # against providerKey-normalized IDs (groq, alibaba). The applet must resolve
        # the stored value through OverviewProviders, the module the settings page
        # uses, so the custom selection is not silently ignored for aliased providers.
        overview_body = function_body(self.applet.text, "overviewProviders")
        self.assertTrue(
            code_contains(overview_body, "OverviewProviders.visibleItems(providers, overviewProviderIDsRaw)"),
            "the Overview rows must share filtering and parsing with the settings page so "
            "aliased providers match runtime keys",
        )
        for retired_overview_fragment in ("maxOverviewProviders", "configuredOverviewProviderIDs"):
            self.assertNotIn(
                retired_overview_fragment,
                self.applet.text,
                "the Overview limit and selection parsing belong to OverviewProviders: "
                + retired_overview_fragment,
            )

    def test_overview_detail_prioritizes_identity_and_active_incidents(self):
        overview_detail_body = function_body((root / "contents/ui/OverviewProviders.js").read_text(encoding="utf-8"), "detailText")
        for overview_detail_fragment in (
            "item.hasIncident === true && item.statusKnown !== false",
            "item.account && item.account.length > 0",
        ):
            self.assertTrue(
                code_contains(overview_detail_body, overview_detail_fragment),
                "the overview detail line stands for account identity; only an active "
                "incident may replace it, never an operational status; "
                f"missing {overview_detail_fragment!r}",
            )

    def test_overview_meters_use_popup_candidates(self):
        # tst_panel_display covers the meter selection; the applet must feed it the
        # popup candidates, not the panel's lane choice.
        self.assertTrue(
            code_contains(function_body(self.applet.text, "overviewMeterRows"),
            "PanelDisplay.overviewMeterRows(switcherCandidateRows(item))"),
            "Overview meters must ignore the panel's quota lane choice",
        )

    def test_overview_items_are_cached_in_property_binding(self):
        self.assertTrue(
            code_contains(self.applet.text, "readonly property var overviewProviderItems: overviewProviders()"),
            "overview provider rows must be cached in a QML property binding",
        )
        self.assertNotIn(".overviewProviders()", self.applet.text, "overview UI bindings must reuse overviewProviderItems")

    def test_monthly_credit_limit_keeps_partial_provider_eligible(self):
        overview_providers_js = (root / "contents/ui/OverviewProviders.js").read_text()
        overview_error_only_body = function_body(overview_providers_js, "isErrorOnly")
        self.assertTrue(
            code_contains(overview_error_only_body, "item.codexCreditLimit === null"),
            "a valid Codex monthly limit must keep a partially healthy provider overview-eligible",
        )

    def test_overview_selection_modules_remain_pure(self):
        overview_providers_js = (root / "contents/ui/OverviewProviders.js").read_text()
        # Direct QtTests cover eligibility, the stored selection, and the automatic
        # ranking. Both modules stay pure so those cases describe the runtime.
        auto_select_js = (root / "contents/ui/ProviderAutoSelect.js").read_text()
        for pure_module_text in (overview_providers_js, auto_select_js):
            for forbidden in ("root.", "Plasmoid.", "Qt.", "i18n(", "i18np(", "Date.now("):
                self.assertNotIn(
                    forbidden,
                    pure_module_text,
                    "Overview filtering and automatic selection must stay pure: " + forbidden,
                )


class OverviewRowsTest(unittest.TestCase):
    def setUp(self):
        self.applet = Surface("applet", root)
        self.overview_provider_row_text = overview_provider_row_qml.read_text(encoding="utf-8")

    def test_overview_rows_fit_content_and_distinguish_keyboard_focus(self):
        overview_row_body = id_block(self.overview_provider_row_text, "overviewRow")
        for fragment in (
            "implicitHeight: overviewRowContent.implicitHeight + Kirigami.Units.largeSpacing * 2",
            "Layout.preferredHeight: implicitHeight",
            "readonly property bool keyboardFocusVisible: overviewRowFocus.visualFocus",
            "border.width: overviewRow.keyboardFocusVisible ? 1 : 0",
            "overviewRowFocus.forceActiveFocus(Qt.MouseFocusReason)",
        ):
            self.assertTrue(
                code_contains(overview_row_body, fragment),
                f"overview rows must fit their content and distinguish keyboard focus: {fragment}",
            )

    def test_overview_rows_keep_quiet_unframed_resting_surface(self):
        overview_row_body = id_block(self.overview_provider_row_text, "overviewRow")
        self.assertTrue(
            code_contains(overview_row_body, "applet.withAlpha(Kirigami.Theme.textColor, 0.035)"),
            "overview rows must keep a quiet neutral resting surface",
        )
        overview_row_surface_bindings = overview_row_body.split("RowLayout {", 1)[0]
        self.assertNotIn(
            "border.width",
            overview_row_surface_bindings,
            "overview rows must not regress to a stack of outlined cards",
        )

    def test_overview_identity_uses_shared_rounded_treatment(self):
        overview_row_body = id_block(self.overview_provider_row_text, "overviewRow")
        for polished_overview_fragment in (
            "radius: applet.roundedSurfaceRadius",
            "id: overviewProviderIdentitySurface",
            "radius: overviewRow.applet.nestedSurfaceRadius",
            "applet.withAlpha(overviewRow.accent, 0.12)",
            "border.color: overviewRow.applet.withAlpha(Kirigami.Theme.textColor, 0.1)",
        ):
            self.assertTrue(
                code_contains(overview_row_body, polished_overview_fragment),
                "overview rows must retain the rounded provider identity treatment; "
                f"missing {polished_overview_fragment!r}",
            )

    def test_overview_rows_preserve_accessible_interaction(self):
        overview_row_body = id_block(self.overview_provider_row_text, "overviewRow")
        for interaction_fragment in (
            "activeFocusOnTab: true",
            "Accessible.role: Accessible.Button",
            "Accessible.onPressAction:",
            "Keys.onPressed:",
            "scale:",
        ):
            self.assertTrue(
                code_contains(overview_row_body, interaction_fragment),
                "overview rows must preserve keyboard, assistive, and pressed feedback; "
                f"missing {interaction_fragment!r}",
            )

    def test_overview_rows_use_supported_focus_transition(self):
        self.assertNotIn(
            ".focusReason =",
            self.applet.id_block("overviewRowMouse"),
            "overview rows must use a supported focus transition",
        )


if __name__ == "__main__":
    unittest.main()
