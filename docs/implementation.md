# Implementation reference

Read the relevant ownership, behavior, and QML sections before changing the applet.
Paths are relative to the repository root. Applet QML and JavaScript references
may omit `contents/ui/`; for example, `components/FullRepresentation.qml` means
`contents/ui/components/FullRepresentation.qml`. [Development](development.md)
owns checkout setup, delivery, and repository maintenance.

## Ownership and implementation

- Plasma's executable engine shares source names across DataSources. For each
  one-shot request, its QML owner supplies both the local serial and a fresh
  request nonce from the timestamp and `Math.random()` to
  `CommandLedger.withRunNonce`. The pure module quotes the
  nonce as a separate environment assignment; it never generates identities.
  Keep the serial numeric for existing CLI fixtures. Local serials alone
  collide across controllers and recreated settings pages, allowing one request
  to reuse another's process or cached result. `test_command_source_isolation.py`
  runs paired widget/CLI updaters, usage/cost/session refreshes and settings
  roster controllers through the real Plasma executable engine. A file-locked
  synthetic helper gives each actual execution a different result.
  The continuous provider-configuration watcher deliberately shares its polling
  source and does not use a one-shot nonce.
- `contents/ui/main.qml` owns provider notification policy and routing,
  account coordination, selected state, quota-cache persistence, configuration updates, and external
  effects. Its adapters supply the panel and popup. `UsageState.js` plans live
  commits, failures, restore, invalidation and expiry from explicit snapshots,
  cache context and time. Its publication result distinguishes no cache write
  (`null`) from clearing the cache (`""`), and gives semantic update-label and
  clock/notification decisions. `applyUsageTransition` is the single persisted
  usage-cache writer; it clears notification suppression before publishing fresh
  data and keeps localization and configuration effects in QML.
  An accepted empty provider list clears disk quotas even without a cache
  context, preventing the first checksum callback from restoring removed
  providers. A failed early refresh leaves the unverified disk cache intact.
  `ProviderViewModel.js` projects normalized snapshots and explicit localized
  decorations into the shared popup/account model. It bounds display metadata,
  converts Qt sequences to arrays and preserves receipt time without copying
  unknown fields. `main.qml` still localizes rows, costs, labels and provider URLs.
  Direct `tst_usage_state.qml` and `tst_provider_view_model.qml` cover these
  boundaries; existing metadata/reset fixtures exercise the production adapters.
- `contents/ui/PanelDisplay.js` constructs compact quota candidates from explicit
  normalized rows, canonical provider identity, optional provider cost and a
  QML-localized included-plan label. It preserves provider preference order and
  row identity while constructing a fresh Cursor fallback. Capability and lane
  selection remain shared by panel text, meters and popup tabs. Direct QtTests
  cover ordering, duplicate references, missing lanes, exhausted quotas, cost
  fallback coercion and input immutability; executed root fixtures cover aliases
  and the localized label adapter. Configuration and effects stay in QML.
- `contents/ui/controllers/IdentifiedTokensController.qml` owns the opt-in
  identified Codex scan, its manual local/SSH action, nonce, 120-second deadline
  and disconnect lifecycle. Its independent GNU process-group timeout sends
  TERM at 110 seconds and KILL after a 5-second grace; a waiting shell preserves
  this bound after source disconnection. It has no startup or refresh timer.
  Settings changes
  retire outstanding requests and clear transient results. `IdentifiedTokens.js`
  validates the captured UTC window, bounded ledger/envelope and exit status,
  then returns aggregate counts and optional CLI API-price estimates without
  request IDs, model metadata, hosts or raw errors. It accepts schemas 1 and 2,
  reports schema incompatibility separately, and leaves pricing to the CLI.
  `IdentifiedTokensSection.qml` localizes the scope and independent availability
  and partial-request notices. Generic costs and sharing remain separate.
  Direct `tst_identified_tokens.qml` and `tst_identified_tokens_section.qml`, process tests in
  `test_identified_tokens_context.py`, paired source-isolation tests and the
  `identified-*` smoke scenarios cover this path with synthetic data, including
  schema 2 estimates, unpriced requests and schema mismatch guidance. The section
  tests exercise pointer/keyboard disclosure, exact snapshot dates, visible
  source/partial warnings, inherited LTR/RTL load-action order and focus retention
  when a new result closes details. The QML runner repeats the section tests with
  an RTL application to catch double mirroring of the load actions.
- `UsageDetails.js` bounds detail sections and preserves only the CLI row
  severities `normal`, `warning`, and `critical`. Charts without a usable title,
  unit, or point are omitted so an empty detail section cannot suppress the
  legacy dashboard or no-usage placeholder. `ProviderDetailSection.qml`
  localizes warning/critical descriptions and paints compact Canvas symbols
  with theme-contrast accents and transparent cutouts. Painting the accent
  directly works with software and OpenGL rendering. It supplies readable
  value colors and meter colors without deriving severity from progress.
  `tst_usage_details.qml`, the detail cases in `tst_visual_layout.qml`, and
  `detail-severity` smoke coverage exercise normalization, accessible descriptions,
  narrow layouts, rendered accent pixels/cutouts, theme contrast and privacy
  toggling. Snapshot/view-model, privacy and quota-cache tests keep details out
  of private and retained views.
- `contents/ui/components/CostText.qml` localizes normalized token-cost snapshots,
  history labels, qualified cost values, count plurals, spend totals and legacy
  dashboard rows. It receives regional number formatting explicitly and takes
  already selected costs for totals. `CostPresentation.js` builds bounded rows
  and range-matched aggregates. `CostAmounts.js` owns locale-explicit formatting,
  missing-versus-zero arithmetic, averages and current-day amounts.
  `CostCurrency.js` selects the monetary currency and excludes foreign amounts
  without dropping currency-free tokens. `CostTrust.js` folds pricing confidence
  and returns bounded semantic notice transitions. `CostChart.js` owns geometry,
  point memoization, date-preserving selection and calendar heatmap slots; its
  drawing method receives a canvas, explicit bounds and a corner radius.
  These modules take explicit inputs and contain no localization or process
  effects. The applet retains range selection, privacy projection,
  provider attachment, trust-notice state, configuration and refresh effects.
  `ProviderNormalizer.normalizeCostDaily` selects and gap-fills amount rows
  before projecting models for retained days. `CostResponse` requests
  `includeModels: false` for averages, preserving the same calendar rules.
  Raw records stay in a bounded call-local map; model-label memoization is
  keyed by exact raw model identity and discarded after each normalization.
  Only validated labels are memoized, never amounts or counts. Each populated
  model summary validates its shared currency once when projecting its rows;
  no currency value is retained across summaries or normalization calls.
  Root adapters preserve the existing popup and chart interfaces. Executed
  tests in `tests/tst_cost_text.qml` cover snapshot immutability, period-label
  precedence, totals, qualifiers, count plurals, dashboard bounds and regional
  format changes. Catalog and integration fixtures exercise the production
  component through its root adapters, including all six shipped languages.
  `LegacyUsageDashboard.js` normalizes compatibility dashboard rows before
  localization. A custom period label replaces its semantic label key only
  after bounding and validation leave displayable text; otherwise the existing
  translated label remains available. Direct dashboard QtTests and the
  UsageResponse-to-CostText tests cover malformed labels without losing amounts.
  The direct `tst_cost_presentation.qml` suite exercises each pure module through
  the same interfaces used by production callers. It covers finite drawing
  coordinates and clamped corners, overflow, sparse dates, currency precedence,
  confidence and bounded dismissal scopes. Pure behavior belongs there;
  `test_ui_cost.py` checks QML routing and effect ownership rather than the
  internal arrangement of helpers.
- `contents/ui/NotificationObservations.js` projects normalized providers into
  planner observations with `build(providers, selectedAccounts, refreshPending,
  thresholds)` and returns a copied pending map with
  `freshPending(items, selectedAccounts, refreshPending)`. It owns account scopes,
  alias normalization, freshness and quota/pace eligibility; it does not mutate
  snapshots, localize or dispatch. `main.qml` supplies configured thresholds and
  commits the pending map before publishing fresh providers. Direct QtTests in
  `tests/tst_notification_observations.qml` exercise this interface with the real
  planner, including account switches, stale quotas and fresh status. Keep
  composition-root effect ordering and routing in `test_notification_wiring.py`;
  observation tests must not reconstruct root functions from source.
- `contents/ui/NotificationPlanner.js` composes provider status and account-scoped
  usage transitions through `transition(observations, previousMemo, options)`.
  Per-row quota, pace and reset decisions preserve their distinct recovery rules;
  observation processing keeps pending refreshes, stale usage and usage errors
  without rows from rebuilding baselines. An initial authoritative window needs
  a finite measured percentage or a known forecast to prime its account scope;
  an empty window cannot make the first measurement look like a threshold crossing.
  Intents retain the original
  observation/row indexes and status, quota, pace, reset ordering. Bounded memo
  selection protects current keys before retaining recent stale scopes,
  preserving source insertion order.
  Pace memo entries use stable row identities and retain the last validated
  reset instant as their value. Missing reset metadata cannot split an ongoing
  warning or hide a measured recovery; only distinct known reset instants start
  a new window. Untrusted rows cannot update that identity.
  Direct `tst_notification_planner.qml` tests these contracts, input immutability
  and notification toggles. Localization and dispatch remain in QML.
