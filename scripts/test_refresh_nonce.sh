#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT_DIR}/scripts/lib/qml_surfaces.sh"

# Every external process must carry a per-run nonce so a late result cannot be
# mistaken for a fresh one. That rule follows the command, not the file it lives
# in, so assert it across the whole surface.

require_in_surface applet "function commandWithRunNonce(command)"
require_in_surface applet "function withRunNonce(command, serial)"
require_in_surface applet "commandWithRunNonce(commandSource)"
require_in_surface applet "commandWithRunNonce(costCommandSource)"
require_in_surface applet "commandWithRunNonce(sessionsCommandSource)"
require_in_surface applet "commandWithRunNonce(providerConfigCommandSource)"
# The nonce alone does not drop a late result; the ledger does, by no longer
# holding the retired source name. Assert that routing reads the ledger and not
# a parallel per-kind string that could disagree with it.
require_in_surface applet "CommandLedger.find(root.activeCommandDescriptors, sourceName)"
reject_in_surface applet "property string connectedCommandSource"
reject_in_surface applet "property string connectedCostCommandSource"
reject_in_surface applet "property string connectedSessionsCommandSource"
reject_in_surface applet "property string connectedProviderConfigCommandSource"
require_in_surface applet "var baseCommand = buildProviderUsageCommand(providerID)"
require_in_surface applet "sourceName: commandWithRunNonce(baseCommand)"
require_in_surface applet 'connectNotificationCommand(commandWithRunNonce(":; " + command))'
reject_in_surface applet "notificationSource.connectSource(command)"

sh -n <<'SH'
CODEXBAR_PLASMA_RUN=1 :; if command -v notify-send >/dev/null 2>&1; then notify-send -- "CodexBar" "Test"; fi
SH

require_in_surface providers "property int commandRunSerial: 0"
require_in_surface providers 'import "CommandLedger.js" as CommandLedger'
reject_in_surface providers "function commandWithRunNonce(command)"
require_in_surface providers "function disconnectCommandsByKind(kind)"
require_in_surface providers "disconnectCommandsByKind(\"list\")"
require_in_surface providers "commandRunSerial += 1"
require_in_surface providers "var sourceName = CommandLedger.withRunNonce(command, commandRunSerial)"
require_in_surface providers "commands = CommandLedger.opened(commands, sourceName, nextDescriptor)"
require_in_surface providers "configSource.connectSource(sourceName)"
reject_in_surface providers "existing[command] = descriptor"
reject_in_surface providers "configSource.connectSource(command)"

require_in_surface display "property int commandRunSerial: 0"
require_in_surface display 'import "CommandLedger.js" as CommandLedger'
reject_in_surface display "function commandWithRunNonce(command)"
require_in_surface display "commandRunSerial += 1"
require_in_surface display "var sourceName = CommandLedger.withRunNonce(command, commandRunSerial)"
require_in_surface display "overviewProviderCommands = CommandLedger.opened("
require_in_surface display "overviewProviderSource.connectSource(sourceName)"

reject_in_surface applet "console.log(\"CodexBar"
reject_in_surface providers "console.log(\"CodexBar"

echo "KDE plasmoid refresh nonce checks passed."
