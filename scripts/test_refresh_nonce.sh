#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QML="${ROOT_DIR}/contents/ui/main.qml"

require_line() {
  local needle="$1"
  if ! grep -Fq "$needle" "$QML"; then
    echo "missing expected QML fragment: $needle" >&2
    exit 1
  fi
}

reject_line() {
  local needle="$1"
  if grep -Fq "$needle" "$QML"; then
    echo "unexpected QML fragment: $needle" >&2
    exit 1
  fi
}

require_line "function commandWithRunNonce(command)"
require_line "connectedCommandSource = commandWithRunNonce(commandSource)"
require_line "connectedCostCommandSource = commandWithRunNonce(costCommandSource)"
require_line "connectedProviderConfigCommandSource = commandWithRunNonce(providerConfigCommandSource)"
require_line "var baseCommand = buildProviderUsageCommand(providerID, true)"
require_line "var command = commandWithRunNonce(baseCommand)"

reject_line "console.log(\"CodexBar"

echo "KDE plasmoid refresh nonce checks passed."
