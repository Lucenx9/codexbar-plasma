"""Static UI checks for theme contrast and provider accent colors."""

import unittest

from ui_regression_support import (
    Surface,
    code_contains,
    compact_representation_qml,
    function_body,
    overview_provider_row_qml,
    provider_config_row_qml,
    provider_detail_section_qml,
    provider_usage_row_qml,
    providers_qml,
    root,
    theme_contrast_js,
)

# The popup UI rules below belong to the plasmoid surface, not to main.qml
# specifically, so read the surface as one text. Extracting the popup into a
# component keeps these assertions meaningful instead of silently unhooking them.
applet = Surface("applet", root)
main_text = applet.text
providers_text = providers_qml.read_text(encoding="utf-8")
theme_contrast_text = theme_contrast_js.read_text(encoding="utf-8")
provider_config_row_text = provider_config_row_qml.read_text(encoding="utf-8")
provider_usage_row_text = provider_usage_row_qml.read_text(encoding="utf-8")
overview_provider_row_text = overview_provider_row_qml.read_text(encoding="utf-8")
provider_detail_section_text = provider_detail_section_qml.read_text(encoding="utf-8")
compact_representation_text = compact_representation_qml.read_text(encoding="utf-8")


class ThemeTest(unittest.TestCase):
    def test_contrast_helpers(self):
        for function_name in (
            "linearColorChannel",
            "relativeLuminance",
            "contrastRatio",
            "interpolateColor",
            "maximumContrastColor",
            "readableAccentColor",
        ):
            if not code_contains(theme_contrast_text, f"function {function_name}("):
                raise AssertionError(f"ThemeContrast.js must define contrast helper {function_name}")

        for function_name in ("readableAccentColor", "providerReadableColor"):
            if not code_contains(main_text, f"function {function_name}("):
                raise AssertionError(f"main.qml must expose theme contrast wrapper {function_name}")

        readable_accent_body = function_body(main_text, "readableAccentColor")
        for contrast_fragment in (
            "ThemeContrast.readableAccentColor(",
            "accent",
            "surface",
            "Kirigami.Theme.textColor",
        ):
            if not code_contains(readable_accent_body, contrast_fragment):
                raise AssertionError(
                    "readableAccentColor must preserve provider hue while enforcing "
                    f"non-text contrast; missing {contrast_fragment!r}"
                )

        shared_readable_accent_body = function_body(theme_contrast_text, "readableAccentColor")
        for contrast_fragment in (
            "contrastRatio(accent, background) >= minimumNonTextContrastRatio",
            "interpolateColor(accent, themeTextColor, step / 10)",
            "contrastRatio(candidate, background) >= minimumNonTextContrastRatio",
            "maximumContrastColor(background)",
        ):
            if not code_contains(shared_readable_accent_body, contrast_fragment):
                raise AssertionError(
                    "ThemeContrast.readableAccentColor must preserve hue while enforcing "
                    f"non-text contrast; missing {contrast_fragment!r}"
                )

        provider_readable_body = function_body(main_text, "providerReadableColor")
        if not code_contains(provider_readable_body, "readableAccentColor(" not in provider_readable_body or "providerColor(value)"):
            raise AssertionError("providerReadableColor must derive a safe color from canonical provider metadata")

    def test_provider_accents(self):
        config_provider_readable_body = function_body(providers_text, "providerReadableColor")
        for contrast_fragment in (
            "ThemeContrast.readableAccentColor(",
            "providerColor(value)",
            "Kirigami.Theme.textColor",
        ):
            if not code_contains(config_provider_readable_body, contrast_fragment):
                raise AssertionError(
                    "configProviders.qml must share the provider contrast contract; "
                    f"missing {contrast_fragment!r}"
                )
        if not code_contains(provider_config_row_text, "providerReadableColor("):
            raise AssertionError("ProviderConfigRow must keep unselected provider icons theme-readable")
        if not code_contains(provider_config_row_text, 'Accessible.name: i18n("Enable %1", providerRow.providerData.displayName)'):
            raise AssertionError("ProviderConfigRow switches must name the provider for assistive technology")
        if not code_contains(provider_config_row_text, 'i18n("%1 - CodexBar default", providerRow.providerData.provider)'):
            raise AssertionError("ProviderConfigRow must distinguish the CodexBar default from widget defaults")

        for source_name, source_text in (
            ("ProviderUsageRow.qml", provider_usage_row_text),
            ("ProviderDetailSection.qml", provider_detail_section_text),
            ("CompactRepresentation.qml", compact_representation_text),
            ("OverviewProviderRow.qml", overview_provider_row_text),
        ):
            if not code_contains(source_text, "providerReadableColor("):
                raise AssertionError(f"{source_name} must use a theme-readable provider accent")

        quota_meter_color_body = function_body(main_text, "quotaMeterColor")
        if not code_contains(quota_meter_color_body, "statusBadgeColor("):
            raise AssertionError(
                "quotaMeterColor must reuse statusBadgeColor so the quota level and the "
                "provider status badge stay one colour vocabulary"
            )
        quota_severity_body = function_body(main_text, "quotaSeverity")
        if not code_contains(quota_severity_body, "showQuotaWarningMarkers"):
            raise AssertionError(
                "the setting that hides the quota markers must also hide the quota "
                "meter colour, so one switch owns the whole warning presentation"
            )
        for meter_surface, meter_surface_text in (
            (overview_provider_row_qml, overview_provider_row_text),
            (provider_usage_row_qml, provider_usage_row_text),
            (compact_representation_qml, compact_representation_text),
        ):
            if not code_contains(meter_surface_text, "quotaMeterColor("):
                raise AssertionError(
                    f"{meter_surface.name} must colour its meter fill through "
                    "quotaMeterColor; a meter that stays provider-coloured at 99% used "
                    "reads exactly like an idle one"
                )

        for selected_row_fragment in (
            "readonly property color selectedForeground: ThemeContrast.readableTextColor(",
            "readonly property color selectedSecondaryForeground: ThemeContrast.readableTextColor(",
            "? providerRow.selectedForeground",
            "? providerRow.selectedSecondaryForeground",
        ):
            if not code_contains(provider_config_row_text, selected_row_fragment):
                raise AssertionError(
                    "ProviderConfigRow selected state must set explicit contrast-aware "
                    f"text colors; missing {selected_row_fragment!r}"
                )

        if "ThemeContrast.readableTextColor(" not in applet.id_block("providerStatusBadgeLabel"):
            raise AssertionError("provider incident badge text must use the shared text contrast rule")


if __name__ == "__main__":
    unittest.main()
