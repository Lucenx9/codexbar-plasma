"""Static UI checks for the compact panel representation and its tooltip."""

import re
import unittest

from ui_regression_support import (
    Surface,
    code_contains,
    compact_representation_qml,
    function_body,
    id_block,
    root,
)

# The popup UI rules below belong to the plasmoid surface, not to main.qml
# specifically, so read the surface as one text. Extracting the popup into a
# component keeps these assertions meaningful instead of silently unhooking them.
applet = Surface("applet", root)
main_text = applet.text
compact_representation_text = compact_representation_qml.read_text(encoding="utf-8")


class PanelTest(unittest.TestCase):
    def test_compact_controls_do_not_consume_clicks(self):
        for mouse_id in ("compactStatusMouse", "heatmapMouse"):
            mouse_body = applet.id_block(mouse_id)
            if not re.search(r"(?m)^[ \t]*acceptedButtons:[ \t]*(?:Qt\.NoButton|\(0\))[ \t]*;?[ \t]*(?://[^\n]*)?$", mouse_body):
                raise AssertionError(f"{mouse_id} must not consume clicks")
        for vertical_fragment in (
            "readonly property bool verticalPanel: applet.verticalFormFactor",
            "columns: compactRoot.verticalPanel ? 1 : -1",
            "!compactRoot.verticalPanel",
        ):
            if not code_contains(compact_representation_text, vertical_fragment):
                raise AssertionError(
                    "CompactRepresentation must show vertical meters with an icon fallback; "
                    f"missing {vertical_fragment!r}"
                )

    def test_compact_layout_scales_with_panel(self):
        compact_row_body = id_block(compact_representation_text, "compactRow")
        for centering_fragment in (
            "anchors.centerIn: parent",
            "implicitWidth))",
        ):
            if not code_contains(compact_row_body, centering_fragment):
                raise AssertionError(
                    "the compact row must stay centred when the panel reserves more width "
                    f"than the content needs; missing {centering_fragment!r}"
                )
        if "anchors.fill: parent" in compact_row_body:
            raise AssertionError("the compact row must not stretch its content to the reserved panel width again")

        compact_meter_body = id_block(compact_representation_text, "compactMeter")
        for meter_fragment in (
            "Layout.preferredWidth: compactRoot.meterWidth",
            "Layout.preferredWidth: compactRoot.meterIconSize",
            "Layout.preferredHeight: compactRoot.meterIconSize",
            "Layout.preferredHeight: compactRoot.meterBarHeight",
        ):
            if not code_contains(compact_meter_body, meter_fragment):
                raise AssertionError(
                    "panel provider meters must scale with the panel instead of using "
                    f"fixed pixel sizes; missing {meter_fragment!r}"
                )
        for provider_click_fragment in (
            "id: compactMeterMouse",
            "anchors.fill: parent",
            "function activate()",
            "activeFocusOnTab: compactRoot.interactive",
            "visible: compactMeter.activeFocus",
            "Accessible.role: compactRoot.interactive ? Accessible.Button : Accessible.Graphic",
            "Accessible.name: compactRoot.interactive ? i18n(\"Open %1\", modelData.title) : modelData.title",
            "Accessible.onPressAction: compactMeter.activate()",
            "Keys.onPressed:",
            "case Qt.Key_Space:",
            "case Qt.Key_Enter:",
            "compactRoot.applet.openProviderFromPanel(compactMeter.modelData.provider)",
            "onClicked: compactMeter.activate()",
        ):
            if not code_contains(compact_meter_body, provider_click_fragment):
                raise AssertionError(
                    "each panel provider meter must be keyboard- and assistive-accessible "
                    "and open its matching provider tab; "
                    f"missing {provider_click_fragment!r}"
                )
        if not code_contains(compact_representation_text, "property bool interactive: true"):
            raise AssertionError("the live panel must keep interaction enabled by default")
        if "if (!compactRoot.interactive)" not in function_body(compact_meter_body, "activate"):
            raise AssertionError("preview meters must not dispatch provider selection")
        for mouse_id in ("compactMeterMouse", "compactStatusMouse"):
            if "enabled: compactRoot.interactive" not in id_block(compact_representation_text, mouse_id):
                raise AssertionError("preview meter and status pointer input must be disabled")
        root_pointer_body = id_block(compact_representation_text, "compactBackgroundMouse")
        if not code_contains(root_pointer_body, "enabled: compactRoot.interactive"):
            raise AssertionError("the compact background must not open a popup in preview mode")
        if "forceActiveFocus(Qt.MouseFocusReason)" in compact_meter_body:
            raise AssertionError(
                "a mouse click on a panel meter must not leave the keyboard focus ring active"
            )
        if "Controls.ToolTip" in compact_meter_body:
            raise AssertionError(
                "panel meters must rely on the plasmoid tooltip instead of stacking a second tooltip"
            )
        for meter_hover_fragment in (
            "onContainsMouseChanged",
            "compactRoot.applet.setHoveredPanelProvider(compactMeter.modelData.provider)",
            "compactRoot.applet.clearHoveredPanelProvider(compactMeter.modelData.provider)",
        ):
            if not code_contains(compact_meter_body, meter_hover_fragment):
                raise AssertionError(
                    "hovering a panel provider meter must narrow the plasmoid tooltip "
                    "to that provider; "
                    f"missing {meter_hover_fragment!r}"
                )
        for meter_cleanup_fragment in (
            "onMeterProvidersChanged",
            "compactRoot.applet.clearHoveredPanelProvider(hovered)",
        ):
            if not code_contains(compact_representation_text, meter_cleanup_fragment):
                raise AssertionError(
                    "a hovered meter filtered out of the rendered set must clear its "
                    "stale hover instead of relying on a destroyed MouseArea; "
                    f"missing {meter_cleanup_fragment!r}"
                )

    def test_panel_provider_selection(self):
        compact_provider_body = applet.function_body("selectedCompactProvider")
        for compact_selection_fragment in (
            "providers.length === 0",
            "return null",
            "PopupSelection.compactPanelProvider(",
            "panelProviderItems()",
            "autoSelectedProviderIndex(panelItems)",
        ):
            if not code_contains(compact_provider_body, compact_selection_fragment):
                raise AssertionError(
                    "compact provider selection must adapt the panel-filtered roster and "
                    "popup selection through PopupSelection; "
                    f"missing {compact_selection_fragment!r}"
                )

        # The panel provider selection is presentation-only: meters, text, and the
        # tooltip roster narrow through the same pure filter, while fetching and
        # notifications keep the full provider list.
        compact_providers_body = applet.function_body("compactProviders")
        for panel_filter_fragment in (
            "panelProviderItems()",
            "PanelProviders.maximumSelectableProviders",
        ):
            if not code_contains(compact_providers_body, panel_filter_fragment):
                raise AssertionError(
                    f"compactProviders must apply the panel provider selection; missing {panel_filter_fragment!r}"
                )

        open_panel_provider_body = function_body(main_text, "openProviderFromPanel")
        for panel_selection_fragment in (
            "providerIndexForID(providerID)",
            "selectedProviderID = providers[index].provider",
            "selectionInitialized = true",
            "expanded = true",
        ):
            if not code_contains(open_panel_provider_body, panel_selection_fragment):
                raise AssertionError(
                    "panel meter selection must stay in the applet state owner; "
                    f"missing {panel_selection_fragment!r}"
                )
        if not code_contains(compact_representation_text, "readonly property int meterContentHeight: Math.max(0, height"):
            raise AssertionError("panel meter geometry must derive from the compact representation height")
        if not code_contains(compact_representation_text, "compactRoot.meterProviders.length * compactRoot.meterWidth"):
            raise AssertionError("the meters element must reserve panel width from the shared meter width")

    def test_incident_badges(self):
        vertical_status_badge_body = id_block(compact_representation_text, "compactVerticalStatusBadge")
        for vertical_badge_fragment in (
            "objectName: \"panelIdentityBadge\"",
            "visible: compactRoot.identityCarriesIncidentBadge",
            "!compactRoot.applet.loading",
            "statusBadgeColor(compactRoot.selectedProvider.statusSeverity)",
            "border.width: 1",
            "border.color: Kirigami.Theme.backgroundColor",
        ):
            if not code_contains(vertical_status_badge_body, vertical_badge_fragment):
                raise AssertionError(
                    "without meters the identity icon may badge only its own provider's "
                    "incident, never another provider's outage; "
                    f"missing {vertical_badge_fragment!r}"
                )

        for vertical_anchor_fragment in (
            "readonly property bool identityCarriesIncidentBadge: verticalPanel",
            "!hasProviderMeters",
            "incidentProvider !== null",
            "incidentProvider.provider === selectedProvider.provider",
        ):
            if not code_contains(compact_representation_text, vertical_anchor_fragment):
                raise AssertionError(
                    "the identity badge anchor must be limited to the selected "
                    "provider's own incident so a foreign outage keeps the standalone "
                    f"fallback; missing {vertical_anchor_fragment!r}"
                )

        # One rule, shared by the element loader, the badge itself, and the text width
        # budget that has to reserve the slot the badge occupies.
        for status_rule_fragment in (
            "readonly property bool statusElementVisible: (!verticalPanel || hasProviderMeters",
            "|| !identityCarriesIncidentBadge)",
            "incidentProvider.hasIncident",
            "!incidentProviderHasMeterBadge",
        ):
            if not code_contains(compact_representation_text, status_rule_fragment):
                raise AssertionError(
                    "the standalone status element is a fallback: when a meter can carry "
                    "the badge, the ambiguous floating dot must hide; missing "
                    f"{status_rule_fragment!r}"
                )

        horizontal_status_badge_body = id_block(compact_representation_text, "compactStatusBadge")
        for horizontal_badge_fragment in (
            "visible: compactRoot.statusElementVisible",
            "statusBadgeColor(compactRoot.incidentProvider.statusSeverity)",
            "border.width: 1",
            "border.color: Kirigami.Theme.backgroundColor",
        ):
            if not code_contains(horizontal_status_badge_body, horizontal_badge_fragment):
                raise AssertionError(
                    "the standalone status element is a fallback: when a meter can carry "
                    "the badge, the ambiguous floating dot must hide; "
                    f"missing {horizontal_badge_fragment!r}"
                )

        meter_incident_badge_body = id_block(compact_representation_text, "meterIncidentBadge")
        for meter_badge_fragment in (
            "objectName: \"panelIncidentBadge\"",
            # Starting the predicate with the incident flags pins that a refresh
            # (loading with retained providers) must not hide the meter badge.
            "visible: compactMeter.modelData.hasIncident === true",
            "compactMeter.modelData.statusKnown !== false",
            "statusBadgeColor(compactMeter.modelData.statusSeverity)",
            "border.width: 1",
            "border.color: Kirigami.Theme.backgroundColor",
        ):
            if not code_contains(meter_incident_badge_body, meter_badge_fragment):
                raise AssertionError(
                    "each provider meter must badge its own incident so reordering the "
                    "providers moves the outage marker with it; "
                    f"missing {meter_badge_fragment!r}"
                )

    def test_panel_tooltip(self):
        for tooltip_fragment in (
            "toolTipMainText: Plasmoid.title",
            "toolTipSubText: panelToolTipText()",
            "toolTipTextFormat: Text.PlainText",
            "function panelProviderToolTipText(",
            "function panelToolTipText()",
            "Plasmoid.formFactor === PlasmaCore.Types.Vertical",
        ):
            if not code_contains(main_text, tooltip_fragment):
                raise AssertionError(f"the panel tooltip/form-factor contract is missing {tooltip_fragment!r}")

        provider_tooltip_body = applet.function_body("providerToolTipText")
        tooltip_plan = applet.function_body("providerTooltip")
        if not re.search(r"item\.hasIncident\s*&&\s*item\.statusKnown !== false\s*&&", tooltip_plan):
            raise AssertionError("panel tooltips must exclude inactive and unknown incidents")
        if not code_contains(provider_tooltip_body, 'i18n("%1 - %2", line, parts.incident)'):
            raise AssertionError("panel tooltip localization must retain current incidents")
        panel_text = applet.id_block("panelText")
        if not code_contains(panel_text, "showCredits: Plasmoid.configuration.showCreditsInPanel"):
            raise AssertionError("panel text must follow the configured credit visibility")
        if not code_contains(provider_tooltip_body, 'i18n("%1cr"'):
            raise AssertionError("the tooltip must report the balance the panel can surrender")
        compact_segments_body = function_body(main_text, "compactTextSegments")
        if not code_contains(compact_segments_body, "providerIconIdentifies(item.provider)"):
            raise AssertionError("segment identity must follow the selected provider's icon")
        applet.require("identifying: !options.iconIdentifies", "unidentified names remain recoverable")
        if not code_contains(function_body(main_text, "panelProviderToolTipText"),
                             "panelText.providerToolTipText(presented, panelMeterDescription(presented))"):
            raise AssertionError("tooltip presentation must receive the privacy-filtered provider")
        if "providerBrandColorChannels" not in function_body(main_text, "providerIconIdentifies"):
            raise AssertionError(
                "icon identification must follow the bundled provider tables, not a guess"
            )
        for hover_helper in (
            "property string hoveredPanelProviderID",
            "function setHoveredPanelProvider(",
            "function clearHoveredPanelProvider(",
            "function hoveredPanelProvider(",
            "function panelProviderToolTipText(",
        ):
            if not code_contains(main_text, hover_helper):
                raise AssertionError(
                    "the panel tooltip must track the hovered provider meter; "
                    f"missing {hover_helper!r}"
                )
        hovered_provider_body = function_body(main_text, "hoveredPanelProvider")
        if not code_contains(hovered_provider_body, "compactProviders()"):
            raise AssertionError(
                "the hovered provider lookup must stay limited to rendered meters, "
                "since visibility rules can filter a meter out while its provider "
                "remains in the roster"
            )
        tooltip_body = function_body(main_text, "panelToolTipText")
        if not code_contains(tooltip_body, "hoveredPanelProvider()"):
            raise AssertionError("hovering a panel meter must narrow the tooltip to that provider")
        if not code_contains(tooltip_body, "panelProviderItems()"):
            raise AssertionError(
                "the panel tooltip fallback must list the panel provider selection, not the full roster"
            )
        if not code_contains(tooltip_body, "panelProviderToolTipText("):
            raise AssertionError("the panel tooltip must reuse the per-provider tooltip line")
        if not code_contains(tooltip_body, "boundedDisplayText(errorText"):
            raise AssertionError("the panel tooltip must bound global CLI error text")
        menu_bar_display_body = function_body(main_text, "menuBarDisplayText")
        if not code_contains(menu_bar_display_body, "var row = panelDisplayRow(item, mode)"):
            raise AssertionError("each panel text mode must select a row that supports its own data")
        run_out_text_body = function_body(main_text, "runOutTextForRow")
        if not code_contains(run_out_text_body, "PanelDisplay.remainingSeconds("):
            raise AssertionError("the run-out token must advance from the usage observation time")

        # Every file that calls this unqualified must declare it: QML and JS share no
        # function scope, so a surface-wide search would be satisfied by SafeText.js while
        # the applet root's callers were left with an undefined function.
        applet.require_definition_where_used("boundedDisplayText")

    def test_compact_text_fit(self):
        # Every candidate composition is measured on its own hidden label, outside the
        # layout: the chosen width must not feed back into the choice, and raw font
        # metrics disagree with shaped label widths by a fraction of a pixel, which is
        # enough for the renderer to elide a composition that was picked to fit.
        composition_measurers = (
            "firstCompositionMeasurer", "secondCompositionMeasurer", "thirdCompositionMeasurer")
        for measurer in composition_measurers:
            if (
                f"id: {measurer}" not in compact_representation_text
                or f"Math.ceil({measurer}.implicitWidth)" not in compact_representation_text
            ):
                raise AssertionError(
                    "compact panel text must round up an independent label measurement "
                    f"per candidate composition; missing {measurer!r}"
                )
        if not code_contains(compact_representation_text, "maximumCompactWidth: Kirigami.Units.gridUnit * 18"):
            raise AssertionError("compact panel text must use a bounded wide cap")
        # Content the settings switched on is surrendered whole, never cut into a
        # fragment that reads as a different value.
        for fit_fragment in (
            'import "../PanelTextFit.js" as PanelTextFit',
            "PanelTextFit.compositions(applet.compactTextSegments())",
            "PanelTextFit.fittedIndex(textCompositionWidths, inlineTextBudget)",
            "PanelTextFit.fittedIndex(textCompositionWidths, standaloneTextBudget)",
            "Accessible.name: compactRoot.fullText",
        ):
            if not code_contains(compact_representation_text, fit_fragment):
                raise AssertionError(
                    "crowded panel text must surrender whole segments and keep the full "
                    f"composition for assistive technology; missing {fit_fragment!r}"
                )
        if "applet.compactText()" in compact_representation_text:
            raise AssertionError(
                "the compact renderer must compose panel text from segments so it can "
                "surrender them, not consume one pre-joined string"
            )
        if "elementLoader.implicitWidth" in compact_representation_text:
            raise AssertionError("compact panel text measurement must not feed back through its Loader width")

    def test_capsule_fill_animation(self):
        if "Behavior on width" not in id_block(compact_representation_text, "quotaCapsule"):
            raise AssertionError(
                "the panel capsule fill must grow into a new reading like every popup meter"
            )
        if "enabled: compactRoot.animationsEnabled" not in id_block(compact_representation_text, "quotaCapsule"):
            raise AssertionError(
                "the panel capsule fill animation must opt out where animations are disabled, so the "
                "settings preview keeps rendering a static frame"
            )


if __name__ == "__main__":
    unittest.main()
