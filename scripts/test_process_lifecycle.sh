#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT_DIR}/scripts/lib/qml_surfaces.sh"

# Lifecycle rules belong to a whole surface, not to one file: the plasmoid may
# own its command lifecycle from main.qml or from an extracted controller, and
# either is correct as long as the rule is still there. Assert against the
# surface so a file split cannot silently drop a nonce, deadline, or cleanup.

require_in_surface applet "readonly property int defaultCommandTimeoutMs: 120000"
require_in_surface applet "function connectUsageCommand(sourceName, descriptor)"
require_in_surface applet "function finishUsageCommandSource(sourceName)"
require_in_surface applet "function retireUsageCommands()"
require_in_surface applet "function expireCommands(nowMs)"
require_in_surface applet "function handleCommandTimeout(sourceName, descriptor)"
require_in_surface applet "id: commandTimeoutTimer"
require_in_surface applet "root.expireCommands(Date.now())"
require_in_surface applet "id: usageRefreshTimer"
require_in_surface applet "running: root.refreshIntervalSec > 0"
require_in_surface applet "if (!root.hasPendingPeriodicRefreshCommands())"
require_in_surface applet "function hasPendingPeriodicRefreshCommands()"
require_in_surface applet "interval: 0"
require_in_surface applet "root.finishUsageCommandSource(sourceName)"
require_in_surface applet 'import "ProviderFallbackQueue.js" as ProviderFallbackQueue'
require_in_surface applet 'import "ProviderRosterCache.js" as ProviderRosterCache'
require_in_surface applet 'import "SessionRefreshPolicy.js" as SessionRefreshPolicy'
require_in_surface applet "property var providerFallbackState: null"
require_in_surface applet "readonly property int accountCommandTimeoutMs: 60000"
require_in_surface applet "readonly property int sessionsCommandTimeoutMs: 60000"
require_in_surface applet "readonly property int notificationCommandTimeoutMs: 10000"
require_in_surface applet "function connectNotificationCommand(sourceName)"
require_in_surface applet "function finishNotificationCommandSource(sourceName)"
require_in_surface applet "function refreshSessions()"
require_in_surface applet "readonly property int providerConfigWatchIntervalMs: 60000"
require_in_surface applet "interval: root.providerConfigWatchIntervalMs"
require_in_surface applet 'import "CostRefreshPolicy.js" as CostRefreshPolicy'
require_in_surface applet "readonly property int costAutoRefreshIntervalMs: CostRefreshPolicy.automaticRefreshIntervalMs"
require_in_surface applet "property double lastCostRefreshAttemptAt: -1"
require_in_surface applet "id: costRefreshTimer"
require_in_surface applet "property bool updateRetryPending: false"

require_in_surface providers "readonly property int configCommandTimeoutMs: 60000"
require_in_surface providers "readonly property int configSecretCommandTimeoutSeconds: 60"
require_in_surface providers "readonly property int configSecretCommandKillAfterSeconds: 5"
require_in_surface providers "id: configCommandTimeoutTimer"
require_in_surface providers "page.expireConfigCommands(Date.now())"
require_in_surface providers "Component.onCompleted: Qt.callLater(reload)"
require_in_surface providers "onCfg_commandPathChanged: handleCommandPathChanged()"

require_in_surface display "readonly property int overviewProviderCommandTimeoutMs: 60000"
require_in_surface display 'import "CommandLedger.js" as CommandLedger'
reject_in_surface display "function commandWithRunNonce(command)"
require_in_surface display "Component.onCompleted: Qt.callLater(loadOverviewProviders)"
require_in_surface display "onCfg_commandPathChanged: Qt.callLater(loadOverviewProviders)"
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
reject_in_surface applet "pendingAccountCommands"
reject_in_surface applet "accountCommandTimeoutTimer"
reject_in_surface applet "hasPendingAccountCommands"
reject_in_surface applet "expirePendingAccountCommands"
reject_in_surface applet "function retireUsageCommandSource(sourceName)"
reject_in_surface applet "interval: root.refreshIntervalSec > 0 ? root.refreshIntervalSec * 1000 : 0"
reject_in_surface applet "--source cli"
for legacy_fallback_state in \
  pendingProviderCommands fallbackProviderQueue activeProviderFallbackCount \
  fallbackProviderOrder fallbackProviderResults fallbackProviderSeen pendingProviderCount; do
  reject_in_surface applet "$legacy_fallback_state"
