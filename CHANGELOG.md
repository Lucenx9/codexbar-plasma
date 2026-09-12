# Changelog

Notable changes to the standalone Plasma widget are recorded here, following
[Keep a Changelog](https://keepachangelog.com/en/2.0.0/).
The upstream `codexbar` CLI has its own release history.

This file starts with version 0.2.35, summarized from its
[published notes](https://github.com/Lucenx9/codexbar-plasma/releases/tag/v0.2.35).
For earlier versions, see [GitHub Releases](https://github.com/Lucenx9/codexbar-plasma/releases).

## Unreleased

### Added

- Refresh stale **Usage & Spend** history when revisiting the tab and when a
  visible spend view stays open across midnight. The existing hourly cost
  lifecycle still guards in-flight scans and failed-attempt cooldowns, cached
  charts stay visible during refresh, and switching the cost/token metric or
  inspecting a day still starts no scan.
- Contribution guidelines, a security policy with private vulnerability
  reporting, and issue forms for bug reports and feature requests.

### Fixed

- Preserve the original measurement age when selecting a cached account whose
  usage timestamp is missing, invalid, or future-dated, so old quotas cannot
  become fresh again or extend their 24-hour retention limit.
- Preserve valid Codex quotas and named accounts when optional login-method
  metadata is malformed, and use a valid fallback for the plan label.
- Keep disabled Overview providers from occupying the three selection slots,
  while preserving their saved selection when other providers are chosen.
- Keep unavailable days in their calendar positions in the Usage & Spend
  activity heatmap, so missing cost or token values do not shift weekday rows
  or shorten the displayed range.
- Show cost refresh errors beside retained provider costs, including when the
  details are collapsed, so older values do not hide a failed update.
- Coalesce cost-setting changes applied together into one scan using the final
  settings, avoiding duplicate scans that immediately replace each other.
- Keep panel run-out countdowns tied to each forecast's receipt time, so
  selecting a cached account cannot restart an old or expired prediction.
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
