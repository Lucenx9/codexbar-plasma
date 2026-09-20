# Linux parity review at CodexBar 0.62.0

Checked 2026-09-20 against Plasma commit
[`9205e51`](https://github.com/Lucenx9/codexbar-plasma/commit/9205e518a6b0eba78894386ff8dad5a308305bfb).
The macOS reference is official
[`v0.62.0`](https://github.com/steipete/CodexBar/releases/tag/v0.62.0),
commit [`4b3ed1a2a49a545522fb10196ff420526d85784a`](https://github.com/steipete/CodexBar/commit/4b3ed1a2a49a545522fb10196ff420526d85784a),
published 2026-09-19 at 20:56:00 UTC.

This is a release-delta review for useful Linux behavior. It covers the single
stable release published after the
[0.61.0 review](2026-09-18-macos-parity-0.61.0.md) and does not repeat the full
[0.56.2 contract audit](2026-09-01-macos-parity-0.56.2.md). Current open parity
work belongs in [TODO.md](../../TODO.md).

## Release coverage

| Release | Published | Commit | Linux-relevant observations |
| --- | --- | --- | --- |
| [0.62.0](https://github.com/steipete/CodexBar/releases/tag/v0.62.0) | 2026-09-19 | `4b3ed1a2a49a545522fb10196ff420526d85784a` | `cost --provider muse` reports local Muse session token history with monetary fields absent; `cost` gains Codex-only `--remote` and `--summary-only` modes; hooks gain the `usage_updated` event; cost aggregation nils out invalid totals instead of emitting them; usage, sessions, and config JSON envelopes are otherwise unchanged; the registry stays at 74 providers. |

## Linux CLI contract changes since 0.61.0

Compared `60a677e...4b3ed1a` (50 changed files) under `Sources/CodexBarCLI/`,
`Sources/CodexBarCore/`, and the consumed payload models.

- **Muse token history is a supported cost contract (verified in emitted
  output).** `MuseProviderDescriptor` sets `supportsCostCommand` with a
  tokens-only presentation, and `CostUsageFetcher` serves `cost --provider muse`
  from local Muse CLI session logs. The probe below counted a synthetic
  `model_completed` turn exactly (1000 input + 500 output = 1500 tokens) while
  every monetary field stayed absent. Plasma needs no code change: its cost
  controller already queries the selected provider and the generic
  daily/model normalization keeps absent amounts unknown, the same path that
  already renders Antigravity token-only history. The [usage
  guide](../usage.md#costs-and-history) now documents Muse alongside
  Antigravity.
- **Cost aggregation keeps invalid totals out of JSON (source-observed).**
  Model-breakdown and daily accumulators now emit `totalTokens`/`costUSD` only
  when the inputs are finite, non-negative, and complete; a day whose requests
  are all incomplete still arrives without those keys. This matches the
  existing Plasma normalization, which keeps missing amounts unknown instead
  of turning them into measured zeros. Standard empty-history probes print the
  same established-zero shapes as 0.61.0.
- **Codex-only `--remote` and `--summary-only` cost modes (`--summary-only`
  verified, `--remote` source-observed).** `--summary-only` emits a versioned
  (`schemaVersion: 1`) `CodexCostSummary` without account or session details.
  `--remote <ssh-host>` is built to return separate local and SSH-host
  summaries without adding overlapping histories together, but no successful
  SSH run was exercised: the isolated probe only verified that an invalid
  host fails closed with an args error before any SSH attempt. Both modes
  reject any other provider, `--group-by`, and `--breakdown`. Plasma
  has no multi-host concept, so these stay available CLI features with no
  frontend work tracked.
- **`usage_updated` hook event (verified in help).** `hooks watch` can emit it
  on the first successful poll and reports only events whose command execution
  was attempted. Plasma does not manage hook rules, so this is CLI surface
  with no frontend contract.
- **No new usage, sessions, or config JSON keys.** `hourly` and `quotaSlices`
  enrich the in-process cost snapshot only; neither type is `Codable`, so the
  emitted cost JSON keeps its 0.61.0 keys. `widgetAccountOwnerID` is
  explicitly excluded from `ProviderIdentitySnapshot` coding keys, and the CLI
  usage path never sets `includeAccountIdentity`, so usage JSON is unchanged.
  `config --help` lists the same commands with `set-api-key` as the sole
  writer; Cursor cost is still rejected, with the message now naming Muse Code
  among the supported providers.
- **Quota-week cost dashboards are computed in-process (source-observed).**
  Codex and Claude menu cards split local cost by live Weekly quota windows
  from existing reset metadata plus the local history above; no new emitted
  field backs them. A Plasma-native equivalent is tracked in TODO as
  implementable work with no CLI blocker.
- **macOS-only.** Overview Detailed/Compact layout, Usage & Spend snapshot
  sharing, per-section Visible usage items, pinned Account Usage widgets,
  Warp terminal default, and Codex cost-cache repair are app-surface or
  fetcher-side changes with no emitted-shape change.

## Scoped official Linux probes

The official `CodexBarCLI-v0.62.0-linux-x86_64.tar.gz` asset passed the
release's SHA-256 check:
`11b88fef999f18cd7fd8b52e52a7fb3eb90e84eaf9fc98a1d4bc5d4170353513`.
Assets and checksum are on the
[official release](https://github.com/steipete/CodexBar/releases/tag/v0.62.0).

Probes ran inside a network-isolated Bubblewrap process with temporary home,
configuration, cache, and data roots, a cleared environment, and no host
credentials reachable. No installed CLI was replaced. A synthetic
`$MUSE_SESSIONS_DIR` tree held one `model_completed` turn (1000 in / 500 out)
plus one ignored telemetry record. The extracted asset reports
`CodexBar 0.62.0`.

| Probe | Result |
| --- | --- |
| `--version` | `CodexBar 0.62.0`. |
| `config providers --format json --json-only` | Exit 0; still 74 records with keys `provider`, `displayName`, `enabled`, `defaultEnabled`, including the five 0.61.0 IDs. |
| `config providers --descriptors --format json --json-only` | Exit 1, `error.kind: args`, `Unknown option --descriptors`. |
| `config --help` | Same commands; `set-api-key` remains the sole writer. |
| `cost --provider muse --format json --json-only` | Exit 0; `sessionTokens`/`last30DaysTokens` 1500, daily entry and model breakdown carry token counts only, `coverage.unpriced: 1`, `historyCoverageIsEstablished: true`, no monetary key anywhere. |
| `cost --provider codex --format json --json-only` | Exit 0; established-empty zero shape, keys unchanged from 0.61.0. |
| `cost --provider claude --format json --json-only` | Exit 0; established-empty zero shape, keys unchanged. |
| `cost --provider cursor --format json --json-only` | Exit 1, cost still supported only for Antigravity, Claude, Codex, and Muse Code. |
| `cost --provider codex --summary-only --format json --json-only` | Exit 0; `schemaVersion: 1`, per-window `totalTokens`/`costUSD`/`incompleteRequestCount`/`coverage`/`provenance`, no account or session details. |
| `cost --provider codex --remote 'bad host!' --format json --json-only` | Exit 1, `Enter one SSH host alias or user@host.` with no SSH attempt. |
| `usage --provider claude --format json --json-only` | Exit 1, `No available fetch strategy for claude.` Envelope keys unchanged. |
| `usage --provider codex --status --format json --json-only` | Status block plus fetch error; envelope keys unchanged. |
| `sessions --json-v2` | Exit 0, empty array in the isolated account. |
| `cost --help` / `hooks --help` | Document `--remote`, `--summary-only`, `cost --provider muse`, and the `usage_updated` event. |

No authenticated usage was exercised. The Grok reset-credit detail row,
Mistral and Venice allowances, Hugging Face ZeroGPU quota, workspace balances,
Copilot seat rows, Antigravity progress rows, service tiers, and
display-currency behavior remain unverified in emitted output. Those
limitations stay explicit in TODO.

## Carried-forward blockers

Every blocker in TODO remains open. 0.62.0 adds no provider settings
descriptor, generic config action, Cursor cost support, service-tier field,
structured localization identifier, or display-currency contract. Muse token
history arrives through the existing generic cost envelope, so it resolves no
blocker and adds none.
