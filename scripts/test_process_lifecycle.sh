#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT_DIR}/scripts/lib/qml_surfaces.sh"

# Lifecycle rules belong to a whole surface, not to one file: the plasmoid may
# own its command lifecycle from main.qml or from an extracted controller, and
# either is correct as long as the rule is still there. Assert against the
# surface so a file split cannot silently drop a nonce, deadline, or cleanup.

require_in_surface applet "readonly property int usageCommandTimeoutMs: 120000"
require_in_surface applet "function connectUsageCommand(sourceName, descriptor)"
require_in_surface applet "function finishUsageCommandSource(sourceName)"
require_in_surface applet "function retireUsageCommands()"
require_in_surface applet "function expireUsageCommands(nowMs)"
require_in_surface applet "function handleUsageCommandTimeout(sourceName, descriptor)"
require_in_surface applet "id: usageCommandTimeoutTimer"
require_in_surface applet "root.expireUsageCommands(Date.now())"
require_in_surface applet "id: usageRefreshTimer"
require_in_surface applet "running: root.refreshIntervalSec > 0"
require_in_surface applet "if (!root.hasPendingUsageCommandTimeouts())"
require_in_surface applet "interval: 0"
require_in_surface applet "root.finishUsageCommandSource(sourceName)"
require_in_surface applet "delete commands[sourceName]"
require_in_surface applet "pendingProviderCount = 0"
require_in_surface applet "readonly property int accountCommandTimeoutMs: 60000"
require_in_surface applet "readonly property int sessionsCommandTimeoutMs: 60000"
require_in_surface applet "function refreshSessions()"
require_in_surface applet "id: accountCommandTimeoutTimer"
require_in_surface applet "root.expirePendingAccountCommands(Date.now())"
require_in_surface applet "readonly property int providerConfigWatchIntervalMs: 60000"
require_in_surface applet "interval: root.providerConfigWatchIntervalMs"

require_in_surface providers "readonly property int configCommandTimeoutMs: 60000"
require_in_surface providers "readonly property int configSecretCommandTimeoutSeconds: 60"
require_in_surface providers "readonly property int configSecretCommandKillAfterSeconds: 5"
require_in_surface providers "id: configCommandTimeoutTimer"
require_in_surface providers "page.expireConfigCommands(Date.now())"
require_in_surface providers "onCfg_commandPathChanged: handleCommandPathChanged()"

require_in_surface display "readonly property int overviewProviderCommandTimeoutMs: 60000"
require_in_surface display "function commandWithRunNonce(command)"
require_in_surface display "function expireOverviewProviderCommands(nowMs)"
require_in_surface display "id: overviewProviderCommandTimeoutTimer"
require_in_surface display "page.expireOverviewProviderCommands(Date.now())"

require_in_surface debug "readonly property int diagnosticCommandTimeoutMs: 60000"
require_in_surface debug "function commandWithRunNonce(command)"
require_in_surface debug "function handleDiagnosticTimeout()"
require_in_surface debug "id: diagnosticCommandTimeoutTimer"
require_in_surface debug "page.handleDiagnosticTimeout()"

reject_in_surface applet "retiredUsageCommands"
reject_in_surface applet "pendingAccountCommandStartedAt"
reject_in_surface applet "function retireUsageCommandSource(sourceName)"
reject_in_surface applet "interval: root.refreshIntervalSec > 0 ? root.refreshIntervalSec * 1000 : 0"
reject_in_surface applet "pendingProviderCount = fallbackProviderOrder.length"
reject_in_surface applet "--source cli"

python3 - "$ROOT_DIR" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root / "scripts/lib"))
from qml_surfaces import Surface

applet = Surface("applet", root)
providers = Surface("providers", root)
display = Surface("display", root)
debug = Surface("debug", root)


def require_all(body, fragments, reason):
    for fragment in fragments:
        if fragment not in body:
            raise AssertionError(f"{reason}: {fragment}")


retire_body = applet.function_body("retireUsageCommands")
if "finishUsageCommandSource(" not in retire_body:
    raise AssertionError("retiring active usage sources must disconnect them immediately")
if "connectedSessionsCommandSource" not in retire_body or "sessionsLoading = false" not in retire_body:
    raise AssertionError("retiring active usage sources must also retire the sessions command")

