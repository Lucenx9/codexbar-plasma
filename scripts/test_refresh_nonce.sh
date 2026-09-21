#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT_DIR}/scripts/lib/qml_surfaces.sh"

# Every external process must carry a per-run nonce so a late result cannot be
# mistaken for a fresh one. That rule follows the command, not the file it lives
# in, so assert it across the whole surface.

# The cost controller mints its nonce inline (bare commandSource keeps the
# suite red: the CLI crashes without CODEXBAR_PLASMA_RUN, proven against
# test_manualRefreshSupersedesAnActiveScan), so this surface pin now covers
# only the sessions controller's identical call.
require_in_surface applet "CommandLedger.withRunNonce(commandSource, runSerial)"
# The nonce alone does not drop a late result; the ledger does, by no longer
# holding the retired source name. Assert that routing reads the ledger and not
# a parallel per-kind string that could disagree with it.
reject_in_surface applet "property string connectedCommandSource"
reject_in_surface applet "property string connectedCostCommandSource"
reject_in_surface applet "property string connectedSessionsCommandSource"
reject_in_surface applet "property string connectedProviderConfigCommandSource"
# Notifications register a unique source before connecting it. The dispatcher
# tests execute the real command.
require_in_surface applet 'var sourceName = CommandLedger.withRunNonce(command, runSerial)'
reject_in_surface applet "notificationSource.connectSource(command)"

reject_in_surface providers "function commandWithRunNonce(command)"
reject_in_surface providers "existing[command] = descriptor"
reject_in_surface providers "configSource.connectSource(command)"

reject_in_surface popup "function commandWithRunNonce(command)"

reject_in_surface applet "console.log(\"CodexBar"
reject_in_surface providers "console.log(\"CodexBar"

echo "KDE plasmoid refresh nonce checks passed."
