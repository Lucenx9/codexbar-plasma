# Documentation

The repository keeps maintained documentation and current product screenshots.
The documentation policy is in [AGENTS.md](../AGENTS.md#documentation-hygiene).
Every file under `docs/` is listed below so new material has an explicit purpose.
[TODO.md](../TODO.md) tracks remaining Linux/Plasma parity with the official
macOS app; the guides describe supported behavior. Agents maintain both through the
[documentation workflow](development.md#documentation-and-work-tracking).

## Maintained references

- [Design direction](../DESIGN.md): reference sources, Plasma-native visual
  roles, panel/popup/settings composition, interaction states, and UI review
  criteria. It guides future changes without changing supported behavior.
- [Panel budgets and monthly allowance](panel-budget-and-monthly-allowance.md):
  official Linux 0.84.0 synthetic budget evidence and bounded display decisions
  for panel spend, automatic quota priority, and monthly percentage per day.
- [Linux parity TODO](../TODO.md): open Plasma work, official CLI blockers, and
  the last reviewed upstream release. Agents update it with each release.

- [Contributing](../CONTRIBUTING.md): entry point for outside contributors,
  covering where to report what, checkout setup, and pull request requirements.
- [Security policy](../SECURITY.md): supported versions and private
  vulnerability reporting for the widget.
- [Changelog](../CHANGELOG.md): notable widget changes by version and unreleased
  changes. Future GitHub release notes come from this file.
- [Usage and settings](usage.md): panel and popup options, provider setup,
  Soniox organization-key and Chatbox license-key guidance, usage confidence,
  data freshness and quota cache limits, cost history,
  notifications, and widget defaults.
- [Development](development.md): checkout setup, task-specific implementation and
  verification links, PR delivery, release procedures, repository maintenance,
  and agent instructions. Start here before code or tooling changes.
- [Implementation reference](implementation.md): QML and JavaScript ownership,
  provider credential processes, sharing, behavioral contracts, and QML conventions.
- [Regression checks and CI](testing.md): behavioral and static checks, CI image
  maintenance, coverage selection, and sticky CI reports.
- [Smoke tests](smoke-tests.md): isolated popup and settings scenarios, capture
  requirements, and the panel configuration matrix.
- [Runtime verification and CLI probes](runtime-verification.md): installed-widget
  diagnostics, pinned CLI response contracts, isolated probes, and packaging.
- [Release skill](../.claude/skills/release/SKILL.md): agent command sequence
  for a widget release, from changelog reconciliation to the verified tag run.
- [Parity review skill](../.claude/skills/parity-review/SKILL.md): agent command
  sequence for an upstream release review, including the isolated CLI probe.
- [Provider credential commands](provider-credentials.md): version gates, verified
  cookie allowlist, clear semantics, Copilot event bridge, validated Claude Platform
  session import and regression coverage.
- [Provider settings descriptor](cli-provider-settings-descriptor.md): proposed
  upstream CLI contract for generic settings. It is not a shipped contract.
- [Cost history](cost-history.md): daily model data, selection, currency and
  confidence rules, pinned Linux CLI evidence behind the popup, and the separate
  manual identified Codex token subtotal and its decoder limits.
- [Identified-token screenshot](codexbar-plasma-identified-tokens.png): synthetic
  schema 2 local subtotal and separate API-price estimate retained after an
  SSH-source failure, used in the usage guide.
- [Detail severity screenshot](codexbar-plasma-detail-severity.png): synthetic
  normal, warning and critical detail rows with independent progress, used in
  the usage guide.
- [Chatbox key setup screenshot](codexbar-plasma-chatbox-key-setup.png):
  synthetic license-key and credential-clear actions, setup guidance and documentation link in
  provider settings, used in the usage guide.
- [Provider authentication screenshot](codexbar-plasma-provider-authentication.png):
  synthetic Copilot settings showing device sign-in, credential clearing,
  CLI-described authentication hints and the per-provider source selector, used in the usage guide.
- [AI Insights](ai-insights.md): the optional guided assistant in Usage & Spend, its
  boundary decision, allowlisted snapshot, private helper handoff, language selection, request and credential contracts,
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
- [0.66.0 release review](research/2026-09-24-macos-parity-0.66.0.md): the
  DevPass, Atlas Cloud, Vercel AI Gateway, and llmman registry additions and
  their API-key setup, llmman output verified through a loopback daemon
  fixture, the #3944 plugin-entry preservation in the tested `config disable`
  command, and checksum-verified official CLI probes. Provider descriptors, generic config
  actions, and Cursor cost remain unavailable.
- [0.67.0 release review](research/2026-09-26-macos-parity-0.67.0.md): the
  Aixy, Raycast, and xKiro registry additions and their Linux reachability,
  Aixy output verified through a loopback fixture, the `cost --period` flag and
  its `reportingPeriod`/`historyLabel` fields, and checksum-verified official
  CLI probes. Provider descriptors, generic config actions, Cursor cost, and
  display currency remain unavailable.
- [0.69.0 release review](research/2026-09-29-macos-parity-0.69.0.md): the
  0.68.0 and 0.69.0 delta with an unchanged 87-provider registry, the
  Mistral manual-cookie runtime fix verified before and after, unchanged
  setup reachability for the migrated bundled-plugin providers, the still
  year-1 `--period all` day count, empty-config tolerance, and
  bubblewrap-isolated official CLI probes. Provider descriptors, generic
  config actions, Cursor cost, and display currency remain unavailable.
- [0.72.0 release review](research/2026-10-05-macos-parity-0.72.0.md): the
  0.70.0 through 0.72.0 delta with the Muse, LithosAI, and WorkBuddy
  registry additions (90 records, same keys) and their cookie-only
  macOS-gated Linux reachability, the Claude manual-`sessionKey` runtime
  opening verified before and after, unchanged cost and usage envelopes
  with the still year-1 `--period all` day count, empty-config tolerance,
  and bubblewrap-isolated official CLI probes. Provider descriptors,
  generic config actions, Cursor cost, and display currency remain
  unavailable.
- [0.73.0 release review](research/2026-10-07-macos-parity-0.73.0.md): verified
  persistent provider-source writes, the 91-provider registry and Langdock's
  macOS-only reachability, ClinePass labeled-write rejection, unchanged empty
  cost/usage envelopes, and scoped bubblewrap-isolated official CLI probes.
  Distinguishes private Linux desktop snapshots from standard CLI usage and
  carries the unverified reset-credit and partial-priced output candidates.
- [0.74.0 release review](research/2026-10-11-macos-parity-0.74.0.md): the
  100-provider registry with nine bundled-plugin additions and their Linux
  setup reachability, subscription renewal/expiration dates verified in Linux
  usage output through a loopback fixture, the Cursor `cursor-agent` login
  opening and its intermittent offline stall, unchanged account enumeration,
  and `serve` account discovery, with bubblewrap-isolated official CLI
  probes. Provider descriptors, generic config actions, Cursor cost, and
  display currency remain unavailable.
- [0.74.1 release review](research/2026-10-14-macos-parity-0.74.1.md): the
  OpenCode Go estimated-confidence mismatch verified with isolated local
  history and the Plasma normalizer, xAI generic detail-row compatibility,
  CLI-owned Command Code fixes, unchanged registry/help and empty envelopes,
  and carried blockers rechecked with bubblewrap-isolated official binaries.
- [0.75.0 release review](research/2026-10-15-macos-parity-0.75.0.md): the
  103-provider registry, Command Code/fal API-key reachability, FLORA workspace
  and Parallel cookie blockers, identified-cost failure semantics, source-only
  throughput changes, and bubblewrap-isolated carried-blocker checks.
- [0.76.0 release review](research/2026-10-15-macos-parity-0.76.0.md): the
  104-provider registry and Claude Platform's blocked Linux cookie setup,
  stable concurrent usage order, notice-archive compatibility, fast-probe
  verification, and carried blockers rechecked with the isolated official CLI.
- [0.77.0 release review](research/2026-10-17-macos-parity-0.77.0.md): the
  106-provider registry, Munito API-key reachability, Future AGI's
  environment-only secret, the Linux Gemini Auto regression, the disabled
  app-cache fallback, installer compatibility, and carried blockers rechecked
  with the isolated official CLI.
- [0.79.0 release review](research/2026-10-21-macos-parity-0.79.0.md): the
  0.78.0/0.79.0 delta, verified OpenCode Go costs and detail severity, remaining
  custom-provider routing failure, Vercel setup blocker, libxml2 removal,
  installer compatibility, and isolated carried-blocker checks. Detail-row
  severity presentation was implemented after that review.
- [0.80.0 release review](research/2026-10-23-macos-parity-0.80.0.md): the
  108-provider registry, Soniox key setup, the Copilot `config login` command,
  the verified musl Codex cost fix, the daily-target comparison, installer
  compatibility, and isolated carried-blocker checks. Soniox key setup was
  implemented after that review.
- [0.81.0 release review](research/2026-10-25-macos-parity-0.81.0.md): the
  110-provider registry, abliteration.ai and Chatbox AI key setup, the
  per-strategy Linux Auto gate with the fixed Gemini Auto regression, plugin
  window titles, and isolated carried-blocker checks. The two new key setups
  were implemented after that review.
- [0.82.0 release review](research/2026-10-27-macos-parity-0.82.0.md): the
  `config set-cookie` and `clear-credential` writers, which providers accept a
  manual cookie and which still fail on Linux, and isolated carried-blocker
  checks.
- [0.83.0 release review](research/2026-11-01-macos-parity-0.83.0.md): the
  111-provider registry with OpenDesign, the inventory `authentication` record
  checked against the writers, the identified Codex ledger schema 2 that the
  reviewed widget rejected, and isolated carried-blocker checks. Schema 1/2
  support was implemented after that review.
- [0.84.0 release review](research/2026-11-10-macos-parity-0.84.0.md): the
  113-provider registry, SiliconFlow/Tripo key-setup gaps, Claude Platform
  stdin-login validation, WorkBuddy cookie setup and User-Agent/regional-origin
  writer blockers, Codex
  ordinary symlinked-history fix, remaining identified-history discovery bug,
  schema 2 compatibility, OpenCode Go unavailable costs, and scoped
  carried-blocker checks.
- [0.75.0 Codex contract verification](research/2026-10-15-codex-contracts-0.75.0.md):
  synthetic native partial-priced cost output, identified-request local/remote
  merge and failure semantics, authoritative reset-credit inventory, and the
  seeded historical-pricing output and remaining import verification limits.
- [0.76.0 Claude detail contract](research/2026-10-15-claude-details-0.76.0.md):
  official Linux output for percentage-only resets and pace through an isolated
  synthetic Claude CLI, plus separate authenticated CLI/OAuth observations and
  exhausted-window forecast semantics.
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
  [runtime verification](runtime-verification.md#runtime-verification).
- [Overview](codexbar-plasma-overview.png)
- [Provider details](codexbar-plasma-codex.png)
- [Hidden usage rows](codexbar-plasma-hidden-usage-rows.png): synthetic provider tab showing the inline restore list.
- [Usage and spend](codexbar-plasma-usage-spend.png)
- [Model breakdowns](codexbar-plasma-models.png): synthetic native expanded
  Usage & Spend with provider rows opened to their inline model lists.
- [Daily activity](codexbar-plasma-daily-activity.png): synthetic native calendar
  with month labels and a day selected in the chart and provider details.
- [Chart hover inspection](codexbar-plasma-chart-hover.gif): synthetic native
  chart recording showing provider icons and previews switching sides.
- [Shared usage card](codexbar-plasma-share.png): synthetic local PNG summary,
  with the provider token-share bar, separate provider/model rows, and the
  repository attribution.
- [Usage-sharing window](codexbar-plasma-share-window.png): synthetic aggregate
  preview with native export and window controls.
- [Sessions](codexbar-plasma-sessions.png)
- [Provider colors panel](codexbar-plasma-panel-standard.png): contrast-adjusted colored provider icons and outlined dual quota capsules.
- [Monochrome panel](codexbar-plasma-panel-minimal.png): monochrome provider icons and dual quota capsules.
- [Panel with usage text](codexbar-plasma-panel-information.png): selected-provider text grouped with its quota capsules.

## Store artwork

- [Store icon PNG](codexbar-plasma-store-icon.png): 512 × 512 image for the KDE Store listing.
- [Store icon SVG](codexbar-plasma-store-icon.svg): editable source for the store icon.

## Historical work artifacts

Past captures, completed plans, and review logs are available in
[Git history before the cleanup](https://github.com/Lucenx9/codexbar-plasma/tree/92679f99ce5d5479f4f87edde051fff91e30b91f/docs).
New temporary artifacts go in ignored `dist/review/` or the OS temp directory.
PRs record verification results; this index records documents worth maintaining.
