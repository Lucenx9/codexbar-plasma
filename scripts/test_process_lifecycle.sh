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
require_in_surface applet "running: controller.refreshIntervalSec > 0"
require_in_surface applet "if (!lifecycle.hasPendingPeriodicRefreshCommands())"
require_in_surface applet "function hasPendingPeriodicRefreshCommands()"
require_in_surface applet "interval: 0"
require_in_surface applet "lifecycle.finishUsageCommandSource(sourceName)"
require_in_surface applet 'import "../ProviderFallbackQueue.js" as ProviderFallbackQueue'
require_in_surface applet 'import "../ProviderRosterCache.js" as ProviderRosterCache'
require_in_surface applet 'import "../AccountRequests.js" as AccountRequests'
require_in_surface applet 'import "../SessionRefreshPolicy.js" as SessionRefreshPolicy'
require_in_surface applet "property var providerFallbackState: null"
require_in_surface applet "readonly property int accountCommandTimeoutMs: 60000"
require_in_surface applet "readonly property int sessionsCommandTimeoutMs: 60000"
require_in_surface applet "readonly property int notificationCommandTimeoutMs: 10000"
require_in_surface applet "function connectNotificationCommand(sourceName)"
require_in_surface applet "function finishNotificationCommandSource(sourceName)"
require_in_surface applet "function refreshSessions()"
require_in_surface applet "readonly property int pollIntervalMs: 60000"
require_in_surface applet "interval: controller.pollIntervalMs"
require_in_surface applet 'import "../CostRefreshPolicy.js" as CostRefreshPolicy'
require_in_surface applet "interval: CostRefreshPolicy.automaticRefreshIntervalMs"
require_in_surface applet "property double lastAttemptAtMs: -1"
require_in_surface applet "property bool updateRetryPending: false"
require_in_surface applet "property bool connectedUpdateInstallMode: false"
require_in_surface applet "property bool pendingAutomaticUpdateCheck: false"

require_in_surface providers "readonly property int configCommandTimeoutMs: 60000"
require_in_surface providers "readonly property int configSecretPromptTimeoutMs:"
require_in_surface providers "readonly property int configSecretCommandTimeoutSeconds: 60"
require_in_surface providers "readonly property int configSecretCommandKillAfterSeconds: 5"
require_in_surface providers "id: configCommandTimeoutTimer"
require_in_surface providers "page.expireConfigCommands(Date.now())"
require_in_surface providers "Component.onCompleted: Qt.callLater(reload)"
require_in_surface providers "onCfg_commandPathChanged: handleCommandPathChanged()"

require_in_surface popup "readonly property int providerRosterCommandTimeoutMs: 60000"
# The roster load lives in the shared controllers/ loader: its ledger import
# carries the parent-directory prefix, and its lifecycle reacts to the
# controller's own commandPath/active inputs instead of the page cfg keys.
require_in_surface popup 'import "../CommandLedger.js" as CommandLedger'
reject_in_surface popup "function commandWithRunNonce(command)"
require_in_surface popup "Component.onCompleted: if (active) Qt.callLater(loadProviderRoster)"
require_in_surface popup "onCommandPathChanged: if (active) Qt.callLater(loadProviderRoster)"
require_in_surface popup "function expireProviderRosterCommands(nowMs)"
require_in_surface popup "id: providerRosterCommandTimeoutTimer"
require_in_surface popup "controller.expireProviderRosterCommands(Date.now())"

require_in_surface diagnostics "readonly property int diagnosticCommandTimeoutMs: 60000"
require_in_surface diagnostics "function commandWithRunNonce(command)"
require_in_surface diagnostics "function handleDiagnosticTimeout()"
require_in_surface diagnostics "id: diagnosticCommandTimeoutTimer"
require_in_surface diagnostics "page.handleDiagnosticTimeout()"
require_in_surface diagnostics "onCommandPathChanged:"

reject_in_surface applet "retiredUsageCommands"
reject_in_surface applet "pendingAccountCommandStartedAt"
reject_in_surface applet "pendingAccountCommands"
reject_in_surface applet "accountCommandTimeoutTimer"
reject_in_surface applet "hasPendingAccountCommands"
reject_in_surface applet "property var accountLoading:"
reject_in_surface applet "setAccountLoading("
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
usage = Surface("applet", root)
usage_path = root / "contents/ui/controllers/UsageController.qml"
usage.texts = {usage_path: usage_path.read_text()}
providers = Surface("providers", root)
popup = Surface("popup", root)
diagnostics = Surface("diagnostics", root)


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


