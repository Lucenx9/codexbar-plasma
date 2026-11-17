"""Static UI checks for popup geometry, shared surfaces and headers."""

import re
import unittest

from ui_regression_support import (
    Surface,
    code_contains,
    id_block,
    provider_header_qml,
    providers_qml,
    root,
    sessions_view_qml,
    spend_view_qml,
)


class PopupGeometryTest(unittest.TestCase):
    def setUp(self):
        self.applet = Surface("applet", root)
        self.providers_text = providers_qml.read_text(encoding="utf-8")
        self.sessions_view_text = sessions_view_qml.read_text(encoding="utf-8")

    def test_top_level_cards_match_overview_geometry(self):
        # Sessions retain the Overview card geometry; analysis uses compact action rows.
        fragments = (
            "radius: view.applet.roundedSurfaceRadius",
            "anchors.leftMargin: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing",
            "anchors.rightMargin: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing",
        )
        for card_text in (self.sessions_view_text,):
            missing = [fragment for fragment in fragments if not code_contains(card_text, fragment)]
            self.assertEqual(missing, [], "cards must match overview card geometry")

    def test_scroll_content_uses_native_width_and_single_gutter(self):
        for scroll_id in ("overviewScroll", "providerScroll"):
            scroll_body = id_block(self.applet.text, scroll_id)
            self.assertTrue(
                code_contains(scroll_body, "contentWidth: availableWidth"),
                f"{scroll_id} content width must follow Plasma ScrollView availableWidth",
            )
            self.assertTrue(
                code_contains(scroll_body, f"{scroll_id}.availableWidth - Kirigami.Units.smallSpacing"),
                f"{scroll_id} must retain one quiet content inset before its scrollbar",
            )
            for stale_scroll_gutter in (
                "readonly property real contentRightInset:",
                "rightPadding: contentRightInset",
            ):
                self.assertNotIn(
                    stale_scroll_gutter,
                    scroll_body,
                    f"{scroll_id} must not restore the doubled desktop scrollbar gutter",
                )
        self.assertGreaterEqual(
            self.applet.text.count("PlasmaComponents.ScrollView {"),
            2,
            "popup content must use Plasma-native scroll views",
        )
        self.assertNotIn(
            "Controls.ScrollView {",
            self.applet.text,
            "popup content must not restore desktop-framed scroll views",
        )

    def test_surfaces_and_compact_meters_follow_theme_units(self):
        self.assertTrue(
            code_contains(self.applet.text, "readonly property real roundedSurfaceRadius: Kirigami.Units.cornerRadius"),
            "main.qml must derive its polished radius from Kirigami theme units",
        )
        self.assertTrue(
            code_contains(self.applet.text, "readonly property real nestedSurfaceRadius: Kirigami.Units.cornerRadius"),
            "main.qml must expose a concentric radius for surfaces nested inside a "
            "roundedSurfaceRadius container",
        )
        self.assertTrue(
            code_contains(self.applet.text, "readonly property real compactMeterTrackHeight: Math.round(Kirigami.Units.gridUnit"),
            "list-row meters must derive their thinner track from gridUnit instead of "
            "pinning a device pixel count",
        )

    def test_section_headings_outrank_metric_labels(self):
        # Section headings sit above metric rows that are already DemiBold. A Normal
        # weight heading therefore reads as less important than its own content, so the
        # structural labels stay Primary and the size scale carries the ranking.
        heading_chunks = self.applet.text.split("PlainHeading {")[1:]
        self.assertGreaterEqual(len(heading_chunks), 5, "main.qml must keep its popup section headings")
        for heading_chunk in heading_chunks:
            if "type: Kirigami.Heading.Type.Primary" not in heading_chunk[:300]:
                heading_head = heading_chunk.strip().splitlines()[0].strip()
                raise AssertionError(
                    "popup section headings must outrank the DemiBold metric labels they "
                    f"introduce; heading starting {heading_head!r} is not Primary"
                )

    def test_popup_uses_native_dialog_frame_and_framed_tabs(self):
        # The Plasma dialog already frames the popup. An inner outline nests a card
        # inside it, and a separator under the framed tab strip adds a third line.
        self.assertNotIn(
            "popupInnerSurface",
            self.applet.text,
            "the popup must sit on the native dialog background, not an inner frame",
        )
        self.assertEqual(
            id_block(self.applet.text, "providerTabsBar").count(
            "Kirigami.Separator {"),
            0,
            "the framed tab strip must not add a separator beneath it",
        )

    def test_populated_views_share_height_and_empty_states_size_to_content(self):
        self.assertTrue(
            code_contains(self.applet.text, "fullRepresentation:"),
            "the applet must keep a fullRepresentation root",
        )
        full_representation_head = id_block(self.applet.text, "fullRoot")
        self.assertIn(
            "standardHeightActive",
            full_representation_head,
            "every popup content section must share one standard height; "
            "per-section content heights resize the dialog on each tab switch",
        )
        self.assertIn(
            "popupContent.implicitHeight",
            full_representation_head,
            "the content-less popup states must stay compact and content-driven "
            "instead of inheriting the standard section height",
        )
        self.assertFalse(
            re.search(r"implicitHeight:\s*Kirigami\.Units\.gridUnit\s*\*\s*\d", full_representation_head),
            "the popup must not pin implicitHeight to a grid-unit constant; the "
            "constants belong in the named minimum/maximum height properties",
        )

    def test_presentation_scale_stays_shared_with_settings(self):
        # Text de-emphasis had drifted into eleven ad-hoc opacity literals, several
        # below the WCAG AA 4.5:1 floor for Kirigami.Theme.textColor on Breeze Light.
        # Keep the scale in one place so a new section cannot reintroduce a dimmer step.
        for token_definition in (
            "readonly property real secondaryTextOpacity: 0.7",
            "readonly property real valueTextOpacity: 0.85",
            "readonly property real meterTrackHeight: Math.round(Kirigami.Units.gridUnit * 0.4)",
        ):
            self.assertTrue(
                code_contains(self.applet.text, token_definition),
                f"main.qml must define the shared presentation scale: {token_definition!r}",
            )
        self.assertTrue(
            code_contains(self.providers_text, "readonly property real secondaryTextOpacity: 0.7"),
            "configProviders.qml must mirror main.qml's secondaryTextOpacity step",
        )


