# Implementation reference

Use this reference to locate an owner and preserve its contracts before editing.
Paths are relative to the repository root; applet paths below may omit
`contents/ui/`. [Development](development.md) owns setup and delivery;
[Testing](testing.md) owns check selection. Read the owning implementation,
config entry, CLI input, and nearest behavioral test before changing behavior.

## Ownership and implementation

QML owners manage processes, timers, nonces, configuration, localization and
external effects. Pure JavaScript modules receive explicit inputs and return
bounded data, semantic decisions or opaque next state. Presentation components
receive normalized data and explicit parent APIs; they do not fetch providers or
read applet state implicitly. Configuration lives in `contents/config/main.xml`,
with `cfg_*` bindings in settings and `Plasmoid.configuration` at runtime.

### Find the owner

| Area | Effect owner | Pure contracts and presentation |
| --- | --- | --- |
| Usage publication, cache, selection and account coordination | `main.qml` | `UsageState.js`, `UsageCache.js`, `ProviderSnapshot.js`, `ProviderViewModel.js` |
| Usage discovery, fallback requests and refresh scheduling | `controllers/UsageController.qml` | `UsageResponse.js`, `NetworkState.js` |
| Account discovery | `controllers/AccountsController.qml` | `AccountResponse.js`, shared snapshot normalization |
| Config checksum observation | `controllers/ProviderConfigWatcher.qml` | `ProviderConfigWatch.js` |
| Cost requests and off-thread normalization | `controllers/CostController.qml`, `CostWorker.mjs` | `CostResponse.mjs`, `CostWorkerRequest.mjs`, `ProviderNormalizer.mjs` |
| Sessions scans | `controllers/SessionsController.qml` | `SessionResponse.js`, `SessionRefreshPolicy.js`, `components/SessionLabels.qml` |
| Identified Codex subtotal | `controllers/IdentifiedTokensController.qml` | `IdentifiedTokens.js`, `components/IdentifiedTokensSection.qml`; [cost contract](cost-history.md) |
| Panel | `main.qml`, `components/CompactRepresentation.qml` | `PanelDisplay.js`, `PanelRules.js`, `PanelProviders.js`, `PanelText.js`, `PanelTextFit.js`, `components/PanelText.qml` |
| Popup and tab navigation | `components/FullRepresentation.qml`, `components/PopupTabStrip.qml` | `TabStripGeometry.js`, `PopupSelection.js`, `OverviewProviders.js`, hidden-row/section modules |
| Detail and cost display | Popup presentation owners | `UsageDetails.js`, `ProviderCostPresentation.js`, `ResetPresentation.js`, `SubscriptionDates.mjs`, localized text components |
| Quota and status notification policy | `main.qml` | `NotificationObservations.js`, `NotificationPlanner.js`, `QuotaThresholds.js`, `components/ProviderNotificationText.qml` |
| Notification execution and update policy | `controllers/NotificationDispatcher.qml`, `controllers/UpdateNotificationsController.qml` | `NotificationCommand.js`, `UpdateNotificationState.js` |
| Widget updates | `controllers/WidgetUpdateController.qml`, `scripts/update-widget.sh` | `UpdateLogic.js` |
| CLI checks and private installation | `controllers/CliUpdateController.qml`, `controllers/ManagedCliController.qml`, Python helpers | `CliUpdate.js`, `ManagedCli.js`, `scripts/lib/cli_release.py`, `scripts/lib/managed_cli.py` |
| Provider settings and writes | `configProviders.qml`, `controllers/ProviderRosterController.qml` | `config/` protocol, capability, authentication and operation modules; [credential contract](provider-credentials.md) |
| AI Insights | `controllers/AiInsightsController.qml`, `configAiInsights.qml`, Python helper | Policy, protocol and snapshot modules; [AI contract](ai-insights.md) |
| Usage export | `main.qml`, `components/ShareUsageWindow.qml` | `ShareUsage.js`, `ShareUsageCard.qml`; [sharing](#usage-sharing) |

Use direct `tests/tst_*.qml` checks for pure/component interfaces and the
corresponding `tests/test_*.py` controller checks for effects. Do not duplicate
those test inventories here; [Testing](testing.md) explains their scope.

### Executable requests

Plasma's executable engine shares source names between DataSources. Every
one-shot QML owner supplies a local numeric serial and a fresh timestamp/random
nonce to `CommandLedger.withRunNonce`. That module quotes the nonce as a
separate environment assignment; it does not generate identities. Serials alone
collide between instances and recreated settings pages. The continuous config
watcher deliberately shares its polling source instead.

Treat stdout/stderr, descriptors, cached payloads, labels, URLs and status text
as untrusted. Validate types, shape, bounds, command allowlists and URL schemes;
an optional enrichment failure cannot erase healthy provider data. Reuse
`Guards.js` rather than adding independent guard implementations.

`controllers/CliProcess.qml` owns one active request. `start(command, context,
timeoutMs)` supersedes existing work; `cancel()` silently retires it. Completion
forwards captured context and raw stdout, stderr and exit code; timeout forwards
context. Treat context as immutable. The ledger retires requests before callbacks
and rejects late/duplicate replies, including reentrant callbacks. Cancellation
and destruction disconnect sources immediately. Domain normalization, retention,
localization and retry decisions remain with callers.

`Guards.boundedShellCommand` adds a process-group deadline before the nonce:
GNU `timeout` sends TERM two seconds after the UI deadline, then KILL after one
second. A waiting shell keeps the monitor alive after disconnection, destruction
or a direct child exiting on TERM. It catches PIPE so late diagnostic writes
cannot cancel escalation; executed children keep normal signal handlers.
Usage, accounts, provider settings, rosters and notification commands share
this guard. Without GNU `timeout`, UI retirement still applies but the process
may remain hung. Prove termination separately from UI timeout state.

A process success requires `Guards.exitCode` to accept numeric zero or an
integer-string zero. Null, booleans, blank strings, arrays and missing codes
cannot authorize state publication, installation selection or success signals.
Structured CLI errors can remain readable after a nonzero exit. Shared-envelope
consumers use one bounded decoder with separate page-specific projections, so a
common parser does not erase distinct UI meanings.

### Usage, accounts and cache

`UsageController` alone schedules startup. Input changes synchronously retire
old work and coalesce replacement requests; `main.qml` must not start a second
refresh from its completion handler. Manual refresh bypasses the roster cache;
periodic refresh waits for pending usage. Aggregate overrides expand before
scoped scheduling: `both` means Codex and Claude, `all` includes disabled valid
inventory entries, and an empty override discovers enabled providers only.
Changing the override invalidates the roster cache.

A successful aggregate `[]` is a confirmed empty roster: it clears quotas and
successful-refresh freshness. Scoped empty replies and nonempty replies without
usable records are failures. The aggregate behavior was verified with official
Linux CLI 0.84.0 in an isolated bubblewrap home after `config disable`, using
`usage --source api --format json --json-only`; installed 0.83.0 behaved the same.
The `both`/`all` identities were separately verified with isolated CLI 0.83.0,
`--source web`, and no networking: all 111 inventory entries appeared for `all`.
These probes establish identities and empty-result semantics, not authenticated
provider support.

When every scoped usage command fails to launch, the controller reports a global
command-path failure so an empty popup offers CLI setup. Mixed batches still
publish their per-provider results regardless of reply order.

Selected Codex usage uses `--all-accounts` and matches the exact selected key
before provider deduplication. A missing or failed selection cannot borrow healthy
sibling quotas. Other providers use `--account`; clearing selection restores the
default command. Different Codex selections may share a command but still retire
previous request contexts.

Account discovery retains a successful list on failure; a confirmed empty list
clears only that provider. Availability distinguishes named accounts, no accounts,
and the CLI's unsupported-token-account error. Closing the popup dismisses armed
notices, including late results; a new discovery arms them again. Persistent
unsupported availability disables the menu entry and keeps the panel's reload
action reachable after the notice is dismissed. Reset discovery on usage identity,
config, managed-CLI or empty-roster changes. In-place package upgrades need a
reload or Plasma restart.

`ProviderConfigWatcher` polls checksums once a minute. Its first accepted
observation restores cache; later changes invalidate usage and schedule refresh.
Repeated/malformed observations leave state intact. Its parser accepts bounded
`missing` or CRC checksum/byte-count/file records, including whitespace in names.
It follows existing config-path precedence without parsing JSON or writing config.

`UsageState.js` plans commits, failures, restore, invalidation and expiry from
snapshots, context and time. `applyUsageTransition` is the single persisted cache
writer: `null` means no write and `""` clears it. Clear notification suppression
before publishing fresh data. An accepted early empty roster clears disk quotas
without waiting for cache context; an early failed refresh leaves unverified disk
cache intact. The first checksum also persists early successful usage and merges
missing cached providers through `UsageCache.restore`, preserving live results.
Only restored quotas become stale; a fresh-only result keeps its update label.

Quota retention is bounded to 24 hours in memory and on restore. Failed retries
keep the original measurement time; the minute timer expires data even with
refresh disabled. Snapshot receipt times survive account selection and privacy.
They prevent a cached account from renewing retention or restarting another row's
run-out countdown. Receipt fields stay in memory; persistence stores only resolved
measurement time and rebuilds allowlisted records through normalization.

The context fingerprint isolates CLI/config selections, not integrity or
confidentiality. Memory-only account overrides stay outside it, so overridden
providers are omitted from saving/restoring. The cache stores no identities,
credentials, paths or provider prose. Its bounded stale reuse adapts
[RFC 5861](https://www.rfc-editor.org/rfc/rfc5861.html) as local policy, not HTTP
caching, with [input validation](https://cheatsheetseries.owasp.org/cheatsheets/Input_Validation_Cheat_Sheet.html)
and [data minimization](https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html#minimize-the-storage-of-sensitive-information).

Current status evidence is independent of quota freshness. Retained quotas cannot
prime or change notification baselines, but current status still can. A later
response without status marks a retained incident unknown; ranking, tooltips and
badges must not present that old outage as current.

Network reachability loads through `controllers/NetworkReachability.qml` only.
Its `QtNetwork` import needs Qt 6.7, while the applet supports Plasma 6.0, so
`main.qml` uses a Loader and failed loading remains unknown. Returning from
non-online to online requests one refresh after a two-second settle; leaving
online cancels it, and intervening refreshes make it unnecessary. Offline state
never suppresses local-source refreshes. `NetworkState.js` recognizes only tested
Foundation URL codes and unresolved-host forms; classify raw text before privacy
filtering and localize the result in QML.

### Costs, identified tokens and sessions

`CostController` owns context and independent hourly/day-aware scheduling;
`CliProcess` owns execution. Source changes retire commands synchronously and
coalesce settings through `Qt.callLater`. `CostWorker.mjs` normalizes off the GUI
thread. `CostWorkerRequest.mjs` bounds thread-boundary copies while preserving
diagnostic inspection and credential-redaction lookahead after whitespace.
Loading spans process execution and normalization under one 120-second deadline.
Serials invalidate worker replies after context changes, forced refresh, disable
or timeout. One normalization and one replaceable pending reply bound the queue.
Scan warnings follow the active command and the retained snapshot's context.
Same-context retries keep the warning visible until success or a replacement.

QML and WorkerScript share `.mjs` dependencies. `Guards.js` remains the QML entry
point to `Guards.mjs`; validation has one implementation. Export declarations
directly: Qt 6.11.1 `qmllint` cannot resolve members exposed only by a trailing
export list. Cost normalization selects/gap-fills amount rows before projecting
models for retained dates. Averages use `includeModels: false`. Raw-record maps
and exact-model-label memoization are call-local; cache only validated labels,
never amounts or counts. Validate shared currency per populated summary without
retaining it across summaries/calls.

`CostText.qml`, `CostLabels.qml` and `ProviderCostDetails.qml` localize explicit
presentation inputs. `CostPresentation.mjs` builds rows and aggregates;
`CostAmounts.mjs` formats amounts and distinguishes unknown from zero;
`CostCurrency.mjs` excludes foreign money without dropping tokens;
`CostTrust.mjs` owns pricing confidence and bounded dismissal scopes;
`CostChart.mjs` owns geometry and date-preserving selection. `LegacyUsageDashboard.js`
validates compatibility rows; only a bounded displayable custom period label
replaces the translated fallback. Financial semantics, identified-ledger schemas,
model rankings and pinned CLI evidence belong in [Cost history](cost-history.md).

The identified subtotal is manual and independent of ordinary cost refresh.
Its controller has no startup/refresh timer; settings changes retire work and
clear results. `IdentifiedTokens.js` returns aggregate counts and optional CLI
estimates, never request IDs, hosts, model metadata or raw errors. It accepts
schemas 1/2, reports incompatibility separately and leaves pricing to the CLI.
Process timing and SSH constraints are specified in the cost reference.

`SessionsController` scans only while its tab is visible, capped at a 30-second
visible rescan interval. Hiding stops scheduling but permits an active scan to
finish. A command change retires and clears old context. Failed scans retain the
successful snapshot/time, with attempt completion tracked separately so retry
cooldown begins after the reply or timeout. Manual retry bypasses cooldown.
Only the first 128 records are inspected: a nonempty list with no usable records
inside that bound is a failed scan; mixed lists keep readable sessions.

### Notifications and updates

`NotificationObservations.js` owns account scopes, aliases, freshness and quota/
pace eligibility, returning copied observations and pending maps. `main.qml`
commits pending state before publishing fresh providers. `NotificationPlanner.js`
returns intents from observations and opaque memo; localization and dispatch stay
in QML. Intents preserve observation/row indexes and status, quota, pace, reset
order. Bounded memo selection protects current keys before recent stale scopes.
See [behavioral contracts](#behavioral-contracts-to-preserve) for transition rules.

`ProviderNotificationText.qml` takes an intent, normalized row/provider and
preformatted labels, returning title/body/urgency. The shared
`UpdateNotificationsController.send()` applies privacy. `NotificationDispatcher`
accepts localized, filtered text, assigns per-send nonces, and owns ledger and
10-second deadlines, or two minutes for clickable notifications. It retires a
source before reporting the action outcome. Failed commands and missing
`notify-send` are quiet; `NotificationCommand.js` bounds text, quotes arguments,
escapes body markup, restricts urgency and probes action support for older builds.

Update notification policy owns independent switches, localization, persisted
version deduplication and source-specific release actions. Save widget versions
before send; save CLI versions only after a safe source starts, allowing retries.
Managed copies with automatic updates do not announce redundant CLI releases.
`UpdateNotificationState.js` validates release URLs and immutable action maps.
Register the URL before connecting the executable source so even an immediate
reply can consume it. Remove the URL when the command finishes or times out. Only activation
requests that the applet open the URL, after removal.

`WidgetUpdateController.checkNow()` respects disabled checks;
`runNow(install)` permits manual checks/install while automatic settings are off.
Startup honors the saved successful-check timestamp. Pending version state must
survive restart so a failed install remains retryable. `main.qml` services the
runtime `widgetUpdateRequest` through a deferred handler: rewriting a key read by
the same binding synchronously loses the write. Mark accepted work `running:<mode>`;
clear only after `busy` drops in `onBusyChanged`. Both settings buttons follow that
marker. Persist status/results and forward events in `main.qml`; the controller
never reads the root or writes configuration itself.

CLI release checks are read-only. General also runs a separate offline probe on
open/command changes to confirm first-install eligibility; Diagnostics uses local
mode only. Shared Python probes have output/deadline bounds and validate official
release metadata. Failed retargeted checks can retry after one hour even if the
prior command had a recent successful timestamp. Automatic release checks
ignore a retry deadline more than one hour ahead after a wall-clock rollback.

Diagnostics compares transient identifiers derived from validated resolved paths
before display redaction and truncation. The support report shares the comparison
result without including the paths or their identifiers.

Managed installation selects only a helper-verified executable, never a path from
metadata-only `status`. General waits for the offline probe and offers install
only for a confirmed missing command or identified CLI; failed probes offer Retry.
Only Apply saves the chosen path. Restoring defaults retires pending work even
when the path already equals its default.

`scripts/lib/managed_cli.py` owns per-user locking, throttling, bounded official
downloads, strict extraction, isolated version probes, atomic activation and
rollback. Only the configured launcher path is eligible. The release probe reports this
selection separately from ownership of the resolved executable so a PATH lookup
or version-specific path still receives release announcements. Mutations, cleanup and
rollback share the lock; healthy offline reuse bypasses it and release requests.
First-time install rechecks for a newly activated copy under the lock before
contacting GitHub.
Rollback compares the displayed stable `--expected-previous` target after locking
and before probing/pruning/activation. Stale targets return `stale` unchanged.
Probe the rollback executable before activation; failure returns `no_previous`.
A completed rollback blocks automatic reinstall of that release. Other inactive
releases receive a one-hour cleanup grace.

Resolve the base data directory before appending the private root, including
symlink/`..` combinations, while retaining root ownership/symlink checks. Keep a
replaced release's backup outside temporary staging until replacement succeeds.
Restore it on failure; failed restoration leaves `.retained-*` for recovery.
Validate finite attempt timestamps before mutation. Receipt, checksum/VERSION,
asset identity and permissions remain separate checks. A 600-second helper alarm
and outer GNU timeout cover downloads/decompression. `network`, `unverified`,
`unsupported` and generic `error` stay distinct; new helper codes need an explicit
classification. Retiring UI work cannot undo an installation already in progress.

Runtime `managedCliRevision` triggers a fresh General status read after successful
changes. Coalesce reads until active work retires; never persist it as a `cfg_*`
property. Offline status updates preserve a stale-rollback notice until a later
mutation result replaces it.

### Optional helpers

[AI Insights](ai-insights.md) owns its boundary decision, allowlisted input,
private one-use handoff, credentials, language, request and scheduling contracts.
Its QML controller owns generation and retirement; `main.qml` persists results.
The Python helper alone prompts for and reads Secret Service keys and makes
requests. While disabled, no snapshot or AI process is built. Disclosure never
generates; an explicit fixed intent is bound to the captured snapshot and saved
answer. Analytics selection/curves remain pure; QML owns drawing and interaction.

The Status page's component helper is an explicit CLI-boundary exception while
the CLI exposes overall status only. `main.qml` owns one expanded provider,
request and 30-second deadline. Collapse, popup close, navigation or another
expansion cancels it; late results cannot update a different provider.
`StatusComponents.js` validates bounded names/states; `scripts/status-components.py`
reads fixed public Claude/OpenAI/xAI feeds without credentials, raw remote text or
errors. Prefer installed curl for
[Happy Eyeballs](https://curl.se/docs/manpage.html#--happy-eyeballs-timeout-ms),
disabling curl config, redirects and non-HTTPS destinations. Require HTTP 200,
5-second connect and 10-second transfer bounds; Python caps 1 MiB and enforces a
12-second child deadline. The bounded, non-redirecting urllib fallback also
rejects a body that ends before its declared Content-Length.

Keep component expansion outside action-row identity and preserve group names
across refreshes. Malformed affected-component collections keep healthy siblings
and unknown states; absent/null/empty collections retain operational fallback.
Grok/xAI's `https://data.x.ai/status/summary.json`, linked by
[the status page](https://status.x.ai/), was verified 2026-11-12 with available
components. Its published schema maps `available`, `info`, `disruption`, `outage`,
`no_data` to `none`, `info`, `minor`, `critical`, `unknown`; non-available states
are synthetic-fixture coverage, not observed outages. Component `info` is neutral
and does not alter provider severity. Replace the helper when an official CLI
contract appears; [TODO](../TODO.md#status-components) tracks that dependency.

### Provider credential commands

`configProviders.qml` owns prompts, writes, nonces, locks, confirmation,
configuration revisions and diagnostics invalidation. Pure modules in `config/`
own capability gates, protocol parsing, authentication metadata and pending
operation transitions. `ProviderOperations.js` defers roster reloads until source
and credential writes finish, preserving the write error through the reload.
Retirement clears ephemeral operation state.

`ProviderConfigProtocol.response` accepts bounded stdout according to explicit
command profiles. Only `setApiKey` permits legacy empty successful output.
`enabledRoster` retains tolerant record projection with failed-exit precedence.
For writes, structured errors win; valid success at exit zero ignores stderr
noise; other outcomes preserve stderr, timeout, exit-code and payload/status
failure ordering. Parse errors are bounded/redacted before localization.

`ProviderAuthentication.js` projects optional official 0.83.0 inventory metadata
into bounded source modes, writer flags, environment names, redacted account hints
and the allowlisted Copilot hint. Missing metadata retains fallback behavior;
malformed capabilities authorize no writes and cannot discard healthy providers.
The curated Linux API-key allowlist remains required alongside the advertised
flag. Credential-marker filtering is conservative and assumes no minimum token
length. Arbitrary commands and credentials never survive metadata projection.

`ProviderCapabilities.js` owns released-version gates and the legacy key list;
`ProviderCredentials.js` owns the probe-backed cookie allowlist, helper commands
and semantic results. The page resets flags on executable changes/failed probes.
Only `promptDescriptorSecret` carries secrets inside its script and official CLI
stdin; it reads the value inside the script. Secrets never enter command lines,
including shell positional arguments piped to stdin, because `/proc/<pid>/cmdline`
exposes them. Generic field writers reject `kind === "secret"`. Session import
uses the same private path and requires one authorized event plus exit zero.
Never retain raw keys, cookies, bearer tokens, auth headers or unredacted
diagnostics in logs, UI, fixtures or persisted data. AI service keys stay inside
`scripts/lib/ai_insights.py`, which prompts, stores and reads them through Secret
Service; they never enter QML.

`scripts/provider-auth.py` transports supported commands; it never parses config,
authenticates to providers or accepts a GitHub token. It drains bounded JSON,
suppresses raw stderr and returns semantic records. Copilot's newline-delimited
events stream into a native `kdialog --textbox -`, since Plasma publishes stdout
only at process exit. Pure stream/event decisions are separate from the process
loop, which owns dialog stdin, timeout and cleanup.

Credential commands own separate CLI process groups and reap CLI/dialog children
on every outcome. Parent-loss detection spans output draining and CLI exit;
cancellation must escape interrupted-selector handling. A credential-free marker
is written through `credential/LoginCancellation.qml`, a singleton whose lifetime
survives page destruction. Private markers expire after 20 minutes; no event
file or persistent service is created. Dialog close cancels; OK dismisses the
dialog while settings keep waiting. Success bumps the existing config revision.
Never test with the user's provider config. [Provider credentials](provider-credentials.md)
owns exact released commands, evidence and exclusions.

`ProviderDescriptorField.qml` only renders normalized fields and emits write,
enum-selection or prompt requests. The page resolves enum IDs and validates and
executes effects. Restore the saved enum binding after a started write completes;
keep rejected choices available for retry.

`ProviderRosterController` loads settings rosters. Popup loads on open; Panel
loads only while its selection section is expanded, reading command/order at
runtime rather than claiming unrelated `cfg_*` keys. Queued work rechecks active
state; deactivation clears loading/error. Command changes synchronously retire
old work and clear old roster/error even while inactive. A nonzero exit cannot
supply selectable providers, and malformed stdout cannot hide that process error.

## Usage sharing

`ShareUsage.js` exports a bounded, range-matched aggregate, never whole provider,
account, project or raw-error records. Raw model identity is the aggregation key;
labels are display only. Cost/token rankings remain separate before display caps,
share calendar selection with totals, and survive privacy projection. Missing daily
rankings cannot inherit period data. Malformed/duplicate dates suppress zero-day
inference without discarding valid observations. See [Cost history](cost-history.md)
for financial and model semantics.

Redact whole model labels containing absolute paths, including embedded, quoted,
Unicode and space-containing UNC shares; retain ordinary namespaced model IDs and
aggregate amounts. `main.qml` freezes the projection when lazily opening
`ShareUsageWindow.qml`. The window owns capture generations, native clipboard
writes and save results/dialogs. Closing it or changing privacy retires captures;
the panel popup may close independently.

Capture uses Qt's [asynchronous item grab](https://doc.qt.io/qt-6/qml-qtquick-item.html#grabToImage-method),
[PNG save](https://doc.qt.io/qt-6/qquickitemgrabresult.html#saveToFile),
[FileDialog](https://doc.qt.io/qt-6/qml-qtquick-dialogs-filedialog.html), and KDE's
[Clipboard](https://api.kde.org/qml-org-kde-kquickcontrols-addons-clipboard.html).
Copy the QImage, not its temporary image-provider URL. Keep native overwrite
confirmation. No shell clipboard helper, upload or provider fetch is involved.
Runtime needs `QtQuick.Dialogs` and `org.kde.kquickcontrolsaddons`.

The isolated window fixture paints a QML-owned background around content/footer:
native window roots lack a QML engine on some supported Qt versions. Tests cover
real PNG/clipboard MIME, retirement and keyboard behavior; smoke captures include
the complete window. They cannot establish interoperability with every Wayland
application or portal backend.

## Behavioral contracts to preserve

### Quota confidence and notifications

`ProviderSnapshot.js` stamps rows with `exact`, `estimated`, `percentOnly`,
`unknown`, or the empty legacy marker. Only an absent raw confidence field gets
legacy behavior; explicit empty/undefined values become unknown. Cache writes
omit the legacy marker and preserve other values. `authoritativeQuota` gates
automation, warning colors, visibility and auto-selection. `canPresentQuotaDetails`
also admits `percentOnly` for explicit resets/forecasts, without granting automation.
Percentage-only rows have no panel badge; their source limitation is explained
once in the provider tooltip, and missing resets remain explicitly unavailable.

Privacy retains at most six bounded semantic pace parts and drops prose fallbacks
and unknown fields. QML relocalizes the parts and advances forecasts from each
row's original receipt time. Numeric reset dates become ISO text; string reset
validation is shared with `SubscriptionDates.mjs` on live/cache save/restore paths.
Malformed dates must not discard healthy percentages.

`QuotaThresholds.js` supplies shared notification/bar thresholds;
`limitResetArmThreshold` is a separate reset detector. The opaque planner memo
preserves provider incident baselines when settings change or usage refreshes.
Unknown status is missing evidence, including a returned status object: it neither
notifies nor primes, while fresh quotas still run independently.

Initial authoritative windows require finite measured usage or a known forecast
to establish an account scope silently. Empty or entirely nonauthoritative
observations cannot prime it. Missing rows retain thresholds; only observed
authoritative recovery/escalation can change them. Nonauthoritative observations
preserve announced quota severity and same-window pace warnings but disarm reset
notifications. Stale usage never rebuilds baselines.

Pace memo uses stable row identity and the last validated reset instant. Missing
reset metadata cannot split a warning or hide measured recovery. Only a distinct
known reset instant starts a new window; untrusted rows cannot alter it.
Predictive notifications fire on a new projected-exhaustion transition, after a
silent baseline. Keep quota, pace and reset recovery rules distinct.

### Panel, popup and session identity

`PanelDisplay` shares quota/capability selection across text, meters and tabs.
Automatic meters use primary then secondary; either displayed quota can satisfy
a visibility rule. Missing explicit quotas stay omitted. Run-out requires an
authoritative quota and a CLI forecast. Presentation settings must not fetch data,
change notification state or break the minute clock/icon fallback.

`PanelProviders.js` filters only panel meters, text and tooltip roster. Empty
stored text means automatic/all enabled, `__none__` means none, and unknown saved
IDs stay saved. Manual selections display at most four enabled providers in roster
order; absent IDs consume no slots. An empty manual roster suppresses panel text;
automatic mode retains its loading/no-data fallback. `OverviewProviders.js` shares
canonical selection transitions through `ProviderOrder.toggledSelection`.
Automatic mode shows the first three eligible providers. Manual mode filters
the bounded roster by the saved selection and keeps roster order.

Overview excludes error-only snapshots, retaining any usable quota, credit,
subscription date, cost, detail, dashboard or placeholder. Empty detail-chart
containers need a title, unit, row or valid point to qualify. QML localizes the
result; the selection modules read no root state.

`PanelTextFit.js` offers whole-content reductions from explicit localized
segments. QML measures candidates independently, chooses the widest that fits,
and preserves the complete composition for tooltips/accessibility. Drop the
optional quota name, then provider name and credits before the usage figure or
compact pace verdict. When the icon is generic, identification outlives credits.

Rings and capsules share selected rows, direction, severity and contrast policy.
`PanelRingGeometry.js` bounds geometry; `PanelQuotaRings.qml` draws it, while
`CompactRepresentation.qml` owns interaction. `panelMeterShape` remains independent
of `panelStyle`, defaults to `capsules`, and resets with General defaults. Ring
neutral/warning tracks target 5.5:1 source contrast for at least 3:1 antialiased
hairlines. Permanently reserved confidence-marker space prevents overlap and
refresh resizing. Icon-only feedback follows the ring cell; the complete provider
group, including the marker, remains clickable. Inline text expands feedback to
the group without exceeding its bounds.

`PopupTabStrip` owns scrolling, overflow and focus traversal without an applet
reference; `FullRepresentation` retains selection effects. A tab press interrupts
page scrolling and keeps its hit area fixed through the visual press scale.
Pressed feedback follows the visible part of the tab. Clicks acquire mouse focus
after release inside the viewport so focus-driven scrolling cannot move a
partially visible target during the press. `ProviderUsageRow`
renders explicit normalized inputs and emits hide requests, while the popup
binds clock/theme/settings and routes them. Sessions intentionally discard paths,
IDs and PIDs: same-sized rescans rebind positional cards, preserving focus/hover
at each index; count changes recreate cards. Share the active-state predicate
between count and cards. Session state text targets 4.5:1 against its composited
background; other accent callers keep 3:1.

### Hidden content, privacy and settings

`PopupHiddenRows.js` persists only validated provider IDs and row keys (`primary`,
`secondary`, `tertiary`, `extra:<window ID>`), never provider prose. Filtering is
popup-only; panel, Overview, notifications and fetching use unfiltered rows.
Privacy/cache retain identifier-shaped `windowId`. A full 64-entry list refuses
new entries instead of evicting old choices. Both hidden-preference readers accept
at most 65,536 UTF-16 JSON code units, including escaped surrogate IDs.

`PopupHiddenSections.js` persists provider IDs and versioned MD5 title digests,
not CLI prose. This is display identity, not encryption. Equal titles group;
reordering/value changes keep identity, renaming resets it, and untitled sections
cannot hide. Official Linux CLI 0.67.0 emitted titled groups without IDs in a
2026-09-27 loopback Bifrost probe, extending
[0.65.0 evidence](research/2026-09-23-macos-parity-0.65.0.md).
Privacy removes titles before restoration UI. Popup restores current groups;
settings can clear absent saved groups. General defaults clear preferences.

Privacy projects presentation without mutating cached snapshots or account command
keys. The compact renderer projects its selected provider before using display
fields, including accessible names; navigation still uses the canonical provider ID.
Preserve config keys and pending defaults. General synchronizes history days
and calendar mode as one pending range; an external update releases that edit only
when both fields match. Metric synchronization stays independent in
`ConfigValueSync.js`. `PopupRefreshPolicy.js` handles freshness, failed-attempt
cooldown and queued/in-flight work; opening the popup cannot start cost scans.
See the [settings decision](research/2026-09-08-settings-experience.md).

`SubscriptionDates.mjs` admits only official renewal/expiration fields and true
date-only flags, rejecting impossible calendar components before parsing.
`TimeLabels` formats full regional dates/clocks; date-only values keep their
serialized calendar day. Privacy, stale retention and disk cache omit subscription
enrichment. Validate `credits.codexCreditLimit` independently as finite nonnegative
amounts, clamped percentages and bounded reset metadata. Its denominator never
applies to a plain credit balance.

Diagnostics collection remains offline: `collect-support-report.py` may run only
`--version` and `config providers --format json --json-only` (verified on official
Linux CLI 0.67.0/0.73.0/0.83.0/0.84.0), projecting only enabled provider IDs. The roster
probe has a 256 KiB stdout limit to accommodate the
[authentication metadata added in 0.83.0](research/2026-11-01-macos-parity-0.83.0.md#linux-cli-contract-changes).
An oversized enabled-ID list is unavailable. If long escaped paths make the
JSON report too large, omit the paths and preserve the remaining facts.
The report excludes raw config, account lists, provider fetches, `diagnose`,
hostname/hardware fields and network requests. `SupportReport.js` accepts explicit
facts; QML owns probes, clipboard and localized feedback. Local version facts may retain paths;
the shared report retains only the selected/PATH location comparison.

Shared diagnostics omit whole lines with path separators, including relative,
tilde, drive and UNC forms and JSON-encoded paths. Decode bounded JSON values and
keys to distinguish message escapes from paths; more than 512 inspected values
redacts the line. Previously credential-redacted lines are omitted too, since
filtering may have consumed a separator. Startup failures expose fixed reasons
instead of paths/library names. `SafeText.mjs` also redacts secret/access-key
assignments, including environment/SDK and multiply encoded quoted keys;
escaped quoted values redact the remainder rather than guessing their end.

## QML conventions

Follow [Design](../DESIGN.md) for visual roles, interaction and accessibility;
[Usage](usage.md) describes supported behavior.

- Keep the standard `metadata.json`, `contents/ui`, `contents/config/main.xml`
  and `contents/config/config.qml` package layout. Use Plasma controls in the
  panel/popup and Kirigami/Qt Quick Controls in settings. `ContainmentItem` belongs
  to containment/panel/desktop code; the Plasma 6 applet root stays `PlasmoidItem`.
  Preserve persisted config keys and keep user-facing text in `i18n`/`i18np`.
- Give children dimensions through layouts, anchors, implicit sizes or compact
  dimensions. Use `Kirigami.Units` and layout hints rather than panel-size magic
  numbers. Keep hints independent of computed layout geometry. A plain `Item`
  can size children from sibling widths, but its implicit size must not depend
  on its assigned width. See [Qt size constraints](https://doc.qt.io/qt-6/qtquicklayouts-overview.html#size-constraints).
- Set fill-width settings checkboxes' `implicitWidth: 0`: Breeze's wrapped-label
  width otherwise feeds back into mirrored layouts. Set an explicit
  `TabButton.baselineOffset` where baseline alignment is unused, since older KDE
  styles derive it from an absent content item.
- Keep editable spinboxes numeric with units in the form label. KDE commits each
  keystroke, so suffix formatting can rewrite the editor and lose later digits.
  Preserve locale-digit parsing and invalid-input fallback. Use checkboxes for
  booleans, spinboxes/sliders for numbers, text fields for short strings, and a
  combobox for more than three choices.
- Give settings editors/selectors an `Accessible.name` tied to the form label;
  `Kirigami.FormData.label` alone is insufficient. Append `displayText` for
  non-editable combos, which expose no accessible value.
- Prefer bindings and stable delegates. Keep expensive JavaScript out of hot
  delegates, timers and callbacks; profile before optimizing. Introduce clipping,
  shaders or nested layouts only for a demonstrated visual need.
- External Repeater/view delegates declare `required property var modelData`
  themselves. Parent aliases do not establish scope and `qmllint` may miss it.
- Pure names such as `build*`, `format*`, `provider*Url`, `*Rows` and `*Text`
  must stay pure. Effectful helpers may use `refresh*`, `load*`, `parse*`,
  `select*`, `set*` and `process*`. Name lifecycle state explicitly and update it
  beside its effect. Extract helpers/components to hide real complexity; comments
  explain contracts or workarounds rather than assignments.
- Use Qt 6 `qmlformat` only for new files or dedicated formatting work. Check
  `--version`: distributions may put Qt 5 first. Existing files have no formatter
  baseline, and [Testing](testing.md#regression-checks) records current limitations.
  `qmlls` is useful in editors; machine-specific `.qmlls.ini` stays untracked and
  editor diagnostics do not replace checks.

`TimeLabels.qml` owns displayed clock times and short dates. Regional names and
hour cycle combine with catalog-defined ordering; literal `Qt.formatDateTime`
patterns would force English names. `UsageWindowText.qml` localizes explicit
reset/pace parts with a supplied clock and no timer, state write or dispatch.
See [Translations](translations.md) for catalog coverage and adapter checks.

When changing provider identity, compare IDs, CLI aliases, title, color,
docs/dashboard/login URLs, icons and the icon checks. Register packaged icon
filenames in `ProviderIdentity.mjs`; unknown providers return no filename so QML
uses a theme fallback. A nonexistent local URL does not trigger that fallback.
The catalog is fallback presentation, never an assumed current upstream count;
use the [pinned audit](research/2026-09-01-macos-parity-0.56.2.md) and later reviews.
