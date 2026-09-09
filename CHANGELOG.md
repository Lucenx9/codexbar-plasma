# Changelog

Notable changes to the standalone Plasma widget are recorded here, following
[Keep a Changelog](https://keepachangelog.com/en/2.0.0/).
The upstream `codexbar` CLI has its own release history.

This file starts with version 0.2.35, summarized from its
[published notes](https://github.com/Lucenx9/codexbar-plasma/releases/tag/v0.2.35).
For earlier versions, see [GitHub Releases](https://github.com/Lucenx9/codexbar-plasma/releases).

## Unreleased

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