# The applet coordinates presentation/cache; usage owns all of its effects.
usage_text = usage_path.read_text()
for forbidden in ("Plasmoid.configuration", "required property var applet", "root."):
    if forbidden in usage_text:
        raise AssertionError("usage controller must not reach the applet root")
require_all(applet.id_block("usageController"),
    ("selectedAccounts: root.selectedAccounts", "providerConfigRevision: root.providerConfigRevision",
     "providerConfigStamp: root.providerConfigStamp", "popupVisible: root.expanded",
     "onSnapshotReceived:", "root.commitUsageSnapshot(", "onFailed:", "root.failUsageRefresh(message)"),
    "usage must receive explicit inputs and publish through the cache owner")
require_ordered(usage.function_body("connectUsageCommand"),
    ("CommandLedger.opened(", "usageSource.connectSource("),
    "usage requests must register before synchronous replies")
require_ordered(usage.function_body("finishUsageCommandSource"),
    ("CommandLedger.closed(", "usageSource.disconnectSource("),
    "usage requests must retire before disconnect callbacks")
require_ordered(usage.id_block("usageSource"),
    ("CommandLedger.find(lifecycle.activeCommandDescriptors, sourceName)",
     "if (!descriptor)", "return", 'data["stdout"]', "switch (descriptor.kind)"),
    "retired usage replies must be dropped before parsing")
require_all(usage_text,
    ("Component.onDestruction: lifecycle.retireUsageCommands()", "onRequestContextChanged:",
     "lifecycle.expireCommands(Date.now())", "readonly property bool loading:"),
    "usage must own input retirement, destruction, and deadline cleanup")

# Completion-handler order is undefined: only the controller owns startup.
main_text = (root / "contents/ui/main.qml").read_text()
main_start = main_text.index("Component.onCompleted:")
main_startup = Surface._match_braces(main_text, main_text.index("{", main_start))
for duplicate in ("refreshNow(", "scheduleUsageRefresh(", "usageController.refresh(", "usageController.scheduleRefresh("):
    if duplicate in main_startup:
        raise AssertionError("the applet must not start a second initial usage refresh")
usage_start = usage_text.index("Component.onCompleted:")
usage_startup = Surface._match_braces(usage_text, usage_text.index("{", usage_start))
require_ordered(usage_startup,
    ("lifecycle.initialized = true", "lifecycle.scheduleUsageRefresh()"),
    "the usage controller must initialize and schedule its own startup")

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

require_all(applet.function_body("loadAccounts"), ("accountsController.load(providerID)",),
            "account discovery must reach its controller")
require_all(applet.function_body("accountLoadingForProvider"), ("accountsController.loadingForProvider(key)",),
            "account loading must follow the controller ledger")
require_all(applet.function_body("invalidateUsageData"), ("accountsController.reset()",),
            "a full usage context invalidation must reset account lists")

for function_name in ("buildProviderUsageCommand",):
    body = applet.function_body(function_name)
    if 'if (controller.sourceMode.length > 0)' not in body:
        raise AssertionError(f"{function_name} must preserve the automatic CLI source by default")
    if 'effectiveSource' in body or '"cli"' in body:
        raise AssertionError(f"{function_name} must not force Codex to the CLI source")

# The deadline scan moved into CommandLedger.js. Assert that main.qml still
# hands every overdue command to the timeout handler, and that the scan itself
# keeps comparing against the recorded deadline with a clock that fails closed.
require_all(
    usage.function_body("expireCommands"),
    ("CommandLedger.expired(activeCommandDescriptors, nowMs)", "handleCommandTimeout("),
    "command timeout scan is incomplete",
)
require_all(
    applet.function_body("expired"),
    ("Number(entry.deadlineMs)", "Number(nowMs)", "isFinite(now)", "now < deadline"),
    "the ledger deadline scan is incomplete",
)
require_all(
    usage.function_body("hasPendingCommandTimeouts"),
    ("CommandLedger.hasDeadlines(activeCommandDescriptors)",),
    "the timeout timer must read its deadlines from the ledger",
)