- `contents/ui/components/ProviderNotificationText.qml` builds localized status,
  quota, predictive pace and reset messages from a planner intent, normalized
  provider/row and preformatted reset/ETA labels. It returns title/body/urgency
  without reading applet state or dispatching. `main.qml` resolves observation
  indexes, supplies labels and sends the result through the shared privacy owner.
  Planner transitions, account freshness and memo commit ordering stay in their
  existing owners. Direct QtTests and the executed notification pipeline cover
  text, severity, missing rows and effect ordering; catalog tests exercise all
  six shipped languages. The usage-retention smoke checks the localized retained
  label in the panel tooltip, so it also runs with `--language it`.
- `contents/ui/controllers/NotificationDispatcher.qml` owns notification
  execution, per-send nonces, the request ledger, the 10-second deadline, the
  2-minute deadline for clickable notifications, and
  disconnection on completion, timeout, or destruction. Its `send(title, body,
  urgency, actionLabel)` method accepts already localized and privacy-filtered
  text plus an optional default-action label, returns the started source name,
  and emits `activated(sourceName)` only after that reply retired its ledger
  entry; read-only `sending` reports whether requests remain pending. Failed
  commands finish silently, and missing `notify-send` remains a quiet no-op.
  The shared `Guards.boundedShellCommand` process-group bound sends TERM two
  seconds after the UI deadline, then escalates after a one-second grace.
  Its monitored shell stays alive after TERM so a direct child exiting cannot
  cancel the kill escalation for surviving descendants. CLI owners using the
  same process-group guard keep this guarantee too. That shell catches PIPE
  so diagnostics written after engine disconnection cannot end it early;
  executed children retain their normal signal handlers.
  Disconnection and widget destruction leave the process bound intact; GNU
  timeout is optional, as for CLI commands.
  `NotificationCommand.js` bounds notification text, escapes the body's markup
  (`&`, `<`, `>`) so CLI text stays literal while the summary stays plain text,
  builds the quoted command,
  restricts urgency to the supported values, and probes `notify-send --help`
  for action support so older libnotify builds keep the plain send.
  `UpdateNotificationsController.qml` supplies privacy-filtered text to this
  single dispatcher for both provider and update notifications. The applet
  retains provider policy and account freshness and opens requested release
  pages; it owns no executable notification DataSource or command ledger.
- `contents/ui/controllers/UpdateNotificationsController.qml` owns widget/CLI
  notification switches, localization, persisted version deduplication and the
  pending release actions. It receives the configuration object, global enable
  flag and privacy mode explicitly. Widget versions are saved before sending;
  CLI versions are saved only after a safe source starts, preserving retry
  behavior. Its `send()` method also applies privacy to provider notifications.
  `UpdateNotificationState.js` validates release URLs, chooses the widget memo
  key and copies/registers/consumes source-specific actions without effects.
  Activations retire their action before emitting `releasePageRequested(url)`;
  the applet opens that URL. Update process lifecycles remain independent.
- `contents/ui/controllers/CliUpdateController.qml` owns the read-only CLI
  version/release process, nonce, deadline, stale-reply retirement and optional
  daily scheduling. General runs manual release checks and a separate local-only
  probe on opening/command changes for managed-install confirmation; Diagnostics uses its
  local-only mode; `main.qml` persists background check timestamps, while
  `UpdateNotificationsController.qml` persists notification deduplication and
  skips announcements for a managed copy while its automatic updates are on.
  Both this controller and `ManagedCliController.qml` validate process results
  with `Guards.exitCode`: only numeric zero or an integer-string zero accepts
  stdout. Null, booleans, blank strings, arrays, and missing codes fail without
  emitting successful-check, installation-selection, or change signals.
  `CliUpdate.js` bounds results and constructs host-pinned release links. `scripts/check-cli-update.py` probes `--version` and positive package
  ownership, then optionally reads the official GitHub latest-release metadata.
  This read-only entry point never installs or changes the CLI. Shared probes and
  release validation live in `scripts/lib/cli_release.py`. Its subprocesses have output/deadline
  bounds, and the QML command has an outer GNU timeout. Tests cover numeric
  version comparison, unsupported banners, package provenance, network failure,
  process retirement, manual checks, one-hour retries after a failed retargeted
  check despite a recent prior timestamp, and the offline Diagnostics boundary.
- `contents/ui/controllers/ManagedCliController.qml` owns private CLI installation
  processes, per-request nonces, deadlines, stale-result retirement and optional
  background scheduling. General owns the explicit installation/selection action;
  only Apply saves its command path. `ManagedCli.js` validates results and quotes
  allowlisted operations. General waits for the independent offline CLI probe
  before offering a first install, clears confirmation on command changes, and
  does not require a GitHub check. Only a confirmed missing command or an identified
  local CLI enables first installation; failed probes show an offline Retry action.
  `test_managed_cli_install_confirmation.py`
  exercises these page interactions with real synthetic CLI version banners.
  Selecting a prepared managed copy also runs the helper's `install` action,
  which verifies existing copies offline before emitting `installed(path)`.
  The page must not select a path from the metadata-only `status` response.
  The same tests exercise the real helper with healthy, non-executable,
  corrupt, and version-mismatched prepared copies, without network access.
  Restoring defaults explicitly retires the request, including when the command
  is already the default and its change handler would not run; a delayed-helper
  test checks that the reset selection survives completion.
  `scripts/manage-cli.py` calls `scripts/lib/managed_cli.py`
  for per-user locking, daily throttling, bounded official asset downloads, strict
  archive extraction, isolated-environment version probes, atomic activation and
  rollback. Only the exact managed command is eligible for update/rollback.
  `run` keeps the shared lock around cleanup, install and
  rollback; offline reuse still bypasses that lock and all release requests.
  Rollback requires the stable `--expected-previous` version shown by General.
  The helper compares it with the previous receipt only after acquiring the
  installation lock and before probing, pruning or activating anything. A missing,
  invalid or changed target returns `stale` with current installation metadata;
  the active copy and state stay unchanged. General passes the displayed target
  through `ManagedCli.command`; other actions never receive that argument.
  The previous receipt already guarantees a stable version, so exact equality
  also rejects malformed targets. Successful rollback owns its post-activation
  cleanup inside the same lock; stale requests never prune releases.
  The applet increments runtime-owned `managedCliRevision` after a successful
  installation change. General observes it and requests a fresh offline status;
  the controller coalesces requests made while another action is running and
  executes them after that action retires. Settings must not declare or save a
  `cfg_managedCliRevision` property. Direct helper/QtTests and the General smoke
  scenario cover stale targets, lock acquisition ordering and deferred refresh.
  `tests/test_managed_cli_rollback.py` owns rollback verification and target-race
  regressions; it shares isolated installations and synthetic release archives
  with `test_managed_cli.py` through `managed_cli_test_support.py`.
  Offline status replies update installation facts while preserving an earlier
  stale-rollback notice; a subsequent install/update/rollback result replaces it.
  Receipt identity, asset selection and checksum/VERSION text validation are
  separate checks inside the helper; installation and recovery retain their
  existing lock and filesystem ownership.
  Managed CLI tests cover recovery on both sides of the atomic switch, archive
  name and member-count limits, VERSION size rejection and resource permissions,
  and cleanup failures during install, update and rollback.
  Rollback runs the same bounded, isolated version probe used for offline reuse
  against the previous copy before writing activation state or switching the
  symlink. A failed probe returns `no_previous` without changing either; the
  managed CLI tests cover damaged executables, version mismatches and timeout.
  Resolve the base data directory before appending the private CLI root: staging
  and returned command paths must agree even when `XDG_DATA_HOME` combines a
  symbolic link with `..`. Keep the root's own symlink and ownership checks.
  Replacing a retained release keeps its backup outside temporary staging until
  the verified replacement is in place. A failed move restores that backup;
  a failed restore leaves `.retained-*` inside the private CLI root for manual
  recovery. `test_managed_cli.py` injects both failure cases and verifies the
  rollback copy survives staging cleanup.
  `failure_status` maps a raised failure onto the bounded status the widget
  renders, so a refused download (`unverified`) stays distinct from an
  unreachable server (`network`) and an unsupported system (`unsupported`).
  Timeouts, dropped connections and bodies shorter than the published size are
  `network`: urllib wraps only connection setup in `URLError`.
  Add new helper failure codes to `UNVERIFIED` or `UNSUPPORTED`; anything
  unlisted degrades to the generic `error`.
  Parsed attempt timestamps that are not finite numbers, including integers too
  large for floating-point conversion, raise `state_time` before mutation.
  Decoder failures also return the helper's bounded generic JSON error. The managed
  CLI tests exercise every helper action and its JSON error response while
  checking that the state file and active release remain unchanged.
  Tests use temporary XDG directories and synthetic archives, never host binaries
  or provider configuration. The helper's 600-second alarm and QML's outer GNU
  timeout bound downloads, including decompression. Inactive releases other than
  the previous one have a one-hour grace period before cleanup. A completed
  rollback blocks that release from automatic reinstall. Changing the selection retires UI replies; an already
  started install can still finish in the private directory.
