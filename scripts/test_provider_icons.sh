#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_DIR="${ROOT_DIR}/contents/icons/providers"
MAIN_QML="${ROOT_DIR}/contents/ui/main.qml"

missing=0
declare -A provider_key_aliases=()
declare -A provider_icon_aliases=()

while IFS=$'\t' read -r alias_kind alias_key alias_value; do
  if [[ "$alias_kind" == "provider" ]]; then
    provider_key_aliases["$alias_key"]="$alias_value"
  else
    provider_icon_aliases["$alias_key"]="$alias_value"
  fi
done < <(python3 - "$MAIN_QML" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")

def function_body(name):
    start = text.index(f"function {name}(")
    brace = text.index("{", start)
    depth = 1
    index = brace + 1
    while depth:
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
        index += 1
    return text[brace + 1:index - 1]

for kind, function_name in (("provider", "providerKey"), ("icon", "providerIconSource")):
    body = function_body(function_name)
    aliases = re.search(r"var aliases = \{(.*?)\n\s*\}", body, re.S)
    if not aliases:
        raise SystemExit(f"missing aliases map in {function_name}")
    for key, value in re.findall(r'"([^"]+)":\s*"([^"]+)"', aliases.group(1)):
        print(f"{kind}\t{key}\t{value}")
PY
)

require_icon() {
  local provider="$1"
  local provider_key="${provider_key_aliases[$provider]:-$provider}"
  local icon_key="${provider_icon_aliases[$provider_key]:-$provider_key}"
  local icon_name
  if [[ "$icon_key" == *.* ]]; then
    icon_name="$icon_key"
  else
    icon_name="${icon_key}.svg"
  fi
  if [[ ! -f "${ICON_DIR}/${icon_name}" ]]; then
    echo "missing runtime provider icon: ${provider} -> ${icon_name}" >&2
    missing=1
  fi
}

# Released official CodexBar v0.48.1 provider registry. The live CLI probe below
# adds an early warning when a newer installed release introduces another provider.
released_providers=(
  codex
  openai
  azureopenai
  claude
  clinepass
  cursor
  opencode
  opencodego
  alibaba
  alibabatokenplan
  qwencloud
  factory
  gemini
  antigravity
  copilot
  devin
  zai
  minimax
  manus
  kimi
  kilo
  kiro
  vertexai
  augment
  jetbrains
  moonshot
  amp
  t3chat
  ollama
  synthetic
  warp
  openrouter
  elevenlabs
  windsurf
  zed
  perplexity
  mimo
  doubao
  sakana
  abacus
  mistral
  deepseek
  deepinfra
  codebuff
  crof
  venice
  commandcode
  qoder
  stepfun
  bedrock
  grok
  groq
  llmproxy
  litellm
  deepgram
  poe
  chutes
  neuralwatt
  clawrouter
  longcat
  sub2api
  wayfinder
  zenmux
  aiand
  zoommate
  xai
  notion
)

for provider in "${released_providers[@]}"; do
  require_icon "$provider"
done

if command -v codexbar >/dev/null 2>&1; then
  while IFS= read -r provider; do
    [[ -n "$provider" ]] || continue
    require_icon "$provider"
  done < <(codexbar config providers --format json --json-only 2>/dev/null | jq -r '.[].provider' 2>/dev/null || true)
fi

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

echo "KDE plasmoid provider icon checks passed."
