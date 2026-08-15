#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QML="${ROOT_DIR}/contents/ui/main.qml"
PROVIDERS_QML="${ROOT_DIR}/contents/ui/configProviders.qml"
DISPLAY_QML="${ROOT_DIR}/contents/ui/configDisplay.qml"
DEBUG_QML="${ROOT_DIR}/contents/ui/configDebug.qml"

require_in_file() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq "$needle" "$file"; then
    echo "missing expected lifecycle fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

reject_in_file() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$file"; then
    echo "unexpected lifecycle fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

require_in_file "$QML" "readonly property int usageCommandTimeoutMs: 120000"
require_in_file "$QML" "function connectUsageCommand(sourceName, descriptor)"
require_in_file "$QML" "function finishUsageCommandSource(sourceName)"
require_in_file "$QML" "function retireUsageCommands()"
require_in_file "$QML" "function expireUsageCommands(nowMs)"
require_in_file "$QML" "function handleUsageCommandTimeout(sourceName, descriptor)"
require_in_file "$QML" "id: usageCommandTimeoutTimer"
require_in_file "$QML" "root.expireUsageCommands(Date.now())"
require_in_file "$QML" "id: usageRefreshTimer"
require_in_file "$QML" "running: root.refreshIntervalSec > 0"
require_in_file "$QML" "if (!root.hasPendingUsageCommandTimeouts())"
require_in_file "$QML" "interval: 0"
require_in_file "$QML" "root.finishUsageCommandSource(sourceName)"
require_in_file "$QML" "delete commands[sourceName]"
require_in_file "$QML" "pendingProviderCount = 0"
require_in_file "$QML" "readonly property int accountCommandTimeoutMs: 60000"
require_in_file "$QML" "readonly property int sessionsCommandTimeoutMs: 60000"
require_in_file "$QML" "function refreshSessions()"
require_in_file "$QML" "id: accountCommandTimeoutTimer"
require_in_file "$QML" "root.expirePendingAccountCommands(Date.now())"
require_in_file "$QML" "readonly property int providerConfigWatchIntervalMs: 60000"
require_in_file "$QML" "interval: root.providerConfigWatchIntervalMs"

require_in_file "$PROVIDERS_QML" "readonly property int configCommandTimeoutMs: 60000"
require_in_file "$PROVIDERS_QML" "readonly property int configSecretCommandTimeoutSeconds: 60"
require_in_file "$PROVIDERS_QML" "readonly property int configSecretCommandKillAfterSeconds: 5"
require_in_file "$PROVIDERS_QML" "id: configCommandTimeoutTimer"
require_in_file "$PROVIDERS_QML" "page.expireConfigCommands(Date.now())"
require_in_file "$PROVIDERS_QML" "onCfg_commandPathChanged: handleCommandPathChanged()"

require_in_file "$DISPLAY_QML" "readonly property int overviewProviderCommandTimeoutMs: 60000"
require_in_file "$DISPLAY_QML" "function commandWithRunNonce(command)"
require_in_file "$DISPLAY_QML" "function expireOverviewProviderCommands(nowMs)"
require_in_file "$DISPLAY_QML" "id: overviewProviderCommandTimeoutTimer"
require_in_file "$DISPLAY_QML" "page.expireOverviewProviderCommands(Date.now())"

require_in_file "$DEBUG_QML" "readonly property int diagnosticCommandTimeoutMs: 60000"
require_in_file "$DEBUG_QML" "function commandWithRunNonce(command)"
require_in_file "$DEBUG_QML" "function handleDiagnosticTimeout()"
require_in_file "$DEBUG_QML" "id: diagnosticCommandTimeoutTimer"
require_in_file "$DEBUG_QML" "page.handleDiagnosticTimeout()"

reject_in_file "$QML" "retiredUsageCommands"
reject_in_file "$QML" "pendingAccountCommandStartedAt"
reject_in_file "$QML" "function retireUsageCommandSource(sourceName)"
reject_in_file "$QML" "interval: root.refreshIntervalSec > 0 ? root.refreshIntervalSec * 1000 : 0"
reject_in_file "$QML" "pendingProviderCount = fallbackProviderOrder.length"
reject_in_file "$QML" "--source cli"