- `contents/ui/controllers/AiInsightsController.qml` owns the optional AI
  Insights generation process: one request at a time, per-request nonce, the
  185-second deadline, retry delays, interval scheduling, and retirement on a
  context change, disable, or destruction. It runs nothing while disabled and
  emits `attemptStarted`/`generated`/`rateLimitStored`; `main.qml` persists the
  attempt time, rate-limit deadline, and cached insight and builds the snapshot
  only while enabled. `AiInsights.js` owns the language tag, context key, cache
  validation, schedule, retry delays, rate-limit record, model-list match,
  helper command, and reply validation; `AiInsightsSnapshot.js` builds
  the allowlisted snapshot and deterministic signals. `scripts/ai-insights.py`
  prepares a private one-use INI file for the controller's `QtCore.Settings`
  write; `scripts/lib/ai_insights_input.py` validates and removes it before
  generation, so process arguments carry only a random request ID. The
  controller captures the snapshot before preparation, retires both phases on
  context changes, and requests cleanup on cancellation. The helper prunes
  expired crash leftovers during a later preparation. The entry point
  calls `scripts/lib/ai_insights.py`, which alone reads Secret Service keys,
  prompts for them with `kdialog`, and performs the HTTPS or local Ollama
  request. `configAiInsights.qml` owns the key-status, key, and model-discovery
  processes; `components/AiInsightsMessages.qml` localizes helper reasons for
  both surfaces. Both process owners read exit results through
  `AiInsights.processResult`, which uses `Guards.exitCode`: null, booleans,
  blank strings, arrays, and missing fields never count as a successful exit.
  See the [AI Insights reference](ai-insights.md) for the
  boundary decision and contracts; keep it current with any change.
  `components/FullRepresentation.qml` owns navigation from the compact
  `AiInsightsCard.qml` to `AiInsightsView.qml` and restores the origin's scroll
  position and keyboard focus on return. The detail view reuses the card's
  saved-answer presentation; opening it never starts a process or a cost scan.
