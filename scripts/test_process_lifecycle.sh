#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QML="${ROOT_DIR}/contents/ui/main.qml"
PROVIDERS_QML="${ROOT_DIR}/contents/ui/configProviders.qml"

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
  if grep -Fq "$needle" "$file"; then
    echo "unexpected lifecycle fragment in ${file#"$ROOT_DIR"/}: $needle" >&2
    exit 1
  fi
}

require_in_file "$QML" "function connectUsageCommand(sourceName)"
require_in_file "$QML" "function finishUsageCommandSource(sourceName)"
require_in_file "$QML" "function retireUsageCommands()"
require_in_file "$QML" "id: usageRefreshTimer"
require_in_file "$QML" "running: root.refreshIntervalSec > 0"
require_in_file "$QML" "onTriggered: root.refreshNow()"
require_in_file "$QML" "interval: 0"
require_in_file "$QML" "root.finishUsageCommandSource(sourceName)"
require_in_file "$QML" "delete commands[sourceName]"
require_in_file "$QML" "pendingProviderCount = 0"
require_in_file "$QML" "readonly property int accountCommandTimeoutMs: 60000"
require_in_file "$QML" "id: accountCommandTimeoutTimer"
require_in_file "$QML" "root.expirePendingAccountCommands(Date.now())"

require_in_file "$PROVIDERS_QML" "readonly property int configCommandTimeoutMs: 60000"
require_in_file "$PROVIDERS_QML" "id: configCommandTimeoutTimer"
require_in_file "$PROVIDERS_QML" "page.expireConfigCommands(Date.now())"

reject_in_file "$QML" "retiredUsageCommands"
reject_in_file "$QML" "pendingAccountCommandStartedAt"
reject_in_file "$QML" "function retireUsageCommandSource(sourceName)"
reject_in_file "$QML" "interval: root.refreshIntervalSec > 0 ? root.refreshIntervalSec * 1000 : 0"
reject_in_file "$QML" "pendingProviderCount = fallbackProviderOrder.length"

python3 - "$QML" "$PROVIDERS_QML" <<'PY'
import sys
from pathlib import Path

main_text = Path(sys.argv[1]).read_text(encoding="utf-8")
providers_text = Path(sys.argv[2]).read_text(encoding="utf-8")


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

load_accounts_body = function_body(main_text, "loadAccounts")
for fragment in ("providerID: normalizedProviderID", "deadlineMs: Date.now() + accountCommandTimeoutMs"):
    if fragment not in load_accounts_body:
        raise AssertionError(f"loadAccounts must store one timeout descriptor: {fragment}")

parse_accounts_body = function_body(main_text, "parseProviderAccountsOutput")
if "descriptor.providerID" not in parse_accounts_body or "delete commands[sourceName]" not in parse_accounts_body:
    raise AssertionError("normal account completion must consume its pending descriptor")

expire_accounts_body = function_body(main_text, "expirePendingAccountCommands")
for fragment in (
    "finishUsageCommandSource(sourceName)",
    "setAccountLoading(providerID, false)",
    "Loading accounts timed out. Try again.",
):
    if fragment not in expire_accounts_body:
        raise AssertionError(f"account timeout cleanup is incomplete: {fragment}")

run_command_body = function_body(providers_text, "runCommand")
for fragment in ("nextDescriptor.timeoutMs", "nextDescriptor.deadlineMs"):
    if fragment not in run_command_body:
        raise AssertionError(f"runCommand must honor explicit command timeouts: {fragment}")

for function_name in ("runProviderListCommand", "setEnabled", "loadProviderSettings", "writeDescriptorField", "runDescriptorAction"):
    body = function_body(providers_text, function_name)
    if "timeoutMs: configCommandTimeoutMs" not in body:
        raise AssertionError(f"noninteractive {function_name} commands must be bounded")
for function_name in ("setApiKey", "promptDescriptorSecret"):
    body = function_body(providers_text, function_name)
    if "timeoutMs" in body:
        raise AssertionError(f"interactive {function_name} commands must not expire while prompting")

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
PY

echo "KDE plasmoid process lifecycle checks passed."
