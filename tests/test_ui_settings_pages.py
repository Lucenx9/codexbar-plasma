"""Static UI checks for the General, Popup, Panel, Notifications, AI Insights, and
Diagnostics settings pages."""

import re
import unittest

from ui_regression_support import (
    Surface,
    assert_dismissible_message_restores_visibility,
    assert_form_sections,
    code_contains,
    config_xml,
    diagnostics_qml,
    function_body,
    general_qml,
    id_block,
    providers_qml,
    qml_default_literal,
    require_block_fragment,
    root,
)

providers_surface = Surface("providers", root)
diagnostics_surface = Surface("diagnostics", root)
general_surface = Surface("general", root)
general_text = general_surface.text
popup_surface = Surface("popup", root)
popup_text = popup_surface.text
panel_surface = Surface("panel", root)
notifications_surface = Surface("notifications", root)
insights_surface = Surface("insights", root)
providers_text = providers_qml.read_text(encoding="utf-8")
diagnostics_text = diagnostics_qml.read_text(encoding="utf-8")
config_text = config_xml.read_text(encoding="utf-8")


class SettingsPagesTest(unittest.TestCase):
    def test_reorder_focus_follows_identity(self):
        for order_surface, move_function, repeater in (
            (popup_surface, "moveProvider", "providerOrderRepeater"),
            (panel_surface, "movePanelElement", "panelOrderRepeater"),
        ):
            order_surface.require_definition_where_used("restoreOrderFocus")
            order_surface.require_definition_where_used("revealFocusedOrderButton")
            order_surface.require(
                "onYChanged: page.revealFocusedOrderButton(upButton, downButton)",
                "reordered rows must reveal focused buttons after layout placement")
            reveal_order_focus_body = order_surface.function_body("revealFocusedOrderButton")
            for focus_fragment in ("upButton.activeFocus", "downButton.activeFocus",
                                   "page.ensureVisible(button, position.x - button.x, position.y - button.y)"):
                if not code_contains(reveal_order_focus_body, focus_fragment):
                    raise AssertionError("reorder scrolling must follow only the focused button")
            move_body = order_surface.function_body(move_function)
            if not code_contains(move_body, f"Qt.callLater(restoreOrderFocus, {repeater}, key, delta)"):
                raise AssertionError("keyboard reorder must restore focus after delegates are replaced")
            restore_order_focus_body = order_surface.function_body("restoreOrderFocus")
            for focus_fragment in ("row.orderKey === key", "!button.enabled",
                                   "button.forceActiveFocus(Qt.TabFocusReason)"):
                if not code_contains(restore_order_focus_body, focus_fragment):
                    raise AssertionError("reorder focus must follow identity and use an enabled button")

    def test_restore_all_defaults_covers_schema(self):
        internal_config_keys = {
            "usageCache",
            "autoUpdateLastCheck",
            "cliUpdateLastCheck",
            "cliUpdateLastNotifiedVersion",
            "widgetUpdateLastStatus",
            "widgetUpdateLastError",
            "lastNotifiedUpdateVersion",
            "providerConfigRevision",
            "aiInsightsCache",
            "aiInsightsLastAttempt",
            "aiInsightsRateLimit",
        }
        all_config_keys = set(re.findall(r'<entry name="([^"]+)"', config_text))
        resettable_config_keys = all_config_keys - internal_config_keys
        restore_defaults_body = function_body(general_text, "restoreUserDefaults")
        defaults_check_body = function_body(general_text, "userSettingsAreDefault")
        # History-range defaults are exercised through the real page functions and
        # change handlers in test_general_config_sync.py, without KDE module skips.
        behaviorally_checked_defaults = {"costHistoryDays", "costHistoryPeriod"}
        restore_statements = {
            "costHistoryMetric": "editCostHistoryMetric(cfg_costHistoryMetricDefault)",
        }
        for config_key in sorted(resettable_config_keys):
            property_pattern = re.compile(
                rf"\bproperty\s+(?:alias|string|int|bool)\s+cfg_{re.escape(config_key)}(?::|\s|$)"
            )
            default_property_pattern = re.compile(
                rf"\bproperty\s+(?:string|int|bool|real)\s+cfg_{re.escape(config_key)}Default(?::|\s|$)"
            )
            if not property_pattern.search(general_text) or not default_property_pattern.search(general_text):
                raise AssertionError(
                    f"global defaults must declare the value and default for {config_key} on General"
                )
            expected_assignment = restore_statements.get(
                config_key, f"cfg_{config_key} = cfg_{config_key}Default"
            )
            if config_key not in behaviorally_checked_defaults and not code_contains(restore_defaults_body, expected_assignment):
                raise AssertionError(f"global defaults must restore {config_key}")
            expected_pair = f"[cfg_{config_key}, cfg_{config_key}Default]"
            if not code_contains(defaults_check_body, expected_pair):
                raise AssertionError(f"global defaults button state must account for {config_key}")

        uninitialized_general_defaults = sorted(
            key for key in resettable_config_keys
            if not re.search(
                rf"\bproperty\s+(?:string|int|bool|real)\s+cfg_{re.escape(key)}Default\s*:",
                general_text,
            )
        )
        if uninitialized_general_defaults:
            raise AssertionError(
                "global defaults must initialize cfg_*Default from main.xml for: "
                + ", ".join(uninitialized_general_defaults)
            )
        for internal_key in sorted(internal_config_keys):
            if f"cfg_{internal_key}" in restore_defaults_body:
                raise AssertionError(f"global defaults must preserve internal state {internal_key}")

        restore_defaults_button = id_block(general_text, "restoreAllDefaultsButton")
        for restore_button_fragment in (
            'text: i18n("Restore all defaults")',
            "enabled: !page.userSettingsAreDefault()",
            "onClicked: page.restoreUserDefaults()",
        ):
            if restore_button_fragment not in restore_defaults_button:
                raise AssertionError(
                    "the global defaults action must remain explicit and cancelable; "
                    f"missing {restore_button_fragment!r}"
                )
        if "defaultsActionRequested = false" not in function_body(general_text, "saveConfig"):
            raise AssertionError("saving global defaults must clear the pending confirmation message")

    def test_default_initializers_match_schema(self):
        # Config loaders differ in which cfg_*Default properties they inject. Keep the
        # initializers as a portable fallback matching contents/config/main.xml: an
        # initializer matching every schema default and no initializer contradicting it.
        xml_entry_pattern = re.compile(r'<entry name="([^"]+)" type="(\w+)">(.*?)</entry>', re.S)
        xml_defaults = {}
        for entry_name, entry_type, entry_body in xml_entry_pattern.findall(config_text):
            default_match = re.search(r"<default>(.*?)</default>", entry_body, re.S)
            xml_defaults[entry_name] = (entry_type, default_match.group(1) if default_match else "")

        qml_default_pattern = re.compile(
            r"\bproperty\s+(?:string|int|bool|real)\s+cfg_(\w+)Default\s*:\s*(.+?)\s*$", re.M
        )
        for settings_page_text, settings_page_name in (
            (general_text, "configGeneral.qml"),
            (popup_text, "configPopup.qml"),
            (panel_surface.text, "configPanel.qml"),
            (notifications_surface.text, "configNotifications.qml"),
            (providers_text, "configProviders.qml"),
            (diagnostics_text, "configDiagnostics.qml"),
            (insights_surface.text, "configAiInsights.qml"),
        ):
            for default_key, literal in qml_default_pattern.findall(settings_page_text):
                if default_key not in xml_defaults:
                    raise AssertionError(
                        f"{settings_page_name} initializes cfg_{default_key}Default "
                        "without a main.xml entry"
                    )
                entry_type, xml_value = xml_defaults[default_key]
                expected_literal = qml_default_literal(entry_type, xml_value)
                if literal != expected_literal:
                    raise AssertionError(
                        f"{settings_page_name} cfg_{default_key}Default initializer {literal} "
                        f"drifts from the main.xml default {expected_literal}"
                    )

    def test_form_sections(self):
        assert_form_sections(
            general_text,
            "configGeneral.qml",
            ("Refresh", "Privacy", "Usage history", "Updates", "CLI updates", "Defaults"),
        )
        assert_form_sections(
            popup_text,
            "configPopup.qml",
            ("Usage details", "Popup"),
        )

        assert_form_sections(panel_surface.text, "configPanel.qml", ("Appearance", "Contents", "Panel visibility"))
        assert_form_sections(notifications_surface.text, "configNotifications.qml", ("Quota warnings", "Notifications"))
        assert_form_sections(diagnostics_text, "configDiagnostics.qml",
                             ("Support report", "Connection", "Versions", "Advanced provider override"))

    def test_diagnostics_versions_summary(self):
        # The environment summary is what a bug report needs: the widget and CLI
        # versions plus the absolute command Plasma actually resolved, which the
        # configured value hides whenever it is a bare name resolved through PATH.
        for needle in ('i18n("CodexBar Plasma:")', 'i18n("CodexBar CLI:")',
                       'i18n("Resolved command:")', 'i18n("Check versions")',
                       "Controllers.CliUpdateController", "localOnly: true"):
            if not code_contains(diagnostics_text, needle):
                raise AssertionError(f"configDiagnostics.qml must keep the versions summary: {needle}")

    def test_managed_cli_auto_update_stays_reachable(self):
        # Managed-CLI automatic updates apply only to the managed copy, so the checkbox
        # dims once another command is selected. It must stay reachable while it is
        # still on, or the setting is stranded with no way to switch it back off.
        if not re.search(
            r"enabled:\s*\(managedCli\.selected\s*\|\|\s*page\.cfg_cliAutomaticUpdates\)",
            general_text,
        ):
            raise AssertionError(
                "configGeneral.qml must keep the managed CLI automatic update checkbox "
                "enabled while cfg_cliAutomaticUpdates is set"
            )

    def test_presentation_pages_stay_process_free(self):
        # Presentation pages must not acquire provider processes or claim configuration
        # owned by an unrelated page when Plasma saves its cfg_* creation properties.
        # The Panel page deliberately loads the read-only enabled roster through the
        # shared controller to offer the panel provider selection: the process stays in
        # the controller, gated on the selection being expanded, and the page reads the
        # command path and provider order at runtime instead of claiming their cfg keys.
        panel_page_text = (root / "contents/ui/configPanel.qml").read_text(encoding="utf-8")
        panel_preview_page_text = (root / "contents/ui/components/PanelSettingsPreview.qml").read_text(encoding="utf-8")
        for page_text, page_name in (
            (panel_page_text, "configPanel.qml"),
            (panel_preview_page_text, "PanelSettingsPreview.qml"),
        ):
            for forbidden_page_fragment in (
                "Plasma5Support.DataSource",
                "connectSource(",
                "cfg_commandPath",
                "cfg_providerOrder",
            ):
                if forbidden_page_fragment in page_text:
                    raise AssertionError(
                        f"{page_name} must stay process-free and not claim another page's "
                        f"configuration: unexpected {forbidden_page_fragment!r}"
                    )
        for controller_fragment in (
            "Controllers.ProviderRosterController {",
            "active: page.providersExpanded",
            "presentationConfig.commandPath",
        ):
            if not code_contains(panel_page_text, controller_fragment):
                raise AssertionError(
                    f"configPanel.qml must load the roster through the gated shared controller; "
                    f"missing {controller_fragment!r}"
                )
        panel_surface.require(
            "function loadProviderRoster(",
            "the shared roster controller must own the panel and popup roster loads",
        )
        for key, control in (("privacyMode", "privacyModeCheck"), ("refreshOnOpen", "refreshOnOpenCheck")):
            general_surface.require(f"property alias cfg_{key}: {control}.checked", "General must expose the pending setting")
        for key in ("showPopupPace", "showPopupCredits", "showPopupProviderDetails"):
            popup_surface.require(f"property alias cfg_{key}: {key}Check.checked", "Popup content must stay configurable")
        panel_surface.require("Components.PanelSettingsPreview {", "Panel must preview pending settings")
        panel_surface.require("configPage: page", "Preview must use the actual pending config")

    def test_update_status(self):
        for label_id in ("lastUpdateCheckLabel", "lastUpdateStatusLabel"):
            require_block_fragment(general_qml, f"id: {label_id}", "Layout.fillWidth: true")
            require_block_fragment(general_qml, f"id: {label_id}", "wrapMode: Text.WordWrap")

        for runtime_cfg in (
            "cfg_autoUpdateLastCheck",
            "cfg_widgetUpdateLastStatus",
            "cfg_widgetUpdateLastError",
            "cfg_providerConfigRevision",
        ):
            if runtime_cfg in general_text:
                raise AssertionError(
                    f"configGeneral.qml must not save runtime-owned {runtime_cfg} on Apply"
                )
        for live_config_fragment in (
            "Plasmoid.configuration.autoUpdateLastCheck",
            "Plasmoid.configuration.widgetUpdateLastStatus",
            "Plasmoid.configuration.widgetUpdateLastError",
        ):
            if not code_contains(general_text, live_config_fragment):
                raise AssertionError(
                    "configGeneral.qml must read update status directly from runtime config; "
                    f"missing {live_config_fragment!r}"
                )

        last_update_check_body = function_body(general_text, "lastUpdateCheckText")
        for last_check_fragment in (
            "UpdateLogic.lastCheckMs(value)",
            'i18n("Last checked: never")',
            "Qt.locale().toString(checkedAt, Locale.ShortFormat)",
        ):
            if not code_contains(last_update_check_body, last_check_fragment):
                raise AssertionError(
                    "General must display the last update check in the local short format; "
                    f"missing {last_check_fragment!r}"
                )
        last_update_check_label = id_block(general_text, "lastUpdateCheckLabel")
        if "page.lastUpdateCheckText(autoUpdateLastCheck)" not in last_update_check_label:
            raise AssertionError("the last update check label must use the bounded local formatter")
        # The manual updater records results where the applet's automatic updater does.
        for fragment in (
            "widgetUpdater.runNow(widgetUpdater.availableVersion.length > 0)",
            "Plasmoid.configuration.widgetUpdateLastStatus = statusText",
            "Plasmoid.configuration.autoUpdateLastCheck = timestamp",
        ):
            if not code_contains(general_text, fragment):
                raise AssertionError(f"General must offer a manual widget update; missing {fragment!r}")

    def test_diagnostics_controls(self):
        require_block_fragment(diagnostics_qml, "id: usePathCommandButton", 'text: i18n("Use PATH")')
        require_block_fragment(
            diagnostics_qml,
            "id: usePathCommandButton",
            'enabled: page.cfg_commandPath.trim() !== (page.cfg_commandPathDefault || "codexbar")',
        )
        require_block_fragment(
            diagnostics_qml,
            "id: usePathCommandButton",
            'page.cfg_commandPath = page.cfg_commandPathDefault || "codexbar"',
        )
        require_block_fragment(diagnostics_qml, "id: diagnosticProviderField", "maximumLength: 256")
        require_block_fragment(diagnostics_qml, "id: diagnosticOutputArea", "selectByMouse: true")
        # The README must have users discover the executable instead of assuming an
        # installation-specific location.
        readme_text = (root / "README.md").read_text(encoding="utf-8")
        if "command -v codexbar" not in readme_text:
            raise AssertionError("README.md must discover the CLI with `command -v codexbar`")
        for stale_readme_fragment in ("yay -S codexbar-cli", "for example `/usr/bin/codexbar`"):
            if stale_readme_fragment in readme_text:
                raise AssertionError(f"README.md must not suggest {stale_readme_fragment!r}")

        command_path_row_body = diagnostics_surface.id_block("commandPathRow")
        command_path_row_layout = command_path_row_body.split("Controls.TextField {", 1)[0]
        if "Layout.maximumWidth: Kirigami.Units.gridUnit * 24" not in command_path_row_layout:
            raise AssertionError(
                "the command path row must stay bounded in the FormLayout control column so resizing "
                "cannot push Use PATH outside the visible page"
            )

        advanced_override_body = id_block(diagnostics_text, "advancedOverrideExplanation")
        for explanation_fragment in (
            "Layout.fillWidth: true",
            "Layout.preferredWidth: Kirigami.Units.gridUnit * 24",
            "wrapMode: Text.WordWrap",
            "font: Kirigami.Theme.smallFont",
        ):
            if not code_contains(advanced_override_body, explanation_fragment):
                raise AssertionError(
                    "Advanced override guidance must remain a readable full-width form row; "
                    f"missing {explanation_fragment!r}"
                )
        if "Kirigami.FormData.label:" in advanced_override_body:
            raise AssertionError("Advanced override guidance must not masquerade as a field label")
        if not code_contains(diagnostics_text, 'Kirigami.FormData.label: i18n("Advanced provider override")'):
            raise AssertionError("Diagnostics must retain the provider override section title")
        if not code_contains(diagnostics_text, "Kirigami.FormData.isSection: true"):
            raise AssertionError("Advanced provider override must use the shared Kirigami section hierarchy")

    def test_notification_status_incidents_follow_toggles(self):
        require_block_fragment(
            root / "contents/ui/configNotifications.qml",
            "id: notifyStatusIncidentsCheck",
            "enabled: enableNotificationsCheck.checked && page.includeStatus",
        )

    def test_cost_history_settings_stay_pending(self):
        # Plasma injects cfg_* creation properties, so declarative cfg_* bindings do not
        # stay live. The General surface must observe the runtime values explicitly and
        # keep user edits pending until Apply.
        for live_binding in (
            "cfg_costHistoryDays: Plasmoid.configuration.costHistoryDays",
            "cfg_costHistoryMetric: Plasmoid.configuration.costHistoryMetric",
        ):
            general_surface.reject(live_binding, "cost history settings must stay pending until Apply")

    def test_dismissible_messages_restore_visibility(self):
        assert_dismissible_message_restores_visibility(
            providers_surface, "providerErrorMessage", "page.errorText"
        )
        assert_dismissible_message_restores_visibility(
            providers_surface, "providerStatusMessage", "page.statusText"
        )
        assert_dismissible_message_restores_visibility(
            diagnostics_surface, "diagnosticErrorMessage", "page.diagnosticError"
        )

    def test_popup_page_provider_order(self):
        overview_provider_selection_body = popup_surface.id_block("overviewProviderSelection")
        if not code_contains(overview_provider_selection_body, 'model: page.orderedEnabledProviderRoster'):
            raise AssertionError(
                "Popup must show the saved provider order in the Overview selection"
            )
        if "orderedEnabledProviderRoster" not in popup_surface.function_body("overviewRosterProviderIDs"):
            raise AssertionError(
                "overviewRosterProviderIDs must use the saved provider order"
            )
        for overview_order_function in (
            "resolvedOverviewProviderIDs",
            "toggleOverviewProvider",
        ):
            overview_order_body = popup_surface.function_body(overview_order_function)
            if "orderedEnabledProviderRoster" not in overview_order_body \
                    and "overviewRosterProviderIDs()" not in overview_order_body:
                raise AssertionError(
                    f"{overview_order_function} must use the saved provider order"
                )
        for overview_delegate_function in (
            "resolvedOverviewProviderIDs",
            "parseOverviewProviderIDs",
            "overviewProviderSelected",
            "toggleOverviewProvider",
        ):
            if "OverviewProviders." not in popup_surface.function_body(overview_delegate_function):
                raise AssertionError(
                    f"{overview_delegate_function} must delegate to OverviewProviders so "
                    "the checkboxes cannot drift from the runtime selection"
                )

        popup_surface.reject('source: "handle-sort"',
            "Arrow-based ordering must not advertise unsupported dragging")

        if not code_contains(popup_text, "required property int index"):
            raise AssertionError("the panel element editor delegate must explicitly receive its model index")


if __name__ == "__main__":
    unittest.main()
