#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QML="${ROOT_DIR}/contents/ui/main.qml"
PROVIDERS_QML="${ROOT_DIR}/contents/ui/configProviders.qml"

require_in_file() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq "$needle" "$file"; then
    echo "missing expected QML fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

reject_in_file() {
  local file="$1"
  local needle="$2"
  if grep -Fq "$needle" "$file"; then
    echo "unexpected QML fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

require_in_file "$QML" "function commandWithRunNonce(command)"
require_in_file "$QML" "connectedCommandSource = commandWithRunNonce(commandSource)"
require_in_file "$QML" "connectedCostCommandSource = commandWithRunNonce(costCommandSource)"
require_in_file "$QML" "connectedProviderConfigCommandSource = commandWithRunNonce(providerConfigCommandSource)"
require_in_file "$QML" "var baseCommand = buildProviderUsageCommand(providerID, true)"
require_in_file "$QML" "var command = commandWithRunNonce(baseCommand)"

require_in_file "$PROVIDERS_QML" "property int commandRunSerial: 0"
require_in_file "$PROVIDERS_QML" "function commandWithRunNonce(command)"
require_in_file "$PROVIDERS_QML" "function disconnectCommandsByKind(kind)"
require_in_file "$PROVIDERS_QML" "disconnectCommandsByKind(\"list\")"
require_in_file "$PROVIDERS_QML" "var sourceName = commandWithRunNonce(command)"
require_in_file "$PROVIDERS_QML" "existing[sourceName] = nextDescriptor"
require_in_file "$PROVIDERS_QML" "configSource.connectSource(sourceName)"
reject_in_file "$PROVIDERS_QML" "existing[command] = descriptor"
reject_in_file "$PROVIDERS_QML" "configSource.connectSource(command)"

reject_in_file "$QML" "console.log(\"CodexBar"
reject_in_file "$PROVIDERS_QML" "console.log(\"CodexBar"

echo "KDE plasmoid refresh nonce checks passed."
