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
- [Translations](translations.md): adding and checking a language catalog.
- [CLI 0.56.2 parity baseline](research/2026-09-01-macos-parity-0.56.2.md):
  verified official Linux contracts at that comparison date. The
  [usage guide](usage.md) describes current Plasma behavior; later scoped checks
  in the cost and settings documents do not replace this full audit.
- [0.57.0 release review](research/2026-09-09-macos-parity-0.57.0.md): Linux-relevant
  changes since 0.56.2, current Plasma gaps, and scoped official CLI probes.
- [Settings decisions](research/2026-09-08-settings-experience.md): Panel disclosure and text grouping,
  Plasma settings, privacy, refresh behavior, and the macOS 0.56.8 comparison.

## Earlier CLI evidence

These small reports preserve version-specific evidence used by later audits.
They are historical comparisons, not current feature plans. Preserve their
original findings; a new audit names the report it supersedes and its exact
versions. Current guides describe implemented recommendations; TODO lists
remaining Linux work.

- [0.49.1](research/2026-08-10-macos-parity-progress.md)
- [0.49.6](research/2026-08-15-macos-parity-0.49.6.md)
- [0.50.0](research/2026-08-16-macos-parity-0.50.0.md)
- [0.54.0](research/2026-08-20-macos-parity-0.54.0.md)
- [0.55.0](research/2026-08-24-macos-parity-0.55.0.md)

## Product screenshots

These synthetic captures appear in the project README or usage guide. The README
captures are also included in the widget package. Replace the relevant image
when the product changes instead of adding dated before/after copies.

- [Overview](codexbar-plasma-overview.png)
- [Provider details](codexbar-plasma-codex.png)
- [Usage and spend](codexbar-plasma-usage-spend.png)
- [Sessions](codexbar-plasma-sessions.png)
- [Standard panel](codexbar-plasma-panel-standard.png): colored provider icons and dual quota capsules.
- [Minimal panel](codexbar-plasma-panel-minimal.png): monochrome provider icons and dual quota capsules.
- [Panel with usage text](codexbar-plasma-panel-information.png): selected-provider text grouped with its quota capsules.

## Historical work artifacts

Past captures, completed plans, and review logs are available in
[Git history before the cleanup](https://github.com/Lucenx9/codexbar-plasma/tree/92679f99ce5d5479f4f87edde051fff91e30b91f/docs).
New temporary artifacts go in ignored `dist/review/` or the OS temp directory.
PRs record verification results; this index records documents worth maintaining.