class PopupHeadersTest(unittest.TestCase):
    def setUp(self):
        self.applet = Surface("applet", root)
        self.provider_header_text = provider_header_qml.read_text(encoding="utf-8")
        self.sessions_view_text = sessions_view_qml.read_text(encoding="utf-8")
        self.spend_view_text = spend_view_qml.read_text(encoding="utf-8")

    def test_header_actions_align_with_inset_and_top(self):
        header_sources = {
            "overviewHeaderRow": self.applet.text,
            "providerHeaderRow": self.provider_header_text,
            "spendHeaderRow": self.spend_view_text,
            "sessionsHeaderRow": self.sessions_view_text,
        }
        for header_id, source_text in header_sources.items():
            header_body = id_block(source_text, header_id)
            self.assertTrue(
                code_contains(header_body, "Layout.rightMargin: Kirigami.Units.smallSpacing"),
                f"{header_id} must align header actions with the inset scroll content",
            )
            self.assertTrue(
                code_contains(header_body, "Layout.alignment: Qt.AlignTop"),
                f"{header_id} must align header action buttons to top",
            )

    def test_overview_and_provider_headers_share_busy_refresh_control(self):
        overview_header_body = id_block(self.applet.text, "overviewHeaderRow")
        provider_header_body = id_block(self.provider_header_text, "providerHeaderRow")
        for header_id, header_body in (
            ("overviewHeaderRow", overview_header_body),
            ("providerHeaderRow", provider_header_body),
        ):
            self.assertTrue(
                code_contains(header_body, "RefreshButton {"),
                f"{header_id} must use the shared refresh control; missing 'RefreshButton {{'",
            )
            self.assertTrue(
                code_contains(header_body, "busy:"),
                f"{header_id} must give the shared refresh control busy feedback; missing 'busy:'",
            )

    def test_refresh_control_preserves_footprint_without_owning_effects(self):
        refresh_control_body = self.applet.id_block("refreshControl")
        for fragment in (
            "implicitWidth: refreshButton.implicitWidth",
            "implicitHeight: refreshButton.implicitHeight",
            "if (!refreshControl.busy)",
            "visible: refreshControl.busy",
            "running: visible",
            "Accessible.name: refreshControl.label",
            "delay: Kirigami.Units.toolTipDelay",
        ):
            self.assertTrue(
                code_contains(refresh_control_body, fragment),
                f"refresh controls must retain their footprint and feedback: {fragment}",
            )
        for effect in ("refreshNow(", "refreshCost(", "refreshSessions("):
            self.assertNotIn(
                effect,
                refresh_control_body,
                "the shared refresh control must leave effects in its owning view",
            )

    def test_history_refresh_actions_keep_scoped_busy_feedback(self):
        for fragment in (
            "busy: view.applet.costLoading",
            "busy: view.applet.sessionsLoading",
            "onRequested: view.applet.refreshCost(true)",
            "onRequested: view.applet.refreshSessions()",
        ):
            self.applet.require(fragment, "history and sessions must retain scoped refresh feedback and actions")

    def test_provider_header_exposes_stable_identity_structure(self):
        provider_header_body = id_block(self.provider_header_text, "providerHeaderRow")
        for header_fragment in (
            "id: providerIdentitySurface",
            "id: providerHeaderIcon",
            "id: providerTitleRow",
            "id: providerMetaRow",
            "id: providerAccountLabel",
            "id: providerPlanLabel",
        ):
            self.assertTrue(
                code_contains(provider_header_body, header_fragment),
                f"providerHeaderRow must expose {header_fragment} for stable header layout",
            )

    def test_provider_identity_uses_canonical_icon_theme_color_and_heading(self):
        provider_header_body = id_block(self.provider_header_text, "providerHeaderRow")
        self.assertTrue(
            code_contains(provider_header_body, "providerIconSource(providerHeaderRow.providerData.provider)"),
            "providerHeaderRow must reinforce provider identity with the canonical icon",
        )
        self.assertTrue(
            code_contains(provider_header_body, "providerReadableColor("),
            "providerHeaderRow must keep provider identity visible on the active theme",
        )
        self.assertTrue(
            code_contains(provider_header_body, "radius: providerHeaderRow.applet.nestedSurfaceRadius"),
            "providerHeaderRow must share the nested rounded surface scale",
        )
        self.assertTrue(
            code_contains(provider_header_body, "type: Kirigami.Heading.Type.Primary"),
            "the provider title must stay the heaviest label in the detail view so "
            "the section headings below it never outrank it",
        )

    def test_provider_account_label_fills_without_outgrowing_text(self):
        provider_account_label_body = id_block(self.provider_header_text, "providerAccountLabel")
        for account_label_fragment in (
            # Filling with a cap at the label's own text lets the account elide on
            # narrow popups while never stretching past the email it shows.
            "Layout.fillWidth: true",
            "Layout.maximumWidth: Math.ceil(implicitWidth)",
        ):
            self.assertTrue(
                code_contains(provider_account_label_body, account_label_fragment),
                "providerAccountLabel must fill without outgrowing its text and "
                f"cap long account text before the refresh edge; "
                f"missing {account_label_fragment!r}",
            )
        self.assertFalse(
            "providerHeaderRow.width" in provider_account_label_body or "providerMetaRow.width" in provider_account_label_body,
            "providerAccountLabel must not bind its width to the header layout width",
        )

    def test_provider_plan_label_caps_to_implicit_width(self):
        provider_plan_label_body = id_block(self.provider_header_text, "providerPlanLabel")
        self.assertTrue(
            code_contains(provider_plan_label_body, "Layout.fillWidth: true"),
            "providerPlanLabel must fill available space beside account",
        )
        self.assertTrue(
            code_contains(provider_plan_label_body, "Layout.maximumWidth: Math.ceil(implicitWidth)"),
            "providerPlanLabel must cap at implicitWidth to avoid rounding false truncation",
        )

    def test_provider_identity_and_updated_time_use_separate_lines(self):
        self.assertNotIn(
            "providerUpdatedLabel",
            self.applet.id_block("providerMetaRow"),
            "account identity and the update timestamp must have separate lines",
        )


if __name__ == "__main__":
    unittest.main()