done

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


def require_ordered(body, fragments, reason):
    offset = 0
    for fragment in fragments:
        index = body.find(fragment, offset)
        if index < 0:
            raise AssertionError(f"{reason}: {fragment}")
        offset = index + len(fragment)


retire_body = applet.function_body("retireUsageCommands")
if "finishUsageCommandSource(" not in retire_body and "retireUsageCommandKind(" not in retire_body:
    raise AssertionError("retiring active usage sources must disconnect them immediately")
# A quota refresh replaces only quota work. Sessions has its own lifecycle and
# must survive a concurrent quota refresh.
for retired_kind in ('retireUsageCommandKind("usage")',
                     'retireUsageCommandKind("providerConfig")',
                     'retireUsageCommandKind("providerFallback")'):
    if retired_kind not in retire_body:
        raise AssertionError(
            f"retiring active usage sources must also retire {retired_kind}"
        )
if 'retireUsageCommandKind("sessions")' in retire_body or "sessionsLoading" in retire_body:
    raise AssertionError("quota refresh must not retire or mutate independent Sessions work")
retire_kind_body = applet.function_body("retireUsageCommandKind")
for retire_kind_fragment in ("CommandLedger.sourcesOfKind(activeCommandDescriptors, kind)",
                             "finishUsageCommandSource("):
    if retire_kind_fragment not in retire_kind_body:
        raise AssertionError(
            "retiring by kind must read the ledger and disconnect every match; "
            f"missing {retire_kind_fragment!r}"
        )

require_all(
    applet.function_body("loadAccounts"),
    (
        "buildCommandDescriptor(",
        '"account", normalizedProviderID, accountCommandTimeoutMs)',
        "descriptor.commandSignature = command",
        "connectUsageCommand(connectedCommand, descriptor)",
    ),
    "account loads must enter the shared deadline ledger",
)

require_all(
    applet.function_body("parseProviderAccountsOutput"),
    (
        "descriptor.providerID",
        "finishUsageCommandSource(sourceName)",
        "accountCommandIsCurrent(descriptor)",
    ),
    "normal account completion must reject stale context",
)