require_all(
    applet.function_body("loadAccounts"),
    (
        "providerID: normalizedProviderID",
        "commandSignature: command",
        "deadlineMs: Date.now() + accountCommandTimeoutMs",
    ),
    "loadAccounts must store one timeout descriptor",
)

require_all(
    applet.function_body("parseProviderAccountsOutput"),
    (
        "descriptor.providerID",
        "delete commands[sourceName]",
        "accountCommandIsCurrent(descriptor)",
    ),
    "normal account completion must reject stale context",
)

require_all(
    applet.function_body("retireStaleAccountCommands"),
    (
        "accountCommandIsCurrent(descriptor)",
        "finishUsageCommandSource(sourceName)",
        "setAccountLoading(staleProviderID, false)",
    ),
    "stale account cleanup is incomplete",
)

if "retireStaleAccountCommands()" not in applet.function_body("refreshNow"):
    raise AssertionError("refreshNow must retire account commands from an obsolete CLI context")

for function_name in ("buildProviderAccountsCommand", "buildProviderUsageCommand"):
    body = applet.function_body(function_name)
    if 'if (source.length > 0)' not in body:
        raise AssertionError(f"{function_name} must preserve the automatic CLI source by default")
    if 'effectiveSource' in body or '"cli"' in body:
        raise AssertionError(f"{function_name} must not force Codex to the CLI source")

require_all(
    applet.function_body("expirePendingAccountCommands"),
    (
        "finishUsageCommandSource(sourceName)",
        "setAccountLoading(providerID, false)",
        "Loading accounts timed out. Try again.",
    ),
    "account timeout cleanup is incomplete",
)

require_all(
    applet.function_body("expireUsageCommands"),
    ("descriptor.deadlineMs", "handleUsageCommandTimeout("),
    "usage timeout scan is incomplete",
)

require_all(
    applet.function_body("handleUsageCommandTimeout"),
    (
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
    ),
    "usage timeout cleanup is incomplete",
)

require_all(
    applet.function_body("buildCostCommandDescriptor"),
    ('buildUsageCommandDescriptor("cost", "")', "descriptor.costHistoryDays = costHistoryDays"),
    "cost command descriptors must retain the requested history range",
)
for fragment in (
    "var costDescriptor = root.activeUsageCommands[sourceName]",
    "root.parseCostOutput(stdoutText, stderrText, requestedHistoryDays)",
):
    applet.require(fragment, "cost completion must pass its captured request range to normalization")

fallback_result_body = applet.function_body("parseProviderFallbackOutput")
if fallback_result_body.count("completeProviderFallbackCommand()") != 2:
    raise AssertionError("every accepted fallback result path must complete its queue accounting")

require_all(
    applet.function_body("completeProviderFallbackCommand"),
    (
        "activeProviderFallbackCount = Math.max(0, activeProviderFallbackCount - 1)",
        "pendingProviderCount = Math.max(0, pendingProviderCount - 1)",
        "pumpProviderFallbackCommands()",
        "finishProviderFallback()",
    ),
    "fallback completion must preserve liveness",
)

require_all(
    applet.id_block("usageRefreshTimer"),
    ("root.hasPendingUsageCommandTimeouts()", "root.refreshNow()"),
    "periodic refreshes must not starve active command deadlines",
)

require_all(
    providers.function_body("runCommand"),
    ("nextDescriptor.timeoutMs", "nextDescriptor.deadlineMs", "nextDescriptor.commandPathSignature = commandPath"),
    "runCommand must honor explicit command timeouts",
)

require_all(
    providers.function_body("handleCommandPathChanged"),
    ("retireAllConfigCommands()", "providers = []", "Qt.callLater(reload)"),
    "changing the CLI path must retire stale page state",
)

require_all(
    providers.function_body("retireAllConfigCommands"),
    (
        "configSource.disconnectSource(sourceName)",
        "commands = ({})",
        "pending = ({})",
        "providerFieldPending = ({})",
        "providerDiagnosticLoading = ({})",
    ),
    "config command retirement is incomplete",
)

if "descriptor.commandPathSignature !== commandPath" not in providers.function_body("handleData"):
    raise AssertionError("config command results must reject a stale CLI path")

for function_name in ("runProviderListCommand", "setEnabled", "loadProviderSettings", "writeDescriptorField", "runDescriptorAction"):
    body = providers.function_body(function_name)
    if "timeoutMs: configCommandTimeoutMs" not in body:
        raise AssertionError(f"noninteractive {function_name} commands must be bounded")
