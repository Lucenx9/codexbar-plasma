# Documentation

The repository keeps maintained documentation and current product screenshots.
The documentation policy is in [AGENTS.md](../AGENTS.md#documentation-hygiene).
Every file under `docs/` is listed below so new material has an explicit purpose.
[TODO.md](../TODO.md) tracks remaining Linux/Plasma parity with the official
macOS app; the guides describe supported behavior. Agents maintain both through the
[documentation workflow](development.md#documentation-and-work-tracking).

## Maintained references

- [Linux parity TODO](../TODO.md): open Plasma work, official CLI blockers, and
  the last reviewed upstream release. Agents update it with each release.

- [Contributing](../CONTRIBUTING.md): entry point for outside contributors,
  covering where to report what, checkout setup, and pull request requirements.
- [Security policy](../SECURITY.md): supported versions and private
  vulnerability reporting for the widget.
- [Changelog](../CHANGELOG.md): notable widget changes by version and unreleased
  changes. Future GitHub release notes come from this file.
- [Usage and settings](usage.md): panel and popup options, provider setup,
  data freshness and quota cache limits, cost history, notifications, and widget defaults.
- [Development](development.md): QML ownership, regression checks, runtime
  verification, PR delivery and CI follow-up, repository maintenance, and agent
  instructions. Read before code or tooling changes.
- [Provider settings descriptor](cli-provider-settings-descriptor.md): proposed
  upstream CLI contract for generic settings. It is not a shipped contract.
- [Cost history](cost-history.md): daily model data, selection behavior, and
  the pinned Linux CLI evidence behind the popup.
- [AI Insights](ai-insights.md): the optional insight card's boundary decision,
  allowlisted snapshot, language selection, request and credential contracts,
  scheduling, and tests.
- [Translations](translations.md): adding and checking a language catalog.
- [CLI 0.56.2 parity baseline](research/2026-09-01-macos-parity-0.56.2.md):
  verified official Linux contracts at that comparison date. The
  [usage guide](usage.md) describes current Plasma behavior; later scoped checks
  in the cost and settings documents do not replace this full audit.
- [0.57.0 release review](research/2026-09-09-macos-parity-0.57.0.md): Linux-relevant
  changes since 0.56.2, current Plasma gaps, and scoped official CLI probes.
- [0.58.0 release review](research/2026-09-11-macos-parity-0.58.0.md): release
  delta with no Linux CLI contract changes, feature classification against
  existing Plasma behavior, and scoped official CLI probes.
- [0.60.4 release review](research/2026-09-16-macos-parity-0.60.4.md): releases
  0.59.0 through 0.60.4, source-observed credit-availability and detail-row
  fields, unchanged JSON schemas, and scoped official CLI probes. Cursor cost,
  provider descriptors, and generic config actions remain unavailable on Linux.
- [0.60.5 release review](research/2026-09-18-macos-parity-0.60.5.md): the new
  cost `incompleteRequestCount` contract verified in official Linux output,
  its unknown-not-zero day shape, and scoped official CLI probes. Provider
  descriptors, generic config actions, and Cursor cost remain unavailable.
- [0.61.0 release review](research/2026-09-18-macos-parity-0.61.0.md): the
  registry growth to 74 providers, the source-observed Grok reset-credit detail
  row, the live-only `grokResetCredits` property, and scoped official CLI
  probes. Provider descriptors, generic config actions, and Cursor cost remain
  unavailable.
- [0.62.0 release review](research/2026-09-20-macos-parity-0.62.0.md): the
  verified Muse token-history cost contract, the Codex-only `--remote` and
  `--summary-only` cost modes, the `usage_updated` hook event, invalid-total
  suppression in cost aggregation, and scoped official CLI probes. Provider
  descriptors, generic config actions, and Cursor cost remain unavailable.
- [0.63.0 release review](research/2026-09-21-macos-parity-0.63.0.md): the
  Pi registry growth with local token history and estimated costs, the
  still-rejected Cursor cost and descriptors probes, and scoped official CLI
  probes. Provider descriptors, generic config actions, and Cursor cost remain
  unavailable.
- [0.64.1 release review](research/2026-09-22-macos-parity-0.64.1.md): the
  Helmcode, v0, and TypeSafe registry additions, the Crof retirement, the
  measured split between v0's supported API-key setup and the two cookie-only
  providers, and scoped official CLI probes. Provider descriptors and generic
  config actions remain unavailable.
- [0.65.0 release review](research/2026-09-23-macos-parity-0.65.0.md): the
  Bifrost, Charm Hyper, and GitKraken AI registry additions and their Linux
  reachability, detail-row `progress`/`usageValue` and unknown named windows
  verified through a loopback Bifrost fixture, and checksum-verified official
  CLI probes. Provider descriptors, generic config actions, token-account
  writes, and Cursor cost remain unavailable.
- [Settings decisions](research/2026-09-08-settings-experience.md): Panel disclosure and text grouping,
  Plasma settings, privacy, refresh behavior, the macOS 0.56.8 comparison, and
  the shared settings visual conventions.

## Earlier CLI evidence

The 0.49.1 through 0.55.0 reports were superseded by the
[0.56.2 audit](research/2026-09-01-macos-parity-0.56.2.md), which re-verified
their contracts, and were removed. They remain recoverable from Git history
at commit `ba0a0d8`.

## Product screenshots

These synthetic captures appear in the project README or usage guide. The README
captures are also included in the widget package. Replace the relevant image
when the product changes instead of adding dated before/after copies.

- [Popup tour](codexbar-plasma-tour.gif): the README animation stepping through
  Overview, Usage & Spend, Sessions, and a provider detail tab. Rebuild it from
  the `readme-` popup smoke scenarios; see
  [runtime verification](development.md#runtime-verification).
- [Overview](codexbar-plasma-overview.png)
- [Provider details](codexbar-plasma-codex.png)
- [Usage and spend](codexbar-plasma-usage-spend.png)
- [Shared usage card](codexbar-plasma-share.png): synthetic local PNG summary,
  with separate provider/model rows and the repository attribution.
- [Sessions](codexbar-plasma-sessions.png)
- [Standard panel](codexbar-plasma-panel-standard.png): colored provider icons and dual quota capsules.
- [Minimal panel](codexbar-plasma-panel-minimal.png): monochrome provider icons and dual quota capsules.
- [Panel with usage text](codexbar-plasma-panel-information.png): selected-provider text grouped with its quota capsules.

## Store artwork

- [Store icon PNG](codexbar-plasma-store-icon.png): 512 × 512 image for the KDE Store listing.
- [Store icon SVG](codexbar-plasma-store-icon.svg): editable source for the store icon.

## Historical work artifacts

Past captures, completed plans, and review logs are available in
[Git history before the cleanup](https://github.com/Lucenx9/codexbar-plasma/tree/92679f99ce5d5479f4f87edde051fff91e30b91f/docs).
New temporary artifacts go in ignored `dist/review/` or the OS temp directory.
PRs record verification results; this index records documents worth maintaining.
