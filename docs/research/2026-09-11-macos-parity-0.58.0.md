# Linux parity review at CodexBar 0.58.0

Checked 2026-09-11 against Plasma commit
[`59cbc89b168c9cc665589a6856102275be929e9e`](https://github.com/Lucenx9/codexbar-plasma/commit/59cbc89b168c9cc665589a6856102275be929e9e).
The macOS reference is official
[`v0.58.0`](https://github.com/steipete/CodexBar/releases/tag/v0.58.0),
commit [`88fa2f45fa1e7e04c3c96234ddf973ca947208db`](https://github.com/steipete/CodexBar/commit/88fa2f45fa1e7e04c3c96234ddf973ca947208db),
published 2026-09-10 at 04:06:38 UTC.

This is a release-delta review for useful Linux behavior. It covers published
stable releases after the [0.57.0 review](2026-09-09-macos-parity-0.57.0.md)
through 0.58.0, with targeted source inspection and scoped CLI probes. It does
not repeat the full 0.56.2 contract audit. Current open parity work belongs in
[TODO.md](../../TODO.md).

## Release coverage

The official release list contained only 0.58.0 after 0.57.0 on the review
date.

| Release | Linux-relevant observations |
| --- | --- |
| [0.58.0](https://github.com/steipete/CodexBar/releases/tag/v0.58.0) | macOS daily spend ledger, chart hover details, visible-row selection, percent-window and reset-layout pickers, and account reset labels. No Linux CLI payload code changed. Cost scanner fixes benefit Linux output unchanged. |

## No Linux CLI payload changes

The [0.57.0…0.58.0 comparison](https://github.com/steipete/CodexBar/compare/45cda6084d6415795053624b80ca3f8c05026580...88fa2f45fa1e7e04c3c96234ddf973ca947208db)
modifies no file under `Sources/CodexBarCLI/`. The emitted JSON contracts for
`usage`, `cost`, `sessions`, and `config` are therefore unchanged from the
[0.56.2 audit](2026-09-01-macos-parity-0.56.2.md) and scoped 0.57.0 probes.
Core-side changes stay CLI-owned: Codex local-cost subagent boundary and cache
revision fixes, OpenCodex full-history aggregation, and `UsageFormatter` token
rounding (`1000K` to `1M`) that affects text rendering, not JSON numbers.

[`ProviderConfig`](https://github.com/steipete/CodexBar/blob/88fa2f45fa1e7e04c3c96234ddf973ca947208db/Sources/CodexBarCore/Config/CodexBarConfig.swift)
gains `hiddenUsageItemIDs` for macOS visible-row preferences, and
[`ProviderConfig+FetchIdentity`](https://github.com/steipete/CodexBar/blob/88fa2f45fa1e7e04c3c96234ddf973ca947208db/Sources/CodexBar/Config/ProviderConfig+FetchIdentity.swift)
strips display-only fields from cache identity. The isolated probe below shows
the Linux `config providers` record still carries only `provider`,
`displayName`, `enabled`, and `defaultEnabled`; the new field is not emitted,
so it is not a Linux contract.

## 0.58.0 features against existing Plasma behavior

- **Daily spend ledger (#2635).** macOS
  [`SpendDashboardModel`](https://github.com/steipete/CodexBar/blob/88fa2f45fa1e7e04c3c96234ddf973ca947208db/Sources/CodexBar/SpendDashboardModel.swift)
  computes `DailySummary` rows from existing snapshot optionals
  (`totalTokens`, `requestCount`, `totalCost`), a display calendar, and
  `historyCoverageIsEstablished`. Plasma already renders interactive daily
  cost/token charts with explicit day selection from the same generic fields.
  The unknown-versus-zero distinction remains presentation over existing data;
  the unavailable-cost blocker in TODO still needs its established-empty CLI
  case verified.
- **Chart hover details (#3413).** Plasma charts are already interactive with
  per-day detail on inspection. No new contract or work.
- **Visible usage rows (#3196, #3182).** macOS hides menu-card rows per
  provider through `hiddenUsageItemIDs`. Plasma already chooses visible panel
  rows natively with panel visibility rules, ordering, the settings preview,
  and Overview, all local to the widget. The new provider-config field is not
  emitted to Linux consumers, so there is nothing to sync.
- **Percent-window picker (#3124).**
  [`MenuBarPercentWindowPreference`](https://github.com/steipete/CodexBar/blob/88fa2f45fa1e7e04c3c96234ddf973ca947208db/Sources/CodexBar/MenuBarPercentWindowPreference.swift)
  rewrites the app-local menu-bar layout. Plasma exposes explicit per-provider
  quota lane selection (`panelQuotaLane`) covering the same session/weekly
  choice. Existing native behavior.
- **Reset countdown/clock layout tokens (#3481).** macOS adds window-selectable
  reset tokens to menu-bar layouts. The Plasma panel already has a reset-time
  element with countdown and absolute display
  (`resetTimesShowAbsolute`) beside explicit quota lanes. Existing native
  behavior.
- **Account rows with reset times (#3477).** macOS compact account menu rows
  gain reset labels. Plasma popup quota rows already show reset times per
  window, while the account list is a selector by design. No useful gap.

## Scoped official Linux probes

The official `CodexBarCLI-v0.58.0-linux-x86_64.tar.gz` asset passed the
release's SHA-256 check:
`a327f8428fc8d2fd8707f2deab4e082a209f90707b7cfa91e1a2a6d4420dcb10`.
Assets and checksum are on the [official release](https://github.com/steipete/CodexBar/releases/tag/v0.58.0).

Probes ran inside a network-isolated Bubblewrap process with temporary home,
configuration, cache, data, Claude, and Codex roots, a cleared environment, and
no host credentials reachable. No installed CLI was replaced. Running the bare
binary without its adjacent bundle prints only `CodexBar`; executed from the
extracted asset it reports `CodexBar 0.58.0`, which the probes used.

| Probe | Result |
| --- | --- |
| `config providers --format json --json-only` | Exit 0; 69 records, keys `provider`, `displayName`, `enabled`, `defaultEnabled`. No descriptor, `hiddenUsageItemIDs`, or `accentColor` emitted. |
| `config providers --descriptors --format json --json-only` | Exit 1, `Unknown option --descriptors`. The descriptor remains unavailable. |
| `config --help` | Lists existing config commands, with no generic `set` or `action`; `set-api-key` only. |
| `cost --provider cursor --format json --json-only` | Exit 1; supported list remains Antigravity, Claude, Codex. |
| `cost --provider claude --format json --json-only` | Exit 0; empty history with `historyCoverageIsEstablished: true` and measured zeros. A fresh scan of empty roots is genuinely zero; it does not retest the unavailable-cost established-empty case. |
| `cost --provider antigravity --format json --json-only` | Exit 0; empty daily/projects, no cost totals, matching the 0.57.0 fresh-history shape. |
| `sessions --json-v2` | Exit 0, empty array in the isolated account. |

No authenticated usage, credit validity, account switching, provider balance
units, or nonempty cost history was exercised. Those limitations remain
explicit in TODO; this is not a replacement for the full 0.56.2 audit.

## Carried-forward blockers

Every blocker in TODO remains open. No 0.58.0 change adds a provider settings
descriptor, generic config action, Cursor cost support, service-tier fields,
cost availability metadata beyond `historyCoverageIsEstablished`, structured
localization identifiers, or a display-currency contract. The scoped 0.58.0
probes re-verify the descriptor rejection, the absent generic config commands,
and the Cursor cost rejection at this version. The [0.56.2 audit](2026-09-01-macos-parity-0.56.2.md)
remains the contract baseline for unprobed authenticated cases.