for function_name in ("setApiKey", "promptDescriptorSecret"):
    body = providers.function_body(function_name)
    if "timeoutMs" in body:
        raise AssertionError(f"interactive {function_name} commands must not expire while prompting")
    require_all(
        body,
        (
            "command -v timeout",
            "timeout --kill-after=1s 1s true",
            "timeout --kill-after",
            "configSecretCommandTimeoutSeconds",
            "configSecretCommandKillAfterSeconds",
        ),
        f"interactive {function_name} must bound the post-prompt CLI phase",
    )

if 'printf \'%s\' \\"$key\\" | timeout --kill-after=' not in providers.function_body("setApiKey"):
    raise AssertionError("setApiKey must pipe the secret to a bounded CLI process")

if 'printf \'%s\' \\"$value\\" | " + boundedCommandLine' not in providers.function_body("promptDescriptorSecret"):
    raise AssertionError("descriptor secrets must stay on stdin and use the bounded CLI command")

require_all(
    providers.function_body("handleSetApiKeyResult"),
    ("markPending(descriptor.provider, false)", "Number(exitCode) === 124", "Number(exitCode) === 137"),
    "set-api-key timeout cleanup is incomplete",
)

require_all(
    providers.function_body("parseCommandPayload"),
    ("Number(exitCode) === 124", "Number(exitCode) === 137", "codexbar command timed out. Try again."),
    "descriptor secret timeout reporting is incomplete",
)

require_all(
    providers.function_body("expireConfigCommands"),
    ("disconnectSource(sourceName)", "handleConfigCommandTimeout(descriptor)"),
    "config timeout cleanup is incomplete",
)

require_all(
    providers.function_body("handleConfigCommandTimeout"),
    (
        "descriptor.kind === \"list\"",
        "descriptor.kind === \"diagnose\"",
        "descriptor.kind === \"toggle\"",
        "descriptor.kind === \"descriptorField\"",
        "descriptor.kind === \"descriptorAction\"",
        "setProviderDiagnosticLoading",
        "markPending(descriptor.provider, false)",
        "markFieldPending(descriptor.provider, fieldID, false)",
    ),
    "config timeout handler is incomplete",
)

require_all(
    display.function_body("loadOverviewProviders"),
    ("commandWithRunNonce(command)", "deadlineMs: Date.now() + overviewProviderCommandTimeoutMs"),
    "overview provider loads need nonce and deadline",
)

require_all(
    display.function_body("expireOverviewProviderCommands"),
    ("overviewProviderSource.disconnectSource(sourceName)", "Loading providers timed out. Try again."),
    "overview provider timeout cleanup is incomplete",
)

require_all(
    debug.function_body("runCommand"),
    ("commandWithRunNonce(command)", "diagnosticCommandTimeoutTimer.restart()"),
    "debug commands need nonce and timeout",
)

require_all(
    debug.function_body("handleDiagnosticTimeout"),
    ("finishDiagnosticCommand(activeCommand)", "Diagnostic command timed out. Try again."),
    "debug timeout cleanup is incomplete",
)

require_all(
    applet.function_body("scheduleNextUpdateCheck"),
    (
        "updateCheckTimer.stop()",
        "connectedUpdateCommandSource.length > 0",
        "UpdateLogic.nextUpdateCheckDelay(",
        "updateCheckTimer.restart()",
    ),
    "update scheduling lifecycle is incomplete",
)

require_all(
    applet.function_body("checkForWidgetUpdate"),
    ("scheduleNextUpdateCheck()", "updateCheckTimer.stop()"),
    "update checks must avoid overlap and rearm when not due",
)

require_all(
    applet.function_body("finishUpdateCommand"),
    ("var completedAt = new Date().toISOString()", "scheduleNextUpdateCheck(completedAt)"),
    "every completed update command must rearm from its exact completion time",
)

require_all(
    applet.id_block("updateCheckTimer"),
    ("repeat: false", "running: false", "root.checkForWidgetUpdate()"),
    "update timer must remain single-shot",
)

applet.require(
    "onAutoUpdateIntervalHoursChanged: scheduleNextUpdateCheck()",
    "changing the update interval must rearm the scheduler",
)
PY

echo "KDE plasmoid process lifecycle checks passed."
