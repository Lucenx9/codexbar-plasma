#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT_DIR}/scripts/lib/qml_surfaces.sh"

# The panel providerColor signature is owned by the Surface extraction below,
# which fails the check when the function is renamed or removed; the literal
# signature is not pinned here as well.
# Kept: the ThemeContrast import is unobservable in executed tests (removing
# it keeps every naming module green: each fixture imports the module itself,
# and the applet is never instantiated), so no mutation can prove this pin
# redundant. It stays as the only pin that the applet resolves its readable
# accents through the shared contrast helper.
require_in_surface applet 'import "ThemeContrast.js" as ThemeContrast'
require_definition_where_used applet contrastTextColor

python3 - "$ROOT_DIR" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(root / "scripts/lib"))
from qml_surfaces import Surface, surface_files

# Raw colors are allowed only inside theme-derivation helpers, and only in the
# runtime, provider-config, and panel-preview surfaces. Deriving that from the manifest means a
# component that takes over part of the popup gets checked rather than silently
# exempted, which is what the old `contents/ui/*.qml` glob did.
allowed_files = set().union(*(surface_files(name, root) for name in ("applet", "providers", "panel")))
patterns = [
    re.compile(r"Qt\.rgba\("),
    re.compile(r"#[0-9A-Fa-f]{3,8}"),
    re.compile(r'"(?:black|white)"'),
]
# Required provider colors are exercised through the public lookup in
# tests/tst_provider_metadata.qml. This check owns QML theme boundaries.

def current_function(text, index):
    for match in re.finditer(r"\n    function ([A-Za-z0-9_]+)\(", text[:index]):
        brace = text.find("{", match.end())
        depth = 0
        for cursor in range(brace, len(text)):
            if text[cursor] == "{":
                depth += 1
            elif text[cursor] == "}":
                depth -= 1
                if depth == 0:
                    if brace <= index < cursor:
                        return match.group(1)
                    break
    return ""

def allowed_qml(path, text, index):
    return (
        path in allowed_files
        and current_function(text, index) in {"providerColor", "contrastTextColor", "withAlpha"}
    )

def function_body(text, name):
    marker = f"    function {name}("
    start = text.find(marker)
    if start == -1:
        raise ValueError(f"missing function {name}")
    brace = text.find("{", start)
    depth = 0
    for index in range(brace, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[brace + 1:index]
    raise ValueError(f"unterminated function {name}")

# Every surface must read that one table instead of growing a local palette.
for surface_name in ("applet", "providers", "panel"):
    body = Surface(surface_name, root).function_body("providerColor")
    if "ProviderIdentity.providerBrandColorChannels(value)" not in body:
        print(
            f"providerColor in surface {surface_name} must read the shared brand table",
            file=sys.stderr,
        )
        sys.exit(1)
    if "Kirigami.Theme.highlightColor" not in body:
        print(
            f"providerColor in surface {surface_name} must fall back to the theme highlight",
            file=sys.stderr,
        )
        sys.exit(1)

for path in sorted(path for path in surface_files("all", root) if path.suffix == ".qml"):
    text = path.read_text(encoding="utf-8")
    for pattern in patterns:
        for match in pattern.finditer(text):
            if allowed_qml(path, text, match.start()):
                continue
            token = match.group(0)
            print(f"unexpected hardcoded generic UI color in {path.relative_to(root)}: {token}", file=sys.stderr)
            sys.exit(1)

print("Theme boundary checks passed.")
PY
