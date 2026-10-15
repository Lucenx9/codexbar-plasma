# Codex cost and reset-credit contracts at 0.75.0

Checked 2026-10-15 against Plasma
[`bcd777b`](https://github.com/Lucenx9/codexbar-plasma/commit/bcd777ba18a2207e0957810772fb32af4bbf730e)
and official CodexBar [v0.75.0](https://github.com/steipete/CodexBar/releases/tag/v0.75.0),
commit `4668969c8507d75e2f173b72a742c92f97e60344`.
This focused verification extends the [release review](2026-10-15-macos-parity-0.75.0.md).
It does not repeat its registry or blocker audit. [TODO](../../TODO.md) owns
remaining implementation and verification work.

## Partial-priced native history

The released Linux executable read synthetic Codex session JSONL through
`cost --provider codex --days 7 --json --refresh --provider-native-only`.
Each request had 100 input and 10 output tokens. One model was `gpt-5`;
the other was the deliberately unknown `gpt-5-synthetic-unpriced`.
Both cases exited 0 with empty stderr.

| Input | Tokens | USD | Coverage |
| --- | --- | --- | --- |
| One priced and one unpriced request | 220 | 0.000225 | priced 1, unpriced 1 |
| Only the unpriced request | 110 | absent | priced 0, unpriced 1 |

The mixed day's `totalCost` and priced model's `cost` remain 0.000225;
the other model has `totalTokens: 110` and no `cost`. Its day has 220 tokens.
With only unpriced usage, top-level, totals, daily, and model monetary fields
are absent. Coverage occurs on the payload and `totals`; it is not repeated
on each daily/model row. Provenance is `listPriceEstimate` for the mixed
record and `unknown` for the all-unpriced record.

Plasma already preserves these amounts and missing values through
`CostResponse.response`, daily/model normalization, and `ShareUsage.snapshot`,
including privacy projection. The sharing notice stays partial in both cases;
unpriced tokens remain in the ranking. Direct QtTests retain reduced versions
of these emitted records. No pricing or aggregation change is required for
these verified shapes.

The known-model historical case also passed through the released executable.
Three `gpt-5` requests initially report 330 tokens and USD 0.000675. Following
the tagged
[partial-pricing tests](https://github.com/steipete/CodexBar/blob/4668969c8507d75e2f173b72a742c92f97e60344/Tests/CodexBarTests/CostUsageCodexPartialPricingTests.swift)
fixture, one already-scanned row in the **synthetic** scanner SQLite cache
received `unpricedTokens: 110`. The next official CLI invocation emitted
330 tokens, USD 0.00045 on totals/day/model, and coverage `priced: 2, unpriced: 1`.
Marking all three cached requests omitted every monetary field while retaining
330 tokens and coverage `priced: 0, unpriced: 3`. All processes exited 0 with
empty stderr. Plasma preserves the known-model subtotal and qualifies it as
partial in both ordinary and privacy-safe sharing.

This verifies the output from seeded historical scanner state, not the upstream
recovery algorithm that naturally creates that state. No host cache was read
or changed. Imported incomplete model rows remain unverified: the tagged
[import loader](https://github.com/steipete/CodexBar/blob/4668969c8507d75e2f173b72a742c92f97e60344/Sources/CodexBarCLI/CLICostCommand.swift#L769)
depends on an application preference. No supported Linux writer was established,
and neither inspecting source nor the native probes establishes that imported
output. The narrower import case remains in TODO; no host application preferences
were changed.

## Identified local and remote requests

`cost --provider codex --days 7 --identified-only --identified-end <ms> --json`
returns a **ledger object** for successful local-only collection, rather than
the normal cost array. Two files repeating the same thread/response identity
produce one record. A second distinct request survives. These records use
SHA-256 identities and expose token counts without models, account names,
project paths, or conversation content.

Adding `--remote fixture-<case>` returns reports and a merged subtotal. The
controlled SSH subprocess fixture invokes the same official binary on another
synthetic history inside the sandbox. It is bound over `/usr/bin/ssh` only
inside that namespace. This verifies CLI transport decoding and merge behavior,
not real SSH authentication, host-key configuration, or connectivity.

The local source contains a shared 110-token request and a local-only 210-token
request. The remote source contains the same shared identity and a remote-only
310-token request. Both use the same explicit UTC window end.

| Case | Subtotal tokens | Accepted requests | Result |
| --- | --- | --- | --- |
| Shared request repeated across sources | 630 | 3 | exit 0, complete |
| Shared identity has contradictory input counts | 520 | 2 | exit 0, partial, one conflict |
| Remote process exits 255 | 320 | 2 | exit 1, local subtotal retained |
| Local sessions root missing | 420 | 2 | exit 1, remote subtotal retained |
| Additional legacy request without strong identity | 630 | 3 | exit 0, partial, excluded count positive |

Every subtotal explicitly has `costUSD: null`. `allSourcesAvailable` describes
source availability, separately from `partial`, which also covers exclusions
and conflicts. A partial result can therefore exit 0. These behaviors follow
the released [collector](https://github.com/steipete/CodexBar/blob/4668969c8507d75e2f173b72a742c92f97e60344/Sources/CodexBarCLI/CLICodexIdentifiedUsage.swift)
and [ledger merger](https://github.com/steipete/CodexBar/blob/4668969c8507d75e2f173b72a742c92f97e60344/Sources/CodexBarCore/Providers/Codex/CodexRequestLedger.swift).

An optional, explicitly requested identified-token subtotal is **Plasma-native
and implementable now**. It would need its own bounded decoder, user-selected
SSH host, process lifecycle, availability/partial notices, and token-only
presentation. It must not replace generic history totals, claim account-wide
coverage, infer prices, persist request identities, or run SSH by default.
That feature remains separate implementation work in TODO; this change does
not add SSH settings or another history scan.

## Reset-credit inventory

A loopback HTTP fixture supplied native Codex OAuth usage and reset-credit
responses to the released CLI. The native synthetic `auth.json` had fake
tokens and a fresh `last_refresh`; `config.toml` set
`chatgpt_base_url = "http://127.0.0.1:8765"`. Both files existed only in the
isolated synthetic Codex home. The CLI requested `/api/codex/usage` and
`/wham/rate-limit-reset-credits`. No CodexBar config JSON was edited.

Each `usage --provider codex --source oauth --format json --json-only` exited
0 with empty stderr and preserved the healthy 25%-used primary quota.

| Provider response | Top-level summary | Nested legacy aggregate |
| --- | --- | --- |
| Two usable, one expired, one redeemed credit; aggregate 99 | `available: 2`, `nextExpiresAt: "2099-01-01T00:00:00Z"` | `availableCount: 99` |
| Empty inventory; aggregate 99 | `available: 0` | `availableCount: 99` |
| One expired credit; aggregate 1 | `available: 0` | `availableCount: 1` |
| Optional credit endpoint returns HTTP 500 | absent | absent |

The [payload encoder](https://github.com/steipete/CodexBar/blob/4668969c8507d75e2f173b72a742c92f97e60344/Sources/CodexBarCLI/CLIPayloads.swift#L96)
projects usable inventory at observation time, filtering expired/redeemed
credits through the [inventory model](https://github.com/steipete/CodexBar/blob/4668969c8507d75e2f173b72a742c92f97e60344/Sources/CodexBarCore/CreditsModels.swift#L155).
The older aggregate can disagree. This is verified standard Linux output,
independent of the private desktop snapshot contract.

Plasma previously read only the nested aggregate. It now prefers the top-level
summary, including zero. A present malformed summary suppresses the old count;
only an absent summary permits the legacy fallback. New counts must be finite,
nonnegative safe integers. Positive counts retain the existing internal
`{availableCount: count}` presentation; zero hides the section. The raw inventory
and optional expiry are not retained or displayed. Existing localization,
privacy projection, and stale-cache removal remain in place.

## Isolation and reproduction

The official Linux x86_64 archive matched its published SHA-256 file:
`7920c8e42a64aa5dc249bdb3a745e8ec91a062cb2668b78dc9266dfffa0d7ad7`.
The installed executable, discovered with `command -v codexbar`, remains
`/usr/local/bin/codexbar` at 0.74.1. Sources came from a separate archive of the
exact upstream commit; local upstream/fork workspaces were not changed.

Every released CLI invocation ran under `bwrap --unshare-all --clearenv`,
with tmpfs over `/home`, `/root`, `/run`, and `/tmp`, fresh HOME/config/cache,
and no host network or IPC. Native cost discovery also received synthetic
`CODEX_HOME` and a synthetic home bind over `/home/simone` for passwd-based
discovery. The OAuth server ran on loopback inside the same isolated namespace.
Each process had an external deadline of at most 40 seconds.

To recreate native request inputs, write a JSONL file per session under
`$CODEX_HOME/sessions/` with these records, substituting a current timestamp:

```json
{"type":"session_meta","timestamp":"2026-10-15T00:01:00Z","payload":{"id":"synthetic-thread"}}
{"type":"turn_context","timestamp":"2026-10-15T00:01:00Z","payload":{"model":"gpt-5","turn_id":"known"}}
{"type":"token_usage_record","timestamp":"2026-10-15T00:01:00Z","payload":{"thread_id":"synthetic-thread","response_id":"known","usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10},"thread_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}}}
```

Change the thread/response pair for a distinct request, repeat it for deduplication,
or change input counts with the same pair for conflict testing. Native quota
responses and reset-credit rows follow the pinned
[OAuth fetcher](https://github.com/steipete/CodexBar/blob/4668969c8507d75e2f173b72a742c92f97e60344/Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift#L524).
Temporary probe scripts, source/binary archives, and synthetic captures are in
ignored `dist/review/cost-contracts-075/`; they are not shipped with the widget.
Regression checks retain the verified presentation contracts in
`tst_provider_snapshot.qml` and `tst_share_usage.qml`.

No authenticated provider, real SSH host, or imported incomplete model output
was observed. Natural historical-pricing recovery was not exercised. Those limits must
not be interpreted as proof that the corresponding contracts are absent.
