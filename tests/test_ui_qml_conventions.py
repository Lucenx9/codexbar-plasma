"""Static checks for QML conventions shared across the applet and settings pages."""

import re
import unittest

from ui_regression_support import (
    Surface,
    code_contains,
    copyable_value_qml,
    enclosing_element,
    plain_tool_tip_qml,
    root,
)

# The popup UI rules below belong to the plasmoid surface, not to main.qml
# specifically, so read the surface as one text. Extracting the popup into a
# component keeps these assertions meaningful instead of silently unhooking them.
applet = Surface("applet", root)
providers = Surface("providers", root)
copyable_value_text = copyable_value_qml.read_text(encoding="utf-8")
plain_tool_tip_text = plain_tool_tip_qml.read_text(encoding="utf-8")


class QmlConventionsTest(unittest.TestCase):
    def test_visible_text_avoids_dashes(self):
        # The dash rule follows the visible text, not the file it lives in: an em dash
        # in an extracted component reads the same in the popup as one in main.qml, so
        # assert it across the whole surface.
        for dash, dash_name in (("\u2014", "em dash"), ("\u2013", "en dash")):
            applet.reject(dash, f"visible UI text must avoid {dash_name} placeholders")

    def test_filling_labels_elide(self):
        # Popup and panel labels that fill the available width must truncate. A long
        # translation or a CLI-supplied title otherwise widens the row past the popup
        # instead of eliding, and the popup cannot grow to meet it.
        plain_label_component = re.compile(r"(?:Components\.)?Plain(?:PlasmaLabel|ControlsLabel|Heading)\s*\{")
        component_paths = set((root / "contents/ui/components").glob("*.qml"))
        component_paths.update((root / "contents/ui/config").glob("*.qml"))
        for component_path in sorted(component_paths):
            component_text = component_path.read_text(encoding="utf-8")
            for match in plain_label_component.finditer(component_text):
                body = Surface._match_braces(component_text, match.end() - 1)
                if "Layout.fillWidth: true" not in body:
                    continue
                if "elide" in body or "wrapMode" in body:
                    continue
                line = component_text.count("\n", 0, match.start()) + 1
                raise AssertionError(
                    f"{component_path.relative_to(root)}:{line}: a label that fills the width must "
                    "elide or wrap, so a long translation cannot push the row past the popup"
                )

    def test_tool_tip_delays(self):
        if not code_contains(plain_tool_tip_text, "delay: Kirigami.Units.toolTipDelay"):
            raise AssertionError(
                "PlainToolTip must default to the Plasma hover delay: Controls.ToolTip opens with no "
                "delay of its own, so a pointer crossing the popup flashes every tooltip it passes"
            )

    def test_copyable_value_feedback(self):
        if not code_contains(copyable_value_text, 'valueRow.copied ? "checkmark" : "edit-copy"'):
            raise AssertionError("CopyableValue must provide immediate checkmark icon feedback when copied")

        if not code_contains(copyable_value_text, "visible: copyButton.hovered && !valueRow.copied"):
            raise AssertionError(
                "the copy button's hover label must hide while the copied confirmation is "
                "shown, so feedback gets its own visibility transition"
            )
        if not code_contains(copyable_value_text, "visible: valueRow.copied"):
            raise AssertionError(
                "the copied confirmation must ride its own visibility transition: flipping delay "
                "on an already-visible tooltip would not restart the pending hover delay"
            )
        if not code_contains(copyable_value_text, "delay: 0"):
            raise AssertionError(
                "the copied confirmation must appear at once and outlive no hover delay"
            )

    def test_text_sizes_follow_theme_fonts(self):
        # Derived from the manifest rather than listed by hand, so a newly extracted
        # component is covered the moment it exists instead of when someone remembers to
        # add it here. JS helpers are excluded: these rules are about QML elements.
        popup_and_provider_surfaces = tuple(
            (path, applet.texts[path]) for path in applet.files if path.suffix == ".qml"
        ) + tuple(
            (path, providers.texts[path]) for path in providers.files if path.suffix == ".qml"
        )

        for surface, surface_text in popup_and_provider_surfaces:
            surface_lines = surface_text.splitlines()
            for line_number, line in enumerate(surface_lines):
                if not re.match(r"\s*opacity:\s", line):
                    continue
                element = enclosing_element(surface_lines, line_number)
                if "Label" not in element and "Heading" not in element:
                    continue
                if re.search(r"\b0\.\d+", line):
                    raise AssertionError(
                        f"{surface.name}:{line_number + 1} sets text opacity from a literal; "
                        "use secondaryTextOpacity or valueTextOpacity so the de-emphasis "
                        "scale stays consistent and above WCAG AA contrast"
                    )

        for surface, surface_text in popup_and_provider_surfaces:
            hardcoded_font = re.search(r"font\.pixelSize:\s*\d+(?:\.\d+)?", surface_text)
            if hardcoded_font:
                raise AssertionError(
                    "popup and provider-config text must size from Kirigami.Theme fonts, "
                    f"not device pixels: {surface.name}: {hardcoded_font.group(0)!r}"
                )

    def test_delegates_declare_model_data(self):
        for qml_path in sorted(root.glob("contents/**/*.qml")):
            qml_content = qml_path.read_text(encoding="utf-8")
            local_imports = {
                alias: qml_path.parent / directory
                for directory, alias in re.findall(
                    r'^import "([^"]+)" as (\w+)', qml_content, re.MULTILINE
                )
                if not directory.endswith(".js")
            }
            for match in re.finditer(r"delegate:\s*([A-Za-z0-9_.]+)\s*\{", qml_content):
                element_type = match.group(1)
                alias, separator, component_name = element_type.partition(".")
                if separator and alias in local_imports:
                    component_path = local_imports[alias] / f"{component_name}.qml"
                    if not component_path.exists():
                        raise AssertionError(f"missing external component delegate file: {component_path}")
                    component_content = component_path.read_text(encoding="utf-8")
                    if "required property var modelData" not in component_content:
                        raise AssertionError(
                            f"{component_path.name} must declare "
                            "'required property var modelData' for Qt 6 QML scoping safety"
                        )
                    continue
                start_index = match.end() - 1
                brace_depth = 1
                cursor = start_index + 1
                while cursor < len(qml_content) and brace_depth > 0:
                    if qml_content[cursor] == "{":
                        brace_depth += 1
                    elif qml_content[cursor] == "}":
                        brace_depth -= 1
                    cursor += 1
                delegate_body = qml_content[start_index + 1:cursor - 1]
                if not code_contains(delegate_body, "required property var modelData"):
                    raise AssertionError(
                        f"{qml_path.name} delegate {element_type} must declare "
                        "'required property var modelData' for Qt 6 QML scoping safety"
                    )


if __name__ == "__main__":
    unittest.main()