timeout_body = usage.function_body("handleCommandTimeout")
require_all(
    timeout_body,
    (
        "switch (descriptor.kind) {",
        'case "usage":',
        'case "providerConfig":',
        'case "providerFallback":',
        "finishUsageCommandSource(sourceName)",
        "Loading usage timed out. Try again.",
        "Loading provider configuration timed out. Try again.",
    ),
    "command timeout cleanup is incomplete",
)
fallback_timeout_start = timeout_body.find('case "providerFallback":')
fallback_timeout_end = timeout_body.find('default:', fallback_timeout_start)
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

require_all(
    applet.function_body("completeProviderFallbackSlot"),
    (
        "ProviderFallbackQueue.complete(",
        "applyProviderFallbackTransition(transition)",
    ),
    "fallback slot completion must cross the pure queue interface",
)
fallback_parse_body = applet.function_body("parseProviderFallbackOutput")
require_ordered(fallback_parse_body,
    ("finishUsageCommandSource(sourceName)", "UsageResponse.response(",
     "completeProviderFallbackSlot(sourceName, item)"),
    "fallback replies must normalize and settle their slot once after retirement")
if fallback_parse_body.count("completeProviderFallbackSlot(") != 1:
    raise AssertionError("fallback replies must complete exactly once")
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
    ("lifecycle.hasPendingPeriodicRefreshCommands()", "lifecycle.refreshNow(false)"),
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

if "refreshSessions" in usage.function_body("refreshNow"):
    raise AssertionError("quota refresh must not start Sessions work")

# Sessions owns its executable source and timers. The applet supplies inputs
# and projects outputs; runtime tests exercise refresh and cooldown behavior.
sessions_controller = root / "contents/ui/controllers/SessionsController.qml"
sessions_text = sessions_controller.read_text(encoding="utf-8")
require_all(
    applet.id_block("sessionsController"),
    ("commandPath: root.commandPath", "refreshIntervalSec: root.refreshIntervalSec",
     "active: root.expanded && root.sessionsSelected"),
    "Sessions must receive explicit configuration and visibility inputs",
)
require_all(
    applet.function_body("refreshSessions"),
    ("sessionsController.refresh()",),
    "the applet's manual Sessions action must reach its controller",
)
for forbidden in ("Plasmoid.configuration", "required property var applet", "root."):
    if forbidden in sessions_text:
        raise AssertionError("Sessions controller must own its lifecycle without the applet root")
if 'case "sessions"' in usage.function_body("handleCommandTimeout"):
    raise AssertionError("Sessions timeouts must leave the shared applet dispatcher")
if 'case "sessions"' in applet.id_block("usageSource"):
    raise AssertionError("Sessions replies must leave the shared usage source")
require_all(
    sessions_text,
    ("CommandLedger.withRunNonce(commandSource, runSerial)",
     'engine: "executable"', "running: controller.loading",
     "lifecycle.expireRequests(Date.now())", "Component.onDestruction: lifecycle.retireRequests()",
     "Loading sessions timed out. Try again."),
    "Sessions must own nonce, process, timeout, and destruction cleanup",
)
def controller_function(text, name):
    start = text.index("function " + name + "(")
    return Surface._match_braces(text, text.index("{", start))


reply = controller_function(sessions_text, "acceptReply")
require_all(
    " ".join(reply.split()),
    ("if (!CommandLedger.find(commands, sourceName)) { return; }",),
    "Sessions must return immediately for a retired source",
)
if reply.index("CommandLedger.find(commands, sourceName)") > reply.index("finishRequest(sourceName)"):
    raise AssertionError("Sessions must reject retired replies before committing a result")
finish = controller_function(sessions_text, "finishRequest")
if finish.index("CommandLedger.closed(") > finish.index("disconnectSource("):
    raise AssertionError("Sessions must retire a request before disconnect callbacks")
request = controller_function(sessions_text, "requestRefresh")
if request.index("CommandLedger.opened(") > request.index("connectSource("):
    raise AssertionError("Sessions must register a request before synchronous replies")

