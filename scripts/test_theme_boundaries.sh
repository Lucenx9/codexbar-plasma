#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN_QML="${ROOT_DIR}/contents/ui/main.qml"
PROVIDERS_QML="${ROOT_DIR}/contents/ui/configProviders.qml"

require_in_file() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "missing expected theme fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

require_in_file "$MAIN_QML" "function providerColor(value)"
require_in_file "$PROVIDERS_QML" "function providerColor(value)"
require_in_file "$MAIN_QML" "function contrastTextColor(color)"
require_in_file "$MAIN_QML" "Kirigami.Theme.textColor"
require_in_file "$MAIN_QML" "Kirigami.Theme.highlightColor"
require_in_file "$MAIN_QML" "Kirigami.Theme.highlightedTextColor"
require_in_file "$MAIN_QML" "Kirigami.Theme.negativeTextColor"
require_in_file "$MAIN_QML" "Kirigami.Theme.neutralTextColor"

python3 - "$ROOT_DIR" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
allowed_files = {
    root / "contents/ui/main.qml",
    root / "contents/ui/configProviders.qml",
}
patterns = [
    re.compile(r"Qt\.rgba\("),
    re.compile(r"#[0-9A-Fa-f]{3,8}"),
    re.compile(r'"(?:black|white)"'),
]

def current_function(text, index):
    function_name = ""
    for match in re.finditer(r"\n    function ([A-Za-z0-9_]+)\(", text[:index]):
        function_name = match.group(1)
    return function_name

def allowed_qml(path, text, index):
    return (
        path in allowed_files
        and current_function(text, index) in {"providerColor", "contrastTextColor", "withAlpha"}
    )

for path in sorted((root / "contents/ui").glob("*.qml")):
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
