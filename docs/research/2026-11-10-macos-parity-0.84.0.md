# Linux parity review at CodexBar 0.84.0

Checked 2026-11-10 against Plasma commit
[`ad1d246`](https://github.com/Lucenx9/codexbar-plasma/commit/ad1d24679a2117974b532a2a686d78a0fef60d06).
The official reference is [v0.84.0](https://github.com/steipete/CodexBar/releases/tag/v0.84.0),
commit `5bebf9a05e68059eae11d5031c7239f1aa1d49ef`, published
2026-11-07 at 05:02:09 UTC. This covers the only stable release since the
[0.83.0 review](2026-11-01-macos-parity-0.83.0.md), including its unresolved
findings. It does not replace the full [0.56.2 audit](2026-09-01-macos-parity-0.56.2.md).
[TODO.md](../../TODO.md) owns follow-up work. This review changes documentation
only. The installed CLI reports 0.83.0; only its version was requested, and it
was neither replaced nor run against host account data.

## Release coverage

| Release | Published | Commit | Linux-relevant changes |
| --- | --- | --- | --- |
| [0.84.0](https://github.com/steipete/CodexBar/releases/tag/v0.84.0) | 2026-11-07 05:02:09 UTC | `5bebf9a05e68059eae11d5031c7239f1aa1d49ef` | SiliconFlow and Tripo providers (#4925, #4927); Claude Platform stdin login (#4845); WorkBuddy manual User-Agent (#4939, #4940); Synthetic weekly credit quotas (#4871, #4885); Neuralwatt typed balance (#4870); Claude dashboard partial-data warning (#4809, #4877); OpenCode Go unavailable local costs (#4931); stricter cost-day and hook-interval validation; CLI startup, history, cache, transport, DST, and provider-fetch fixes. |

The comparison is the official
[0.83.0...0.84.0 delta](https://github.com/steipete/CodexBar/compare/v0.83.0...v0.84.0),
88 commits. No upstream-main or fork observations are used as release evidence.

## Linux CLI contract changes

- Both checksum-verified glibc x86_64 binaries report their exact versions.
  `config providers --format json --json-only` grows from 111 to 113 records.
  SiliconFlow and Tripo are the only additions; all existing records, including
  authentication hints, are unchanged. Both new records default to disabled,
  advertise `sourceModes: ["api", "auto"]`, support the API-key writer, and
  advertise no cookie writer. SiliconFlow lists
  `SILICONFLOW_API_KEY` and `SILICONFLOW_BASE_URL`; Tripo lists `TRIPO_API_KEY`.
- `config set-api-key --provider siliconflow --stdin --json` and the Tripo
  equivalent accept synthetic input, return `{provider, enabled, configPath}`
  with `enabled: true`, and save through the official writer. Subsequent Auto
  and API usage requests reach their fetches, failing with DNS error `-1003`
  inside the offline namespace rather than a missing-key or macOS-only error.
  This verifies setup and Linux dispatch, not balances or valid authentication.
- SiliconFlow defaults to `https://api.siliconflow.cn`. The pinned
  [settings reader](https://github.com/steipete/CodexBar/blob/5bebf9a05e68059eae11d5031c7239f1aa1d49ef/Sources/CodexBarCore/Providers/SiliconFlow/SiliconFlowSettingsReader.swift)
  also accepts the international `.com` origin through the environment.
  A synthetic key plus an invalid environment origin fails before fetching.
  `set-api-key --base-url` remains unknown, so regional editing has no released
  CLI writer. Source emits localized balance/purchased/bonus detail text for
  SiliconFlow and available/reserved credit detail text for Tripo; neither
  implies a quota denominator.
- `config login --provider claudeplatform --stdin --json` is newly accepted.
  Empty input returns setup instructions; a cookie without `sessionKey` is
  rejected before fetching. A synthetic `sessionKey` reaches validation and
  emits `{"status":"failed","error":"...NSURLErrorDomain error -1003..."}`,
  exit 1, without creating a config file. The same stdin command is rejected
  by 0.83.0. The pinned
  [login command](https://github.com/steipete/CodexBar/blob/5bebf9a05e68059eae11d5031c7239f1aa1d49ef/Sources/CodexBarCLI/CLIConfigLoginCommand.swift)
  validates the supplied candidate before saving, emits `authorized` after
  saving, checks concurrent config changes, and supports cancellation. Those
  successful/conflict/cancellation paths were source-inspected, not executed
  against an authenticated account. This is a private session import, not a
  device-login or browser-opening command. Inventory still advertises only
  Copilot's `loginCommand`.
- WorkBuddy accepts a synthetic cookie through `set-cookie --stdin`, then
  reaches the Linux Web fetch. Without the stored cookie it reports the
  macOS-only source error. `set-cookie --user-agent` is unknown. The pinned
  [provider descriptor](https://github.com/steipete/CodexBar/blob/5bebf9a05e68059eae11d5031c7239f1aa1d49ef/Sources/CodexBarCore/Providers/WorkBuddy/WorkBuddyProviderDescriptor.swift)
  reads `workBuddyUserAgent` from config for manual cookies, but no official
  field writer exists. Plasma must not add config editing for it.
- With no OpenCode installation, `cost --provider opencodego --days 7 --json`
  now exits 0 with empty `daily`/`projects`, zero coverage counts,
  `historyCoverageIsEstablished: false`, and no cost/token totals. 0.83.0 exits
  1 and includes an unavailable error. Plasma's production `CostResponse`
  accepts the new record and preserves null totals, today amounts, and session
  amounts. It retains the history-coverage flag; no measured zero is invented.
- Synthetic native Codex history under a symlinked `sessions` root, with one
  flat JSONL file containing a 101-input/10-output request, produces no daily
  activity on 0.83.0 and 111 tokens on 0.84.0. The new report leaves the
  unpriced cost absent. This is a CLI scanner fix; Plasma already consumes the
  token and missing-cost fields. Separately, a dated native file produces one
  schema 2 identified request with 111 tokens on both versions; Plasma's
  current `IdentifiedTokens.decode` accepts both. The earlier schema 2 gap is
  implemented. Moving that same dated file outside the Codex home and linking
  `sessions` to its new root returns an empty ledger with `partial: false` on
  both versions. This isolates a remaining CLI discovery bug; the ordinary-cost
  fix does not cover the separate identified command.
- `cost --days 7x --json` now fails with `Error: --days must be an integer.`;
  0.83.0 silently accepts it. Plasma constructs bounded integer day arguments,
  so no frontend adjustment is needed. `sessions`, `plugins`, and `serve`
  help are unchanged except for the version; usage/cost help add the two
  providers, and config help adds the Console import.
- The source adds a `model-breakdown-unavailable` warning to dashboard API
  payloads. Plasma consumes one-shot `usage` JSON, not dashboard API snapshots;
  the warning is not evidence of a new `usage` contract. CLI-owned supplemental
  OpenAI cache expiry, provider recovery, symlink scanning, local CSV handling,
  pricing/cache performance, HTTP cancellation, and DST fixes require no
  duplicated provider or history logic in QML.

## Plasma comparison

- **Plasma-native and implementable now:** version-gated SiliconFlow/Tripo key
  prompts and fallback metadata. `ProviderConfigProtocol.response` accepts all
  113 official inventory records and preserves both new names and source modes,
  but `ProviderCapabilities.supportsApiKey` returns false for both providers
  even with the CLI's true writer flag. `ProviderIdentity.mjs` lacks their
  static links/artwork. Preserve the curated policy for unknown providers.
- **Plasma-native and implementable now:** WorkBuddy's manual-cookie action.
  Its stored-cookie Web fetch is now verified on Linux, but
  `ProviderCredentials.supportsCookie` excludes it. Reuse the existing private
  prompt with a 0.84.0 version gate. An optional matching User-Agent may still
  require external configuration until the CLI supplies its writer; a
  successful billing response remains unverified.
- **Plasma-native and implementable now:** the explicit Console session import
  can use the released stdin contract. Plasma currently offers Set cookie for
  Claude Platform and reserves its device-login helper for Copilot. An import
  must keep cookies inside the native secret prompt/helper process, validate
  terminal results and exit status, and preserve cancellation, timeout,
  concurrent-change and stale-result safeguards. Success remains an
  authenticated verification limit, not a missing CLI command.
- **Blocked on official CLI contracts:** the WorkBuddy User-Agent and
  SiliconFlow regional-origin editors have no writer. Generic descriptors,
  setup actions, account-private selection, and the other carried blockers
  remain separate from the newly released commands.
- **Blocked on an official CLI fix:** identified-token discovery silently
  misses a symlinked session root. Plasma accepts the returned empty ledger
  and cannot distinguish it from a measured empty history. The CLI must retain
  those records or report unavailable/partial discovery; QML must not scan the
  filesystem to compensate.
- **Verify before implementation:** authenticated balances and changed quota
  shapes. `ProviderSnapshot.costFields` still drops `providerCost.balance`;
  `ProviderCostPresentation` does not recognize Neuralwatt as a typed balance.
  Source adds that balance in 0.84.0, but no emitted authenticated record was
  captured. Keep the automatic-balance candidate unverified. Synthetic's
  weekly-only credits and Cursor's current monthly Auto name also need emitted
  records before replacing Plasma's static lane labels. New providers' detail
  rows should use the existing generic path if verified output permits it.

The previous inventory/source-mode gap is implemented by the current
`config/ProviderAuthentication.js`, `ProviderSource.js`, and their QtTests.
Their capability hints still correctly avoid authorizing unverified writers.
The earlier OpenDesign cookie action is implemented as well. None of those
completed items needs a new implementation entry.

## Carried-forward blockers rechecked

- `config providers --descriptors`, `config action`, and `config set-currency`
  still fail as unknown option/subcommands.
- Cursor cost is still refused; the supported list remains Antigravity,
  Claude, Codex, Muse Code, OpenCode Go, and Pi. `cost --account synthetic`
  and `usage --account-stdin` remain unknown options.
- ClinePass `set-api-key --label` still fails with the z.ai-only token-account
  restriction. Existing provider inventory authentication records are unchanged.
- An unknown `usage --provider audit-fixture` still returns a Codex error.
  Approved-plugin routing was not reprobed; retain its earlier verified
  0.79.0 through 0.81.0 blocker. Empty `sessions --json-v2` returns `[]`.
- Offline Codex `usage --status` still emits indicator, description and URL,
  without component records. No typed network error is added to the observed
  usage errors. The Antigravity established-empty cost ambiguity was not
  reproduced; the OpenCode Go fix does not resolve it.

## Excluded from the Linux backlog

The macOS allocator policy, WebKit cleanup, Keychain interaction, MenuBarAgent
diagnostics, native popup selectors, sidebar search/sorting, iCloud account
filtering, SwiftUI chart/window lifetime, icon raster reuse, and WidgetKit
timeline publication are app/runtime-specific. Their implementation is not a
Plasma porting task. Saved Codex credential matching and refresh recovery remain
CLI-owned. Weekly-reset confirmation and Grok celebration changes are app
references for existing account/stale-data and reset-notice candidates, not
new authoritative Linux reset fields. Retained-quota dimming and tabular-digit
polish do not establish a new CLI requirement.

## Unverified in this review

No authenticated requests or external network calls were made. Successful
Claude Platform authorization, cancellation and concurrent-write handling;
SiliconFlow China/international balances; Tripo credit reservations; WorkBuddy
with a matching User-Agent; Synthetic weekly credits/regeneration; Neuralwatt's
typed balance; TypeSafe restored billing; Kiro token recovery/Pro+; Bedrock
measured-zero days; Claude weekly-only/model-specific rows; Cursor encrypted
sessions and trailing CSV fields; and the fresh/stale OpenAI cache boundary
remain unobserved in official Linux output. Claude symlinked roots, Grok local
turn counting, hook-overflow validation, transport cancellation and DST changes
were source/release-reviewed but not exercised. Earlier unresolved authenticated
cases carry forward. Approved custom plugins, real SSH, non-null identified
API-price estimates, musl and aarch64 execution were not tested.

## Probe method

Official glibc x86_64 assets matched their published SHA-256 files:

- 0.84.0: `724b0beb0d2769cfc6fc1558f2782b5b812eb73a140582b9716faf662adbaea0`.
- 0.83.0: `e278eb0a1b6d620b5c84c157dfb16860a82477af6ec7330b6b6fb5c7f2729b5b`.

Every released-CLI probe ran under `bwrap --unshare-all`, tmpfs over `/home`,
`/root`, `/run`, and `/tmp`, a cleared environment, temporary home/config/cache
paths, and an outer 30-second deadline. The native-history probes also bound
the synthetic home over the passwd home directory and set a synthetic
`CODEX_HOME`. Host history, credentials, network and IPC were inaccessible.
Only synthetic keys/cookies entered supported writers over stdin. Native JSONL
used the request-record shape from the pinned upstream ledger tests.
Production pure JS decoders ran under Node after resolving their QML JS imports;
this checks payload compatibility, not live QML rendering. Temporary source,
captures and probe scripts stayed outside the repository. No config was
hand-edited, installed binary replaced, or upstream source modified.
