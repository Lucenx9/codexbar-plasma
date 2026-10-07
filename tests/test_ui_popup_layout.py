"""Static UI checks for popup layout, headers, Overview rows, usage rows, and
states."""

import re
import unittest

from ui_regression_support import (
    Surface,
    code_contains,
    cost_presentation_js,
    full_representation_qml,
    function_body,
    id_block,
    overview_provider_row_qml,
    provider_header_qml,
    provider_usage_row_qml,
    providers_qml,
    root,
    sessions_view_qml,
    spend_view_qml,
)

# The popup UI rules below belong to the plasmoid surface, not to main.qml
# specifically, so read the surface as one text. Extracting the popup into a
# component keeps these assertions meaningful instead of silently unhooking them.
applet = Surface("applet", root)
main_text = applet.text
providers_text = providers_qml.read_text(encoding="utf-8")
cost_presentation_text = cost_presentation_js.read_text(encoding="utf-8")
provider_header_text = provider_header_qml.read_text(encoding="utf-8")
provider_usage_row_text = provider_usage_row_qml.read_text(encoding="utf-8")
overview_provider_row_text = overview_provider_row_qml.read_text(encoding="utf-8")
sessions_view_text = sessions_view_qml.read_text(encoding="utf-8")
spend_view_text = spend_view_qml.read_text(encoding="utf-8")
full_representation_text = full_representation_qml.read_text(encoding="utf-8")