require_all(
    applet.function_body("startProviderFallback"),
    (
        "bypassProviderRosterCache !== true",
        "ProviderRosterCache.read(",
        "providerRosterContext()",
        "startProviderFallbackForProviders(cachedProviderIDs)",
        "buildProviderConfigCommandDescriptor()",
    ),
    "global fallback must reuse only a current provider roster",
)
require_all(
    usage.function_body("refreshNow"),
    ("startProviderFallback(bypassProviderRosterCache === true)",),
    "manual refresh intent must reach provider discovery",
)

manual_refresh_fragments = {
    root / "contents/ui/main.qml": (
        "onTriggered: root.refreshNow(true)",
        'actionID === "refresh"',
        "root.refreshNow(true)",
    ),
    root / "contents/ui/components/ProviderHeader.qml": (
        "onRequested: providerHeaderRow.applet.refreshNow(true)",
    ),
    root / "contents/ui/components/FullRepresentation.qml": (
        "onRequested: applet.refreshNow(true)",
    ),
}
for path, fragments in manual_refresh_fragments.items():
    require_all(
        path.read_text(),
        fragments,
        f"{path.relative_to(root)} manual refresh must bypass the provider roster cache",
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
        "var result = UsageResponse.roster(stdoutText, stderrText)",
        'if (result.outcome !== "success")',
        "return",
        "ProviderRosterCache.remember(",
    ),
    "provider config replies must reject stale contexts and unsupported envelopes before caching",
)
watcher_path = root / "contents/ui/controllers/ProviderConfigWatcher.qml"
watcher_text = watcher_path.read_text()
watcher = Surface("applet", root)
watcher.texts = {watcher_path: watcher_text}
for forbidden in ("root.", "Plasmoid.configuration", "required property var applet"):
    if forbidden in watcher_text:
        raise AssertionError("config watcher must not reach the applet root or persist cache")
require_all(applet.id_block("providerConfigWatcher"),
            ("active: root.usageLifecycleInitialized", "root.handleProviderConfigObservation(stamp, initial)"),
            "the applet must activate the watcher after initialization and handle its observations")
require_ordered(applet.function_body("handleProviderConfigObservation"),
                ("providerConfigStamp = stamp", "if (initial)", "restoreUsageCache()", "return",
                 "invalidateUsageData()", "scheduleUsageRefresh()"),
                "first checksum restores cache; later changes invalidate before refreshing")
require_ordered(watcher.function_body("disconnect"),
                ('connectedCommand = ""', "watchSource.disconnectSource(previous)"),
                "disconnect must retire the source before process effects")
require_ordered(watcher.function_body("reconnect"),
                ("disconnect()", "connectedCommand = nextCommand", "watchSource.connectSource(nextCommand)"),
                "reconnect must register the new source before synchronous cached replies")
require_ordered(watcher.function_body("accept"),
                ("sourceName !== connectedCommand", "watchSource.disconnectSource(sourceName)", "return",
                 "ProviderConfigWatch.observation(", "stamp = result.stamp", "controller.stampObserved("),
                "retired replies must stop polling and observations must commit before signaling")
require_all(watcher_text,
            ("onActiveChanged: lifecycle.reconnect()", "onCommandChanged: lifecycle.reconnect()",
             "Component.onDestruction: lifecycle.disconnect()"),
            "watcher must reconnect on inputs and disconnect during destruction")


accounts_text = (root / "contents/ui/controllers/AccountsController.qml").read_text()
require_all(applet.id_block("accountsController"),
            ("commandPath: root.commandPath", "sourceMode: root.source", "includeStatus: root.includeStatus"),
            "account discovery must receive explicit CLI inputs")
for forbidden in ("root.", "Plasmoid.configuration", "required property var applet"):
    if forbidden in accounts_text:
        raise AssertionError("account controller must own its lifecycle without root callbacks")
for body in (usage.function_body("handleCommandTimeout"), applet.id_block("usageSource")):
    if 'case "account"' in body:
        raise AssertionError("account processes must leave the usage dispatcher")
require_ordered(controller_function(accounts_text, "request"),
                ("controller.loadingForProvider(key)", "CommandLedger.withRunNonce(",
                 "descriptor.commandSignature = baseCommand", "CommandLedger.opened(", "connectSource("),
                "account requests must suppress duplicates and register before connecting")
require_ordered(controller_function(accounts_text, "acceptReply"),
                ("AccountRequests.completion(", "if (!decision)", "return;", "finishRequest(sourceName)",
                 "if (!decision.acceptsPayload)", "return;", "AccountResponse.response("),
                "account replies must reject obsolete sources before normalization")
