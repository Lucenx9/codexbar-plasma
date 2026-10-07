"""Static UI checks for the popup tab strip, tab customization, and navigation."""

import unittest

from ui_regression_support import (
    Surface,
    code_contains,
    config_xml,
    function_body,
    global_tab_qml,
    id_block,
    overview_provider_row_qml,
    root,
)

# The popup UI rules below belong to the plasmoid surface, not to main.qml
# specifically, so read the surface as one text. Extracting the popup into a
# component keeps these assertions meaningful instead of silently unhooking them.
applet = Surface("applet", root)
main_text = applet.text
popup_surface = Surface("popup", root)
config_text = config_xml.read_text(encoding="utf-8")
overview_provider_row_text = overview_provider_row_qml.read_text(encoding="utf-8")
global_tab_text = global_tab_qml.read_text(encoding="utf-8")


class PopupTabsTest(unittest.TestCase):
    def test_tab_customization_persists(self):
        provider_tabs_body = applet.id_block("providerTabsBar")
        for config_fragment in (
            '<entry name="providerOrder" type="String">',
            '<entry name="showPopupTabLabels" type="Bool">',
        ):
            if not code_contains(config_text, config_fragment):
                raise AssertionError(f"popup tab customization must be persisted; missing {config_fragment!r}")
        for display_fragment in (
            'id: showPopupTabLabelsCheck',
            'model: page.orderedEnabledProviderRoster',
            'ProviderOrder.movedOrder(',
        ):
            popup_surface.require(display_fragment, "Popup must expose tab customization")

        for applet_fragment in (
            'property string providerOrderRaw:',
            'property bool showPopupTabLabels:',
            'ProviderOrder.orderedItems(',
        ):
            applet.require(applet_fragment, "the popup must apply persisted tab customization")

        for global_tab_id in ("overviewTab", "spendTab", "sessionsTab"):
            if "showLabel: applet.showPopupTabLabels" not in applet.id_block(global_tab_id):
                raise AssertionError(f"{global_tab_id} must use the popup label preference")
        for icon_only_fragment in (
            'visible: applet.showPopupTabLabels',
            'visible: (!applet.showPopupTabLabels || providerTabLabel.truncated)',
        ):
            if not code_contains(provider_tabs_body, icon_only_fragment):
                raise AssertionError(
                    f"icon-only popup tabs must retain discoverable names; missing {icon_only_fragment!r}"
                )
        for global_tab_fragment in (
            'property bool showLabel: true',
            'visible: tab.showLabel',
            'visible: (!tab.showLabel || tab.textTruncated) && tabMouse.containsMouse',
        ):
            applet.require(global_tab_fragment, "global tabs must support accessible icon-only display")

    def test_tab_hierarchy(self):
        for tab_content_id, leading_spacer_id, trailing_spacer_id, condition in (
            (
                "providerTabContent",
                "providerTabLeadingSpacer",
                "providerTabTrailingSpacer",
                "!applet.showPopupTabLabels",
            ),
            (
                "globalTabContent",
                "globalTabLeadingSpacer",
                "globalTabTrailingSpacer",
                "!tab.showLabel",
            ),
        ):
            tab_content_body = applet.id_block(tab_content_id)
            for centered_icon_fragment in (
                f"id: {leading_spacer_id}",
                f"id: {trailing_spacer_id}",
                f"visible: {condition}",
                f"Layout.fillWidth: {condition}",
            ):
                if not code_contains(tab_content_body, centered_icon_fragment):
                    raise AssertionError(
                        f"{tab_content_id} must center its icon-only content; "
                        f"missing {centered_icon_fragment!r}"
                    )
        provider_tabs_body = applet.id_block("providerTabsBar")
        for tabs_fragment in (
            "Layout.preferredHeight: Kirigami.Units.gridUnit * 2.35",
            "id: providerTabsSurface",
            "radius: applet.roundedSurfaceRadius",
            "border.color: applet.withAlpha(Kirigami.Theme.textColor, 0.06)",
            "anchors.margins: Kirigami.Units.smallSpacing / 2",
            "applet.withAlpha(Kirigami.Theme.textColor, 0.1)",
            "anchors.bottomMargin: 2",
            "providerReadableColor(",
            "activeFocusOnTab: true",
            "Accessible.role: Accessible.PageTab",
            "Accessible.onPressAction:",
            "Keys.onPressed:",
            "scale:",
        ):
            if not code_contains(provider_tabs_body, tabs_fragment):
                raise AssertionError(
                    "providerTabsBar must preserve the compact, accent-led tab hierarchy; "
                    f"missing {tabs_fragment!r}"
                )

    def test_tab_strip_scrolling(self):
        provider_tabs_flickable_body = id_block(main_text, "providerTabsFlickable")
        for scroll_fragment in (
            "WheelHandler {",
            "acceptedDevices: PointerDevice.Mouse",
            "function ensureVisible(item)",
            "function focusableTabs(item)",
            "function navigateFromTab(item, key)",
            "TabStripGeometry.keyboardTargetIndex(action, tabs.indexOf(item), tabs.length)",
            "case Qt.Key_Home:",
            "case Qt.Key_End:",
            "function scrollBy(delta, immediate)",
        ):
            if not code_contains(provider_tabs_flickable_body, scroll_fragment):
                raise AssertionError(
                    "the tab strip must stay reachable without touch gestures; "
                    f"missing {scroll_fragment!r}"
                )
        # The scroll arithmetic moved into TabStripGeometry.js, where the edge cases are
        # tested. Assert the delegation, and that neither decision grew a second copy
        # back inside the strip.
        for tab_geometry_fragment in (
            "TabStripGeometry.boundedPosition(position, contentWidth, width)",
            "TabStripGeometry.revealPosition(",
            "if (target !== null) {",
        ):
            if not code_contains(provider_tabs_flickable_body, tab_geometry_fragment):
                raise AssertionError(
                    "the tab strip must take its scroll positions from TabStripGeometry.js; "
                    f"missing {tab_geometry_fragment!r}"
                )
        for inlined_tab_geometry in (
            "Math.min(contentWidth - width, position)",
            "right + margin > contentX + width",
        ):
            if inlined_tab_geometry in provider_tabs_flickable_body:
                raise AssertionError(
                    "tab strip scroll arithmetic must not be re-inlined beside the module; "
                    f"found {inlined_tab_geometry!r}"
                )

        for button_id, direction in (
            ("previousTabsButton", "-providerTabsFlickable.tabPageStep"),
            ("nextTabsButton", "providerTabsFlickable.tabPageStep"),
        ):
            button_body = applet.id_block(button_id)
            for fragment in (
                "visible: providerTabsBar.tabsOverflow",
                "Accessible.name: text",
                "display: PlasmaComponents.AbstractButton.IconOnly",
                f"onClicked: providerTabsFlickable.scrollBy({direction}, visualFocus)",
                "delay: Kirigami.Units.toolTipDelay",
            ):
                if not code_contains(button_body, fragment):
                    raise AssertionError(f"{button_id} must remain a native accessible scroll control: {fragment}")
        # Native controls stay outside the viewport; their space is reserved at both
        # edges, even when the corresponding direction is disabled at an endpoint.
        for fragment in (
            "? previousTabsButton.width + Kirigami.Units.smallSpacing",
            "? nextTabsButton.width + Kirigami.Units.smallSpacing",
            "scrollTo(target, true)",
            "onMovementStarted: providerTabsScroll.stop()",
        ):
            if not code_contains(provider_tabs_flickable_body, fragment):
                raise AssertionError(f"tab navigation must preserve visible content and direct focus: {fragment}")

    def test_tab_keyboard_navigation(self):
        # Arrow, Home and End keys reach the strip through one handler, so every tab
        # kind wraps and jumps the same way.
        if not code_contains(main_text, "providerTabsFlickable.navigateFromTab(providerFocus, event.key)"):
            raise AssertionError("the provider tabs must navigate with arrow, Home and End keys")
        # The Overview, Usage & Spend and Sessions tabs share GlobalTab, so its strip
        # wiring below covers navigation, reveal and selection for all three.
        overview_tab_marker = main_text.index("id: overviewTab")
        overview_tab_brace = main_text.rindex("{", 0, overview_tab_marker)
        overview_tab_type = main_text[main_text.rindex("\n", 0, overview_tab_brace) + 1:overview_tab_brace].strip()
        if overview_tab_type != "Components.GlobalTab":
            raise AssertionError("the Overview tab must reuse GlobalTab instead of an inline copy")
        overview_tab_body = id_block(main_text, "overviewTab")
        for overview_tab_fragment in (
            "tabStrip: providerTabsFlickable",
            "selected: applet.overviewSelected",
            'onActivated: applet.selectGlobalView("overview")',
        ):
            if not code_contains(overview_tab_body, overview_tab_fragment):
                raise AssertionError(f"the Overview tab must join the tab strip; missing {overview_tab_fragment!r}")
        # A provider tab shows its quota as an underline and a failure as dimming; both
        # must reach screen readers as text.
        if not code_contains(main_text, "Accessible.description: applet.switcherDescription(providerTab.modelData)"):
            raise AssertionError("provider tabs must describe their quota and error state to assistive tools")
        for switcher_description_fragment in (
            "function switcherDescription(item)",
            "var row = switcherMetricRow(item)",
            "parts.push(lastGoodUsageText(item))",
            "parts.push(item.error)",
        ):
            if not code_contains(main_text, switcher_description_fragment):
                raise AssertionError(
                    "the provider tab description must cover quota, stale usage, and errors; "
                    f"missing {switcher_description_fragment!r}"
                )
        if not code_contains(overview_provider_row_text, "visible: overviewRow.textTruncated && overviewRowMouse.containsMouse"):
            raise AssertionError("a truncated Overview row must reveal its full title and detail on hover")
        if not code_contains(main_text, "providerTabsFlickable.ensureVisible(providerTab)"):
            raise AssertionError("focusing a provider tab must pull it back into view")
        provider_tabs_flickable_body = id_block(main_text, "providerTabsFlickable")
        if not code_contains(provider_tabs_flickable_body, "function claimSelectedTab(item, isSelected)"):
            raise AssertionError("the tab strip must track which tab is selected in one place")
        # Every tab kind must report selection, or the strip keeps revealing a stale tab
        # after the user switches between a provider and a global view.
        if main_text.count("providerTabsFlickable.claimSelectedTab(") != 1:
            raise AssertionError("the provider tabs must report selection; global tabs report through GlobalTab")
        if not code_contains(main_text, "onSelectedChanged: providerTab.claimSelectedTab()"):
            raise AssertionError("selection tracking is missing 'onSelectedChanged: providerTab.claimSelectedTab()'")
        if not code_contains(global_tab_text, "tab.tabStrip.claimSelectedTab(tab, tab.selected)"):
            raise AssertionError("global tabs must report selection to the strip")
        if not code_contains(global_tab_text, "onSelectedChanged: tab.claimSelectedTab()"):
            raise AssertionError("global tabs must report selection changes to the strip")
        if not code_contains(global_tab_text, "tab.tabStrip.navigateFromTab(tabFocus, event.key)"):
            raise AssertionError("global tabs must take part in keyboard tab navigation")
        if not code_contains(global_tab_text, "tab.tabStrip.ensureVisible(tab)"):
            raise AssertionError("a focused global tab must be scrolled into view")

    def test_tab_selection_state(self):
        provider_tabs_body = applet.id_block("providerTabsBar")

        if "Kirigami.Theme.highlightedTextColor" in provider_tabs_body:
            raise AssertionError("provider tabs must not depend on a heavy solid-highlight selected state")
        for stale_selected_overlay in (
            "applet.withAlpha(brandAccent, 0.12)",
            "selected ? applet.withAlpha(accent, 0.32)",
        ):
            if stale_selected_overlay in provider_tabs_body:
                raise AssertionError(
                    "provider tabs must not restore a persistent accent capsule; "
                    f"found {stale_selected_overlay!r}"
                )
        for tab_id in ("providerTab",):
            tab_body = id_block(main_text, tab_id)
            focus_id = "providerFocus"
            for focus_fragment in (
                f"readonly property bool keyboardFocusVisible: {focus_id}.visualFocus",
                "border.width: keyboardFocusVisible ? 1 : 0",
                f"id: {focus_id}",
                "activeFocusOnTab: true",
                f"{focus_id}.forceActiveFocus(Qt.MouseFocusReason)",
            ):
                if not code_contains(tab_body, focus_fragment):
                    raise AssertionError(
                        f"{tab_id} must transfer pointer focus without drawing a keyboard ring; "
                        f"missing {focus_fragment!r}"
                    )
            for stale_pointer_focus_fragment in ("focusAcquiredByPointer",):
                if stale_pointer_focus_fragment in tab_body:
                    raise AssertionError(
                        f"{tab_id} must not retain a pointer-assigned focus overlay after the popup reopens; "
                        f"found {stale_pointer_focus_fragment!r}"
                    )

        for global_tab_focus_fragment in (
            "readonly property bool keyboardFocusVisible: tabFocus.visualFocus",
            "border.width: keyboardFocusVisible ? 1 : 0",
            "id: tabFocus",
            "activeFocusOnTab: true",
            "tabFocus.forceActiveFocus(Qt.MouseFocusReason)",
        ):
            if not code_contains(global_tab_text, global_tab_focus_fragment):
                raise AssertionError(
                    "global tabs must preserve keyboard focus without pointer focus state; "
                    f"missing {global_tab_focus_fragment!r}"
                )
        for stale_global_pointer_focus_fragment in ("focusAcquiredByPointer",):
            if stale_global_pointer_focus_fragment in global_tab_text:
                raise AssertionError(
                    "global tabs must not retain a pointer-assigned focus overlay after the popup reopens; "
                    f"found {stale_global_pointer_focus_fragment!r}"
                )

        provider_tab_body = id_block(main_text, "providerTab")
        if "visible: providerTab.meter >= 0" not in provider_tab_body:
            raise AssertionError("providerTab must draw its underline only as a quota meter")
        if not code_contains(provider_tab_body, "color: providerTab.selected ? providerTab.accent"):
            raise AssertionError(
                "unselected provider tabs must dim their icon while keeping the provider "
                "hue, so selection reads the same way as on the global tabs"
            )
        # The tab surface alone marks selection. A selection underline beside the
        # provider quota underline made a partly filled meter read as a selected tab.
        for underline_tab_text in (
            global_tab_text,
            provider_tab_body,
        ):
            if "selected ? 1 : 0" in underline_tab_text:
                raise AssertionError("tabs must mark selection with their surface, not an accent underline")

    def test_popup_selection_policy(self):
        # Selection policy is behavioral code in PopupSelection. The root only supplies
        # observations, commits the result, and invokes reconciliation for effects.
        select_body = function_body(main_text, "updateSelectedProvider")
        if not code_contains(main_text, 'import "PopupSelection.js" as PopupSelection'):
            raise AssertionError("main.qml must import the tested popup selection policy")
        if not code_contains(select_body, "PopupSelection.reconcile("):
            raise AssertionError("updateSelectedProvider must delegate its transition to PopupSelection")
        for selection_commit in (
            "selectedProviderID = next.providerID",
            "selectedGlobalView = next.globalView",
            "selectionInitialized = next.initialized",
        ):
            if not code_contains(select_body, selection_commit):
                raise AssertionError(f"main.qml must commit popup selection state: {selection_commit}")
        if not code_contains(main_text, "function providerIndexForID(providerID)"):
            raise AssertionError("the selected provider index must be derived from its provider id")
        select_global_body = function_body(main_text, "selectGlobalView")
        if not code_contains(select_global_body, "PopupSelection.globalViewIsAvailable(candidate, globalViewAvailability())"):
            raise AssertionError("explicit global selection must use the shared availability contract")
        reconcile_global_body = function_body(main_text, "reconcileGlobalViewAvailability")
        if not code_contains(reconcile_global_body, "PopupSelection.globalSelectionNeedsReconciliation("):
            raise AssertionError("availability handlers must ignore valid global and provider selections")
        if not code_contains(reconcile_global_body, "updateSelectedProvider()"):
            raise AssertionError("an unavailable global selection must reconcile immediately")
        for availability_handler in (
            "onOverviewAvailableChanged: reconcileGlobalViewAvailability()",
            "onSpendAvailableChanged: reconcileGlobalViewAvailability()",
            "onSessionsAvailableChanged: reconcileGlobalViewAvailability()",
        ):
            if not code_contains(main_text, availability_handler):
                raise AssertionError(f"global selection is missing availability wiring: {availability_handler}")

        for global_view_fragment in (
            'applet.selectGlobalView("spend")',
            'applet.selectGlobalView("sessions")',
            "Components.SpendView",
            "Components.SessionsView",
        ):
            if not code_contains(main_text, global_view_fragment):
                raise AssertionError(f"global popup navigation is missing {global_view_fragment!r}")


if __name__ == "__main__":
    unittest.main()
