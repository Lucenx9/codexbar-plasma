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

for provider in chutes litellm poe sakana zed; do
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