require_ordered(controller_function(accounts_text, "finishRequest"),
                ("CommandLedger.closed(", "disconnectSource("),
                "account requests must retire before disconnect callbacks")
require_all(accounts_text,
            ("onCommandContextChanged: retireRequests()", "Component.onDestruction: lifecycle.retireRequests()",
             "CommandLedger.hasDeadlines(lifecycle.commands)", "lifecycle.expireRequests(Date.now())",
             "Loading accounts timed out. Try again."),
            "account controller must own context retirement, deadlines, and destruction cleanup")

cost_text = (root / "contents/ui/controllers/CostController.qml").read_text()
require_all(
    applet.id_block("costController"),
    ("commandPath: root.commandPath", "provider: root.provider",
     "historyDays: root.costHistoryDays", "costUsageEnabled: root.costUsageEnabled",
     "active: root.spendSelected && root.expanded"),
    "cost lifecycle must receive explicit command, range, enabled, and visibility inputs",
)
for forbidden in ("root.", "Plasmoid.configuration", "required property var applet"):
    if forbidden in cost_text:
        raise AssertionError("cost lifecycle must be independent of the applet root")
for body in (usage.function_body("handleCommandTimeout"), applet.id_block("usageSource")):
    if 'case "cost"' in body:
        raise AssertionError("cost processes must leave the shared usage dispatcher")
require_all(
    cost_text,
    ('engine: "executable"', "running: controller.loading", "lifecycle.expireRequests(Date.now())",
     "Component.onDestruction: lifecycle.retireRequests()", "Loading cost data timed out. Try again.",
     "interval: CostRefreshPolicy.automaticRefreshIntervalMs", "running: lifecycle.commandSource.length > 0",
     "running: controller.active", "CostRefreshPolicy.isNewBucketDay(lifecycle.lastAttemptAtMs, Date.now())",
     "snapshotContext === lifecycle.commandSource", "Qt.callLater(refreshChangedSource)"),
    "cost controller must own process cleanup, hourly scans, day rollover, and context projection",
)
require_ordered(
    controller_function(cost_text, "requestRefresh"),
    ("CostRefreshPolicy.refreshAction(", "retireRequests()", "lastAttemptAtMs = nowMs",
     "CommandLedger.withRunNonce(commandSource, runSerial)", "descriptor.historyDays = controller.historyDays",
     "descriptor.context = commandSource", "CommandLedger.opened(", "connectSource("),
    "cost runs must capture their context, replace older runs, and register before connecting",
)
require_ordered(
    controller_function(cost_text, "acceptReply"),
    ("CommandLedger.find(commands, sourceName)", "if (!descriptor)", "return;",
     "finishRequest(sourceName)", "CostResponse.response(stdoutText, stderrText, descriptor.historyDays)",
     "snapshotContext === descriptor.context", "Normalizer.mergeCostSnapshotsAfterPartialFailure("),
    "only live cost replies may commit or retain snapshots from the captured context",
)
require_ordered(
    controller_function(cost_text, "finishRequest"),
    ("CommandLedger.closed(", "disconnectSource("),
    "cost commands must retire before disconnect callbacks",
)
require_all(applet.function_body("refreshCost"), ("costController.refresh(force)",),
            "manual cost refresh must reach the controller")
require_all(applet.function_body("refreshSpendIfStale"),
            ("!spendSelected || !expanded", "costController.refresh(false)"),
            "spend revisits must respect visibility and cooldown")
require_all(applet.function_body("selectGlobalView"),
            ('candidate === "spend"', "refreshSpendIfStale()"),
            "reselecting spend must recheck freshness")

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
# Interactive prompts own one long escape-hatch deadline so a wedged kdialog
# cannot disable a provider's actions until the page reopens. They must never
# share the short noninteractive deadline, which would kill a live dialog.
for function_name in ("setApiKey", "promptDescriptorSecret"):
    body = providers.function_body(function_name)
    if "timeoutMs: configCommandTimeoutMs" in body:
        raise AssertionError(f"interactive {function_name} commands must not share the noninteractive deadline")
    if "timeoutMs: configSecretPromptTimeoutMs" not in body:
        raise AssertionError(f"interactive {function_name} commands must keep the long escape-hatch deadline")
    require_all(
        body,
        (
            "command -v timeout",
            "timeout --kill-after=1s 1s true",
            "timeout --kill-after",
            "configSecretCommandTimeoutSeconds",
            "configSecretCommandKillAfterSeconds",
            "configSecretPromptDialogTimeoutSeconds",
            "configSecretPromptDialogKillAfterSeconds",
        ),
        f"interactive {function_name} must bound the dialog and the post-prompt CLI phase",
    )