require_all(
    applet.function_body("retireStaleAccountCommands"),
    (
        'CommandLedger.sourcesOfKind(activeCommandDescriptors, "account")',
        "CommandLedger.find(activeCommandDescriptors, sourceName)",
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

# The deadline scan moved into CommandLedger.js. Assert that main.qml still
# hands every overdue command to the timeout handler, and that the scan itself
# keeps comparing against the recorded deadline.
require_all(
    applet.function_body("expireCommands"),
    ("CommandLedger.expired(activeCommandDescriptors, nowMs)", "handleCommandTimeout("),
    "command timeout scan is incomplete",
)
require_all(
    applet.function_body("expired"),
    ("Number(entry.deadlineMs)", "nowMs < deadline"),
    "the ledger deadline scan is incomplete",
)
require_all(
    applet.function_body("hasPendingCommandTimeouts"),
    ("CommandLedger.hasDeadlines(activeCommandDescriptors)",),
    "the timeout timer must read its deadlines from the ledger",
)

timeout_body = applet.function_body("handleCommandTimeout")
require_all(
    timeout_body,
    (
        "switch (descriptor.kind) {",
        'case "usage":',
        'case "cost":',
        'case "sessions":',
        'case "providerConfig":',
        'case "account":',
        'case "providerFallback":',
        'case "notification":',
        "finishUsageCommandSource(sourceName)",
        "finishNotificationCommandSource(sourceName)",
        "Loading usage timed out. Try again.",
        "Loading cost data timed out. Try again.",
        "Loading sessions timed out. Try again.",
        "Loading provider configuration timed out. Try again.",
        "Loading accounts timed out. Try again.",
    ),
    "command timeout cleanup is incomplete",
)
account_timeout_start = timeout_body.find('case "account":')
account_timeout_end = timeout_body.find('case "providerFallback":', account_timeout_start)
if account_timeout_start < 0 or account_timeout_end < 0:
    raise AssertionError("account timeout branch is missing")
require_all(
    timeout_body[account_timeout_start:account_timeout_end],
    (
        "finishUsageCommandSource(sourceName)",
        "setAccountLoading(descriptor.providerID, false)",
        "setAccountError(",
        "descriptor.providerID",
    ),
    "account timeout must close the shared ledger entry and clear its loading state",
)
fallback_timeout_start = timeout_body.find('case "providerFallback":')
fallback_timeout_end = timeout_body.find('case "notification":', fallback_timeout_start)
if fallback_timeout_start < 0 or fallback_timeout_end < 0:
    raise AssertionError("provider fallback timeout branch is missing")
require_all(
    timeout_body[fallback_timeout_start:fallback_timeout_end],
    ("parseProviderFallbackOutput(", "descriptor.providerID"),
    "provider fallback timeouts must complete the queue before returning",
)

require_all(
    applet.function_body("connectNotificationCommand"),
    (
        'buildCommandDescriptor(',
        '"notification", "", notificationCommandTimeoutMs)',
        "CommandLedger.opened(",
        "activeCommandDescriptors, sourceName, descriptor)",
        "notificationSource.connectSource(sourceName)",
    ),
    "notifications must enter the shared deadline ledger",
)
require_all(
    applet.function_body("finishNotificationCommandSource"),
    (
        "notificationSource.disconnectSource(sourceName)",
        "CommandLedger.closed(activeCommandDescriptors, sourceName)",
    ),
    "notification completion must disconnect and close its ledger entry",
)
require_all(
    applet.function_body("sendPlasmaNotification"),
    ("connectNotificationCommand(", "commandWithRunNonce("),
    "notification dispatch must start a unique bounded command",
)
require_all(
    applet.id_block("notificationSource"),
    (
        "CommandLedger.find(root.activeCommandDescriptors, sourceName)",
        '!descriptor || descriptor.kind !== "notification"',
        "root.finishNotificationCommandSource(sourceName)",
    ),
    "notification replies must close only their live ledger entry",
)

require_all(
    applet.function_body("buildCostCommandDescriptor"),
    ('buildCommandDescriptor("cost", "")', "descriptor.costHistoryDays = costHistoryDays"),
    "cost command descriptors must retain the requested history range",
)
for fragment in (
    "var descriptor = CommandLedger.find(root.activeCommandDescriptors, sourceName)",
    "descriptor.costHistoryDays !== undefined",
    "root.parseCostOutput(stdoutText, stderrText, requestedHistoryDays)",
):
    applet.require(fragment, "cost completion must pass its captured request range to normalization")

# Routing reads the ledger entry, so a reply whose source name has already been
# retired returns before any parse runs. That is the whole staleness guarantee.
usage_source_block = applet.id_block("usageSource")
if "if (!descriptor) {" not in usage_source_block:
    raise AssertionError("a reply the ledger no longer holds must be dropped before parsing")
for stale_route_fragment in (
    "root.connectedCommandSource",
    "root.connectedCostCommandSource",
    "root.connectedSessionsCommandSource",
    "root.connectedProviderConfigCommandSource",
):
    if stale_route_fragment in usage_source_block:
        raise AssertionError(
            "process replies must route on the ledger entry, not a parallel "
            f"per-kind source name: {stale_route_fragment}"
        )

if "root.parseProviderAccountsOutput(sourceName, descriptor, stdoutText, stderrText)" not in usage_source_block:
    raise AssertionError("account completion must consume the descriptor routed by the shared ledger")

require_all(
    applet.function_body("parseProviderFallbackOutput"),
    (
        "Normalizer.dedupeProviderSnapshots(normalizedItems)",
        "ProviderFallbackQueue.complete(",
        "item: semanticItems.length > 0 ? semanticItems[0] : null",
        "applyProviderFallbackTransition(transition)",
    ),
    "fallback replies must cross the pure queue interface",
)
require_all(
    applet.function_body("applyProviderFallbackTransition"),
    (
        "providerFallbackState = transition.state",
        "transition.sourcesToStart",
        "connectUsageCommand(",
        'buildCommandDescriptor("providerFallback", request.providerID)',
        "finishProviderFallback(transition.orderedItems)",
    ),
    "the QML adapter must apply queue transitions and own process effects",
)
require_all(
    applet.function_body("retireUsageCommands"),
    (
        'retireUsageCommandKind("providerFallback")',
        "providerFallbackState = null",
    ),
    "retiring usage work must cancel active fallback commands and discard queued state",
)

require_all(
    applet.id_block("usageRefreshTimer"),
    ("root.hasPendingPeriodicRefreshCommands()", "root.refreshNow()"),
    "periodic refreshes must not starve active command deadlines",
)

periodic_refresh_body = applet.function_body("hasPendingPeriodicRefreshCommands")
require_all(
    periodic_refresh_body,
    (
        "CommandLedger.hasAnyKind(",
        '"usage"',
        '"providerConfig"',
        '"providerFallback"',
    ),
    "the quota timer must wait only for work it would retire",
)
for independent_kind in ('"cost"', '"sessions"'):
    if independent_kind in periodic_refresh_body:
        raise AssertionError(
            f"independent {independent_kind} work must not block the quota refresh timer"
        )

if "refreshSessions" in applet.function_body("refreshNow"):
    raise AssertionError("quota refresh must not start Sessions work")

require_all(
    applet.function_body("requestSessionsRefresh"),
    (
        "SessionRefreshPolicy.refreshAction(",
        "expanded && sessionsSelected",
        "sessionsLastCompletedAtMs",
        "sessionsLoadedCommandSource",
        'retireUsageCommandKind("sessions")',
        "commandWithRunNonce(sessionsCommandSource)",
    ),
    "Sessions intent must cross the freshness policy before starting a command",
)
require_all(
    applet.handler_body("onExpandedChanged"),
    ("if (expanded)", "Qt.callLater(refreshSessionsIfStale)"),
    "opening the popup must check visible Sessions freshness",
)
require_all(
    applet.handler_body("onSessionsSelectedChanged"),
    ("if (sessionsSelected && expanded)", "Qt.callLater(refreshSessionsIfStale)"),
    "entering Sessions must check freshness",
)
require_all(
    applet.function_body("selectGlobalView"),
    ('candidate === "sessions"', "refreshSessionsIfStale()"),
    "reselecting the Sessions tab must check whether its snapshot became stale",
)

require_all(
    applet.function_body("startProviderFallback"),
    (
        "ProviderRosterCache.read(",
        "providerRosterContext()",
        "startProviderFallbackForProviders(cachedProviderIDs)",
        "buildProviderConfigCommandDescriptor()",
    ),
    "global fallback must reuse only a current provider roster",
)
require_all(
    applet.function_body("buildProviderConfigCommandDescriptor"),
    (
        'buildCommandDescriptor("providerConfig", "")',
        "descriptor.providerRosterContext = providerRosterContext()",
    ),
    "provider config commands must capture their roster context",
)
require_all(
    applet.function_body("parseProviderConfigOutput"),
    (
        "ProviderRosterCache.responseContextsMatch(",
        "descriptor.providerRosterContext",
        "ProviderRosterCache.remember(",
    ),
    "provider config replies must reject stale contexts before caching",
)
require_ordered(
    applet.function_body("parseProviderConfigOutput"),
    (
        "ProviderRosterCache.responseContextsMatch(",
        "scheduleUsageRefresh()",
        "return",
        "ProviderRosterCache.remember(",
    ),
    "provider config replies must reject stale contexts before caching",
)
require_ordered(
    applet.function_body("handleProviderConfigWatch"),
    (
        "if (stamp === providerConfigStamp)",
        "return",
        "providerConfigStamp = stamp",
        "invalidateProviderRosterCache()",
        "scheduleUsageRefresh()",
    ),
    "a changed provider config checksum must invalidate and refresh the roster",
)

cost_refresh_body = applet.function_body("refreshCost")
require_all(
    cost_refresh_body,
    (
        "CostRefreshPolicy.refreshAction(",
        "costCommandSource.length > 0",
        "costLoading",
        "force === true",
        "lastCostRefreshAttemptAt",
        "CostRefreshPolicy.clearAction",
        "CostRefreshPolicy.startAction",
        'retireUsageCommandKind("cost")',
    ),
    "cost refreshes must preserve their independent hourly lifecycle",
)

require_all(
    applet.id_block("costRefreshTimer"),
    (
        "interval: root.costAutoRefreshIntervalMs",
        "running: root.costCommandSource.length > 0",
        "root.refreshCost(false)",
    ),
    "automatic cost scans must use their own hourly scheduler",
)

require_all(
    providers.function_body("runCommand"),
    (
        "CommandLedger.withRunNonce(command, commandRunSerial)",
        "nextDescriptor.timeoutMs",
        "nextDescriptor.deadlineMs",
        "nextDescriptor.commandPathSignature = commandPath",
        "CommandLedger.opened(commands, sourceName, nextDescriptor)",
    ),
    "runCommand must register bounded commands in the shared ledger",
)

require_all(
    providers.function_body("disconnectCommandsByKind"),
    (
        "CommandLedger.sourcesOfKind(commands, kind)",
        "configSource.disconnectSource(sourceName)",
        "CommandLedger.closed(remaining, sourceName)",
    ),
    "config commands must retire one ledger kind without duplicating its scan",
)

require_all(
    providers.function_body("hasTimedConfigCommands"),
    ("CommandLedger.hasDeadlines(commands)",),
    "the config timeout timer must read the shared ledger",
)

require_all(
    providers.function_body("handleData"),
    (
        "CommandLedger.find(commands, sourceName)",
        "CommandLedger.closed(commands, sourceName)",
    ),
    "config command completion must close the shared ledger entry",
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

list_start_body = providers.function_body("runProviderListCommand")
if "providerConfigRevision: providerConfigRevisionValue()" not in list_start_body:
    raise AssertionError("provider lists must capture the config revision they started with")
list_result_body = providers.function_body("handleListResult")
if "ProviderConfigProtocol.providerListResultIsCurrent(" not in list_result_body:
    raise AssertionError("provider lists must reject results made stale by a completed mutation")
if "reload(true)" not in list_result_body:
    raise AssertionError("a stale provider list must schedule a current replacement")

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

set_api_key_result_body = providers.function_body("handleSetApiKeyResult")
if "markPending(descriptor.provider, false)" not in set_api_key_result_body:
    raise AssertionError("set-api-key timeout cleanup is incomplete: markPending(descriptor.provider, false)")
if "ProviderConfigProtocol.commandOutcome(" not in set_api_key_result_body:
    raise AssertionError(
        "set-api-key results must classify through ProviderConfigProtocol.commandOutcome"
    )
if "ProviderConfigProtocol.setApiKeyOutcomeIsSuccess(result)" not in set_api_key_result_body:
    raise AssertionError("set-api-key results must use the tested empty-output decision")

# Timeout recognition is covered behaviorally by tst_provider_config_protocol;
# the page owns only the localized wording and pending-state cleanup.
require_all(
    providers.function_body("providerCommandFailureText"),
    ("codexbar command timed out. Try again.",),
    "descriptor secret timeout reporting is incomplete",
)

require_all(
    providers.function_body("expireConfigCommands"),
    (
        "CommandLedger.expired(commands, nowMs)",
        "disconnectSource(sourceName)",
        "CommandLedger.closed(remaining, sourceName)",
        "handleConfigCommandTimeout(descriptor)",
    ),
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
    (
        "CommandLedger.withRunNonce(command, commandRunSerial)",
        "CommandLedger.descriptor(",
        "overviewProviderCommands = CommandLedger.opened(",
    ),
    "overview provider loads need nonce and deadline",
)

require_all(
    display.function_body("expireOverviewProviderCommands"),
    (
        "CommandLedger.expired(overviewProviderCommands, nowMs)",
        "overviewProviderSource.disconnectSource(sourceName)",
        "CommandLedger.closed(remaining, sourceName)",
        "Loading providers timed out. Try again.",
    ),
    "overview provider timeout cleanup is incomplete",
)

require_all(
    display.function_body("disconnectOverviewProviderCommands"),
    (
        "CommandLedger.sourcesOfKind(",
        'overviewProviderCommands, "overviewProviders"',
        "overviewProviderSource.disconnectSource(sourceName)",
    ),
    "overview provider retirement must read the shared ledger",
)

require_all(
    display.function_body("hasPendingOverviewProviderCommands"),
    ('CommandLedger.hasKind(overviewProviderCommands, "overviewProviders")',),
    "overview provider loading state must read the shared ledger",
)

require_all(
    display.function_body("handleOverviewProviderData"),
    (
        "CommandLedger.find(overviewProviderCommands, sourceName)",
        "CommandLedger.closed(overviewProviderCommands, sourceName)",
    ),
    "overview provider completion must close the shared ledger entry",
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
        "updateRetryPending = false",
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
    (
        "successfulCheck",
        "Plasmoid.configuration.autoUpdateLastCheck = completedAt",
        "scheduleNextUpdateCheck(completedAt)",
        "scheduleUpdateRetry()",
    ),
    "successful update checks must use the normal interval and failures must retry sooner",
)

require_all(
    applet.function_body("scheduleUpdateRetry"),
    (
        "UpdateLogic.updateRetryDelay(",
        "consecutiveUpdateFailures",
        "updateRetryPending = true",
        "updateCheckTimer.restart()",
    ),
    "failed update checks need a bounded retry schedule",
)

require_all(
    applet.function_body("handleUpdateCheckTimer"),
    (
        "var forceCheck = updateRetryPending",
        "updateRetryPending = false",
        "checkForWidgetUpdate(forceCheck)",
    ),
    "a retry timer must bypass the normal successful-check interval gate",
)

require_all(
    applet.function_body("handleUpdateCommandTimeout"),
    ("finishUpdateCommand(sourceName, false)",),
    "timed-out update checks must take the failure retry path",
)

require_all(
    applet.function_body("handleUpdateData"),
    (
        "finishUpdateCommand(sourceName, false)",
        "var resultIntent = UpdateLogic.resultIntent(payload, autoUpdateEnabled)",
        "applyUpdateResultIntent(resultIntent)",
        "finishUpdateCommand(sourceName, resultIntent.successful)",
    ),
    "update result parsing must choose success scheduling only after classifying the payload",
)

require_all(
    applet.id_block("updateCheckTimer"),
    ("repeat: false", "running: false", "root.handleUpdateCheckTimer()"),
    "update timer must remain single-shot",
)

apply_update_body = applet.function_body("applyUpdateResultIntent")
require_all(
    apply_update_body,
    ("widgetUpdateErrorText(intent.errorCode, intent.errorDetail)",),
    "the QML adapter must localize and apply semantic update intents",
)
if "payload" in apply_update_body:
    raise AssertionError("the update effect adapter must not inspect raw updater payloads")

applet.require(
    "onAutoUpdateIntervalHoursChanged: scheduleNextUpdateCheck()",
    "changing the update interval must rearm the scheduler",
)
PY

echo "KDE plasmoid process lifecycle checks passed."