python3 - "$QML" "$PROVIDERS_QML" "$DISPLAY_QML" "$DEBUG_QML" <<'PY'
import sys
from pathlib import Path

main_text = Path(sys.argv[1]).read_text(encoding="utf-8")
providers_text = Path(sys.argv[2]).read_text(encoding="utf-8")
display_text = Path(sys.argv[3]).read_text(encoding="utf-8")
debug_text = Path(sys.argv[4]).read_text(encoding="utf-8")


def function_body(text, name):
    marker = f"function {name}("
    start = text.find(marker)
    if start < 0:
        raise AssertionError(f"missing function {name}")
    brace = text.find("{", start)
    depth = 1
    index = brace + 1
    while index < len(text) and depth > 0:
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
        index += 1
    if depth != 0:
        raise AssertionError(f"unterminated function {name}")
    return text[brace + 1:index - 1]


retire_body = function_body(main_text, "retireUsageCommands")
if "finishUsageCommandSource(" not in retire_body:
    raise AssertionError("retiring active usage sources must disconnect them immediately")
if "connectedSessionsCommandSource" not in retire_body or "sessionsLoading = false" not in retire_body:
    raise AssertionError("retiring active usage sources must also retire the sessions command")

load_accounts_body = function_body(main_text, "loadAccounts")
for fragment in (
    "providerID: normalizedProviderID",
    "commandSignature: command",
    "deadlineMs: Date.now() + accountCommandTimeoutMs",
):
    if fragment not in load_accounts_body:
        raise AssertionError(f"loadAccounts must store one timeout descriptor: {fragment}")

parse_accounts_body = function_body(main_text, "parseProviderAccountsOutput")
for fragment in (
    "descriptor.providerID",
    "delete commands[sourceName]",
    "accountCommandIsCurrent(descriptor)",
):
    if fragment not in parse_accounts_body:
        raise AssertionError(f"normal account completion must reject stale context: {fragment}")

retire_stale_accounts_body = function_body(main_text, "retireStaleAccountCommands")
for fragment in (
    "accountCommandIsCurrent(descriptor)",
    "finishUsageCommandSource(sourceName)",
    "setAccountLoading(staleProviderID, false)",
):
    if fragment not in retire_stale_accounts_body:
        raise AssertionError(f"stale account cleanup is incomplete: {fragment}")

refresh_body = function_body(main_text, "refreshNow")
if "retireStaleAccountCommands()" not in refresh_body:
    raise AssertionError("refreshNow must retire account commands from an obsolete CLI context")

for function_name in ("buildProviderAccountsCommand", "buildProviderUsageCommand"):
    body = function_body(main_text, function_name)
    if 'if (source.length > 0)' not in body:
        raise AssertionError(f"{function_name} must preserve the automatic CLI source by default")
    if 'effectiveSource' in body or '"cli"' in body:
        raise AssertionError(f"{function_name} must not force Codex to the CLI source")

expire_accounts_body = function_body(main_text, "expirePendingAccountCommands")
for fragment in (
    "finishUsageCommandSource(sourceName)",
    "setAccountLoading(providerID, false)",
    "Loading accounts timed out. Try again.",
):
    if fragment not in expire_accounts_body:
        raise AssertionError(f"account timeout cleanup is incomplete: {fragment}")

expire_usage_body = function_body(main_text, "expireUsageCommands")
for fragment in ("descriptor.deadlineMs", "handleUsageCommandTimeout("):
    if fragment not in expire_usage_body:
        raise AssertionError(f"usage timeout scan is incomplete: {fragment}")

usage_timeout_body = function_body(main_text, "handleUsageCommandTimeout")
for fragment in (
    'descriptor.kind === "usage"',
    'descriptor.kind === "cost"',
    'descriptor.kind === "sessions"',
    'descriptor.kind === "providerConfig"',
    'descriptor.kind === "providerFallback"',
    "finishUsageCommandSource(sourceName)",
    "Loading usage timed out. Try again.",
    "Loading cost data timed out. Try again.",
    "Loading sessions timed out. Try again.",
    "Loading provider configuration timed out. Try again.",
):
    if fragment not in usage_timeout_body:
        raise AssertionError(f"usage timeout cleanup is incomplete: {fragment}")

