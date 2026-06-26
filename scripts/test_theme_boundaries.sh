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
required_provider_colors = """
codex openai azureopenai claude cursor opencode opencodego alibaba
alibabatokenplan factory gemini antigravity copilot devin zai minimax
manus kimi kilo kiro vertexai augment jetbrains kimik2 moonshot amp
t3chat ollama synthetic warp openrouter elevenlabs windsurf zed
perplexity mimo doubao abacus mistral deepseek codebuff crof venice
commandcode stepfun bedrock grok groq llmproxy litellm deepgram poe
chutes
""".split()

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

for path in [root / "contents/ui/main.qml", root / "contents/ui/configProviders.qml"]:
    body = function_body(path.read_text(encoding="utf-8"), "providerColor")
    cases = set(re.findall(r'case "([^"]+)":', body))
    missing = [provider for provider in required_provider_colors if provider not in cases]
    if missing:
        joined = ", ".join(missing)
        print(f"missing provider brand color in {path.relative_to(root)}: {joined}", file=sys.stderr)
        sys.exit(1)

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
