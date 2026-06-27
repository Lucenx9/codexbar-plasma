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

require_line "function connectUsageCommand(sourceName)"
require_line "function finishUsageCommandSource(sourceName)"
require_line "function retireUsageCommands()"
require_line "id: usageRefreshTimer"
require_line "running: root.refreshIntervalSec > 0"
require_line "onTriggered: root.refreshNow()"
require_line "interval: 0"
require_line "root.finishUsageCommandSource(sourceName)"
require_line "delete commands[sourceName]"
require_line "pendingProviderCount = 0"

reject_line "interval: root.refreshIntervalSec > 0 ? root.refreshIntervalSec * 1000 : 0"
reject_line "pendingProviderCount = fallbackProviderOrder.length"

echo "KDE plasmoid process lifecycle checks passed."
