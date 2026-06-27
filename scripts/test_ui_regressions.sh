#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERAL_QML="${ROOT_DIR}/contents/ui/configGeneral.qml"
PROVIDERS_QML="${ROOT_DIR}/contents/ui/configProviders.qml"

require_in_file() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "missing expected UI fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

require_block_fragment() {
  local file="$1"
  local block_id="$2"
  local needle="$3"
  if ! awk -v block_id="$block_id" -v needle="$needle" '
    index($0, block_id) { in_block = 1 }
    in_block && index($0, needle) { found = 1 }
    in_block && $0 ~ /^        }$/ { exit }
    END { exit found ? 0 : 1 }
  ' "$file"; then
    echo "missing expected UI fragment near ${block_id} in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

reject_in_file() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$file"; then
    echo "unexpected stale UI fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

require_in_file "$GENERAL_QML" "id: lastUpdateCheckLabel"
require_in_file "$GENERAL_QML" "id: lastUpdateStatusLabel"
require_block_fragment "$GENERAL_QML" "id: lastUpdateCheckLabel" "Layout.fillWidth: true"
require_block_fragment "$GENERAL_QML" "id: lastUpdateCheckLabel" "wrapMode: Text.WordWrap"
require_block_fragment "$GENERAL_QML" "id: lastUpdateStatusLabel" "Layout.fillWidth: true"
require_block_fragment "$GENERAL_QML" "id: lastUpdateStatusLabel" "wrapMode: Text.WordWrap"

require_in_file "$PROVIDERS_QML" "Provider-specific controls come from the CodexBar CLI descriptor"
reject_in_file "$PROVIDERS_QML" "Provider-specific editing stays in the CodexBar CLI until it exposes a stable settings descriptor"

echo "UI regression checks passed."
