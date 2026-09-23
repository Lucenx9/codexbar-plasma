# Changelog

Notable changes to the standalone Plasma widget are recorded here, following
[Keep a Changelog](https://keepachangelog.com/en/2.0.0/).
The upstream `codexbar` CLI has its own release history.

This file starts with version 0.2.35, summarized from its
[published notes](https://github.com/Lucenx9/codexbar-plasma/releases/tag/v0.2.35).
For earlier versions, see [GitHub Releases](https://github.com/Lucenx9/codexbar-plasma/releases).

## Unreleased

### Added

- Add a square CodexBar icon for the KDE Store listing, with a 512-pixel PNG
  and an editable SVG source.
- Install or update the latest widget release from one terminal command without
  cloning or building the repository. Setup verifies the release package,
  offers a private official CLI when needed, and asks before restarting Plasma.
  Non-interactive setup is supported; private CLI selection remains in settings.

- Share the selected Usage & Spend history as a local PNG or plain-text summary,
  with a separate preview, native image clipboard and save picker, bounded
  provider/model rankings, separate currencies, partial-data notices, and a
  small repository attribution. Exports exclude account and project details.

- Show **Quota weeks** in a provider's expanded cost details: the local cost
  and tokens of the current weekly quota window and up to three earlier ones,
  with exact boundaries; a current week with no full day yet is omitted until it
  has one. Totals that count a whole day around a mid-day reset
  are marked as estimated, unknown days are never counted as zero, and weeks
  older than the scanned history are omitted. This mirrors the macOS 0.62.0
  recent-windows list and needs no new CLI contract.
- Bundle the fallback name, icon, documentation link, and dashboard link for
  the `Helmcode`, `v0`, and `TypeSafe` providers that official CodexBar 0.64.0
  adds to the registry. Brand colors and status links are omitted because
  upstream defines none; the widget uses the theme highlight and hides missing
  links by design. `v0` also offers the widget's API-key setup, which the
  0.64.1 CLI accepts for it; Helmcode and TypeSafe are cookie-only and have no
  supported Linux setup path yet.
- Bundle the fallback name, icon, and documentation link for the `Pi`
  provider that official CodexBar 0.63.0 adds to the registry. Brand color and
  dashboard, login, and status links are omitted pending verifiable upstream
  sources; the widget uses the theme highlight and hides missing links by
  design.

### Changed

- Panel quota capsules no longer borrow a warning look. When a provider's brand
  hue sits within 20 degrees of the theme's warning or critical color, such as
  Z.ai's red or Claude's orange in Breeze, its capsules use a muted version of
  the brand color while the icon keeps the brand color. The muted color keeps
  the capsule's contrast and replaces the brand only when it is farther from
  every warning color. Any quota above zero
  now fills at least a round dot, as popup meters already did, so 4% remaining
  no longer looks like an empty capsule.
- Refine the popup's visual hierarchy. Content sits on the native Plasma dialog
  background without a nested inner frame or a separator under the tab strip.
  A selected tab now has a clearly visible surface, and a provider tab's
  underline is only its quota meter, so a partly filled bar no longer reads as
  a selection. Overview, session, and spend rows share borderless surfaces and
  identity tiles. The provider header separates account and plan.
- Keep a provider's quotas ahead of its cost history in the detail view. The
  cost section drops the day count the axis and summary already state, uses a
  flat metric selector and details toggle, and sets its estimate note in the
  same small type as the other cost footnotes. A current incident appears once,
  as the severity banner below the header, instead of also as a header badge.
- The Usage & Spend activity heatmap names each weekday row in the system
  locale and widens its cells up to a 2:1 tile, so long ranges use the width
  without stretching short ranges into bars. Rows stay unlabelled when the
  history is not calendar aligned.
- Bring the six settings pages to the popup's visual language. Explanatory
  text uses one quieter small style and sits under the text of the check box
  it explains; the CLI release notification option is indented under its
  parent like the widget update options. Panel and Providers use the popup's
  flat details toggle, and opening Panel's quota, order and visibility options
  no longer shifts the form sideways. The selected provider appears on one
  borderless surface with its identity tile, and long setting names wrap.
  Popup groups provider order and Overview providers under **Providers**,
  Diagnostics places redacted diagnostics in the same form under **Provider
  diagnostics**, and Notifications explains an unavailable incident option
  directly below it. Settings, defaults and saved values are unchanged.
- The popup smoke runner captures every settings page, including Providers
  with a long synthetic roster, narrow pages with larger text, and error
  states. `--theme light|dark` applies a Breeze color scheme and `--language`
  runs any scenario in a shipped translation.
- Keep the `Crof` fallback metadata after official CodexBar 0.64.1 retired the
  provider, so an older installed CLI that still reports it keeps showing a
  named provider instead of the unknown-provider fallback.
- `make check` runs its checks concurrently and exposes each one as its own
  target, such as `make check-shellcheck`, so contributors can iterate on a
  single check instead of the whole suite. `make check JOBS=2` bounds the
  concurrency on a constrained machine.
- The check suite also lints GitHub workflows with `actionlint` and the Python
  scripts and tests with `pyflakes`. Both are optional locally and report
  themselves as skipped when absent; CI installs them.

### Fixed

- Align provider header identity icon tile to the top of the row, matching the
  refresh button and title heading alignment when account, plan, or update
  metadata expands the middle column.
- Keep a fully measured share export free of an incomplete-data warning when
  its model ranking has more rows than the six shown, while still flagging
  missing model costs and source scans that reached their safety bound.
- Mask unknown provider identifiers in shared images and statistics when
  personal information is hidden, and mark quota-week amounts as partial while
  the CLI is still establishing local history coverage.
- Keep absolute paths embedded in model labels out of shared images and text.
- Mark quota-week cost and token totals as partial when a measured day excludes
  incomplete requests, and show both boundaries of the current week.
- Mark Quota weeks totals as partial when the cost history is older than the
  current day and has not scanned the trailing dates of a quota week.
- Bound **Diagnostics** commands shell-side with GNU `timeout --foreground
  --kill-after`, so a hung `codexbar diagnose` or provider list is killed
  instead of surviving as an orphan after the page times out or the dialog
  closes. The shell bound (50s plus a 5s kill grace) stays inside the
  existing 60s page timeout, and systems without GNU `timeout` run the raw
  command unchanged. A command reaped by the bound reports the same timeout
  message as the page timeout instead of an exit-code line or the shell's
  own signal notice.

## 0.2.40 - 2026-09-20

### Added

- Bundle names, icons, brand colors, and dashboard, status, and documentation
  links for the five providers official CodexBar 0.61.0 added to the registry:
  Nous Portal, Muse Code, CodeRabbit, Replicate, and Hugging Face. They
  previously fell back to the CLI name, a generic icon, and the theme
  highlight color.
- Install an optional widget-managed CodexBar CLI, update it manually or with
  opt-in daily automatic updates, and restore the previous version. Official
  Linux downloads are checksum-verified and activated atomically. External and
  package-manager installations remain independent; Diagnostics identifies the
  managed copy. A failed attempt names its reason, so a refused download reads
  differently from an unreachable release server or an unsupported system.
- Confirm before installing a managed copy while a working external CLI is
  selected, so the resulting second copy is explicit. Diagnostics also reports
  the PATH-resolved system CLI version next to the selected command.
- Check official CodexBar CLI releases manually or with optional daily checks
  and notifications. Package-managed installations keep their original updater;
  Diagnostics reports installed versions and recognized package ownership offline.
- Publish a Ko-fi donation link through the repository **Sponsor** button and a
  README **Support** section.
- Tell an unreachable CodexBar CLI apart from a provider that is not set up.
  When the shell reports the configured command as not found or not executable,
  the empty popup now says so, names the configured value, and points at
  **Diagnostics** for an absolute path, instead of offering a retry that cannot
  start or claiming that no provider is enabled.
- Report the widget version in **Diagnostics**, plus the CLI version and the
  absolute command the shell resolved after **Check versions**. The configured
  value can be a bare name, so the resolved path is what identifies which
  executable Plasma actually runs.

- Open the update's GitHub release page when clicking the widget-update
  notification. The page address is derived from the release tag announced by
  the updater and stays non-clickable when the installed `notify-send` is too
  old to support notification actions.
- Mark cost totals as partial when the CLI excluded requests that lacked final
  usage, naming how many were left out of the displayed cost and tokens. The
  notice appears for a provider and for the aggregate **Usage & Spend** total,
  and closing it keeps the same warning closed even when the count changes.
- Draw a faint peak reference line across bar charts at the highest plotted
  value, grounding the vertical scale of the columns before any point is
  inspected.

### Changed

- Restyle the **Usage & Spend** provider breakdown rows as subtle cards with a
  bordered, tinted provider identity tile matching the overview and provider
  header tiles.

### Fixed

- Align provider header account label typography with secondary plan and timestamp
  metadata by using small font size.
- Keep **Automatically update the managed CLI daily** switchable while it is on.
  Selecting a command outside the managed copy previously disabled the checkbox
  with the setting still enabled, leaving no way to turn it off and letting the
  widget keep starting an update helper that could never act.
- Standardize helper text font sizing across **General**, **Notifications**,
  and **Diagnostics** settings pages to use `Kirigami.Theme.smallFont`, matching
  the secondary label typography used in **Panel** settings.
- Normalize carriage returns and Windows line endings when reading the resolved
  executable path from the environment probe, so a CLI reporting CRLF output does
  not fail path validation in **Diagnostics**.
- Mark the CLI version and resolved path as not found immediately when running
  **Check versions** with an empty command path in **Diagnostics**.
- Open descriptor action URLs only when the returned HTTPS address fits in
  2048 characters, matching the existing descriptor text bounds. Longer
  addresses now report an unsupported URL instead of opening externally.

[Full diff](https://github.com/Lucenx9/codexbar-plasma/compare/v0.2.39...v0.2.40)

## 0.2.39 - 2026-09-17

### Fixed

- Keep the **Average/day** line visible when every day in the cost history
  window was measured as zero, matching the zeros the history rows below it
  already print. A window with no measured day still shows no average.
- Align popup usage dashboard section heading typographic hierarchy with other
  popup card section titles by using a level-4 primary heading.
- Keep oversized popup tabs aligned at their start when focus or selection is
  reported again, instead of alternating between the tab's start and end.
- Preserve measured zero costs and token counts in recent history rows instead
  of omitting them when the other amount is positive.
- Select the genuinely highest-usage provider automatically even when usage
  differs by a fraction of a percentage point; service incidents only break ties.
- Choose empty-usage messages from validated account identities: malformed
  identity fields no longer imply available account limits, and supported legacy
  identity fields receive the same message as nested identities.
- Show a real countdown for providers whose CLI reports a numeric reset date:
  the stored reset now keeps a parsable date, so the popup no longer prints the
  raw timestamp digits and the panel "resets within" rule matches again.
- Open the displayed provider's detail tab when clicking or keyboard-activating
  its standalone panel icon, instead of reopening a previously selected tab.
  The widget icon still toggles the popup when no provider is selected.
- Keep the panel visibility rule editor's condition combo and threshold spinner
  in sync with external settings changes, such as the restore-defaults action,
  after an interactive pick or typed value in the widget settings.
- Show hover tooltips on the clear-override and reload buttons in provider
  account selection.
- Keep the panel quota-lane combo in sync with external settings changes, such
  as the restore-defaults action, after a manual pick in the widget settings.
- Match stored panel provider selections canonically when toggling, so raw CLI
  spellings and mixed-case IDs resolve to the same provider instead of leaving
  a stale entry that cannot be removed.

[Full diff](https://github.com/Lucenx9/codexbar-plasma/compare/v0.2.38...v0.2.39)

## 0.2.38 - 2026-09-13

### Added

- Offer **Configure providers** when the popup has no provider data, and
  **Retry** and **Settings** beside usage errors. The messages point to
  Providers or Diagnostics in widget settings. Retry keeps last-known quotas
  visible and cannot repeat while a usage refresh is running.
- Refresh stale **Usage & Spend** history when revisiting the tab and when a
  visible spend view stays open across midnight. The existing hourly cost
  lifecycle still guards in-flight scans and failed-attempt cooldowns, cached
  charts stay visible during refresh, and switching the cost/token metric or
  inspecting a day still starts no scan.
- Contribution guidelines, a security policy with private vulnerability
  reporting, and issue forms for bug reports and feature requests.

### Fixed

- Eliminate duplicate section separators in the popup detail view when plain
  credit balances are absent but other additional sections are displayed.
- Ignore malformed configuration checksum replies so they cannot clear cached
  quotas or trigger unnecessary usage refreshes.
- Reserve initial readout row height in interactive charts so that hovering
  a point for the first time does not cause a vertical layout shift.
- Guard session refresh activity calculations against missing, null, or
  non-string command sources, avoiding uncaught exceptions during refresh
  scheduling.
- Keep partial cost refreshes working when a provider error message is malformed,
  retaining its previous costs while healthy providers update.
- Respect the automatic refresh interval after a failed Sessions scan when
  reopening the popup or revisiting the tab, while allowing immediate manual
  retries and scans after changing the CLI command.
- Preserve valid Codex quotas and named accounts when optional login-method
  metadata is malformed, and use a valid fallback for the plan label.
- Keep disabled Overview providers from occupying the three selection slots,
  while preserving their saved selection when other providers are chosen.
- Provider setup no longer reports a successful save when a CLI error has no
  readable message. Structured error messages cannot interrupt result handling;
  the widget shows a generic failure instead.
- Keep unavailable days in their calendar positions in the Usage & Spend
  activity heatmap, so missing cost or token values do not shift weekday rows
  or shorten the displayed range.
- Show cost refresh errors beside retained provider costs, including when the
  details are collapsed, so older values do not hide a failed update.
- Coalesce cost-setting changes applied together into one scan using the final
  settings, avoiding duplicate scans that immediately replace each other.
- Keep panel run-out countdowns tied to each forecast's receipt time, so
  selecting a cached account cannot restart an old or expired prediction.
- Preserve the original measurement age when selecting a cached account whose
  usage timestamp is missing, invalid, or future-dated, so old quotas cannot
  become fresh again or extend their 24-hour retention limit.
- Keep last-known quotas when a provider error has an empty or malformed message,
  showing a generic error while healthy providers and current status still update.
- Preserve healthy usage records after a malformed sibling in provider-scoped
  CLI replies, including measured-zero quotas, while keeping all-invalid
  replies as provider errors.
- Keep settings checkboxes stable in right-to-left layouts under KDE/Breeze
  styles, avoiding repeated width binding loops while the pages settle.
- Keep the provider filter tabs usable with KDE styles whose tab buttons expose
  no content item, avoiding repeated QML errors when opening Providers settings.
- Use the pinned KDE CI image’s authenticated package indexes so an outage of
  the archive’s current metadata does not block checks and package builds.
- Preserve ampersands and angle brackets in provider selection and settings
  checkbox labels when KDE styles process keyboard mnemonics.
- Preserve quota, pace, and reset notification baselines when a successful CLI
  reply contains obsolete quotas alongside current service status, avoiding
  repeated warnings and missed reset notices when fresh usage returns.
- Clear completed Sessions snapshots and update metadata when the configured CLI
  command changes, so a failed or timed-out scan cannot display sessions from
  the previous executable.
- Hide pace and run-out forecasts when an otherwise successful quota snapshot
  is older than the 24-hour retention limit, while preserving its last-known
  measurement and current service status.
- Keep failed usage replies from borrowing another account's quota when distinct
  account keys share a display label or the account is identified only by its
  organization. Failures without identity still retain the last known quota,
  and the startup cache still restores its own for a provider whose explicit
  account selection its context already verified.
- Keep the healthy accounts listed in the account picker when another account
  record in the same `codexbar` reply cannot be read.
- Preserve newer retained usage and its last-known timestamp when startup cache
  restoration is delayed past a failed refresh.
- A tiny negative credit balance that rounds to zero now reads as `0` instead
  of the negative-zero string `-0`.
- Preserve valid provider usage when the CLI supplies a malformed optional
  status URL, falling back to the provider's bundled status page instead of
  discarding its usage snapshot.
- Keep the last known provider incident ID across active status replies that omit
  it, including notification priming, so a replacement incident at the same
  severity is still announced without repeating the original incident.
- Preserve valid provider quotas when the CLI supplies malformed optional
  reset metadata, ignoring the unusable reset value instead of discarding
  the provider snapshot.
- Preserve valid provider quotas when the CLI supplies a malformed optional
  provider display name, ignoring the unusable name instead of discarding
  the provider snapshot.
- Align reset countdown / timestamp text with pace metadata along the text
  baseline in provider usage rows.
- Aggregate per-model cost and token totals by the raw model identity instead
  of the bounded display label, so distinct models that share a truncated or
  whitespace-collapsed label no longer merge into one row.

[Full diff](https://github.com/Lucenx9/codexbar-plasma/compare/v0.2.37...v0.2.38)

## 0.2.37 - 2026-09-10

### Added

- Choose which providers appear in the panel through **Panel → Panel
  providers**. The selection lists the enabled providers, follows the saved
  provider order, and is limited to the four meters the panel can draw; the
  panel text, meters, and tooltip follow it, while the popup keeps showing every
  enabled provider. Leave the selection automatic to show all enabled
  providers, as before. Clearing every checkbox keeps the widget icon without
  provider text or meters. Disabled providers keep their saved selection without
  blocking new choices; only the first four enabled selections appear.
  Automatic checkboxes recognize provider aliases and mixed-case IDs.
  The preview uses enabled provider names after the selection list loads, with
  synthetic measurements for every provider.

### Changed

- Refresh quotas when the popup opens by default, so a widget that was idle,
  suspended, or running without periodic refresh no longer presents an old
  measurement as current. Only quotas older than the refresh interval are
  fetched, and failed attempts keep their cooldown, so reopening the popup does
  not repeat the command. Existing widgets keep their stored choice; new widgets
  and **General → Restore all defaults** get the new default, and the setting can
  be turned off again in **General**.

### Fixed

- Keep every enabled **Panel → Additional information** item readable when
  several providers fill the panel. The panel used to squeeze the provider
  name, usage text, and credit balance into whatever the meter row left over
  and cut the result short, so "Claude 82% used 125cr" arrived as
  "Claude 82% u..." and a complete value became a fragment reading as a
  different one. The panel now surrenders whole items instead, dropping the
  provider name first because the icon beside it already identifies the
  provider, then the credit balance, and keeping the usage text. The full text
  stays in accessible names, and only a single remaining item is ever elided.
  For a provider the widget has no icon for, the panel draws a generic icon that
  names no provider, so there the name outlives the credit balance instead. The
  panel also offers the text every pixel the row actually leaves, instead of a
  flat allowance that hid content while space was free.
- Report the credit balance in the panel tooltip while panel credits are
  enabled, so a crowded panel that had no room to draw it does not leave a
  pointer user without it. No meter carries the balance, and the tooltip
  previously reported only quotas and incidents.
- Keep Popup and Notifications settings text and controls in place while the
  page opens. The themed scrollbar gutter stays reserved instead of appearing
  and then disappearing as the content settles, and the Popup overview section
  carries the same width bound as its provider-order sibling while the provider
  list arrives.
- Keep the stored value in the editable settings fields for the custom refresh
  interval, the update check interval, and both quota thresholds when the typed
  text holds no number, instead of replacing a configured value with an
  unrelated default. Clearing the custom interval field, or committing its
  "No periodic refresh" text, no longer turns a disabled refresh into five
  minutes.
- Keep accounts that differ only by internal spacing separately selectable and
  pass the unmodified name to `--account`, instead of collapsing one label onto
  the other and requesting the wrong account.
- Never show the previous executable's cost data beside the new quotas after
  the command source changes, even when the cost refresh fails.
- Survive malformed provider status fields and keep the healthy providers of
  the same refresh, settling loading instead of leaving it active.
- Revalidate carried account keys before use, so a blank or overlong stored
  key falls back to the snapshot identity instead of reaching deduplication,
  selection, or the `--account` argument.
- Skip structured account identity fields when choosing the `--account`
  identity, so a malformed value cannot mask a valid fallback from another
  identity field.
- Screen the provider id inside the per-provider guard during usage parsing,
  so a failing identity read drops only its own provider instead of aborting
  the whole refresh.
- Retain failed providers after a partial cost reply only from the same
  command source, so a source change cannot re-tag the previous executable's
  costs with the new source.
- Show the panel incident badge on the affected provider's own meter icon, so
  reordering providers moves the outage marker with that provider instead of
  leaving a dot beside whichever provider comes first. The badge stays visible
  while a refresh runs. The standalone status dot remains only as a fallback
  for incidents no meter can badge (meters hidden, or the incident provider
  has no meters), and the vertical identity icon carries a badge only for its
  own provider's incident; an incident on another provider keeps the
  standalone fallback when meters are hidden.
- Place the subscription label directly beside the account email in the
  provider header, instead of letting it drift toward the middle of the popup,
  and let the account elide first on narrow popups.
- Stop presenting an "all systems operational" service status as the overview
  account line. Providers whose CLI payload carries no account identity (such
  as Claude on verified CLI 0.56.2) now show no substitute identity; an active
  incident still appears, and the detail line no longer repeats the provider's
  own name or source.
- Recover provider actions when a secret prompt stops responding: the dialog
  closes after a long escape-hatch deadline and the stuck pending state clears,
  instead of leaving the provider disabled until the settings page reopens.
  Late submissions retain the full bounded save window.
- Complete provider fallback slots when a malformed reply fails late, and
  report account normalization failures as errors for the affected provider.
- Keep provider configuration polling connected when another widget instance
  has already cached a response for the same command.
- Keep the provider cost metric picker in sync with the shared cost and token
  history selection after picking an entry.
- Keep the Panel settings preview visible while scrolling through content,
  quota, order, and visibility options.
- Avoid repeating the selected provider's icon with custom panel element
  orders when it is the only visible provider meter.
- Ignore malformed cost breakdown/model rows and keep chart dimensions finite.
- Clear chart selection and hover state when point data disappears, allowing
  keyboard navigation to recover when data returns.
- Normalize provider fallback requests before deduplication and preserve scalar
  zero/false CLI text values.
- Keep theme calculations finite when inputs are unavailable.
- Avoid tab overflow controls during initialization.
- Anchor tab tooltips to their hover areas and improve accessibility labels for
  heatmap cells and decorative controls.
- Animate the panel provider meter hover/press highlight and the Usage & Spend
  heatmap cell hover outline, matching the smooth transitions already used for
  every other interactive surface in the popup. The heatmap outline is a
  separate overlay, so the cell's painted fill never shifts on hover.
- Confirm hover on session cards, which reveal copy actions on hover but
  previously left the card surface unchanged.
- Fade the chart readout in and out with the hovered point instead of blinking
  the label and value on every pointer entry and exit.
- Fade the tab selection indicator with the tab background it sits under,
  instead of blinking the accent bar on every tab change.
- Hold tooltips back for the standard Plasma hover delay instead of flashing
  them the instant the pointer crosses a tab, a panel status dot, or a copy
  button. The heatmap cell readout and the copied confirmation stay immediate.
- Grow the panel capsule fill into a new reading, like every meter in the popup
  already does. The settings preview keeps rendering a static frame.
- Truncate popup section headings and labels that fill the available width, so
  a long translation or a provider-supplied cost title can no longer push the
  row wider than the popup.
- Narrow the panel tooltip to the hovered provider meter, so hovering one
  panel icon reports only that provider's quotas instead of the whole roster.
  The full list remains when hovering elsewhere.
- Lay the Usage & Spend activity heatmap out as a complete block instead of a
  small patch of squares stranded beside an empty half of the tab. Its cells
  now stretch into the width a short range leaves unused, the grid is padded so
  a partial final week no longer cuts a week-wide notch out of it, and ranges
  that fill a single week column hide the heatmap, which repeated the chart
  above it one day per row.
- Reject oversized diagnostics responses with a clear error instead of
  buffering them for display, matching the other CLI surfaces.
- Allow mouse selection in the diagnostics output and bound the diagnostic
  provider field, matching the provider settings inputs.
- Recognize provider aliases and mixed-case IDs in the Overview provider
  checkboxes, matching the runtime selection and the panel provider selection,
  so a stored choice stays checked when the roster spells it differently.

[Full diff](https://github.com/Lucenx9/codexbar-plasma/compare/v0.2.36...v0.2.37)

## 0.2.36 - 2026-09-09

### Added

- Last-known quota recovery after failed refreshes and Plasma restarts, with
  explicit freshness labels, a 24-hour retention limit, and a redacted persistent
  cache.
- A versioned changelog, included in the widget package and used as the source
  for future GitHub release notes.

### Changed

- Panel settings start with appearance and meters. Additional information holds
  provider name, usage text and format, credits, and the monochrome preset.
  Quota, order, conditions, and automatic selection have their own expandable
  section. Closed summaries reflect enabled information and custom choices.
  Standard and Minimal are side by side.
- Default panel order groups optional text with the selected provider's capsules,
  using one logo. Hidden or unavailable meters retain a separate text identity;
  custom element orders keep their independent positions.
- Panel meters place a small provider icon beside primary and secondary quota
  capsules, with matching geometry in colored Standard and monochrome Minimal.
  Meters now work in vertical panels. Explicit quota choices still show one
  capsule; visibility conditions accept either displayed quota. Tooltip and
  accessibility descriptions report both quotas and resets.
- Linux parity work is maintained in TODO.md, with agent review of each stable
  upstream release and updates in the PR that implements a feature.
- Reorganized installation and troubleshooting instructions, with dedicated
  guides for settings, cost history, and development.
- Contributor delivery uses pull requests with required check and smoke jobs.
  Agents follow CI through completion after pushes and authorized merges.
- Pull request titles follow Conventional Commits and are checked automatically.
- CI cancels superseded PR runs and omits graphical smoke tests for changes
  limited to editorial Markdown. Checks and packaging still run; releases keep
  full graphical coverage.

### Fixed

- Provider details and project costs no longer trigger recursive Qt layout
  warnings when opened or resized. Long values stay within the popup.
- Panel settings keep text and controls in place while the page opens, including
  when the scrollbar disappears or collapsed sections finish sizing.
- Restored cached provider quotas are retained across partial early refreshes
  during startup, preventing premature eviction of unrefreshed providers.
- Primary incident selection, tooltips, and status banners ignore providers with
  unknown or inactive status, preventing stale outages from masking active incidents.
- Successful responses without measured quotas keep valid credits and details
  even when their supplemental timestamp is older than the quota-cache limit.
  They no longer show a last-known banner or turn into cache-expired errors.
- Last-known quota handling: unknown service status no longer keeps showing
  the previous outage, extra-lane quotas survive restarts, expired quotas
  keep no measurement instead of undefined state, the restore banner only
  shows when data is actually stale, per-provider resets keep healthy
  providers' disk cache, empty usage results keep CLI error detail, stale
  supplement sections are hidden until revalidated, measurements older than
  24 hours no longer stamp as fresh, future live timestamps use receipt time,
  overview rows keep account/status
  context beside the last-known note, and long update timestamps ellipsize
  on one line.
- Panel settings no longer query a rebuilding element-order layout's attached
  size hints, avoiding a Qt layout crash when expanding and reordering controls.
- Panel text falls back to a separate label if meters exhaust the width available
  for grouped text.
- The settings preview now renders quota capsules from its synthetic data after
  QML converts provider records for delegates.
- Credit balances that round up to a whole number no longer keep a trailing
  ".0" (99.95 credits read as "100"), and huge magnitudes no longer gain a
  bogus group separator.
- Token, request, and point counts now use singular and plural forms in usage
  and cost summaries, while large counts keep their compact notation.
- Corrected quota and plan labels, login actions, and settings wording across
  the five translations. The Brazilian Portuguese panel style is now translated,
  and French and Spanish pace percentages use consistent spacing.
- Switching the account of the configured provider no longer starts a usage
  command twice in a row, discarding the first run immediately.
- Provider settings descriptors whose schema version is not exactly the
  supported number stay unsupported instead of being accepted through type
  coercion, and malformed quota-threshold inputs keep their documented
  fallbacks instead of collapsing to a 1% warning for every provider.

[Full diff](https://github.com/Lucenx9/codexbar-plasma/compare/v0.2.35...v0.2.36)

## 0.2.35 - 2026-09-08

### Added

- Dedicated General, Providers, Panel, Popup, Notifications, and Diagnostics
  settings pages, with a live panel preview.
- Optional privacy mode for widget views and new notifications, refresh-on-open
  for stale usage, and controls for popup pace, credits, and provider details.
- Compact Today and period cost summaries, expandable history, and model details
  for the selected day. Missing amounts and partial model coverage stay explicit.

### Changed

- Fresh installations use Standard provider icons and usage meters by default.
  Existing appearance options and saved preferences are preserved.

### Fixed

- The Accounts action could stay disabled after a reply arrived following a CLI
  settings change.
- Malformed cost, chart, and account data could interrupt display updates.
- Cost history could lose days with zero cache tokens.
- The panel loading fallback was missing in some states.

[Full diff](https://github.com/Lucenx9/codexbar-plasma/compare/v0.2.34...v0.2.35)