fallback_result_body = function_body(main_text, "parseProviderFallbackOutput")
if fallback_result_body.count("completeProviderFallbackCommand()") != 2:
    raise AssertionError("every accepted fallback result path must complete its queue accounting")

complete_fallback_body = function_body(main_text, "completeProviderFallbackCommand")
for fragment in (
    "activeProviderFallbackCount = Math.max(0, activeProviderFallbackCount - 1)",
    "pendingProviderCount = Math.max(0, pendingProviderCount - 1)",
    "pumpProviderFallbackCommands()",
    "finishProviderFallback()",
):
    if fragment not in complete_fallback_body:
        raise AssertionError(f"fallback completion must preserve liveness: {fragment}")

refresh_timer_start = main_text.index("id: usageRefreshTimer")
refresh_timer_end = main_text.index("\n    Timer {", refresh_timer_start + 1)
refresh_timer_body = main_text[refresh_timer_start:refresh_timer_end]
for fragment in ("root.hasPendingUsageCommandTimeouts()", "root.refreshNow()"):
    if fragment not in refresh_timer_body:
        raise AssertionError(
            "periodic refreshes must not starve active command deadlines; "
            f"missing {fragment}"
        )

run_command_body = function_body(providers_text, "runCommand")
for fragment in ("nextDescriptor.timeoutMs", "nextDescriptor.deadlineMs", "nextDescriptor.commandPathSignature = commandPath"):
    if fragment not in run_command_body:
        raise AssertionError(f"runCommand must honor explicit command timeouts: {fragment}")

path_change_body = function_body(providers_text, "handleCommandPathChanged")
for fragment in ("retireAllConfigCommands()", "providers = []", "Qt.callLater(reload)"):
    if fragment not in path_change_body:
        raise AssertionError(f"changing the CLI path must retire stale page state: {fragment}")

retire_config_body = function_body(providers_text, "retireAllConfigCommands")
for fragment in (
    "configSource.disconnectSource(sourceName)",
    "commands = ({})",
    "pending = ({})",
    "providerFieldPending = ({})",
    "providerDiagnosticLoading = ({})",
):
    if fragment not in retire_config_body:
        raise AssertionError(f"config command retirement is incomplete: {fragment}")

handle_config_data_body = function_body(providers_text, "handleData")
if "descriptor.commandPathSignature !== commandPath" not in handle_config_data_body:
    raise AssertionError("config command results must reject a stale CLI path")

for function_name in ("runProviderListCommand", "setEnabled", "loadProviderSettings", "writeDescriptorField", "runDescriptorAction"):
    body = function_body(providers_text, function_name)
    if "timeoutMs: configCommandTimeoutMs" not in body:
        raise AssertionError(f"noninteractive {function_name} commands must be bounded")
for function_name in ("setApiKey", "promptDescriptorSecret"):
    body = function_body(providers_text, function_name)
    if "timeoutMs" in body:
        raise AssertionError(f"interactive {function_name} commands must not expire while prompting")
    for fragment in ("command -v timeout", "timeout --kill-after=1s 1s true", "timeout --kill-after", "configSecretCommandTimeoutSeconds", "configSecretCommandKillAfterSeconds"):
        if fragment not in body:
            raise AssertionError(
                f"interactive {function_name} must bound the post-prompt CLI phase: {fragment}"
            )

set_api_key_body = function_body(providers_text, "setApiKey")
if 'printf \'%s\' \\"$key\\" | timeout --kill-after=' not in set_api_key_body:
    raise AssertionError("setApiKey must pipe the secret to a bounded CLI process")

prompt_secret_body = function_body(providers_text, "promptDescriptorSecret")
if 'printf \'%s\' \\"$value\\" | " + boundedCommandLine' not in prompt_secret_body:
    raise AssertionError("descriptor secrets must stay on stdin and use the bounded CLI command")

set_api_key_result_body = function_body(providers_text, "handleSetApiKeyResult")
for fragment in ("markPending(descriptor.provider, false)", "Number(exitCode) === 124", "Number(exitCode) === 137"):
    if fragment not in set_api_key_result_body:
        raise AssertionError(f"set-api-key timeout cleanup is incomplete: {fragment}")

