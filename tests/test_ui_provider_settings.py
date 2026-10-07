"""Static UI checks for the Providers settings page."""

import re
import unittest

from ui_regression_support import (
    Surface,
    code_contains,
    function_body,
    id_block,
    providers_qml,
    root,
)

providers_surface = Surface("providers", root)
providers_surface_text = providers_surface.text
providers_text = providers_qml.read_text(encoding="utf-8")
providers = Surface("providers", root)


class ProviderSettingsTest(unittest.TestCase):
    def test_focused_controls_scroll_into_view(self):
        providers_surface.require_definition_where_used("revealFocusedProviderControl")
        for focus_fragment in (
            "target: page.Window",
            "function onActiveFocusItemChanged()",
            "page.revealFocusedProviderControl()",
        ):
            providers_surface.require(focus_fragment, "provider settings must reveal focused controls")
        focused_provider_control_body = providers_surface.function_body("revealFocusedProviderControl")
        for focus_fragment in (
            "ancestor !== providerContent",
            "page.flickable.contentItem.mapFromItem(control, 0, 0)",
            "page.ensureVisible(control, position.x - control.x, position.y - control.y)",
        ):
            if not code_contains(focused_provider_control_body, focus_fragment):
                raise AssertionError("provider focus scrolling must be scoped to the page content")

    def test_provider_groups_follow_saved_order(self):
        for provider_group_fragment in (
            'import "ProviderOrder.js" as ProviderOrder',
            "property string cfg_providerOrder",
            "ProviderOrder.settingsGroups(",
            "model: page.visibleEnabledProviders",
            "model: page.visibleDisabledProviders",
        ):
            providers_surface.require(provider_group_fragment, "provider settings must group by the saved order")

    def test_api_key_setup_gates(self):
        api_key_setup_body = function_body(providers_text, "supportsApiKeySetup")
        for provider in ("crossmodel", "clawrouter", "fireworks"):
            if not code_contains(api_key_setup_body, f'case "{provider}":'):
                raise AssertionError(
                    f"supportsApiKeySetup must include released API-key provider {provider}"
                )
        if not code_contains(api_key_setup_body, "return fireworksSingleKeySetupSupported"):
            raise AssertionError(
                "Fireworks API-key setup must stay hidden until the CLI version proves slug discovery support"
            )
        fireworks_gate = re.search(
            r'((?:case "[^"]+":\s*)+)return fireworksSingleKeySetupSupported',
            api_key_setup_body,
        )
        if fireworks_gate is None or re.findall(
            r'case "([^"]+)":', fireworks_gate.group(1)
        ) != ["fireworks"]:
            raise AssertionError(
                "the CLI version gate must apply only to Fireworks API-key setup"
            )
        if "runCliVersionCommand()" not in function_body(providers_text, "reload"):
            raise AssertionError("provider reload must probe the selected CodexBar CLI version")
        cli_version_result_body = function_body(providers_text, "handleCliVersionResult")
        if not code_contains(cli_version_result_body, "ProviderConfigProtocol.cliVersionAtLeast("):
            raise AssertionError("the Providers page must gate versioned capabilities through the bounded CLI parser")

    def test_mutation_results(self):
        # Successful provider commands must be classified by the shared outcome
        # contract, never re-inlined with stderr consulted before the parsed payload:
        # loader diagnostics make successful runs print to stderr, and the inlined
        # order reported those runs as failures. The classification call itself is
        # executed-covered (forcing a literal success in handleToggleResult turns the
        # write-errors test red), so the surface pin is removed.

        # Failure precedence for provider mutations lives in
        # ProviderConfigProtocol.commandOutcome, covered adversarially by
        # tests/tst_provider_config_protocol.qml. The pages must classify results by
        # delegating to it instead of re-inlining an ordering around stderr.
        for mutation_handler in (
            function_body(providers_text, "handleToggleResult"),
            function_body(providers_text, "handleSetApiKeyResult"),
            function_body(providers_text, "parseCommandPayload"),
        ):
            if "ProviderConfigProtocol.commandOutcome(" not in mutation_handler:
                raise AssertionError(
                    "provider mutation handlers must classify CLI results through "
                    "ProviderConfigProtocol.commandOutcome"
                )

        handle_data_body = function_body(providers_text, "handleData")
        for handler_call in (
            "handleSetApiKeyResult(descriptor, stdoutText, stderrText, exitCode)",
            "handleDescriptorFieldResult(descriptor, stdoutText, stderrText, exitCode)",
            "handleDescriptorActionResult(descriptor, stdoutText, stderrText, exitCode)",
        ):
            if not code_contains(handle_data_body, handler_call):
                raise AssertionError(
                    "Provider mutation handlers must receive the executable exit code; "
                    f"missing {handler_call!r}"
                )

        if "codexbar did not return command data." not in function_body(providers_text, "parseCommandPayload"):
            raise AssertionError("parseCommandPayload must reject an empty successful descriptor response")

    def test_failed_reload_preserves_provider_list(self):
        provider_list_result_body = function_body(providers_text, "handleListResult")
        if "providers = []" in provider_list_result_body:
            raise AssertionError("a failed provider reload must preserve the last healthy provider list")
        for descriptor_fallback_fragment in (
            "providerDescriptorsUnavailable = true",
            "providerListHasSupportedDescriptors(next)",
            "runProviderListCommand(false)",
        ):
            if not code_contains(provider_list_result_body, descriptor_fallback_fragment):
                raise AssertionError(
                    "the Providers page must expose descriptor compatibility fallback state; "
                    f"missing {descriptor_fallback_fragment!r}"
                )
        provider_publish_index = provider_list_result_body.find("providers = next")
        descriptor_supported_index = provider_list_result_body.find(
            "providerListHasSupportedDescriptors(next)"
        )
        if provider_publish_index < 0 or descriptor_supported_index < provider_publish_index:
            raise AssertionError(
                "descriptor support must be confirmed only after a valid provider list is published"
            )

    def test_descriptor_fields(self):
        providers_surface.reject(
            "Provider-specific editing stays in the CodexBar CLI until it exposes a stable settings descriptor",
            "provider settings must render CLI descriptors",
        )

        if 'String(modelData.value || "")' in providers_text:
            raise AssertionError("descriptor text fields must preserve numeric zero")
        descriptor_value_body = providers_surface.function_body("valueText")
        if not code_contains(descriptor_value_body, "value === undefined || value === null"):
            raise AssertionError("descriptor value text must only blank nullish values")
        if not code_contains(providers_surface_text, "valueText: normalizedValueText"):
            raise AssertionError("normalized descriptor fields must retain nullish-safe display text")
        if not code_contains(providers_surface_text, "selectedOptionIndex: optionIndex(options, normalizedValueText)"):
            raise AssertionError("descriptor enum selection must read the nullish-safe value text")
        if not code_contains(providers_text, "text: modelData.valueText"):
            raise AssertionError("descriptor text fields must render normalized value text")
        if not code_contains(providers_text, "currentIndex: modelData.selectedOptionIndex"):
            raise AssertionError("descriptor enum fields must render the normalized selection")

        descriptor_enum_box = providers_surface.id_block("descriptorEnumBox")
        for fragment in (
            "property bool restoreBindingAfterWrite: false",
            "readonly property bool descriptorWritePending:",
            "onDescriptorWritePendingChanged:",
            "if (descriptorWritePending || !restoreBindingAfterWrite)",
            "restoreBindingAfterWrite = false",
            "currentIndex = Qt.binding(function()",
        ):
            if not code_contains(descriptor_enum_box, fragment):
                raise AssertionError(
                    "descriptor enum must restore its selection binding after a write result; "
                    f"missing {fragment!r}"
                )
        if "onActivated:" in descriptor_enum_box:
            raise AssertionError("descriptor enum activation must preserve the user's choice until Save")
        descriptor_enum_save = providers_surface.id_block("descriptorEnumSaveButton")
        descriptor_write_index = descriptor_enum_save.find("page.writeDescriptorField(")
        descriptor_restore_arm_index = descriptor_enum_save.find(
            "descriptorEnumBox.restoreBindingAfterWrite ="
        )
        if descriptor_write_index < 0 or descriptor_restore_arm_index < descriptor_write_index:
            raise AssertionError(
                "descriptor enum Save must submit the selected value before arming binding restore"
            )

    def test_provider_filters(self):
        providers.require("ProviderList.filteredProviders(providers, filterText, filterScope)",
                          "provider filters use the pure local projection")
        providers.require("maximumLength: 256", "bound provider search input")
        providers.require("helpfulAction: clearProviderFiltersAction", "empty provider results offer recovery")

    def test_cli_command_disclosure(self):
        provider_cli_toggle_body = id_block(providers_text, "providerCliCommandsToggle")
        for toggle_fragment in (
            'plainText: i18n("CLI commands")',
            "expanded: false",
            "onClicked: expanded = !expanded",
        ):
            if not code_contains(provider_cli_toggle_body, toggle_fragment):
                raise AssertionError(
                    "Provider CLI commands must remain available behind a compact native disclosure; "
                    f"missing {toggle_fragment!r}"
                )

        provider_cli_view_body = id_block(providers_text, "providerCliCommandsView")
        if not code_contains(provider_cli_view_body, "visible: providerCliCommandsToggle.expanded"):
            raise AssertionError("Provider CLI command output must follow the disclosure state")

        settings_toggle = providers_surface.id_block("providerSettingsToggle")
        for fragment in ("expanded: false", "onClicked: expanded = !expanded"):
            if fragment not in settings_toggle:
                raise AssertionError("Provider settings must start collapsed with a native disclosure control")
        settings_details = providers_surface.id_block("providerSettingsDetails")
        if "visible: providerSettingsToggle.expanded" not in settings_details:
            raise AssertionError("Provider settings details must follow the disclosure state")
        if "delegate: Components.ProviderConfigRow" in settings_details:
            raise AssertionError("Collapsing provider settings must leave the provider list available")
        if "!visible && providerSettingsToggle.expanded" not in settings_details:
            raise AssertionError("Collapsing provider settings must not dismiss a diagnostic error")

    def test_provider_list_layout(self):
        provider_list_heading_body = id_block(providers_text, "providerListHeading")
        for heading_fragment in (
            'text: i18n("Providers")',
            'i18np("%1 provider enabled", "%1 providers enabled", page.enabledCount)',
            "font.weight: Font.DemiBold",
        ):
            if not code_contains(provider_list_heading_body, heading_fragment):
                raise AssertionError(
                    "The provider list must retain a distinct, compact heading; "
                    f"missing {heading_fragment!r}"
                )

        provider_list_separator_body = id_block(providers_text, "providerListSeparator")
        if not code_contains(provider_list_separator_body, "Layout.fillWidth: true"):
            raise AssertionError("The provider list boundary must span the available width")

        ordered_provider_fragments = (
            "id: providerCliCommandsView",
            "id: providerListSeparator",
            "id: providerListHeading",
            "delegate: Components.ProviderConfigRow",
        )
        ordered_provider_indexes = [providers_text.index(fragment) for fragment in ordered_provider_fragments]
        if ordered_provider_indexes != sorted(ordered_provider_indexes):
            raise AssertionError("Provider details, list boundary, heading, and rows must keep their visual order")

    def test_reload_and_invalidation(self):
        if not code_contains(providers_text, "onCfg_commandPathChanged: handleCommandPathChanged()"):
            raise AssertionError("the Providers page must reload when the configured CLI path changes")

        descriptor_action_result_body = function_body(providers_text, "handleDescriptorActionResult")
        if not code_contains(descriptor_action_result_body, "bumpProviderConfigRevision()"):
            raise AssertionError("successful descriptor actions must invalidate the main applet snapshot")


if __name__ == "__main__":
    unittest.main()