# The dialog process is a grandchild of the tracked source, so the ledger
# deadline only kills the script shell and would orphan the dialog. Each prompt
# must run kdialog under its own timeout just below the QML deadline.
require_all(
    providers.function_body("setApiKey"),
    (
        "timeout --kill-after=\\\"${7}s\\\" \\\"${6}s\\\" kdialog --password",
        "shellQuote(configSecretPromptDialogTimeoutSeconds)",
        "shellQuote(configSecretPromptDialogKillAfterSeconds)",
    ),
    "setApiKey must bound the kdialog phase below the ledger deadline",
)
require_ordered(
    providers.function_body("promptDescriptorSecret"),
    (
        "var boundedDialogCommand = \"timeout --kill-after=\"",
        "shellQuote(configSecretPromptDialogKillAfterSeconds + \"s\")",
        "shellQuote(configSecretPromptDialogTimeoutSeconds + \"s\")",
        "kdialog --password \\\"$1\\\"",
        'value=$(" + boundedDialogCommand + ',
    ),
    "descriptor secret prompts must bound the dialog process below the ledger deadline",
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
        "descriptor.kind === \"setApiKey\"",
        "descriptor.kind === \"descriptorField\"",
        "descriptor.kind === \"descriptorAction\"",
        "setProviderDiagnosticLoading",
        "markPending(descriptor.provider, false)",
        "markFieldPending(descriptor.provider, fieldID, false)",
    ),
    "config timeout handler is incomplete",
)

require_all(
    popup.function_body("loadProviderRoster"),
    (
        "CommandLedger.withRunNonce(command, commandRunSerial)",
        "CommandLedger.descriptor(",
        "providerRosterCommands = CommandLedger.opened(",
    ),
    "provider roster loads need nonce and deadline",
)

require_all(
    popup.function_body("expireProviderRosterCommands"),
    (
        "CommandLedger.expired(providerRosterCommands, nowMs)",
        "providerRosterSource.disconnectSource(sourceName)",
        "CommandLedger.closed(remaining, sourceName)",
        "Loading providers timed out. Try again.",
    ),
    "provider roster timeout cleanup is incomplete",
)

require_all(
    popup.function_body("disconnectProviderRosterCommands"),
    (
        "CommandLedger.sourcesOfKind(",
        'providerRosterCommands, "enabledProviderRoster"',
        "providerRosterSource.disconnectSource(sourceName)",
    ),
    "provider roster retirement must read the shared ledger",
)

require_all(
    popup.function_body("hasPendingProviderRosterCommands"),
    ('CommandLedger.hasKind(providerRosterCommands, "enabledProviderRoster")',),
    "provider roster loading state must read the shared ledger",
)

require_all(
    popup.function_body("handleProviderRosterData"),
    (
        "CommandLedger.find(providerRosterCommands, sourceName)",
        "CommandLedger.closed(providerRosterCommands, sourceName)",
    ),
    "provider roster completion must close the shared ledger entry",
)

require_all(
    diagnostics.handler_body("onCommandPathChanged"),
    ("finishDiagnosticCommand(activeCommand)", 'diagnosticOutput = ""', 'diagnosticError = ""'),
    "editing the command path must discard pending diagnostics from the old CLI",
)

require_all(
    diagnostics.function_body("runCommand"),
    ("commandWithRunNonce(command)", "diagnosticCommandTimeoutTimer.restart()"),
    "diagnostics commands need nonce and timeout",
)

require_all(
    diagnostics.function_body("handleDiagnosticTimeout"),
    ("finishDiagnosticCommand(activeCommand)", "Diagnostic command timed out. Try again."),
    "diagnostics timeout cleanup is incomplete",
)

