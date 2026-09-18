# Linux parity review at CodexBar 0.60.5

Checked 2026-09-18 against Plasma commit
[`c69b0a0`](https://github.com/Lucenx9/codexbar-plasma/commit/c69b0a0481bbf2373087658f620e0ffeab854429).
The macOS reference is official
[`v0.60.5`](https://github.com/steipete/CodexBar/releases/tag/v0.60.5),
commit [`2ac2323629ce0e3b3759707013aeb4a6c77161c1`](https://github.com/steipete/CodexBar/commit/2ac2323629ce0e3b3759707013aeb4a6c77161c1),
published 2026-09-17 at 21:49:35 UTC.

This is a release-delta review for useful Linux behavior. It covers the single
stable release published after the
[0.60.4 review](2026-09-16-macos-parity-0.60.4.md) and does not repeat the full
[0.56.2 contract audit](2026-09-01-macos-parity-0.56.2.md). Current open parity
work belongs in [TODO.md](../../TODO.md).

## Release coverage

| Release | Published | Commit | Linux-relevant observations |
| --- | --- | --- | --- |
| [0.60.5](https://github.com/steipete/CodexBar/releases/tag/v0.60.5) | 2026-09-17 | `2ac2323629ce0e3b3759707013aeb4a6c77161c1` | Cost JSON gains incomplete-request counts at every level; Codex catch-up publishes validated windows while retaining prior data; Claude proxy estimates without final usage are excluded instead of priced; Copilot seat credits back a macOS switcher percentage; Cursor Enterprise member budgets, Kimi ratio pools, OpenCode Go monthly picker, Antigravity foreign-database skipping. |

## Linux CLI contract changes since 0.60.4

Compared `937b208...2ac2323` under `Sources/CodexBarCLI/` (4 files) and the
consumed Core payload models.

- **Cost incomplete-request counts (new contract, verified in emitted output).**
  `CostPayload`, `CostTotalsPayload`, `CostDailyEntryPayload`, and
  `CostModelBreakdownPayload` each gain `incompleteRequestCount: Int?`. The key
  is encoded only when greater than zero, so an absent key means "none
  reported", and combined counts saturate instead of overflowing
  (`CostUsageIncompleteRequests.sum`). An incomplete request is one that lacked
  final usage; the CLI excludes it from that day's tokens and cost and reports
  the count instead. This is the first change to the cost JSON schema since the
  0.56.2 baseline.
- **Only-incomplete days stay unknown, not zero.** A day whose requests are all
  incomplete keeps `date`, `modelsUsed`, and `modelBreakdowns` but omits
  `totalCost` and `totalTokens`; the model breakdown omits `cost` and
  `totalTokens` too. Upstream text renders that day as `— · — tokens ·
  Incomplete`. Plasma's `normalizeCostDaily` already drops a daily record with
  no cost, tokens, or token parts and blocks calendar filling for that date, so
  the day is treated as unknown rather than as a measured zero. The count
  itself is not consumed yet.
- **`serve` dashboard only.** `DashboardCostPayload` gains
  `todayIncompleteRequestCount` and `last30DaysIncompleteRequestCount`. Plasma
  does not consume `serve`.
- **Usage JSON envelope unchanged.** No new keys on usage, credits, identity,
  or detail rows. `CopilotProviderDescriptor` now reads the existing
  `copilot-seat-credits` detail row's `progress` as a macOS switcher
  used-percent fallback, which is presentation over the detail-row fields that
  are still source-observed only. This strengthens the existing verification
  candidate without adding a contract.
- **No config contracts.** `config providers --descriptors` is still rejected,
  `set-api-key` remains the sole writer, and the provider list is unchanged.
- **Provider internals.** Kimi ratio-pool decoding, Cursor team-spend budgets,
  Antigravity `gen_metadata` schema classification
  (`supported`/`foreign`/`unsupported`), and the Claude recovered-session error
  text are fetcher-side. The Claude error strings stay opaque display text.

## 0.60.5 features against existing Plasma behavior

- **Incomplete cost requests.** New useful Linux work: the widget can mark a
  partial day, total, and model row instead of presenting an amount that
  silently excludes requests. Generic, bounded, and already emitted on Linux.
  Recorded in TODO as implementable.
- **Codex validated catch-up windows (#3669).** Store-side publication and
  retention. Plasma consumes the published payload and already retains prior
  cost data; no frontend change.
- **Claude cost corrections (#3684, #3688).** Long-context pricing boundaries
  and estimate rebuilds are CLI-owned values inside the existing schema, except
  for the incomplete counts above.
- **Cursor Enterprise member budgets (#3646) and unconfirmed-credential retry
  stop (#3703).** Fetcher-side; Cursor cost is still rejected on Linux, so no
  Plasma path changes.
- **Kimi ratio-pool quotas (#3697).** Provider decoding that flows through the
  generic quota fields. No new contract.
- **Copilot seat credits in provider tabs (#3681).** macOS switcher
  presentation over detail-row progress. Plasma keeps its own automatic
  selection; the underlying numeric row stays an unverified Linux candidate.
- **OpenCode Go monthly picker (#3645) and Codex System Account redaction
  (#3702).** macOS menu-bar picker and menu labels. Automatic selection and
  privacy are frontend-owned on Plasma, which already hides personal
  information in its own surfaces. Excluded.
- **Antigravity foreign-database skipping (#3699) and CSRF-gated readiness
  (#3685).** Local-source robustness inside the CLI. No Plasma change.
- **Sharing dates and captions (#3692, #3706), Sparkle staged updates (#3693),
  Homebrew copy button (#3686), keychain symlink recognition (#3690), SSH
  username case (#3700).** macOS app, updater, or CLI-internal. Excluded; the
  sessions change affects CLI-side deduplication only.

## Scoped official Linux probes

The official `CodexBarCLI-v0.60.5-linux-x86_64.tar.gz` asset passed the
release's SHA-256 check:
`2700156a941547cc75d79cfdffd35bec5c0332ea49c5a1c301479abc662c43d8`.
Assets and checksum are on the
[official release](https://github.com/steipete/CodexBar/releases/tag/v0.60.5).

Probes ran inside a network-isolated Bubblewrap process with temporary home,
configuration, cache, and data roots, a cleared environment, and no host
credentials reachable. No installed CLI was replaced. The extracted asset
reports `CodexBar 0.60.5`.

Two synthetic Claude project logs supplied the cost cases: a priced request
with output and cache tokens, and requests with `stop_reason: null`,
`input_tokens > 0`, no output, and no cache keys, which the scanner classifies
as incomplete.

| Probe | Result |
| --- | --- |
| `cost --provider claude --format json --json-only` (mixed day) | Exit 0; `incompleteRequestCount` present at top level, in `totals`, in the daily entry, and per model breakdown. The day reports only the complete request's cost and tokens. |
| `cost --provider claude --format json --json-only --pretty` (only-incomplete day) | Exit 0; that day omits `totalCost` and `totalTokens`, keeps `date`, `modelsUsed`, `modelBreakdowns`, and reports `incompleteRequestCount: 1`. |
| `cost --provider claude --breakdown` | Exit 0; `· Incomplete` markers on today, the window, daily rows, and model rows, plus `Incomplete: N requests lacked final usage and were excluded from tokens and cost.` |
| `cost --provider codex --format json --json-only` | Exit 0; empty history, `historyCoverageIsEstablished: true`, no `incompleteRequestCount` key. |
| `cost --provider antigravity --format json --json-only` | Exit 0; empty daily/projects, no cost totals, `historyCoverageIsEstablished: false`. Unchanged shape. |
| `cost --provider cursor --format json --json-only` | Exit 1, `cost is only supported for Antigravity, Claude, Codex.` |
| `cost --help` | Unchanged flags; no availability or tier options. |
| `config providers --format json --json-only` | Exit 0; 69 records, keys `provider`, `displayName`, `enabled`, `defaultEnabled`. |
| `config providers --descriptors --format json --json-only` | Exit 1, `error.kind: args`, `Unknown option --descriptors`. |
| `config --help` | Existing commands only; `set-api-key` remains the sole writer. |
| `usage --provider claude --format json --json-only` | Exit 1, `No available fetch strategy for claude.` Envelope keys unchanged. |
| `sessions --json-v2` | Exit 0, empty array in the isolated account. |

No authenticated usage, credit validity, workspace balances, Copilot seat rows,
Antigravity progress rows, service tiers, or display-currency behavior was
exercised. Those limitations remain explicit in TODO.

## Carried-forward blockers

Every blocker in TODO remains open. 0.60.5 adds no provider settings
descriptor, generic config action, Cursor cost support, service-tier field,
structured localization identifier, or display-currency contract. The cost
availability blocker keeps its remaining scope: the new counts explain requests
excluded from a measured amount, while an established-empty history with
unavailable costs still reports zero without metadata.
