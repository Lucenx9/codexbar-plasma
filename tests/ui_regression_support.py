"""Shared assertions, AST-like helpers, and file paths for test_ui_*.py modules."""

from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / "scripts/lib"))
from qml_surfaces import Surface

__all__ = [
    "Surface",
    "root",
    "main_qml",
    "general_qml",
    "popup_qml",
    "providers_qml",
    "diagnostics_qml",
    "config_xml",
    "theme_contrast_js",
    "cost_presentation_js",
    "provider_accounts_panel_qml",
    "provider_header_qml",
    "provider_config_row_qml",
    "provider_usage_row_qml",
    "overview_provider_row_qml",
    "provider_detail_section_qml",
    "provider_cost_section_qml",
    "compact_representation_qml",
    "global_tab_qml",
    "interactive_chart_qml",
    "sessions_view_qml",
    "session_labels_qml",
    "copyable_value_qml",
    "spend_view_qml",
    "full_representation_qml",
    "cost_trust_notice_qml",
    "plain_tool_tip_qml",
    "code_contains",
    "function_body",
    "id_block",
    "qml_default_literal",
    "assert_form_sections",
    "assert_dismissible_message_restores_visibility",
    "enclosing_element",
    "require_block_fragment",
]

main_qml = root / "contents/ui/main.qml"
general_qml = root / "contents/ui/configGeneral.qml"
popup_qml = root / "contents/ui/configPopup.qml"
providers_qml = root / "contents/ui/configProviders.qml"
diagnostics_qml = root / "contents/ui/configDiagnostics.qml"
config_xml = root / "contents/config/main.xml"
theme_contrast_js = root / "contents/ui/ThemeContrast.js"
cost_presentation_js = root / "contents/ui/CostPresentation.js"
provider_accounts_panel_qml = root / "contents/ui/components/ProviderAccountsPanel.qml"
provider_header_qml = root / "contents/ui/components/ProviderHeader.qml"
provider_config_row_qml = root / "contents/ui/components/ProviderConfigRow.qml"
provider_usage_row_qml = root / "contents/ui/components/ProviderUsageRow.qml"
overview_provider_row_qml = root / "contents/ui/components/OverviewProviderRow.qml"
provider_detail_section_qml = root / "contents/ui/components/ProviderDetailSection.qml"
provider_cost_section_qml = root / "contents/ui/components/ProviderCostSection.qml"
compact_representation_qml = root / "contents/ui/components/CompactRepresentation.qml"
global_tab_qml = root / "contents/ui/components/GlobalTab.qml"
interactive_chart_qml = root / "contents/ui/components/InteractiveChart.qml"
sessions_view_qml = root / "contents/ui/components/SessionsView.qml"
session_labels_qml = root / "contents/ui/components/SessionLabels.qml"
copyable_value_qml = root / "contents/ui/components/CopyableValue.qml"
spend_view_qml = root / "contents/ui/components/SpendView.qml"
full_representation_qml = root / "contents/ui/components/FullRepresentation.qml"
cost_trust_notice_qml = root / "contents/ui/components/CostTrustNotice.qml"
plain_tool_tip_qml = root / "contents/ui/components/PlainToolTip.qml"


def code_contains(block, fragment):
    """Substring match that ignores the spacing qmlformat chooses."""
    def squeeze(value):
        value = value.replace("function (", "function(").replace(";", " ")
        return re.sub(r"\s+", " ", value).replace("( ", "(").replace(" )", ")")
    return squeeze(fragment) in squeeze(block)


def function_body(text, name):
    marker = f"function {name}("
    start = text.find(marker)
    if start < 0:
        raise AssertionError(f"missing function {name}")
    brace = text.find("{", start)
    depth = 1
    index = brace + 1
    while index < len(text) and depth > 0:
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
        index += 1
    if depth != 0:
        raise AssertionError(f"unterminated function {name}")
    return text[brace + 1:index - 1]


def id_block(text, object_id):
    marker = f"id: {object_id}"
    marker_index = text.find(marker)
    if marker_index < 0:
        raise AssertionError(f"missing id {object_id}")
    brace = text.rfind("{", 0, marker_index)
    if brace < 0:
        raise AssertionError(f"missing object body for id {object_id}")
    depth = 1
    index = brace + 1
    while index < len(text) and depth > 0:
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
        index += 1
    if depth != 0:
        raise AssertionError(f"unterminated object body for id {object_id}")
    return text[brace + 1:index - 1]


def qml_default_literal(entry_type, value):
    if entry_type == "String":
        return '"' + value + '"'
    if entry_type == "Bool":
        return "true" if value == "true" else "false"
    return str(int(value))


def assert_form_sections(text, filename, labels):
    for label in labels:
        pattern = re.compile(
            r"Kirigami\.Separator\s*\{[^}]*"
            + re.escape(f'Kirigami.FormData.label: i18n("{label}")')
            + r"[^}]*Kirigami\.FormData\.isSection:\s*true",
            re.S,
        )
        if not pattern.search(text):
            raise AssertionError(
                f"{filename} must expose a FormLayout section labelled {label!r}"
            )


def assert_dismissible_message_restores_visibility(surface, object_id, state_property):
    block = surface.id_block(object_id)
    for fragment in (
        f"if (visible || {state_property}.length === 0)",
        f'{state_property} = ""',
        f"visible = Qt.binding(function() {{ return {state_property}.length > 0 }})",
    ):
        if not code_contains(block, fragment):
            raise AssertionError(
                f"dismissible message {object_id!r} must clear only on close and restore "
                f"its visibility binding; missing {fragment!r}"
            )


def enclosing_element(source_lines, index):
    for cursor in range(index, -1, -1):
        opener = re.match(r"\s*([A-Z][A-Za-z.]*)\s*\{", source_lines[cursor])
        if opener:
            return opener.group(1)
    return ""


def require_block_fragment(file, block_id, needle):
    content = Path(file).read_text(encoding="utf-8")
    lines = content.splitlines()
    in_block = False
    found = False
    for line in lines:
        if block_id in line:
            in_block = True
        if in_block and needle in line:
            found = True
            break
        if in_block and line == "        }":
            break
    if not found:
        rel = Path(file).relative_to(root)
        raise AssertionError(
            f"missing expected UI fragment near {block_id} in {rel}: {needle}"
        )