parse_payload_body = function_body(providers_text, "parseCommandPayload")
for fragment in ("Number(exitCode) === 124", "Number(exitCode) === 137", "codexbar command timed out. Try again."):
    if fragment not in parse_payload_body:
        raise AssertionError(f"descriptor secret timeout reporting is incomplete: {fragment}")

expire_config_body = function_body(providers_text, "expireConfigCommands")
for fragment in ("disconnectSource(sourceName)", "handleConfigCommandTimeout(descriptor)"):
    if fragment not in expire_config_body:
        raise AssertionError(f"config timeout cleanup is incomplete: {fragment}")

timeout_body = function_body(providers_text, "handleConfigCommandTimeout")
for fragment in (
    "descriptor.kind === \"list\"",
    "descriptor.kind === \"diagnose\"",
    "descriptor.kind === \"toggle\"",
    "descriptor.kind === \"descriptorField\"",
    "descriptor.kind === \"descriptorAction\"",
    "setProviderDiagnosticLoading",
    "markPending(descriptor.provider, false)",
    "markFieldPending(descriptor.provider, fieldID, false)",
):
    if fragment not in timeout_body:
        raise AssertionError(f"config timeout handler is incomplete: {fragment}")

load_overview_body = function_body(display_text, "loadOverviewProviders")
for fragment in ("commandWithRunNonce(command)", "deadlineMs: Date.now() + overviewProviderCommandTimeoutMs"):
    if fragment not in load_overview_body:
        raise AssertionError(f"overview provider loads need nonce and deadline: {fragment}")

expire_overview_body = function_body(display_text, "expireOverviewProviderCommands")
for fragment in (
    "overviewProviderSource.disconnectSource(sourceName)",
    "Loading providers timed out. Try again.",
):
    if fragment not in expire_overview_body:
        raise AssertionError(f"overview provider timeout cleanup is incomplete: {fragment}")

run_debug_body = function_body(debug_text, "runCommand")
for fragment in ("commandWithRunNonce(command)", "diagnosticCommandTimeoutTimer.restart()"):
    if fragment not in run_debug_body:
        raise AssertionError(f"debug commands need nonce and timeout: {fragment}")

debug_timeout_body = function_body(debug_text, "handleDiagnosticTimeout")
for fragment in ("finishDiagnosticCommand(activeCommand)", "Diagnostic command timed out. Try again."):
    if fragment not in debug_timeout_body:
        raise AssertionError(f"debug timeout cleanup is incomplete: {fragment}")

schedule_update_body = function_body(main_text, "scheduleNextUpdateCheck")
for fragment in (
    "updateCheckTimer.stop()",
    "connectedUpdateCommandSource.length > 0",
    "UpdateLogic.nextUpdateCheckDelay(",
    "updateCheckTimer.restart()",
):
    if fragment not in schedule_update_body:
        raise AssertionError(f"update scheduling lifecycle is incomplete: {fragment}")

check_update_body = function_body(main_text, "checkForWidgetUpdate")
for fragment in ("scheduleNextUpdateCheck()", "updateCheckTimer.stop()"):
    if fragment not in check_update_body:
        raise AssertionError(f"update checks must avoid overlap and rearm when not due: {fragment}")

finish_update_body = function_body(main_text, "finishUpdateCommand")
for fragment in ("var completedAt = new Date().toISOString()", "scheduleNextUpdateCheck(completedAt)"):
    if fragment not in finish_update_body:
        raise AssertionError(f"every completed update command must rearm from its exact completion time: {fragment}")

timer_start = main_text.index("id: updateCheckTimer")
timer_end = main_text.index("\n    Timer {", timer_start + 1)
timer_body = main_text[timer_start:timer_end]
for fragment in ("repeat: false", "running: false", "root.checkForWidgetUpdate()"):
    if fragment not in timer_body:
        raise AssertionError(f"update timer must remain single-shot: {fragment}")
if "onAutoUpdateIntervalHoursChanged: scheduleNextUpdateCheck()" not in main_text:
    raise AssertionError("changing the update interval must rearm the scheduler")
PY

echo "KDE plasmoid process lifecycle checks passed."
