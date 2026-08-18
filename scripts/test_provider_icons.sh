#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_DIR="${ROOT_DIR}/contents/icons/providers"

missing=0
declare -A provider_key_aliases=()
declare -A provider_icon_aliases=()

while IFS=$'\t' read -r alias_kind alias_key alias_value; do
  if [[ "$alias_kind" == "provider" ]]; then
    provider_key_aliases["$alias_key"]="$alias_value"
  else
    provider_icon_aliases["$alias_key"]="$alias_value"
  fi
done < <(python3 - "$ROOT_DIR" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])

# Both the popup and the config page resolve icons through the one alias table in
# ProviderIdentity.js, so this check reads that module rather than a QML body.
text = (root / "contents/ui/ProviderIdentity.js").read_text(encoding="utf-8")

for kind, table_name in (("provider", "providerAliases"), ("icon", "providerIconFiles")):
    table = re.search(r"var " + table_name + r" = \{(.*?)\n\}", text, re.S)
    if not table:
        raise SystemExit(f"missing {table_name} table in ProviderIdentity.js")
    for key, value in re.findall(r'"([^"]+)":\s*"([^"]+)"', table.group(1)):
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

# Released official CodexBar v0.49.1 provider registry. The live CLI probe below
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
  fireworks
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
  ibmbob
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
