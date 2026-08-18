#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT_DIR}/scripts/lib/qml_surfaces.sh"
THEME_CONTRAST_JS="${ROOT_DIR}/contents/ui/ThemeContrast.js"

require_in_surface applet "function providerColor(value)"
require_in_surface applet "function providerReadableColor(value, background)"
require_in_surface providers "function providerColor(value)"
require_in_surface providers "function providerReadableColor(value, background)"
require_in_surface applet 'import "ThemeContrast.js" as ThemeContrast'
require_in_surface providers 'import "ThemeContrast.js" as ThemeContrast'
require_in_file "$THEME_CONTRAST_JS" "var minimumNonTextContrastRatio = 3"
require_definition_where_used applet contrastTextColor
require_in_surface applet "Kirigami.Theme.textColor"
require_in_surface applet "Kirigami.Theme.highlightColor"
require_in_surface applet "Kirigami.Theme.negativeTextColor"
require_in_surface applet "Kirigami.Theme.neutralTextColor"

python3 - "$ROOT_DIR" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(root / "scripts/lib"))
from qml_surfaces import Surface, surface_files

# Raw colors are allowed only inside theme-derivation helpers, and only in the
# runtime and provider-config surfaces. Deriving that from the manifest means a
# component that takes over part of the popup gets checked rather than silently
# exempted, which is what the old `contents/ui/*.qml` glob did.
allowed_files = set(surface_files("applet", root)) | set(surface_files("providers", root))
patterns = [
    re.compile(r"Qt\.rgba\("),
    re.compile(r"#[0-9A-Fa-f]{3,8}"),
    re.compile(r'"(?:black|white)"'),
]
required_provider_colors = """
codex openai azureopenai claude clinepass cursor opencode opencodego alibaba
alibabatokenplan qwencloud factory gemini antigravity copilot devin zai minimax
manus kimi kilo kiro vertexai augment jetbrains kimik2 moonshot amp
t3chat ollama synthetic warp openrouter elevenlabs windsurf zed
perplexity mimo doubao abacus mistral deepseek codebuff crof venice
commandcode stepfun bedrock grok groq llmproxy litellm deepgram poe
chutes sakana deepinfra neuralwatt longcat sub2api zenmux aiand zoommate
xai notion
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

# Brand colors live once, as channel triples in ProviderIdentity.js, because the
# popup and the config page must not drift apart on what a provider looks like.
identity_text = (root / "contents/ui/ProviderIdentity.js").read_text(encoding="utf-8")
channels = re.search(r"var providerBrandChannels = \{(.*?)\n\}", identity_text, re.S)
if not channels:
    print("missing providerBrandChannels table in ProviderIdentity.js", file=sys.stderr)
    sys.exit(1)
branded = set(re.findall(r'"([^"]+)":\s*\[', channels.group(1)))
missing = [provider for provider in required_provider_colors if provider not in branded]
if missing:
    joined = ", ".join(missing)
    print(f"missing provider brand color in ProviderIdentity.js: {joined}", file=sys.stderr)
    sys.exit(1)

# Both surfaces must read that one table instead of growing a local palette.
for surface_name in ("applet", "providers"):
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
