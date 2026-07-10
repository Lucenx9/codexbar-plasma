#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_DIR="${ROOT_DIR}/contents/icons/providers"

missing=0

require_icon() {
  local provider="$1"
  if [[ ! -f "${ICON_DIR}/${provider}.svg" && ! -f "${ICON_DIR}/${provider}.png" ]]; then
    echo "missing provider icon: ${provider}" >&2
    missing=1
  fi
}

# Released CodexBar v0.41.0 provider registry. The live CLI probe below adds an
# early warning when a newer installed release introduces another provider.
released_providers=(
  codex
  openai
  azureopenai
  claude
  cursor
  opencode
  opencodego
  alibaba
  alibabatokenplan
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
  kimik2
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
  crossmodel
  clawrouter
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