require_all(
    diagnostics.function_body("handleDiagnosticData"),
    ("SafeText.cliJsonText", "codexbar response exceeded the supported size."),
    "diagnostics oversize cleanup is incomplete",
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
    (
        "UpdateLogic.updateRequestDecision(",
        "pendingAutomaticUpdateCheck = requestDecision.pendingAutomaticCheck",
        "var installMode = requestDecision.installMode",
        "buildUpdateCommand(installMode)",
        "updateCommandTimeoutTimer.interval = installMode",
        "scheduleNextUpdateCheck()",
        "updateCheckTimer.stop()",
    ),
    "update checks must queue automatic installs and capture each command mode",
)

finish_update_body = applet.function_body("finishUpdateCommand")
require_all(
    finish_update_body,
    (
        "successfulCheck",
        "connectedUpdateInstallMode = false",
        "UpdateLogic.updateCompletionDecision(",
        "pendingAutomaticUpdateCheck = completionDecision.pendingAutomaticCheck",
        "completionDecision.startAutomaticCheck",
        "lifecycle.checkForWidgetUpdate(true)",
        "controller.checkSucceeded(completedAt)",
        "scheduleNextUpdateCheck(completedAt)",
        "scheduleUpdateRetry()",
    ),
    "update completion must run a queued automatic install before normal scheduling",
)
queued_check_index = finish_update_body.find("completionDecision.startAutomaticCheck")
retry_index = finish_update_body.find("scheduleUpdateRetry()")
next_check_index = finish_update_body.find("scheduleNextUpdateCheck(completedAt)")
if queued_check_index > retry_index or queued_check_index > next_check_index:
    raise AssertionError("a queued automatic install must take precedence over retry and interval scheduling")

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
        "var installMode = connectedUpdateInstallMode",
        "var resultIntent = UpdateLogic.resultIntent(payload, installMode)",
        "applyUpdateResultIntent(resultIntent)",
        "finishUpdateCommand(sourceName, resultIntent.successful)",
    ),
    "update results must use the mode captured when their command started",
)
if "autoUpdateEnabled" in applet.function_body("handleUpdateData"):
    raise AssertionError("update result handling must not read the current automatic-update setting")

require_all(
    applet.id_block("updateCheckTimer"),
    ("repeat: false", "running: false", "lifecycle.handleUpdateCheckTimer()"),
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
    "lifecycle.scheduleNextUpdateCheck()",
    "changing the update interval must rearm the scheduler",
)
updater_path = root / "contents/ui/controllers/WidgetUpdateController.qml"
updater_text = updater_path.read_text()
main_text = (root / "contents/ui/main.qml").read_text()
for forbidden in ("Plasmoid.configuration", "required property var applet", "root."):
    if forbidden in updater_text:
        raise AssertionError(f"the updater must own its lifecycle without the applet root: {forbidden}")
for forbidden in ("id: updateSource", "id: updateCheckTimer", "id: updateCommandTimeoutTimer",
                  "connectedUpdateCommandSource", "function handleUpdateData("):
    if forbidden in main_text:
        raise AssertionError(f"main must not retain updater lifecycle state: {forbidden}")
require_all(updater_text, (
    'Qt.resolvedUrl("../../../scripts/update-widget.sh")',
    "CommandLedger.withRunNonce(buildUpdateCommand(installMode), commandRunSerial)",
    "if (sourceName !== connectedUpdateCommandSource)",
    "SafeText.cliJsonText(rawStdoutText)",
    "controller.statusRecorded(updateStatusText, updateErrorText)",
    "controller.updateAvailable(intent.version, intent.assetUrl)",
    "controller.updateInstalled(intent.version)",
), "the updater must preserve its packaged script, request identity, validation, and events")
require_all(main_text, (
    "Controllers.WidgetUpdateController {",
    "onStatusRecorded: function(statusText, errorText)",
    "Plasmoid.configuration.widgetUpdateLastStatus = statusText",
    "Plasmoid.configuration.widgetUpdateLastError = errorText",
    "onCheckSucceeded: function(timestamp)",
    "Plasmoid.configuration.autoUpdateLastCheck = timestamp",
    "root.notifyAvailableUpdate(version, assetUrl)",
    "root.notifyInstalledUpdate(version)",
), "main must persist updater results and retain notification delivery")

PY

echo "KDE plasmoid process lifecycle checks passed."
