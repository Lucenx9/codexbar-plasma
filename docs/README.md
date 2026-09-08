# Documentation

The repository keeps maintained documentation and current product screenshots.
The documentation policy is in [AGENTS.md](../AGENTS.md#documentation-hygiene).
Every file under `docs/` is listed below so new material has an explicit purpose.
Open work lives in [GitHub Issues](https://github.com/Lucenx9/codexbar-plasma/issues);
the guides describe supported behavior. Agents maintain both through the
[documentation workflow](development.md#documentation-and-work-tracking).

## Maintained references

- [Usage and settings](usage.md): panel and popup options, provider setup,
  cost history, notifications, and widget defaults.
- [Development](development.md): QML ownership, regression checks, runtime
  verification, and maintenance of agent instructions. Read before code or
  tooling changes.
- [Provider settings descriptor](cli-provider-settings-descriptor.md): proposed
  upstream CLI contract for generic settings. It is not a shipped contract.
- [Cost history](cost-history.md): daily model data, selection behavior, and
  the pinned Linux CLI evidence behind the popup.
- [Translations](translations.md): adding and checking a language catalog.
- [CLI 0.56.2 parity baseline](research/2026-09-01-macos-parity-0.56.2.md):
  verified official Linux contracts at that comparison date. The
  [usage guide](usage.md) describes current Plasma behavior; later scoped checks
  in the cost and settings documents do not replace this full audit.
- [Settings decisions](research/2026-09-08-settings-experience.md): Plasma
  settings, privacy, refresh behavior, and the macOS 0.56.8 comparison.

## Earlier CLI evidence

These small reports preserve version-specific evidence used by later audits.
They are historical comparisons, not current feature plans. Preserve their
original findings; a new audit names the report it supersedes and its exact
versions. Completed recommendations are tracked in issues and current guides.

- [0.49.1](research/2026-08-10-macos-parity-progress.md)
- [0.49.6](research/2026-08-15-macos-parity-0.49.6.md)
- [0.50.0](research/2026-08-16-macos-parity-0.50.0.md)
- [0.54.0](research/2026-08-20-macos-parity-0.54.0.md)
- [0.55.0](research/2026-08-24-macos-parity-0.55.0.md)

## Product screenshots

These synthetic captures appear in the project README and the widget package.
Replace the relevant image when the product changes instead of adding dated
before/after copies.

- [Overview](codexbar-plasma-overview.png)
- [Provider details](codexbar-plasma-codex.png)
- [Usage and spend](codexbar-plasma-usage-spend.png)
- [Sessions](codexbar-plasma-sessions.png)
- [Standard panel](codexbar-plasma-panel-standard.png)
- [Minimal panel](codexbar-plasma-panel-minimal.png)

## Historical work artifacts

Past captures, completed plans, and review logs are available in
[Git history before the cleanup](https://github.com/Lucenx9/codexbar-plasma/tree/92679f99ce5d5479f4f87edde051fff91e30b91f/docs).
New temporary artifacts go in ignored `dist/review/` or the OS temp directory.
PRs record verification results; this index records documents worth maintaining.
