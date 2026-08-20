# CodexBar macOS parity at 0.54.0

Checked 2026-08-20. Read-only comparison of the official `steipete/CodexBar`
product against the Plasma baseline. Supersedes
[`2026-08-16-macos-parity-0.50.0.md`](./2026-08-16-macos-parity-0.50.0.md).

## Pinned scope

| Reference | Exact revision | Date |
| --- | --- | --- |
| Plasma baseline | local [`a30e4ea8ed37de4e9e63438876998abca7cfb8a5`](https://github.com/Lucenx9/codexbar-plasma/commit/a30e4ea8ed37de4e9e63438876998abca7cfb8a5) plus the change that ships this report | 2026-08-20 |
| Official baseline | [`v0.54.0`](https://github.com/steipete/CodexBar/releases/tag/v0.54.0), commit [`22a2168842a9ed4fdd15dd6761cd109c56bcd3b5`](https://github.com/steipete/CodexBar/commit/22a2168842a9ed4fdd15dd6761cd109c56bcd3b5) | published 2026-08-20 13:51 UTC |
| Previous pinned baseline | `v0.50.0`, commit `0e453c4a5b2a13ce69f5400190e62a630e3b4240` | 2026-08-15 |
| Installed Linux CLI | `codexbar` **0.54.0**, official Linux x86_64 release asset | probed 2026-08-20 |

v0.54.0 is the latest upstream release at the time of writing. Every CLI claim
below is a live probe of the exact installed binary; macOS-only claims come from
the pinned release notes and tagged sources.

## Verdict

The provider-settings boundary is unchanged: the released CLI still has no
machine-readable settings/action descriptor, `config set`, or `config action`.
The generic Providers page must keep its current fallback.

The important change is in `codexbar cost`. Since 0.50.0 the contract has added
explicit cost `coverage`, `provenance`, and project breakdown inputs.
The Plasma widget currently ignores those fields, so its totals can look more
definitive than the CLI contract says they are. This is now the highest-value
CLI-backed parity gap. Project rows are also implementable, provided the
frontend discards the emitted local `path` just as the Sessions normalizer does.

The macOS conditional menu-bar tokens, direct usage-lane tokens, and pace
visibility setting are presentation features over data Plasma already has.
They are candidates for a Plasma-native design, not contracts to port from
Swift. Provider catalog coverage remains unchanged at 69 IDs.

## Live CLI probes

```text
$ codexbar --version
CodexBar 0.54.0

$ codexbar config providers --format json --json-only | jq 'length'
69

$ codexbar config providers --format json --json-only \
    | jq -r '[.[] | keys] | add | unique | join(", ")'
defaultEnabled, displayName, enabled, provider

$ codexbar config providers --descriptors --format json --json-only
[{"provider":"cli","error":{"message":"Unknown option --descriptors","code":1,"kind":"args"},"source":"cli"}]
```

`codexbar config --help` still exposes only `validate`, `dump`, `providers`,
`enable`, `disable`, and `set-api-key`. There is no generic field writer or
action runner.

The cost payload has expanded:

```text
$ codexbar cost --days 7 --format json --json-only \
    | jq -r '[.[] | keys] | add | unique | join(", ")'
coverage, currencyCode, daily, historyCoverageIsEstablished, historyDays,
last30DaysCostUSD, last30DaysTokens, projects, provenance, provider,
sessionCostUSD, sessionTokens, source, totals, updatedAt

$ codexbar cost --days 7 --format json --json-only \
    | jq -r '[.[] | .coverage | keys] | add | unique | join(", ")'
estimated, priced, unmetered, unpriced

$ codexbar cost --days 7 --format json --json-only \
    | jq -r '[.[] | .projects[]? | keys] | add | unique | join(", ")'
daily, modelBreakdowns, name, path, sources, totalCost, totalTokens
```

`codexbar usage` continues to return partial healthy provider records even when
one enabled provider makes the command exit non-zero. The observed record union
is `credits, error, provider, source, usage, version`; the widget must preserve
its existing partial-success behavior.

`codexbar sessions --json-v2` still emits private `cwd`, `transcriptPath`, and
`id` fields. The Plasma normalizer already discards them and must keep doing so.

## Changes since 0.50.0

| Release | Relevant official change | Plasma consequence |
| --- | --- | --- |
| 0.50.1 | Provider accent overrides, Claude scoped quotas, configurable workday ticks | Accent settings need a generic descriptor; scoped windows continue to degrade through generic usage rows. |
| 0.51.0 | `cost --group-by session` in text output | No frontend contract. Plasma keeps using `sessions --json-v2` and structured `cost` JSON. |
| 0.52.0 | Project spend aggregation and Projects panel | Project arrays now exist in cost JSON and can be normalized generically. Never retain or render the local path. |
| 0.53.0 | Explicit cost provenance/coverage, hourly activity, 365-day inputs, custom pricing, OpenCodex import | Coverage/provenance is a correctness gap; hourly and all-time presentation need a bounded frontend design. OpenCodex import remains CLI-owned. |
| 0.54.0 | Conditional menu-bar tokens, direct lane tokens, pace visibility, Grok/xAI spend, Fireworks slug discovery | Layout rules are optional Plasma-native work. Spend/provider fixes arrive through the CLI. Fireworks no longer needs a separate slug editor for the single-key flow. |

## Inherited from the CLI upgrade

No QML work is needed for provider-side fixes that already flow through the
generic payloads. This includes Amp's updated subscription parser, Codex PAT
source discovery, Fireworks account-slug discovery, OpenCode Go's authenticated
usage source, Grok/xAI spend inputs, historical GPT-5.6 pricing, and the Linux
`codexbar cost` crash fix.

Fireworks is a concrete roadmap change. `set-api-key` plus the 0.54.0 CLI's slug
discovery can cover its single-key onboarding path, but the Plasma page still
hides that fallback under the old slug requirement. Enabling it is now a small
follow-up. Token-account editing and provider-specific auth/source choices
remain blocked on a generic descriptor.

## Plasma-native and implementable now

| Gap | Official evidence | Plasma consequence |
| --- | --- | --- |
| Cost trust metadata | `cost` emits `coverage` counters and `provenance` | Normalize bounded semantic coverage and label partial, estimated, or unpriced totals instead of presenting false precision. |
| Project spend | `cost.projects[]` carries totals, daily rows, models, sources, name, and local path | A generic bounded Projects view is possible. Discard `path`; accept only safe display fields. |
| Longer/hourly spend views | 0.53.0 introduced 365-day inputs and hourly activity on macOS | The JSON daily contract supports longer ranges now. Hourly parity needs an official JSON field; do not infer hours from dates. |
| Conditional panel elements | 0.54.0 menu layouts can branch on usage, reset, run-out, pace, balance, and cost | Data is available, but Plasma needs its own small rule model and configuration UX. Do not copy the Swift persistence model. |
| Direct lane elements | 0.54.0 exposes primary/secondary/tertiary layout tokens | Existing normalized rows carry lane identity, so a Plasma-native element is possible. Unknown lanes must remain harmless. |
| Pace visibility | 0.54.0 adds a Show pace setting | A small display preference is possible if users need it; notifications must remain independent. |
| Weekly pace reserve token | Existing macOS panel presentation | Still open and distinct from the run-out duration token already implemented. |

The existing quota thresholds, sessions list, interactive charts, panel element
ordering, spend ranges/heatmap, predictive warnings, cost/token switch, and
run-out token remain implemented as documented in the 0.50.0 report.

## Blocked on an official Linux CLI contract

| Gap | Why it remains blocked at 0.54.0 |
| --- | --- |
| Per-provider settings editors | No `--descriptors`, no `descriptor` key, no `config set`. |
| Token-account add/edit/remove | `set-api-key` is not a generic account editor and exposes team account flags only for z.ai. |
| Browser-cookie, OAuth/device-flow, local-file, and CLI-auth onboarding | No JSON-described action contract. Plasma must not read browser or app credential stores. |
| Provider metric, source-mode, accent, and per-provider threshold pickers | macOS settings have no generic CLI descriptor equivalent. |
| OpenRouter management API key | The new optional spend source has no generic safe setter distinct from the provider's ordinary key. |
| Plugin management and hooks | Commands remain text/interactive or have no structured config action. |
| Credits and plan-utilization history, usage/storage breakdown history | No stable generic history payload. |
| Session-equivalent forecast | Requires multiple historical samples; one current rate-window snapshot is insufficient. |

## macOS-only or non-goals

WidgetKit, Sparkle, Keychain/Full Disk Access consent UI, Dock and Settings
window lifecycle, AppKit status-item rendering, remote SSH window focus, iCloud
sync, Cursor's read-only local app session, and the confetti overlay remain
non-goals for this repository.

## Provider catalog

The Plasma fallback catalog and `scripts/test_provider_icons.sh` list 69
provider IDs. The installed 0.54.0 CLI reports the same 69 and adds none. No
catalog sync is needed.

## Recommended parity decision

Keep provider configuration blocked at the frontend boundary. Prioritize:

1. cost coverage/provenance, because it prevents partial or estimated totals
   from looking exact;
2. a bounded, path-free project-spend projection if a richer spend view is the
   next product goal;
3. panel conditionals, direct lanes, pace visibility, and the weekly reserve
   token only after choosing the smallest Plasma-native UX worth maintaining.

Do not implement provider-specific settings, credential discovery, hourly
history inference, or macOS persistence models in QML.