- `contents/ui/main.qml` owns the Status Page component list: its expanded
  provider, the single `CliProcess` request, and the 30-second deadline.
  Collapsing, closing the popup, switching tab or view (including opening
  AI Insights), or expanding another provider cancels the
  request and refetches on the next expansion, and a late
  result for a provider that is no longer expanded is ignored. The official CLI
  emits only overall status, so `scripts/status-components.py` is a deliberate
  exception to CLI ownership: it reads one fixed public feed for Claude,
  OpenAI or xAI without credentials and prints bounded names and indicator values,
  never other remote text or errors. It prefers installed `curl` for
  [Happy Eyeballs connection fallback](https://curl.se/docs/manpage.html#--happy-eyeballs-timeout-ms),
  avoiding serial timeouts on unreachable IPv6 addresses. The request disables
  curl configuration, requires verified HTTPS and HTTP 200 without redirects,
  and sets 5-second connection and 10-second transfer limits. Python separately
  caps the body at 1 MiB and kills the child at a 12-second deadline, including
  when an older curl cannot enforce a streaming size limit. The existing
  bounded, non-redirecting urllib path remains available without curl; the
  outer process deadline and cancellation still cover either transport.
  `tests/test_status_fetch.py` uses synthetic subprocesses to cover success,
  HTTP failures, oversized bodies, stalled transfers, and the urllib fallback
  without network access. `StatusComponents.js` maps providers to
  feeds, builds the command, and validates the record;
  `components/StatusComponentsList.qml` localizes states. Widget QML still
  sends no HTTP itself. Expansion stays out of the action-row model so a
  state change never rebuilds the focused row, and open group names live in
  `statusComponentGroups` so a usage refresh that rebuilds the rows restores
  them. Component states use the page's scale (degraded, partial, major) and a
  separate translation context from the provider status pill. `tests/tst_status_components.qml`
  and `tests/test_status_components.py` cover validation and all three feed formats
  offline, including malformed OpenAI group collections through the helper's
  JSON output. Such groups stay unknown without discarding healthy siblings.
  A malformed affected-component collection preserves the service tree with
  unknown states; absent, null, or empty collections retain the operational fallback.
  Grok and xAI use `https://data.x.ai/status/summary.json`, linked by
  [xAI's status page](https://status.x.ai/), verified on 2026-11-12.
  Its flat `components` contain `id`, `name`, and `status`. The page's published
  JavaScript schema accepts `available`, `info`, `disruption`, `outage`, and
  `no_data`; its labels identify disruption as Degraded and info as Info.
  The helper maps these to `none`, `info`, `minor`, `critical`, and `unknown`.
  Unknown states or unusable IDs remain unknown; malformed entries do not erase
  valid siblings. The component-only `info` indicator has a localized Information
  label and a theme-neutral dot, without affecting provider incident severity.
  The feed was observed with available components; other states are covered by
  synthetic fixtures based on that page schema, not a live outage observation.
  `tests/tst_status_components_list.qml` covers long-name elision and
  keyboard toggling. `tests/test_usage_recovery.py` executes the popup navigation
  and status handlers together, covering cancellation on entering AI Insights,
  ignored late results, and a fresh fetch after returning. Replace the helper
  when the CLI exposes components; see
  [TODO](../TODO.md#status-components).
- `contents/ui/controllers/WidgetUpdateController.qml` owns the widget updater's
  executable source, per-request nonce, captured install mode, timeout, queued
  install request, and retry/interval timers. It receives update settings, the
  last successful check timestamp, and `initialAvailableVersion`, which restores
  a persisted release so a failed install stays retryable after a restart.
  `checkNow()` is the forced automatic entry point and still respects disabled
  checks; `runNow(install)` is the manual one and deliberately ignores both
  check and auto-install settings, so a user can update on demand while
  automatic checks are off. Startup checks respect the saved successful-check
  timestamp and configured interval; first use and overdue checks run immediately.
  Manual checks still bypass the interval while coalescing active requests.
  The applet services the settings page's `widgetUpdateRequest` runtime key
  through `runNow()` from a deferred change handler, because servicing rewrites
  the key its own binding reads; a synchronous write is dropped as a binding
  loop. It marks an accepted request `running:<mode>`, and clears it
  when the controller's `busy` drops through `onBusyChanged`, because the
  controller settles `busy` inside its own completion handling. That deferred
  clear is the only path that releases a finished run's marker, and the settings
  page binds both update buttons to that key being empty.
  `main.qml` persists its status and successful-check
  signals and forwards available/installed events to
  `UpdateNotificationsController.qml`, preserving the existing privacy and
  notification-deduplication rules. The available-update
  notification carries a host-pinned release-page URL derived from the
  updater's validated tag; the notification controller stores the pending source
  and asks `main.qml` to open that URL after activation. The updater never reads
  the applet root or writes configuration. `UpdateLogic.js` keeps the pure
  scheduling and result decisions shared with settings.
  Success intents also require a zero process exit code before changing the
  available version, recording a successful check or emitting notifications.
  Structured updater errors remain readable when the process exits nonzero.
- `contents/ui/controllers/SessionsController.qml` owns Sessions command construction,
  refresh scheduling, snapshots, and attempt/success timestamps. Its
  `CliProcess` child owns executable requests and deadlines. Its inputs are the
  CLI path, refresh interval, and whether the
  Sessions tab is open; `SessionRefreshPolicy.staleAfterMs` caps the visible
  rescan cadence at 30 seconds, matching the macOS local session monitor. `refresh()` requests a manual scan; read-only outputs
  expose normalized sessions, loading, error text, and the last successful
  timestamp. Hiding the tab stops automatic scheduling while an already running
  scan may finish. A command change retires the previous request and clears its
  snapshot before scheduling work for the new command. `main.qml` supplies the
  inputs and adapts the outputs for the existing view and privacy presentation.
  `SessionRefreshPolicy.js` owns pure scheduling decisions; `SessionResponse.js`
  bounds and classifies CLI output through the existing session normalizer.
  The shared response decoder admits session stdout only after a zero exit code;
  failed scans retain the previous successful snapshot and timestamp.
  Normalization inspects only the first 128 records. A nonempty session list
  with no usable records within that bound is a failed scan, not a confirmed
  empty result. Mixed lists retain their readable sessions within that bound.
- `contents/ui/controllers/ProviderConfigWatcher.qml` owns the read-only config
  checksum command, minute polling, connection changes, and retired replies.
  It starts after the applet initializes and emits accepted checksum changes;
  the first observation restores cache in `main.qml`, while later changes
  invalidate usage and schedule a refresh. Repeated or malformed observations
  leave the current state intact. `ProviderConfigWatch.js` preserves the existing
  config-path precedence and checksum text, and accepts only bounded `missing`
  or CRC checksum/byte-count/file records. Filenames may contain whitespace.
  The watcher never reads JSON fields or writes configuration.
- `contents/ui/controllers/UsageController.qml` owns usage commands, provider
  discovery, the cached roster, bounded fallback queue, nonces, deadlines, and
  automatic/popup refresh scheduling. Inputs are CLI settings, selected accounts,
  provider order, configuration revision/checksum, and popup visibility. Changed
  request inputs synchronously retire old work and coalesce a replacement.
  The controller alone schedules startup; `main.qml` does not start a second
  refresh from its completion handler.
  Manual refresh bypasses the roster cache; periodic refresh waits for pending
  usage work. Read-only outputs expose loading, errors, provider display names,
  and refresh timestamps. Signals deliver bounded snapshots, failed refreshes,
  and confirmed empty rosters. `main.qml` presents the snapshots, reconciles and
  persists quotas, and coordinates accounts and notifications. `UsageResponse.js`
  contains bounded response classification and per-record normalization; the
  controller supplies the receipt time and localizes failure outcomes.
  Aggregate provider overrides expand before scheduling scoped commands:
  `both` requests Codex and Claude; `all` discovers every valid roster entry,
  including disabled providers. An empty override retains enabled-only discovery.
  The roster cache is invalidated when the override changes. CLI 0.83.0 was
  checked in a bubblewrap sandbox with host homes/IPC hidden and networking
  disabled: after `config disable --provider codex`, `usage --provider both
  --source web --format json --json-only` still returned Codex and Claude,
  while `--provider all` returned all 111 inventory providers. The runtime
  errors from the unsupported web source establish identities without fetching
  authenticated data. `test_usage_controller.py` covers these scopes, selected
  accounts and cache changes with synthetic process replies;
  `tst_usage_response.qml` checks disabled-entry inclusion without relaxing
  record validation.
  Selected Codex usage uses `--all-accounts`; `UsageResponse.js` reuses the
  account normalizer to match the exact selected key before deduplicating by
  provider. Missing or failed selections cannot use a healthy sibling's quotas.
  Other providers keep `--account`; clearing a selection restores the ordinary
  default-account command. Changed inputs still retire previous requests before
  starting their replacement, even when two Codex selections share a command.
  Its `reachability` input carries `QNetworkInformation` values from
  `controllers/NetworkReachability.qml`, which `main.qml` loads through a
  `Loader` because `NetworkInformation` needs Qt 6.7 while the applet supports
  Plasma 6.0; no other file may import `QtNetwork`. A failed load stays unknown.
  A return from disconnected, local or site (intranet only) to online starts
  one refresh after a two-second settle timer; leaving online first cancels
  it, and a refresh that started after the reconnection makes it a no-op. Offline state does
  not suppress refreshes, because local sources still answer.
  `NetworkState.js` classifies provider messages as offline or timeout from
  Foundation URL error codes and unresolved hosts only, as a tested fallback
  for the missing CLI kind. `main.qml` classifies the raw message before
  privacy filtering and localizes the headline and recovery hint.
  `tests/tst_network_state.qml`, the reconnect case in
  `test_usage_controller.py`, `tests/tst_network_reachability.qml`, and
  `test_usage_recovery.py` cover these boundaries.
- `contents/ui/controllers/AccountsController.qml` owns account discovery's
  executable source, request ledger, nonce, deadlines, per-provider loading and
  errors, and last successful lists. Inputs are the CLI path, source, and status
  setting; `load(providerID)` starts discovery and `reset()` retires requests and
  clears results. Input changes synchronously retire obsolete requests. Failed
  refreshes retain successful lists; a confirmed empty list clears only its
  provider. `availabilityForProvider()` reports the last success as `named`,
  `none` (missing token accounts or an empty list) or `unsupported` (the CLI's
  "does not support token accounts" argument error). Without a selection or a
  newer error, the accounts panel explains the last two through
  `noticeForProvider()`. Each started discovery arms that notice and
  `dismissNotices()`, which `main.qml` calls when the popup closes, clears it,
  so a reply arriving after the popup closed stays silent; `unsupported` disables that provider's menu entry, while
  the panel's reload can retry. `reset()` runs
  on usage identity, CodexBar config and managed CLI changes, and on an empty
  roster; an in-place package upgrade needs a reload or a Plasma restart.
  `main.qml` owns account selection and cache invalidation, localizes
  snapshots, and applies privacy presentation. `AccountResponse.js` bounds and
  classifies replies; `ProviderSnapshot.js` shares pure quota normalization with
  usage refreshes. Cached account quotas and forecasts keep their receipt time
  through presentation, unrelated loads, and later selection.
- `contents/ui/components/PanelText.qml` localizes the panel's optional name,
  usage and credit segments, percent/pace display modes, per-provider tooltip
  lines, and loading/error fallback. It accepts explicit display inputs and settings, without accessing
  the applet or configuration. `PanelText.js` owns the pure segment composition
  and incident/balance projection; `PanelTextFit.js` still owns fitting and
  surrender order. `main.qml` supplies privacy-filtered provider data, selects
  rows, applies visibility rules, limits tooltip roster lines, and narrows the
  tooltip only to a hovered meter that remains rendered. Shared quota selection,
  pace forecasts, reset labels and number formatting stay available to the popup. Direct QtTests in
  `tests/tst_panel_text.qml` exercise the production component and pure plans;
  the existing panel adapter tests also exercise their wiring.
- `contents/ui/components/CompactRepresentation.qml` renders the panel;
  `FullRepresentation.qml` in the same directory renders the popup. Components
  are presentation-only and receive normalized data plus an explicit parent API
  such as `applet` or `configPage`.
- `components/PopupTabStrip.qml` owns the popup tab viewport, overflow controls,
  selected-tab reveal, and keyboard focus traversal. It receives the surface
  radius and caller-declared tab contents, without an applet reference.
  `FullRepresentation.qml` retains provider/global tab rendering and selection
  effects. Tabs pass their focus and selection to the strip through `tabStrip`,
  `ensureVisible`, `claimSelectedTab`, and `navigateFromTab`; `tabHeight` sizes
  their contents. `TabStripGeometry.js` retains the pure geometry decisions.
  Direct `tst_popup_tab_strip.qml` covers keyboard wrapping and activation,
  pointer controls, the mouse wheel, resize, fitting content, and foreign focus.
  The provider-refresh harness uses the production strip, and `tabs-overflow`
  checks the complete popup with synthetic data.
- `components/ProviderUsageRow.qml` renders a normalized row from explicit
  text, percentage, color, marker and sizing inputs. It emits `hideRequested()`
  and has no applet or provider reference. `FullRepresentation.qml` shares one
  `providerUsageDelegate` between quota and monthly-credit repeaters; that owner
  binds current settings, clock-dependent labels and theme-derived colors, and
  routes hide requests to the current provider and row. Layout QtTests exercise
  the view directly; the credit-row harness executes the shared delegate to
  check reactive inputs and hide routing. Forecast tests render the real pace
  label while advancing the applet clock, without extracting its text expression.
- `components/CostLabels.qml` localizes cost-history summaries, breakdowns,
  and model rows from an explicit number format, selected metric, and token-count
  formatter. `ProviderCostSection.qml` supplies these inputs; the module never
  reads the applet. Direct `tst_cost_labels.qml` exercises the production module
  with `CostText`, including reactive formats and input immutability. These
  tests replace the label checks formerly embedded in a copied-root fixture.
- `contents/ui/configProviders.qml` owns provider setup processes, prompts,
  configuration writes, and effects. Its shared dispatcher wraps every command
  in the same independent process-group bound as `CliProcess`, using the
  validated request deadline plus two seconds and a one-second kill grace.
  Existing diagnostic and secret-prompt bounds remain inside that outer bound;
  prompt deadlines still allow the full input window. The executed dispatcher
  test in `test_cli_process_bounds.py` checks a hung CLI and its child both with
  the engine shell alive and after its destruction, without KDE imports.
  Its pure protocol and command-planning
  modules live in `contents/ui/config/`. `ProviderOperations.js` owns immutable
  pending-operation state: provider locks and optimistic enablement, field/action
  locks, diagnostic loading, and deferred reload decisions. Reloads wait for all
  source and credential writes; when released they preserve the current write error through the
  roster refresh. QML supplies ledger activity and localized messages, executes
  the reload intent, and resets this ephemeral state when retiring commands.
  `tst_provider_operations.qml` directly exercises these transitions; the source
  write harness still executes page handlers for timeouts, late results and
  deferred-refresh error retention.
  `ProviderConfigProtocol.response` reads bounded stdout and classifies replies
  from explicit command profiles. Full lists and diagnostics return normalized
  display data; writes return their accepted payload. The `setApiKey` profile
  alone permits legacy empty successful output. The `enabledRoster` profile
  retains the read-only roster's tolerant record projection and failed-exit
  precedence; `ProviderRoster.js` selects enabled identities from those records.
  JSON parsing errors are bounded and redacted before QML localizes them.
  `ProviderAuthentication.js` projects the optional 0.83.0 inventory into bounded
  source modes, writer flags, environment-variable names, redacted account hints
  and the allowlisted Copilot login hint. Missing metadata retains the
  legacy setup behavior; malformed advertised capabilities cannot authorize
  writes and never discard healthy provider records. No credentials or arbitrary
  commands are retained. Hints use the shared conservative credential filter,
  without assuming a minimum bearer-token length; a prose word after a credential
  marker can also be hidden. The curated Linux key setup list remains authoritative
  in addition to the advertised API-key flag.
  Direct QtTests exercise raw stdout, stderr, and exit codes through this shared
  interface; page tests retain effects, pending state, retries, and stale replies.
- `contents/ui/controllers/ProviderRosterController.qml` owns the read-only
  enabled-provider roster for settings pages: one bounded `config providers`
  list command per load with nonce, timeout, and stale-reply retirement.
  `configPopup.qml` loads it on page open; `configPanel.qml` gates it on its
  provider-selection section being expanded and reads the command path and
  provider order at runtime instead of claiming their `cfg_*` keys, so the page
  itself stays process-free. Queued loads recheck activation before starting a
  command, and deactivation clears loading and error state. Command-path changes
  synchronously retire pending requests and clear the previous roster/error,
  even while inactive, before queuing an active reload. `ProviderRoster.js`
  projects the shared provider-list contract into bounded enabled identities
  and semantic errors; QML owns localization and state updates. The DataSource
  forwards the process exit code, so failed commands cannot supply selectable
  providers even with valid JSON. Structured CLI errors and redacted stderr
  remain readable; otherwise QML reports the exit code.
  Malformed stdout from a failed process must not replace its error with a JSON
  parser message.
  `test_provider_roster_exit.py` exercises this boundary with real isolated
  successful and failed CLI processes.
- `ProviderCostPresentation.js` classifies provider costs as balances, points,
  allowances, or spend, and validates reset-credit counts. It preserves the
  established provider exceptions, bounds display metadata, and keeps plain
  balances separate from allowance percentages. `components/ProviderCostDetails.qml`
  localizes those semantic sections, reset-credit counts, and the Codex monthly
  credit-limit row, using an explicit regional number format. Its cost/reset
  inputs pass through the existing pure module; monthly credit limits retain
  the dedicated `ProviderNormalizer.js` contract. The applet keeps snapshot
  coordination and privacy; the popup owns section visibility. Direct component
  tests cover formatting, optional fields and normalized limits, and the production
  component is exercised directly with all six catalogs in
  `tests/test_provider_cost_presentation.py`.
- `ResetPresentation.js` parses bounded reset metadata, splits countdowns into
  semantic units using an explicit clock, and classifies existing reset-label
  compatibility text. `components/UsageWindowText.qml` localizes reset units,
  prefixes, structured pace parts and forecast durations. Its reset method takes
  an explicit clock and its date formatter is the shared `TimeLabels` instance.
  `main.qml` supplies these inputs, applies privacy and advances forecasts from
  each row's observation time. `PacePresentation.etaParts` preserves duration
  rounding in the pure module; QML owns plural selection. No timer, state write
  or dispatch belongs to the text component.
  `components/TimeLabels.qml` owns every displayed clock time
  and short date: it takes names and the hour cycle from the regional format,
  and its catalog strings let a translation order the parts. A literal
  `Qt.formatDateTime` pattern would always write English names. Valid
  timestamps take precedence over descriptions; missing or invalid metadata
  preserves the existing text fallback without discarding healthy quotas.
  String reset timestamps use `SubscriptionDates.date` to reject impossible
  calendar components and missing/invalid timezones before formatting. Numeric
  epoch milliseconds retain their existing compatibility path. `UsageCache`
  applies the same string validation on both save and restore so persistence
  cannot turn an invalid reset into a valid-looking date; percentages survive.
- `SubscriptionDates.js` validates only the official usage renewal/expiration
  fields and true date-only flags, returning at most two semantic dates. It
  rejects impossible calendar values before ISO timestamp parsing. The shared
  `TimeLabels` formats full regional dates and clocks; flagged dates use their
  serialized calendar day without time-zone conversion. `main.qml` supplies
  translated plan labels and the popup renders them separately from quota rows.
  Privacy and stale quota projection remove subscription enrichment; it never
  enters the persisted quota cache. `tst_subscription_dates.qml` covers these
  public normalization, response, account, privacy, retention, and Overview paths.
  `make check-qml-logic` runs it in UTC, Europe/Rome, America/Los_Angeles, and
  Pacific/Apia, including a valid calendar day skipped by the local time zone.
  The `subscription-dates` smoke scenario verifies the real popup,
  privacy toggle, failed refresh, quota-empty snapshot, and cached account path.
- Pure applet modules live in `contents/ui/*.js`; their public interfaces have
  direct tests in `tests/tst_*.qml`. Configuration is declared in
  `contents/config/main.xml` and bound through `cfg_*` in config pages and
  `Plasmoid.configuration` at runtime.
- `UsageCache.js` reconciles failed usage snapshots and projects a bounded quota
  cache. `UsageState.js` composes its retention rules into publication decisions.
  Freshness selection, stale-data projection and persisted-record conversion
  remain separate pure steps behind the same cache interface and schema.
  `main.qml` owns context invalidation effects, configuration reads/writes, and
  stale notification suppression. Its minute timer expires retained measurements
  even when automatic refresh is disabled. Persisted records never bypass
  normalization.

The quota cache adapts the bounded stale reuse and background refresh patterns in
[RFC 5861](https://www.rfc-editor.org/rfc/rfc5861.html); this is a local application
policy, not an HTTP cache implementation. Failed retries preserve the original
measurement time. The 24-hour retention limit applies in memory and on restore.
The context fingerprint isolates CLI/configuration selections; it is not
an integrity check or encryption. Memory-only account selections stay out of the
fingerprint, so `UsageCache.js` omits overridden providers when saving and
restoring instead. Cached JSON remains untrusted and is rebuilt
from allowlisted, bounded fields, following
[OWASP input validation guidance](https://cheatsheetseries.owasp.org/cheatsheets/Input_Validation_Cheat_Sheet.html).
Omitting identities, credentials, paths, and provider prose follows
[OWASP's data minimization guidance](https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html#minimize-the-storage-of-sensitive-information).
Persistence uses Plasma's existing configuration mapping; the restart smoke test
allows its deferred save to complete before starting the second process.
The first configuration-checksum callback also saves any successful usage that
arrived before it, so startup persistence does not depend on a later refresh.
It merges normalized cached providers missing from that early response through
`UsageCache.restore`, preserving live results and marking only restored quotas
as stale. A completed early refresh keeps its update label when no stale quotas
remain.
The restarted fixture delays CLI responses beyond the runner's maximum allowed
scenario duration, proving that the second process displays persisted quotas.
Quota freshness and service-status evidence are independent: retained rows never
reach the notification planner, while a status record from the current response
still can. The observation's `usageStale` flag keeps quota, pace, and reset
baselines unchanged, even when the CLI reports no error. Stale observations do
not prime a new quota scope; its first fresh measurement primes silently.
Retaining or expiring quotas must preserve that current status; a
later response without status marks the retained incident as unknown to the planner.
Incident selection, tooltips, and provider badges/pills also exclude unknown
status instead of presenting a retained outage as current.

Before changing behavior, identify its owning QML page, config entry, CLI input,
external effects, and cheapest behavioral test. Read the existing implementation
and tests. Preserve compatibility and unexpected behavior until evidence or the
request shows it should change.

`controllers/CostController.qml` owns cost command construction, cached
context, and the independent hourly/day-aware refresh policy. Its `CliProcess`
child owns executable requests and deadlines. Source changes
retire obsolete commands synchronously and coalesce settings through
`Qt.callLater`. Only snapshots for the current command context reach `main.qml`,
which supplies them to `CostText` for localization and attaches them to fresh
provider usage. `CostResponse.js`
returns bounded snapshots and semantic failure outcomes without effects or
localization. `tests/test_cost_context.py` exercises the production controller
with isolated CLI processes; `tests/tst_cost_response.qml` covers adversarial
response normalization. Together they cover batched settings, partial failures,
late replies, disabled costs, timeout retention, and forced manual refreshes.

`controllers/CliProcess.qml` owns one active executable request per instance.
`start(command, context, timeoutMs)` supersedes existing work; `cancel()` silently
retires it. Read-only `busy` reflects active work. Completion forwards the captured
context and raw stdout, stderr and exit status; timeout forwards the context.
Callers construct commands and treat context as immutable. The component uses
`CommandLedger.js` for unique sources and deadlines, retires before callbacks,
and rejects late or duplicate replies. Cancellation and destruction disconnect
sources immediately. With GNU `timeout`, the command also has an independent
process-group bound two seconds beyond its UI deadline and a one-second TERM
grace before KILL. `Guards.boundedShellCommand` builds the bound before the nonce
is added, and a waiting shell keeps the timeout monitor alive after source
disconnection or destruction. Usage, account discovery and settings provider
rosters use the same guard with their own deadlines. Without GNU `timeout`,
reads retain their existing unbounded-process fallback. Reentrant
callbacks cannot publish retired results over newer work. Domain normalization,
cache retention, localization and retry policies remain in the controllers.
`tests/test_cli_process.py` exercises the production component with a fake
executable transport, including immediate replies, supersession, deadlines,
reentrancy and destruction. Controller tests retain real executable-engine
coverage, including source isolation between instances.
`tests/test_cli_process_bounds.py` exercises process termination through the
real executable engine with shortened controller deadlines, including hung
children and request retirement. It verifies process exit separately from UI
timeout state; source disconnection alone does not establish termination.

When multiple pages consume one CLI envelope, share the bounded record/envelope
contract and keep page-specific projections separate. Avoid both duplicate raw
parsing and one lossy result that erases different UI semantics. For a new CLI
field, update normalization, rendering, relevant checks, and affected guides.
Reconcile the linked issue against its acceptance criteria.

Use names that identify provider, source, account, window, or unit when ambiguous.
`build*`, `format*`, `provider*Url`, `*Rows`, and `*Text` helpers stay pure;
`refresh*`, `load*`, `parse*`, `select*`, `set*`, and `process*` may mutate state.
Put non-obvious lifecycle state in names such as `connected*`, `pending*`,
`*Memo`, `*Revision`, and `*Initialized`, and update it beside its effect.
Comments explain a workaround or contract, rather than restating assignments.

For repeated JavaScript in delegates, timers, or callbacks, use named helpers.
For repeated or bulky UI blocks, use small presentation-only components.
Extraction must hide complexity, not merely reduce line count.

`config/ProviderDescriptorField.qml` renders one normalized provider setting
as a secret prompt button, text/number editor, enum selector or boolean checkbox.
It receives provider availability, write-pending state and secondary text opacity
explicitly and emits write, enum-selection or secret-prompt requests.
`configProviders.qml` resolves enum IDs and owns validation, credential prompts,
CLI execution, pending state and configuration revisions. Credential entry stays
inside the page's prompt script. Its enum selection restores the saved-value binding
after a started write completes; rejected requests preserve the choice for retry.
Direct interaction tests in `tests/tst_provider_descriptor_field.qml` cover these
transitions, boolean binding restoration, numeric zero and control availability.

### Provider credential commands

`config/ProviderCapabilities.js` owns the released-version capability gates and
legacy API-key allowlist. The Providers page publishes the resulting flags and
resets them on executable changes or failed probes; direct capability QtTests
cover version boundaries, authentication restrictions and descriptor-owned
providers remaining unavailable through the fallback policy. The parity check
verifies QML delegation without requiring a switch statement inside the page.

`config/ProviderCredentials.js` owns version gates, the probe-backed Linux cookie
allowlist, quoted helper commands and bounded semantic results. The Providers
page owns prompts, nonces, pending locks, confirmation, command retirement,
configuration revisions and diagnostics invalidation. Cookie values enter only
`promptDescriptorSecret`'s shell process and the official writer through stdin.
Claude Platform session import uses the same private path; its exact stdin-login
command is secret-only, and the helper requires one authorized event plus exit 0.
`ProviderDescriptor.js` refuses credential writers through non-secret fields.

`scripts/provider-auth.py` is a transport adapter for released CLI commands,
not an authentication implementation: it never reads config, fetches provider
endpoints or receives a GitHub token. It drains bounded JSON, suppresses raw
stderr and projects write results to semantic records. For Copilot it consumes
newline-delimited CLI events while a native `kdialog --textbox -`
shows the pending URI/code. This bridge is necessary because Plasma's executable
engine publishes stdout only when a process exits. QML supplies localized dialog
text and starts the supervised command through `Guards.supervisedShellCommand`.
The helper's bounded `LoginStream` frames events without effects; `login_event`
classifies each event from explicit pending/terminal state. The process loop
applies those decisions, retaining ownership of dialog stdin, timers and cleanup.
Cookie, validated Console session import and clear commands also own a separate
CLI process group, retired on
every outcome. Their selector loop watches parent loss through both output
draining and CLI exit. A dedicated cancellation exception escapes the selector's
interrupted-system-call handling so signals still reach group cleanup.
Disconnecting a cached executable source does not stop its process immediately.
Cancellation sends a credential-free request marker through a short-lived
DataSource owned by the `credential/LoginCancellation.qml` singleton, so page
destruction cannot kill the cancellation writer or invalidate its cleanup handlers. The helper checks the marker and its timeout parent,
signals the CLI on cancel or expiry, and reaps both CLI and dialog process groups.
Markers live in a private temporary directory and expire after 20 minutes;
no event file or persistent service is created. The page ignores retired replies
and clears transient state on executable changes and destruction. The dialog
window close button cancels; OK dismisses it and continues waiting in settings.
Successful login bumps the existing provider-config revision to refresh usage.

Run `make check-python-test_provider_auth check-python-test_provider_source`
and the direct `tst_provider_credentials.qml` and `tst_provider_capabilities.qml`
QtTests while editing. The auth
adapter tests execute synthetic CLI streams, including split writes, bad shapes,
refusal, cancellation, expiry, conflicts and loss of the engine parent.
Checks for descendant termination allow a bounded wait after a group signal;
they must still fail when group cleanup is disabled. A real
Plasma executable-engine test destroys the request owner and verifies both
synthetic CLI and dialog processes stop. Page tests
cover old CLI versions, locks, refresh/diagnostic invalidation and stale replies;
`tests/tst_provider_filters.qml` checks actual action visibility with Plasma modules.
Run `make check` and `make package` before delivery: the helper is a package input.
The [credential contract](provider-credentials.md) pins official CLI evidence and
records the Gemini exclusion. Never test credentials against the user's config.

## Usage sharing

`ProviderNormalizer.js` validates model breakdowns before accumulating amounts
and excluded-request counts by raw model identity. Separate helpers handle
overflow-safe sums, cost-first ordering, and optional token ranking. Display
labels never become aggregation keys. Daily rows and period models share a
calendar selection with separate display-day and input-scan bounds. Their
normalization calls take named `days`, `updatedAt`, and optional `maximumDays`
options; model calls can also request `includeTokenRanking`. Daily rows reuse
the totals normalizer for strict numeric fallback and unknown-versus-zero rules.
Calendar indexing and gap construction remain separate so malformed or duplicate
days disable zero-day inference without losing valid in-range observations.
Direct normalizer QtTests cover label
collisions, excluded-only records before and after measured records, saturated
counts, input immutability, and partially unpriced token rankings.

`ShareUsage.js` projects range-matched cost snapshots into bounded aggregate
fields. `CostResponse.js` retains a separate bounded token ranking before the
normalizer caps its existing cost-first list. Both rankings pass through the
privacy projection. The export never serializes a provider record, account, project, or raw error.
`ShareUsage.js` redacts whole model labels containing absolute paths, including
UNC network shares, while retaining ordinary namespaced model IDs and the
aggregate amounts. Direct sharing tests cover quoted, embedded, Unicode and
space-containing UNC paths.
`main.qml` freezes that projection when the user opens the lazy-loaded
`ShareUsageWindow.qml`. `ShareUsageCard.qml` renders the export with system
fonts, tabular figures, theme colors, a provider token-share bar, and responsive
provider/model columns. `ShareUsage.js` bounds each provider share against the
token total and formats its whole-percent label.
The separate window owns capture generations, native
clipboard writes, save results, and the save dialog. Closing or changing privacy
retires pending captures; the panel popup may close independently.

The implementation uses Qt's [asynchronous item capture](https://doc.qt.io/qt-6/qml-qtquick-item.html#grabToImage-method),
[PNG saving](https://doc.qt.io/qt-6/qquickitemgrabresult.html#saveToFile),
[FileDialog](https://doc.qt.io/qt-6/qml-qtquick-dialogs-filedialog.html), and
KDE Declarative's [Clipboard](https://api.kde.org/qml-org-kde-kquickcontrols-addons-clipboard.html).
It copies the returned QImage, not the temporary image-provider URL. The picker
retains platform integration and overwrite confirmation. No shell clipboard
helper, provider fetching, or file upload is involved. Runtime requirements are
`QtQuick.Dialogs` and `org.kde.kquickcontrolsaddons` in addition to the existing
Plasma modules.

`tests/tst_share_usage.qml` covers the pure projection, missing amounts, mixed
currencies, overflow, text redaction, range matching, and URL restrictions.
`tests/test_share_usage.py` exercises the production window offscreen, checks
clipboard image MIME data and a real PNG file, save failure, close-during-capture,
privacy invalidation, footer grouping with narrow/RTL/enlarged labels, stable
short feedback and keyboard navigation. `share-usage` and `share-usage-narrow` smoke scenarios
capture both the card and the complete sharing window inside Plasma with
synthetic data. The additional `share-usage-window.png` and
`share-usage-narrow-window.png` captures include the footer; the isolated fixture
paints the same native background that item captures otherwise omit. It parents
the content and footer inside that QML-owned background because native window
roots lack a QML engine on some supported Qt versions. These checks do not establish
clipboard interoperability with every Wayland application or portal backend.

## Behavioral contracts to preserve

- Quota thresholds come from `QuotaThresholds.js`, shared by notifications and
  usage-bar markers. `limitResetArmThreshold` detects limit resets separately;
  it is not a warning threshold. `main.qml` resets opaque notification state
  through `NotificationPlanner.js`; its internal `NotificationMemo.js` preserves
  provider status baselines. Settings changes must not announce an ongoing
  incident again or swallow an incident arriving during refresh. Keep these
  decisions pure and covered by `tests/tst_notification_planner.qml` and
  `tests/tst_notification_memo.qml`. Scope priming handles quota, pace and reset
  baselines in one pass over the rows, with shared reset-percentage validation
  and arming-threshold fallback for priming and subsequent observations. Direct
  planner tests cover every quota/pace/reset toggle combination in both initial
  modes, mixed-confidence rows, and reset threshold and percentage boundaries.
  A failed status-page fetch, which the CLI
  reports as severity `unknown`, keeps a known incident baseline instead of
  replacing it. The planner treats that severity as missing status evidence,
  even when a status object was returned: it neither notifies nor primes a new
  baseline, while fresh quota observations still run independently.
  Predictive warnings prime silently and fire
  on a new projected-exhaustion transition. Missing usage rows retain their
  threshold state within the bounded memo; only observed rows can establish
  recovery or consume an armed reset.
- Sessions normalize display fields only. Discard `cwd`, `transcriptPath`, IDs,
  and PIDs; never render, open, or follow them. Remote/SSH host focus is a
  macOS-only non-goal. Without IDs, session cards are positional: the
  Repeater counts sessions so same-size rescans rebind existing cards in place,
  keeping hover and keyboard focus at the same index. Count changes recreate
  the cards. Each scan resynchronizes the clock used for relative ages.
  `SessionLabels.isActiveSession()` shares the active/running/working predicate
  between the header count and each card. The card's keyboard focus surface is
  separate from its animated hover background; state text uses their composited
  color with a 4.5:1 contrast target. Other accent callers retain the default 3:1
  target. `CopyableValue.showTruncatedTextOnFocus` opts Sessions into a combined
  action/title tooltip without changing other copy controls or adding Tab stops.
- `PanelRules.js` evaluates displayed quotas without effects. Automatic capsules
  use `PanelDisplay.meterRows` in primary/secondary order, and either displayed
  quota can satisfy the provider meter condition. Direct missing quotas stay
  omitted; `runOut` requires authoritative quota data and a reported run-out
  forecast through `PanelDisplay.rowHasRunOut`. Panel visibility,
  order, and metric settings preserve the minute clock and icon fallback and
  must not fetch data or change notification state.
- `ProviderSnapshot.js` stamps normalized quota rows with the receipt time
  supplied by their QML owner. Cached account selection and privacy projection
  preserve it, so a later refresh cannot restart another row's run-out countdown. This timestamp stays
  in memory; it is neither a CLI field nor part of the persisted quota cache.
- `ProviderSnapshot.js` stores a quota reset date as text every later reader can
  parse: the live countdown, the panel `resetWithin` rule, and absolute reset
  formatting all read that field, so a numeric CLI date is normalized to its ISO
  form instead of its epoch digits.
- `ProviderSnapshot.js` also preserves the supplied local usage receipt time
  on normalized provider snapshots. `UsageCache.js` uses that original time when
  a measurement timestamp is missing, invalid, or future at receipt, so selecting a cached
  account cannot renew its retention deadline. The receipt field stays in
  memory; persistence continues to store only the resolved measurement time.
- `PanelTextFit.js` composes the optional panel text from the segments the
  settings enable and offers progressively smaller compositions when the meter
  row leaves too little room. The renderer measures each candidate on its own
  hidden label and shows the widest that fits, so content is surrendered whole:
  the optional Auto quota name first, then the provider name and credits,
  keeping the usage figure or compact pace verdict. An identifying provider
  name outlives credits when its icon is generic. The module
  performs no measurement and no localization; QML supplies the segment text and
  the measured widths, and keeps the full composition for tooltips and
  accessible names.
- `PanelProviders.js` filters the panel-only provider selection without
  effects. Meters, panel text, and the panel tooltip roster narrow through it;
  the popup, fetching, and notifications keep the full roster. An empty stored
  value means automatic (all enabled providers), `__none__` stores an explicit
  empty selection, and unknown IDs keep hiding instead of resetting the choice.
  Aliases with mixed-case IDs match canonically. Manual selections show at most
  four enabled providers in roster order. Saved IDs absent from the enabled
  roster do not consume the settings selection limit.
  An empty filtered roster suppresses panel text; automatic mode retains its
  loading and no-data text fallback.
- `ProviderOrder.toggledSelection` shares the panel and Overview selection
  transition: it normalizes aliases, follows roster order, and retains saved
  providers absent from the roster without mutating either input. The panel
  settings page calls it directly; `OverviewProviders.js` applies its visible
  selection limit before calling it. Direct `tst_provider_order.qml` and
  `tst_overview_selection.qml` cover the shared transition and Overview policy.
- `OverviewProviders.js` owns the Overview-tab provider selection without
  effects. An empty stored value means the first three eligible providers,
  `__none__` stores an explicit empty selection, and aliases with mixed-case
  IDs match canonically. Manual selections allow three enabled providers;
  absent IDs survive toggles and settings round trips without occupying slots.
  Returning selections remain saved, and the runtime displays at most three
  eligible providers in roster order. The settings page and the
  runtime share its parsing so the checkboxes cannot drift from the applied
  selection. It also classifies eligibility: a snapshot carrying an error and
  nothing else has no row, while any surviving quota, credit balance, Codex
  monthly limit, subscription date, cost figure, detail section, dashboard summary,
  or placeholder keeps the provider
  visible. QML binds the resulting rows and localizes them; the module reads no root state.
  An empty detail-chart container needs a section/chart title, unit, row, or
  valid point to count as usable content for eligibility.
- `PopupHiddenRows.js` owns the popup's hidden usage rows without effects.
  Entries store a validated provider ID and a row key (`primary`, `secondary`,
  `tertiary`, or `extra:<CLI window ID>`) and no provider prose, so the Popup
  settings page names them from its own label tables. `main.qml` filters only
  the provider tab's usage rows through it and writes hide/restore choices;
  a disclosure in that tab lists current hidden rows for immediate restore,
  while settings can restore saved rows absent from the current CLI result.
  The panel, Overview, notifications, and fetching read unfiltered rows. Privacy
  projection and the quota cache keep the identifier-shaped `windowId` so a
  hidden extra window stays hidden. A full list refuses new entries instead of
  dropping old ones, and its hide actions stay unavailable until a row is restored.
  Both hidden-preference readers allow at most 65536 UTF-16 code units of JSON,
  enough for 64 entries even when each provider ID code unit needs a six-character
  Unicode escape. Direct QtTests replay escaped high and low lone surrogates
  independently of the Qt serializer version and cover the exact read limit.
  Executed applet adapters verify that saving and reparsing retain earlier hide choices.
  `popup-hidden-rows` smoke coverage hides every Codex quota row and restores
  each from the provider tab, capturing the expanded list with synthetic data.
  It also fills the 64-entry list and checks that restoring a saved row
  makes the hide action available again.
- `PopupHiddenSections.js` owns hidden detail-section preferences. It stores
  at most 64 validated provider IDs and versioned MD5 digests of normalized
  titles, without persisting CLI prose. The digest is a display identity, not
  encryption. Equal titles are one group; reordering or changed values keep
  identity, renaming resets visibility, and untitled sections cannot be hidden.
  The official Linux CLI 0.67.0 was probed with a loopback Bifrost quota fixture
  on 2026-09-27: `usage.details` emitted titled row groups without section IDs.
  This extends the [0.65.0 contract evidence](research/2026-09-23-macos-parity-0.65.0.md).
  `main.qml` writes preferences and filters only presented popup details; privacy
  projection removes the titles before restoration UI sees them. The popup
  restores individual current groups; Popup settings clear all saved groups for
  one provider, including titles no longer present. General defaults clear the
  setting. `tst_popup_hidden_sections.qml` covers persistence and identity;
  `popup-hidden-sections` smoke coverage exercises hide/restore and privacy on
  the real applet, saving synthetic before/after captures.
- `ProviderSnapshot.js` preserves usage confidence as `exact`, `estimated`,
  `percentOnly`, `unknown`, or empty for legacy payloads, stamping every quota
  row. The shared `ProviderNormalizer.authoritativeQuota` guard gates quota decisions; unknown
  or malformed confidence never becomes measured quota. `canPresentQuotaDetails`
  separately admits `percentOnly` for explicit CLI resets and forecasts in the
  snapshot, popup, panel modes and pace marker. This keeps supplied details
  visible while quota automation, warning colors, conditional visibility and
  automatic selection retain the conservative `authoritativeQuota` gate.
  `percentOnly` uses plain percentages without a panel badge. A provider-level
  panel tooltip note explains the source limitation, and missing resets have
  an explicit unavailable label in usage rows.
  Privacy retains at most six bounded semantic pace parts, dropping prose
  fallbacks and unknown fields. The root relocalizes those parts for the popup;
  the observation clock continues to advance the private run-out forecast.
  Raw CLI/cache fields
  use `usageConfidenceField`: only an absent field gets the legacy empty marker;
  explicitly empty or undefined values become unknown. Cache writes omit the
  legacy marker and restore field absence. Privacy retains the semantic value.
  The notification planner preserves an already notified quota severity and
  same-window pace warning across nonauthoritative observations while disarming
  resets. An all-nonauthoritative initial observation leaves the scope unprimed,
  so its first authoritative quota establishes a silent baseline.
  Only authoritative observations can establish recovery or escalation;
  a new reset timestamp still gives a forecast its own notification identity.
  `tst_usage_confidence.qml` exercises display, retention, ranking, visibility,
  notifications, and AI Insights at public interfaces. The `estimated-usage`,
  `estimated-panel`, and `unknown-panel` smoke scenarios verify the root
  adapters, rendered qualifier, and panel badges with synthetic data.
  `percent-only-usage` and `percent-only-panel` exercise the Claude primary and
  secondary windows, missing-reset label, root/notification adapters, quota
  guards, the accessible source note, and absence of a panel badge. The usage
  scenario also supports `--language it`.
  `percent-only-pace` verifies reported weekly resets, expected usage, the live
  run-out summary and its marker with the official 0.76.0 synthetic CLI shape.
  The exhausted scenario checks that no missing session reset or forecast is
  invented. See the [pinned contract probe](research/2026-10-15-claude-details-0.76.0.md).
  The pace scenario also enables privacy and verifies the rendered summary
  while account identity stays hidden. `tst_privacy_presentation.qml` covers
  malformed semantic parts; `test_forecast_clock.py` executes the private popup
  label across receipt, elapsed and exhausted forecast times.
- `ProviderAutoSelect.js` ranks the roster for the automatic provider
  selection. Measured consumption decides it, taking the busiest authoritative quota row or the
  provider cost meter, whichever reports further along; incident severity only
  breaks equal-consumption ties, so it cannot outrank even a fractional usage
  difference. Providers with no percentage at all are ordered by
  severity alone, an error-only provider never wins, and the first provider
  keeps a tie. The popup ranks the full roster and the panel ranks its own
  filtered selection through `PopupSelection.js`.
- General synchronizes history days and calendar mode as one pending range.
  External updates release an edit only when both persisted fields match;
  metric synchronization remains independent. `ConfigValueSync.js` owns these
  pure transitions, while the page owns pending values and Apply.
  `tests/test_general_config_sync.py` exercises the page handlers without KDE
  imports, including defaults and external changes during a pending edit.
- Privacy projects display records without changing cached snapshots or account
  command keys. Preserve config keys and pending defaults across all settings
  pages. `PopupRefreshPolicy.js` handles freshness and failed-attempt cooldown,
  including in-flight/queued work; opening the popup must not start cost scans.
  See the [settings decision record](research/2026-09-08-settings-experience.md).
- Validate `credits.codexCreditLimit` as finite non-negative amounts, clamped
  percentages, and bounded reset metadata. Its denominator belongs only to that
  nested record, never to a plain `usage.credits` balance.

## QML conventions

For visual and interaction changes, follow the [design guide](../DESIGN.md)
alongside these implementation rules. It defines reference priorities, shared
visual roles, surface composition, and review criteria; the usage guide remains
the source for supported behavior.

- Use `PlasmaComponents` for panel/popup controls and Kirigami/Qt Quick Controls
  in settings. Use `ContainmentItem` only for containment/panel/desktop code,
  not this applet's root.
- Keep `metadata.json`, `contents/ui`, `contents/config/main.xml`, and
  `contents/config/config.qml` in the standard package layout.
- Use checkboxes for booleans, spinboxes/sliders for numbers, text fields for
  short strings, and a combobox for more than three choices.
- Give visual children a size through layouts, anchors, implicit sizes, or
  explicit compact dimensions. Items otherwise default to 0x0.
- Use layout minimum/preferred sizes, implicit dimensions, and `Kirigami.Units`
  instead of panel-size magic numbers. Prefer anchors/layouts over bindings to
  sibling geometry, except inside the plain-`Item` boundary described below.
- Keep layout size hints independent of the geometry the layout computes.
  Use fixed preferred-size ratios for proportional columns. For width-dependent
  text caps, a plain `Item` may size children from its own and sibling widths.
  Keep those bindings out of layout size hints, and expose implicit sizes
  independent of the `Item`'s assigned width. See [Qt's layout guidance](https://doc.qt.io/qt-6/qtquicklayouts-overview.html#size-constraints).
- Set `implicitWidth: 0` on fill-width settings checkboxes so the layout owns
  their horizontal size. KDE/Breeze checkbox labels derive their implicit width
  from wrapped content; feeding that width back through a mirrored layout can
  otherwise create an `implicitWidth` binding loop.
- Give settings `TabButton` instances an explicit `baselineOffset` when their
  layout does not use baseline alignment. Older KDE desktop styles expose no
  content item but still derive the default baseline from it.
- Keep editable Settings spin boxes numeric, with units in the form label.
  The KDE desktop style commits each keystroke; formatting a unit suffix into
  the editor rewrites its text mid-entry and can drop subsequent digits.
  `test_settings_numbers.py` types into the production editors with both Basic
  and KDE desktop styles, including localized-number round trips. It also
  confirms Arabic, Persian, and Bengali digits in all six editors, starting
  from a different value so the unparsable-input fallback cannot mask a failure.
  Invalid text and legacy ASCII unit suffixes exercise the locale parser's
  exception path before the compatibility fallback.
  The desktop run of `tst_settings_pages.qml` also keeps Custom refresh visible
  while a typed interval passes through a preset prefix.
- Give settings number editors, selectors and text fields an explicit
  `Accessible.name` bound to their form label. `Kirigami.FormData.label` alone
  does not name the input for screen readers. Non-editable combo boxes expose
  no accessible value, so append their `displayText` to the label to keep the
  selected item announced. `tst_settings_pages.qml` checks
  focused production controls and keyboard selection changes with the default
  and KDE desktop styles.
- Prefer declarative bindings. Move repeated or expensive calculations into
  helpers or cached properties. Avoid heavy JavaScript in delegates, compact
  rendering, timers, and DataSource callbacks; profile before optimizing.
- Keep delegates stable. Add clipping, shaders, or nested layouts only for a
  visible need.
- External Repeater/view delegate components must declare
  `required property var modelData` inside the component. An alias assignment
  from the parent does not establish the delegate's scope; `qmllint` may miss
  the resulting runtime error.
- Use the Qt 6 `qmlformat`, such as `/usr/lib/qt6/bin/qmlformat`, for new files
  or a dedicated formatting change, then inspect the diff. Some distributions
  put Qt 5's `qmlformat` first on `PATH`; `--version` must report 6.x. Existing
  files have no formatter baseline, so preserve formatting during unrelated work.
- Keep `qmlls` in the editor. Machine-specific `.qmlls.ini` files stay out of Git;
  language-server diagnostics do not replace `make check`.

For translation/catalog changes, follow [Translations](translations.md).
The checks validate catalog coverage and arguments, then exercise the QML
session, pace, and count adapters against all compiled catalogs. Localized smoke
scenarios also verify these adapters through Plasma's actual translation domain.
When changing provider identity, check keys, CLI aliases, title, color,
docs/dashboard/login URLs, icon assets, and `scripts/test_provider_icons.sh`.
Register bundled icon filenames in `ProviderIdentity.js`'s `providerIconFiles`
table. Unknown providers return no asset filename so QML selects a theme icon;
a nonexistent local file URL does not activate Kirigami's icon fallback.
Repeat this comparison during official CLI release audits. The pinned 0.56.2
audit found the same 69 IDs as 0.55.0; the OpenRouter fallback already uses
`https://openrouter.ai/activity`. Treat the catalog as fallback presentation data
and use the [dated evidence](research/2026-09-01-macos-parity-0.56.2.md), not an
assumed current upstream count.