class PopupLayoutTest(unittest.TestCase):
    def test_overview_rows(self):
        # Overview selection stores canonical provider IDs (legacy raw CLI spellings,
        # e.g. groqcloud, alibaba-coding-plan, still resolve) matched at runtime
        # against providerKey-normalized IDs (groq, alibaba). The applet must resolve
        # the stored value through OverviewProviders, the module the settings page
        # uses, so the custom selection is not silently ignored for aliased providers.
        overview_body = function_body(main_text, "overviewProviders")
        if not code_contains(overview_body, "OverviewProviders.visibleItems(providers, overviewProviderIDsRaw)"):
            raise AssertionError(
                "the Overview rows must share filtering and parsing with the settings page so "
                "aliased providers match runtime keys"
            )
        for retired_overview_fragment in ("maxOverviewProviders", "configuredOverviewProviderIDs"):
            if retired_overview_fragment in main_text:
                raise AssertionError(
                    "the Overview limit and selection parsing belong to OverviewProviders: "
                    + retired_overview_fragment
                )

        overview_detail_body = function_body((root / "contents/ui/OverviewProviders.js").read_text(encoding="utf-8"), "detailText")
        for overview_detail_fragment in (
            "item.hasIncident === true && item.statusKnown !== false",
            "item.account && item.account.length > 0",
        ):
            if not code_contains(overview_detail_body, overview_detail_fragment):
                raise AssertionError(
                    "the overview detail line stands for account identity; only an active "
                    "incident may replace it, never an operational status; "
                    f"missing {overview_detail_fragment!r}"
                )

        overview_row_body = id_block(overview_provider_row_text, "overviewRow")
        for fragment in (
            "implicitHeight: overviewRowContent.implicitHeight + Kirigami.Units.largeSpacing * 2",
            "Layout.preferredHeight: implicitHeight",
            "readonly property bool keyboardFocusVisible: overviewRowFocus.visualFocus",
            "border.width: overviewRow.keyboardFocusVisible ? 1 : 0",
            "overviewRowFocus.forceActiveFocus(Qt.MouseFocusReason)",
        ):
            if not code_contains(overview_row_body, fragment):
                raise AssertionError(f"overview rows must fit their content and distinguish keyboard focus: {fragment}")
        if not code_contains(overview_row_body, "applet.withAlpha(Kirigami.Theme.textColor, 0.035)"):
            raise AssertionError("overview rows must keep a quiet neutral resting surface")
        overview_row_surface_bindings = overview_row_body.split("RowLayout {", 1)[0]
        if "border.width" in overview_row_surface_bindings:
            raise AssertionError("overview rows must not regress to a stack of outlined cards")
        for polished_overview_fragment in (
            "radius: applet.roundedSurfaceRadius",
            "id: overviewProviderIdentitySurface",
            "radius: overviewRow.applet.nestedSurfaceRadius",
            "applet.withAlpha(overviewRow.accent, 0.1)",
        ):
            if not code_contains(overview_row_body, polished_overview_fragment):
                raise AssertionError(
                    "overview rows must retain the rounded provider identity treatment; "
                    f"missing {polished_overview_fragment!r}"
                )
        for interaction_fragment in (
            "activeFocusOnTab: true",
            "Accessible.role: Accessible.Button",
            "Accessible.onPressAction:",
            "Keys.onPressed:",
            "overviewRowMouse.pressed",
            "scale:",
        ):
            if not code_contains(overview_row_body, interaction_fragment):
                raise AssertionError(
                    "overview rows must preserve keyboard, assistive, and pressed feedback; "
                    f"missing {interaction_fragment!r}"
                )

        if not code_contains(overview_provider_row_text, "applet.usageResetText(usageRow)"):
            raise AssertionError("Overview reset labels must use render-time formatting")

        if not code_contains(main_text, "readonly property var overviewProviderItems: overviewProviders()"):
            raise AssertionError("overview provider rows must be cached in a QML property binding")
        if ".overviewProviders()" in main_text:
            raise AssertionError("overview UI bindings must reuse overviewProviderItems")
        overview_providers_js = (root / "contents/ui/OverviewProviders.js").read_text()
        overview_error_only_body = function_body(overview_providers_js, "isErrorOnly")
        if not code_contains(overview_error_only_body, "item.codexCreditLimit === null"):
            raise AssertionError(
                "a valid Codex monthly limit must keep a partially healthy provider overview-eligible"
            )

        # Direct QtTests cover eligibility, the stored selection, and the automatic
        # ranking. Both modules stay pure so those cases describe the runtime.
        auto_select_js = (root / "contents/ui/ProviderAutoSelect.js").read_text()
        for pure_module_text in (overview_providers_js, auto_select_js):
            for forbidden in ("root.", "Plasmoid.", "Qt.", "i18n(", "i18np(", "Date.now("):
                if forbidden in pure_module_text:
                    raise AssertionError(
                        "Overview filtering and automatic selection must stay pure: " + forbidden
                    )

    def test_header_actions_and_refresh_controls(self):
        header_sources = {
            "overviewHeaderRow": main_text,
            "providerHeaderRow": provider_header_text,
            "spendHeaderRow": spend_view_text,
            "sessionsHeaderRow": sessions_view_text,
        }
        for header_id, source_text in header_sources.items():
            header_body = id_block(source_text, header_id)
            if not code_contains(header_body, "Layout.rightMargin: Kirigami.Units.smallSpacing"):
                raise AssertionError(
                    f"{header_id} must align header actions with the inset scroll content"
                )
            if not code_contains(header_body, "Layout.alignment: Qt.AlignTop"):
                raise AssertionError(
                    f"{header_id} must align header action buttons to top"
                )

        overview_header_body = id_block(main_text, "overviewHeaderRow")
        provider_header_body = id_block(provider_header_text, "providerHeaderRow")
        for header_id, header_body in (
            ("overviewHeaderRow", overview_header_body),
            ("providerHeaderRow", provider_header_body),
        ):
            if not code_contains(header_body, "RefreshButton {" not in header_body or "busy:"):
                raise AssertionError(
                    f"{header_id} must use the shared refresh control with busy feedback"
                )

        refresh_control_body = applet.id_block("refreshControl")
        for fragment in (
            "implicitWidth: refreshButton.implicitWidth",
            "implicitHeight: refreshButton.implicitHeight",
            "if (!refreshControl.busy)",
            "visible: refreshControl.busy",
            "running: visible",
            "Accessible.name: refreshControl.label",
            "delay: Kirigami.Units.toolTipDelay",
        ):
            if not code_contains(refresh_control_body, fragment):
                raise AssertionError(f"refresh controls must retain their footprint and feedback: {fragment}")
        for effect in ("refreshNow(", "refreshCost(", "refreshSessions("):
            if effect in refresh_control_body:
                raise AssertionError("the shared refresh control must leave effects in its owning view")
        if ".focusReason =" in applet.id_block("overviewRowMouse"):
            raise AssertionError("overview rows must use a supported focus transition")
        for fragment in (
            "busy: view.applet.costLoading",
            "busy: view.applet.sessionsLoading",
            "onRequested: view.applet.refreshCost(true)",
            "onRequested: view.applet.refreshSessions()",
        ):
            applet.require(fragment, "history and sessions must retain scoped refresh feedback and actions")

    def test_scroll_views_and_surfaces(self):
        for scroll_id in ("overviewScroll", "providerScroll"):
            scroll_body = id_block(main_text, scroll_id)
            if not code_contains(scroll_body, "contentWidth: availableWidth"):
                raise AssertionError(f"{scroll_id} content width must follow Plasma ScrollView availableWidth")
            if not code_contains(scroll_body, f"{scroll_id}.availableWidth - Kirigami.Units.smallSpacing"):
                raise AssertionError(f"{scroll_id} must retain one quiet content inset before its scrollbar")
            for stale_scroll_gutter in (
                "readonly property real contentRightInset:",
                "rightPadding: contentRightInset",
            ):
                if stale_scroll_gutter in scroll_body:
                    raise AssertionError(
                        f"{scroll_id} must not restore the doubled desktop scrollbar gutter"
                    )

        if main_text.count("PlasmaComponents.ScrollView {") < 2:
            raise AssertionError("popup content must use Plasma-native scroll views")
        if "Controls.ScrollView {" in main_text:
            raise AssertionError("popup content must not restore desktop-framed scroll views")

        if not code_contains(main_text, "readonly property real roundedSurfaceRadius: Kirigami.Units.cornerRadius"):
            raise AssertionError("main.qml must derive its polished radius from Kirigami theme units")
        if not code_contains(main_text, "readonly property real nestedSurfaceRadius: Kirigami.Units.cornerRadius"):
            raise AssertionError(
                "main.qml must expose a concentric radius for surfaces nested inside a "
                "roundedSurfaceRadius container"
            )
        if not code_contains(main_text, "readonly property real compactMeterTrackHeight: Math.round(Kirigami.Units.gridUnit"):
            raise AssertionError(
                "list-row meters must derive their thinner track from gridUnit instead of "
                "pinning a device pixel count"
            )

        # Section headings sit above metric rows that are already DemiBold. A Normal
        # weight heading therefore reads as less important than its own content, so the
        # structural labels stay Primary and the size scale carries the ranking.
        heading_chunks = main_text.split("PlainHeading {")[1:]
        if len(heading_chunks) < 5:
            raise AssertionError("main.qml must keep its popup section headings")
        for heading_chunk in heading_chunks:
            if "type: Kirigami.Heading.Type.Primary" not in heading_chunk[:300]:
                heading_head = heading_chunk.strip().splitlines()[0].strip()
                raise AssertionError(
                    "popup section headings must outrank the DemiBold metric labels they "
                    f"introduce; heading starting {heading_head!r} is not Primary"
                )
        # The Plasma dialog already frames the popup. An inner outline nests a card
        # inside it, and a separator under the framed tab strip adds a third line.
        if "popupInnerSurface" in main_text:
            raise AssertionError("the popup must sit on the native dialog background, not an inner frame")
        if main_text.split("id: providerTabsBar", 1)[1].split("id: globalErrorMessage", 1)[0].count(
                "Kirigami.Separator {") != 0:
            raise AssertionError("the framed tab strip must not add a separator beneath it")

        if not code_contains(main_text, "fullRepresentation:"):
            raise AssertionError("the applet must keep a fullRepresentation root")
        full_representation_head = id_block(main_text, "fullRoot")[:900]
        if "standardHeightActive" not in full_representation_head:
            raise AssertionError(
                "every popup content section must share one standard height; "
                "per-section content heights resize the dialog on each tab switch"
            )
        if "popupContent.implicitHeight" not in full_representation_head:
            raise AssertionError(
                "the content-less popup states must stay compact and content-driven "
                "instead of inheriting the standard section height"
            )
        if re.search(r"implicitHeight:\s*Kirigami\.Units\.gridUnit\s*\*\s*\d", full_representation_head):
            raise AssertionError(
                "the popup must not pin implicitHeight to a grid-unit constant; the "
                "constants belong in the named minimum/maximum height properties"
            )

        # Text de-emphasis had drifted into eleven ad-hoc opacity literals, several
        # below the WCAG AA 4.5:1 floor for Kirigami.Theme.textColor on Breeze Light.
        # Keep the scale in one place so a new section cannot reintroduce a dimmer step.
        for token_definition in (
            "readonly property real secondaryTextOpacity: 0.7",
            "readonly property real valueTextOpacity: 0.85",
            "readonly property real meterTrackHeight: Math.round(Kirigami.Units.gridUnit * 0.4)",
        ):
            if not code_contains(main_text, token_definition):
                raise AssertionError(
                    f"main.qml must define the shared presentation scale: {token_definition!r}"
                )
        if not code_contains(providers_text, "readonly property real secondaryTextOpacity: 0.7"):
            raise AssertionError(
                "configProviders.qml must mirror main.qml's secondaryTextOpacity step"
            )
        provider_cost_section_body = id_block(full_representation_text, "providerCostSection")
        if provider_cost_section_body.count("Layout.preferredHeight: applet.meterTrackHeight") != 1:
            raise AssertionError(
                "the provider-cost meter must consume the shared meterTrackHeight"
            )
        if not code_contains(provider_cost_section_body, "Behavior on color"):
            raise AssertionError(
                "the provider-cost meter must animate color like the quota meters"
            )
        if provider_usage_row_text.count(
            "Layout.preferredHeight: usageRow.applet.meterTrackHeight"
        ) != 1:
            raise AssertionError("the provider-usage meter must consume meterTrackHeight")

    def test_provider_header(self):
        provider_header_body = id_block(provider_header_text, "providerHeaderRow")
        for header_fragment in (
            "id: providerIdentitySurface",
            "id: providerHeaderIcon",
            "id: providerTitleRow",
            "id: providerMetaRow",
            "id: providerAccountLabel",
            "id: providerPlanLabel",
        ):
            if not code_contains(provider_header_body, header_fragment):
                raise AssertionError(f"providerHeaderRow must expose {header_fragment} for stable header layout")

        if not code_contains(provider_header_body, "providerIconSource(providerHeaderRow.providerData.provider)"):
            raise AssertionError("providerHeaderRow must reinforce provider identity with the canonical icon")
        if not code_contains(provider_header_body, "providerReadableColor("):
            raise AssertionError("providerHeaderRow must keep provider identity visible on the active theme")
        if not code_contains(provider_header_body, "radius: providerHeaderRow.applet.nestedSurfaceRadius"):
            raise AssertionError("providerHeaderRow must share the nested rounded surface scale")
        if not code_contains(provider_header_body, "type: Kirigami.Heading.Type.Primary"):
            raise AssertionError(
                "the provider title must stay the heaviest label in the detail view so "
                "the section headings below it never outrank it"
            )

        provider_account_label_body = id_block(provider_header_text, "providerAccountLabel")
        for account_label_fragment in (
            # Filling with a cap at the label's own text lets the account elide on
            # narrow popups while never stretching past the email it shows.
            "Layout.fillWidth: true",
            "Layout.maximumWidth: implicitWidth",
        ):
            if not code_contains(provider_account_label_body, account_label_fragment):
                raise AssertionError(
                    "providerAccountLabel must fill without outgrowing its text and "
                    f"cap long account text before the refresh edge; "
                    f"missing {account_label_fragment!r}"
                )
        if "providerHeaderRow.width" in provider_account_label_body or "providerMetaRow.width" in provider_account_label_body:
            raise AssertionError("providerAccountLabel must not bind its width to the header layout width")

        provider_plan_label_body = id_block(provider_header_text, "providerPlanLabel")
        if not code_contains(provider_plan_label_body, "Layout.fillWidth: true"):
            raise AssertionError("providerPlanLabel must fill available space beside account")
        if not code_contains(provider_plan_label_body, "Layout.maximumWidth: Math.ceil(implicitWidth)"):
            raise AssertionError("providerPlanLabel must cap at implicitWidth to avoid rounding false truncation")

        if "providerUpdatedLabel" in applet.id_block("providerMetaRow"):
            raise AssertionError("account identity and the update timestamp must have separate lines")

    def test_usage_rows(self):
        applet.require("row.pace = paceSummaryPartsText(snapshot.paceParts)", "usage rows must localize structured pace fields")

        applet.require_definition_where_used("paceSummaryText")

        usage_percent_body = id_block(provider_usage_row_text, "usagePercentLabel")
        if not code_contains(usage_percent_body, "font.weight: Font.DemiBold"):
            raise AssertionError("usagePercentLabel must remain a prominent scan target")
        if provider_usage_row_text.index("id: usagePercentLabel") > provider_usage_row_text.index("id: usageBar"):
            raise AssertionError("usage percentage must appear in the metric header before its bar")
        usage_bar_body = id_block(provider_usage_row_text, "usageBar")
        if not code_contains(usage_bar_body, "applet.withAlpha(Kirigami.Theme.textColor, 0.1)"):
            raise AssertionError("usageBar must keep its pill track visually restrained")
        # A marker that spans the track edge to edge reads as a gap in the accent fill
        # rather than a threshold, so pace and quota markers share one inset geometry.
        for marker_geometry_fragment in (
            "readonly property real meterMarkerInset:",
            "readonly property real meterMarkerWidth:",
        ):
            if not code_contains(provider_usage_row_text, marker_geometry_fragment):
                raise AssertionError(
                    "ProviderUsageRow must define one shared meter marker geometry; "
                    f"missing {marker_geometry_fragment!r}"
                )
        if usage_bar_body.count("y: usageRow.meterMarkerInset") != 2:
            raise AssertionError("both the pace marker and the quota markers must be inset in the track")
        if usage_bar_body.count("width: usageRow.meterMarkerWidth") != 2:
            raise AssertionError("both the pace marker and the quota markers must share one marker width")
        for full_height_marker in ("height: usageBar.height\n", "y: 0\n"):
            if full_height_marker in usage_bar_body:
                raise AssertionError(
                    "quota markers must not span the meter track edge to edge again"
                )

        credits_section_body = id_block(full_representation_text, "creditsSection")
        reset_credits_section_body = id_block(full_representation_text, "resetCreditsSection")
        if "Kirigami.Separator {" in reset_credits_section_body:
            raise AssertionError(
                "reset credits must share the Credits separator instead of drawing their own"
            )
        if "resetCreditsSection" not in credits_section_body:
            raise AssertionError("reset credits must stay grouped inside the Credits section")
        for credit_limit_fragment in (
            "readonly property var creditLimit:",
            "applet.presentedProviderData.codexCreditLimit",
            "applet.codexCreditLimitUsageRow(",
            "model: creditsSection.creditLimitRow ? [creditsSection.creditLimitRow] : []",
            "delegate: Components.ProviderUsageRow",
        ):
            if not code_contains(credits_section_body, credit_limit_fragment):
                raise AssertionError(
                    "the Credits section must render the validated Codex monthly limit "
                    f"without adding a meter to plain balances; missing {credit_limit_fragment!r}"
                )
        if not re.search(
            r"visible:\s*applet\.presentedProviderData\s*"
            r"&&\s*applet\.presentedProviderData\.credits\s*!==\s*null",
            credits_section_body,
        ):
            raise AssertionError(
                "the plain credits balance must stay null-safe and independent of QML formatting"
            )
        if not code_contains(credits_section_body, 'i18n("Remaining: %1",'):
            raise AssertionError("the Credits section must keep the plain remaining-balance fallback")
        credit_limit_row_body = function_body(main_text, "codexCreditLimitUsageRow")
        for credit_limit_row_fragment in (
            'i18n("Monthly credit limit")',
            'i18n("Used: %1, remaining: %2 of %3"',
            "usedPercent: creditLimit.usedPercent",
            "leftPercent: creditLimit.leftPercent",
            "resetsAt: creditLimit.resetsAt",
        ):
            if not code_contains(credit_limit_row_body, credit_limit_row_fragment):
                raise AssertionError(
                    "the Codex monthly-limit row must present every validated field through "
                    f"the shared usage-meter component; missing {credit_limit_row_fragment!r}"
                )

        format_number_body = function_body(main_text, "formatNumber")
        if not code_contains(format_number_body, "groupedDecimalString(" not in format_number_body and "CostPresentation.formatCount("):
            raise AssertionError(
                "formatNumber must route through groupedDecimalString so credit balances "
                "carry group separators and the locale decimal mark like every other "
                "figure in the popup"
            )
        if "toFixed(" in format_number_body:
            raise AssertionError(
                "formatNumber must not format digits itself again; toFixed hardcodes the "
                "decimal mark and prints a whole balance as '0.0'"
            )
        # The delegated count formatter keeps the same routing contract: locale-aware
        # grouping, never hardcoded digits.
        format_count_body = function_body(cost_presentation_text, "formatCount")
        if not code_contains(format_count_body, "groupedDecimalString("):
            raise AssertionError(
                "formatCount must route through groupedDecimalString so credit balances "
                "carry group separators and the locale decimal mark like every other "
                "figure in the popup"
            )
        if "toFixed(" in format_count_body:
            raise AssertionError(
                "formatCount must not format digits itself again; toFixed hardcodes the "
                "decimal mark and prints a whole balance as '0.0'"
            )
        for usage_metadata_id in ("usagePaceLabel", "usageResetLabel"):
            usage_metadata_body = id_block(provider_usage_row_text, usage_metadata_id)
            if not code_contains(usage_metadata_body, "font: Kirigami.Theme.smallFont"):
                raise AssertionError(f"{usage_metadata_id} must retain the compact metadata type scale")

        reset_credits_body = function_body(main_text, "resetCreditsSection")
        if not code_contains(reset_credits_body, 'i18np("%1 available", "%1 available"'):
            raise AssertionError("reset credit counts must use plural-aware translations")
        if not code_contains(reset_credits_body, "ProviderCostPresentation.resetCount(providerID, resetCredits)"):
            raise AssertionError("reset credits must use the tested semantic count")
        direct_number_call = re.compile(r"(?<![A-Za-z0-9_])Number\(")
        if direct_number_call.search(reset_credits_body):
            raise AssertionError("reset credits must not use loose numeric coercion")

    def test_feedback_and_empty_states(self):
        for message_id, message_type in (
            ("globalErrorMessage", "Kirigami.MessageType.Error"),
            ("providerErrorMessage", "Kirigami.MessageType.Error"),
        ):
            message_body = id_block(main_text, message_id)
            if not code_contains(message_body, f"type: {message_type}"):
                raise AssertionError(f"{message_id} must use the native semantic message style")

        global_error_body = id_block(main_text, "globalErrorMessage")
        provider_usage_loading_body = id_block(main_text, "providerUsageLoadingRow")
        if not code_contains(provider_usage_loading_body, "(applet.loading || applet.errorText.length > 0)"):
            raise AssertionError("usage feedback must absorb remaining height for errors as well as loading")
        if not code_contains(provider_usage_loading_body, "visible: applet.loading && applet.errorText.length === 0"):
            raise AssertionError("an error-only popup must not display a loading indicator")
        for scoped_feedback_body, feedback_name in (
            (global_error_body, "globalErrorMessage"),
            (provider_usage_loading_body, "providerUsageLoadingRow"),
        ):
            if not code_contains(scoped_feedback_body, "applet.providerUsageFeedbackVisible"):
                raise AssertionError(
                    f"{feedback_name} must stay hidden on the independent Spend and Sessions tabs"
                )

        # A RowLayout inherits its children's maximum height, so it cannot absorb the
        # leftover popup height: the layout engine then spreads the slack across every
        # row and drops the tab bar into the middle of an otherwise empty popup.
        if not re.search(r"Item \{\s*\n\s*id: providerUsageLoadingRow", main_text):
            raise AssertionError(
                "providerUsageLoadingRow must be a plain Item so it absorbs the leftover "
                "popup height and keeps the tab bar pinned to the top while usage loads"
            )
        for filler_owner_source, filler_owner_text in (
            ("SessionsView.qml", sessions_view_text),
            ("SpendView.qml", spend_view_text),
        ):
            if not code_contains(filler_owner_text, "Controls.BusyIndicator {\n            anchors.centerIn: parent"):
                raise AssertionError(
                    f"{filler_owner_source} must center its busy indicator inside a filler item "
                    "so the heading stays pinned to the top while loading"
                )

        provider_status_body = id_block(main_text, "providerStatusMessage")
        if not code_contains(provider_status_body, "applet.presentedProviderData.hasIncident"):
            raise AssertionError("healthy provider status must not occupy a permanent inline banner")
        for block_id, source, data in (
            ("providerStatusMessage", main_text, "applet.presentedProviderData"),
            ("providerStatusBadge", provider_header_text, "providerHeaderRow.providerData"),
        ):
            visible = re.search(r"visible:\s*([^\n]*(?:\n\s*&&[^\n]*)*)", id_block(source, block_id))
            if not visible or not re.search(
                rf"{re.escape(data)}\.hasIncident\s*&&\s*{re.escape(data)}\.statusKnown\s*!==\s*false",
                visible.group(1),
            ):
                raise AssertionError(f"{block_id} must hide inactive and unknown provider status")
        if not code_contains(provider_status_body, "applet.statusMessageType(applet.presentedProviderData.statusSeverity)"):
            raise AssertionError("incident banners must reflect the provider status severity")
        status_message_type_body = function_body(main_text, "statusMessageType")
        for semantic_type in ("Kirigami.MessageType.Error", "Kirigami.MessageType.Warning"):
            if not code_contains(status_message_type_body, semantic_type):
                raise AssertionError(f"statusMessageType must expose {semantic_type}")

        for placeholder_id in (
            "overviewPlaceholderMessage",
            "providerPlaceholderMessage",
        ):
            placeholder_body = id_block(main_text, placeholder_id)
            if not code_contains(placeholder_body, "Kirigami.PlaceholderMessage.Type.Informational"):
                raise AssertionError(f"{placeholder_id} must use the native informational empty state")

        empty_providers_body = id_block(main_text, "emptyProvidersMessage")
        for fragment in ("Kirigami.PlaceholderMessage.Type.Actionable", "helpfulAction: configureProvidersAction",
                         "plainExplanation:"):
            if not code_contains(empty_providers_body, fragment):
                raise AssertionError("the empty provider state must explain and open native widget settings")

    def test_provider_actions(self):
        action_rows_body = function_body(main_text, "actionRows")
        if not code_contains(action_rows_body, 'action: "refresh", enabled: true, separatorBefore: true'):
            raise AssertionError("actionRows must separate provider actions from widget-level actions")

        provider_action_rows_body = id_block(main_text, "providerActionRows")
        for action_fragment in (
            "id: providerActionGroupSeparator",
            "visible: modelData.separatorBefore === true",
        ):
            if not code_contains(provider_action_rows_body, action_fragment):
                raise AssertionError(f"providerActionRows must expose {action_fragment} for grouped menu actions")

    def test_generic_details(self):
        snapshot_text = (root / "contents/ui/ProviderSnapshot.js").read_text()
        normalize_provider_body = function_body(snapshot_text, "normalize")

        # Parsing and fallback behavior are covered directly by
        # tst_legacy_usage_dashboard.qml; keep localization and generic-detail priority
        # wired through the applet without pinning the module's private helpers.
        if not code_contains(normalize_provider_body, "providerDetails.length > 0 ? null : LegacyUsageDashboard.normalize(usage, item)"):
            raise AssertionError("generic details must take precedence over bounded legacy dashboards")
        present_provider_body = function_body(main_text, "presentProviderSnapshot")
        for field in ("kpis", "rows"):
            if not code_contains(present_provider_body, f"{field}: dashboard.{field}.map(dashboardDisplayRow)"):
                raise AssertionError("legacy dashboard rows must use the localized adapter")
        dashboard_display_body = applet.function_body("dashboardDisplayRow")
        if not code_contains(dashboard_display_body, "row.parts.map(dashboardPartText)"):
            raise AssertionError("dashboard number formatting must remain in the QML adapter")
        if not code_contains(dashboard_display_body, "dashboardLabelText(row.labelKey)"):
            raise AssertionError("semantic dashboard labels must be localized in QML")
        if not code_contains(main_text, "function providerCountText(count)"):
            raise AssertionError("overview provider counts must use a plural-aware helper")
        provider_count_body = function_body(main_text, "providerCountText")
        if not code_contains(provider_count_body, 'i18np("%1 provider", "%1 providers", total)'):
            raise AssertionError("providerCountText must select the correct singular form")

    def test_reset_labels(self):
        # Popup header and detail lines share the Sessions and Usage & Spend separator.
        for popup_file in ("FullRepresentation.qml", "OverviewProviderRow.qml", "AiInsightsCard.qml"):
            if 'i18n("%1 - %2"' in (root / "contents/ui/components" / popup_file).read_text():
                raise AssertionError(f"{popup_file} must join popup detail lines with the middle dot separator")
        reset_text_body = function_body(main_text, "resetText")
        # Direct QtTests cover timestamp precedence, bounds, and countdown arithmetic.
        # The owning adapter supplies the live clock and keeps local date formatting.
        if not code_contains(reset_text_body, "ResetPresentation.parts(window, panelClockMs, absolute)"):
            raise AssertionError("reset formatting must use semantic parts with the live panel clock")
        for formatter in ("timeLabels.monthDayTime(parts.timestampMs)", "timeLabels.weekdayTime(parts.timestampMs)"):
            if not code_contains(reset_text_body, formatter):
                raise AssertionError("absolute reset dates must use the locale-aware time labels")
        # A literal Qt.formatDateTime pattern writes English day and month names and a
        # fixed hour cycle whatever the user's regional format; TimeLabels owns them.
        for path in sorted((root / "contents/ui").rglob("*.qml")):
            if "Qt.formatDateTime(" in path.read_text():
                raise AssertionError(f"{path.relative_to(root)} must format times through TimeLabels")
        if not code_contains(reset_text_body, "ResetPresentation.absoluteShowsDate(parts.timestampMs, panelClockMs)"):
            raise AssertionError("absolute resets beyond the next six days must show their date")
        for field in ("window.resetsAt", "window.resetDescription", "Math.round", "Math.floor"):
            if field in reset_text_body:
                raise AssertionError("reset parsing and arithmetic belong in ResetPresentation: " + field)
        for message in ("%1 min", "%1h", "%1d"):
            if not code_contains(reset_text_body, f'i18np("{message}"'):
                raise AssertionError("reset duration units must retain plural-aware localization")
        reset_presentation = (root / "contents/ui/ResetPresentation.js").read_text()
        for forbidden in ("root.", "Plasmoid.", "Qt.", "i18n(", "i18np(", "Date.now("):
            if forbidden in reset_presentation:
                raise AssertionError("reset decisions must be pure and use the caller's clock: " + forbidden)

        reset_label_body = function_body(main_text, "resetLabel")
        if not code_contains(reset_label_body, "ResetPresentation.labelParts(value)"):
            raise AssertionError("reset labels must use the tested semantic text classification")
        if not code_contains(reset_label_body, 'i18n("Resets %1", parts.text)'):
            raise AssertionError("QML must localize the reset-label prefix")


if __name__ == "__main__":
    unittest.main()
