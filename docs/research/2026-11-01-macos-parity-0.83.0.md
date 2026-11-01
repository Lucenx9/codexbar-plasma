# Linux parity review at CodexBar 0.83.0

Checked 2026-11-01 against Plasma commit
[`59d45ba`](https://github.com/Lucenx9/codexbar-plasma/commit/59d45ba825735c0045a38d680b455a579478501b).
The official reference is [v0.83.0](https://github.com/steipete/CodexBar/releases/tag/v0.83.0),
commit `348e2fa8d36ae8e452739ca07a79e83ab9d25e98`, published
2026-10-31 at 10:12:05 UTC. This covers the only stable release since the
[0.82.0 review](2026-10-27-macos-parity-0.82.0.md), including its unresolved
findings. It does not replace the full [0.56.2 audit](2026-09-01-macos-parity-0.56.2.md).
[TODO.md](../../TODO.md) owns follow-up work. This review implements no feature.
The installed `codexbar` command was neither executed against host data nor
replaced.

## Release coverage

| Release | Published | Commit | Linux-relevant changes |
| --- | --- | --- | --- |
| [0.83.0](https://github.com/steipete/CodexBar/releases/tag/v0.83.0) | 2026-10-31 10:12:05 UTC | `348e2fa8d36ae8e452739ca07a79e83ab9d25e98` | `authentication` record in provider inventory JSON (#4705); identified Codex ledger schema 2 with several `--remote` hosts and API-price estimates (#4833, #4834, #4836); new OpenDesign provider (#4601); strict Commander 0.3.0 argument parsing; `serve` `refresh=1` (#4785); `usage_updated` hook plan fields (#4775, #4800); CLI-owned fetch fixes for Kiro, MiniMax China, Perplexity, WorkBuddy, LiteLLM, z.ai, Copilot, AWS Bedrock, Claude, OpenCode Go, and Codex `.jsonl.zst` archives. |

## Linux CLI contract changes

- The isolated glibc and musl binaries report `CodexBar 0.83.0`. The
  registry grows to 111 records: `opendesign` is new, and the 110 existing
  records keep their IDs, names, and defaults. Top-level and `usage` help add
  `opendesign` to the provider list. `cost` help documents repeated `--remote`
  hosts and schema 2. `sessions`, `plugins`, `config`, and `serve` help are
  unchanged apart from the version line.
- **Identified Codex ledger schema 2 breaks Plasma's subtotal.** With one
  synthetic native request, `cost --provider codex --days 7 --identified-only
  --identified-end <ms> --json` returns `schemaVersion: 1` on 0.82.0 and
  `schemaVersion: 2` on 0.83.0. Each 0.83.0 record adds `model`, `pricingMode`
  (`standard`, `priority`, or null), and `includedInPlan`. Reports add
  `source` (`local` or `ssh`) and `collectedAt` (omitted for a failed source).
  The subtotal adds `unpricedRequestCount`; its `costUSD` is an API-price
  estimate from the collector's pricing snapshot, null when a price is unknown.
  Plasma's unchanged `IdentifiedTokens.decode`, run on both captured outputs,
  returns `data` for 0.82.0 and `unsupported` for 0.83.0, because
  `ledgerSummary` requires `schemaVersion === 1`. The envelope check also
  requires `subtotal.costUSD === null` and exactly one remote report.
- Schema 2 is coordinated across hosts. With a 0.83.0 collector, a 0.82.0
  remote fixture fails with `Remote identified usage is unavailable. Check SSH
  and update its CLI for schema 2 --identified-only.` and exit 1, keeping the
  local subtotal. A missing host gives the same error.
- `config providers --format json --json-only` adds an `authentication`
  object to every built-in record, with `sourceModes`, `supportsConfigAPIKey`,
  `supportsConfigCookieHeader`, and `environmentVariables`. 39 records add
  `tokenAccounts` with `title` and `setupHint`; only Copilot adds
  `loginCommand` (`codexbar config login --provider copilot`).
  `--descriptors` is still an unknown option.
- Against the writers in the same sandbox, `supportsConfigAPIKey` matches
  `set-api-key` acceptance for all 111 providers (63 true).
  `supportsConfigCookieHeader` is true for 48 providers, but `set-cookie`
  accepts 50: Sakana and DeepSeek report false and are still accepted. Sampled
  `set-source` writes accept exactly the listed `sourceModes` and reject others
  with `Source <mode> is not supported for <id>. Supported sources: ...`
  (`zai`, `cursor`, `openrouter`, `codex`).
- The record describes what is configurable, not what works on Linux.
  Helmcode lists `web` and `set-source --source web` succeeds, although its
  web fetch is macOS-only. `environmentVariables` mixes required and optional
  values: FLORA lists `FLORA_WORKSPACE_ID` and Future AGI lists
  `FI_SECRET_KEY`, both required at runtime, while Claude lists the optional
  `ANTHROPIC_ADMIN_WORKSPACE_SPEND`. Plasma's curated API-key allowlist must
  stay until a field states that a stored key alone is enough.
- OpenDesign is cookie-only (`auto`, `web`). `set-cookie --provider opendesign
  --stdin` stores a synthetic cookie and enables it; Auto and `--source web`
  then reach the network (`NSURLErrorDomain error -1003` offline) instead of
  the macOS-only web error.
- Commander 0.3.0: every command shape Plasma builds is still accepted.
  `--format=json` is now parsed as an option; 0.82.0 rejected it as unknown.
- `cost` JSON keys, `sessions --json-v2` records, and the usage error and
  `--status` envelopes are unchanged in the sandbox. `ProviderStatusPayload`
  (`CLIPayloads.swift`) is unchanged since 0.82.0.

## Plasma comparison

- New implementable gap: accept identified ledger schema 2 (and its
  `costUSD` estimate, `unpricedRequestCount`, `source`, and several remote
  reports) or report a clear version mismatch instead of `unsupported`. The
  usage guide and README claimed 0.75.0 or later works; with 0.83.0 every
  successful load fails, and the guide now names 0.75.0 through 0.82.0. With
  a 0.83.0 collector, the CLI output rejects a 0.82.0 SSH host's contribution
  while the local schema 2 report remains; the widget still rejects that
  report as `unsupported`. The UI strings in `configGeneral.qml` and
  `IdentifiedTokensSection.qml` still say "0.75.0 or later" and need an i18n
  update with the schema 2 work.
- New implementable gap: read `authentication` from the existing provider
  inventory call to offer only the CLI's `sourceModes` in the source selector,
  gate key setup on `supportsConfigAPIKey`, and show `tokenAccounts.setupHint`
  and `loginCommand` text. Today `ProviderSource.modes` offers all five modes
  for every provider and lets the CLI refuse them.
- OpenDesign joins the manual-cookie candidates whose Linux fetch reads the
  cookie.
- The macOS 0.83.0 weekly-reset and reset-credit expiry reminders (#4849,
  #4838) are a pinned reference for the reset-imminent candidate. They are
  app notifications; the CLI emits no reminder field.
- Auto window labels now name the window once per row (#4820). This is app
  rendering and only refines the Auto lane naming candidate.
- `serve` `refresh=1` does not apply: Plasma runs one-shot commands, not the
  HTTP server.

The pinned source comparison is
[0.82.0...0.83.0](https://github.com/steipete/CodexBar/compare/v0.82.0...v0.83.0).
Relevant contract owners at 0.83.0 are the
[identified usage command](https://github.com/steipete/CodexBar/blob/348e2fa8d36ae8e452739ca07a79e83ab9d25e98/Sources/CodexBarCLI/CLICodexIdentifiedUsage.swift),
the [request ledger](https://github.com/steipete/CodexBar/blob/348e2fa8d36ae8e452739ca07a79e83ab9d25e98/Sources/CodexBarCore/Providers/Codex/CodexRequestLedger.swift),
and the [provider inventory](https://github.com/steipete/CodexBar/blob/348e2fa8d36ae8e452739ca07a79e83ab9d25e98/Sources/CodexBarCLI/CLIConfigCommand.swift).

## Carried-forward blockers rechecked

- `config providers --descriptors` is still an unknown option. `config action`
  and `config set-currency` are still unknown subcommands.
- Cursor cost is still rejected; the supported list is unchanged. `cost
  --account synthetic` and `usage --account-stdin` still fail as unknown options.
- ClinePass `set-api-key --label` still fails as a z.ai-only token-account
  option.
- An unknown `usage --provider audit-fixture` still returns a Codex error. The
  approved-plugin path was not reprobed; `plugins` help is unchanged.
- `sessions --json-v2` returns the synthetic Codex thread on both versions.
- The prior authenticated candidates remain open.

## Excluded from the Linux backlog

- Plugin menu-bar layouts, compact multi-quota summaries, built-in plugin
  logos, separator glyphs, the neutral pace default with state bars, Codex
  account names in Settings, Sparkle updates, iCloud Sync retries, and the
  browser-cookie imports for plugins, DeepSeek, Cursor, and MiniMax are macOS
  app behavior.

## Unverified in this review

No authenticated provider requests or external network calls were made.
OpenDesign quotas, Kiro CLI 3, MiniMax China quotas, Perplexity organization
credits, WorkBuddy reward credits, LiteLLM team budgets, z.ai CNY balances,
Copilot monthly pace and ended subscriptions, the AWS Bedrock unavailable
state, the Claude unavailable per-model breakdown, OpenCode Go server quotas,
and Codex `.jsonl.zst` cost coverage remain unobserved. A non-null identified
`costUSD` was not produced: the synthetic `gpt-5` request stayed unpriced.
Whether the Linux CLI applies Codex account names to usage labels was not
observed. Real SSH was not used. aarch64 binaries were not executed. The
0.82.0 unverified list carries over.

## Probe method

Official assets matched their published SHA-256 files:

- 0.83.0 glibc x86_64: `e278eb0a1b6d620b5c84c157dfb16860a82477af6ec7330b6b6fb5c7f2729b5b`.
- 0.83.0 musl x86_64: `00e453ece6ee2efda9aecbd8a1c47f0eea6391ae1c8a922f019b9e466f809e53`.
- 0.82.0 glibc x86_64: `de1b083e0ddce2b92eb2e2d45026f3f88d889d974876e81fde9df7d83e19363e`,
  for the help, registry, ledger, and command-shape comparisons.

Every CLI execution used `bwrap --unshare-all`, tmpfs over `/home`, `/root`,
`/run`, and `/tmp`, a cleared environment, and temporary home/config/cache
paths, with a 30-second outer deadline. Host credentials, history, network, and
IPC were inaccessible. The identified-ledger probes also set a synthetic
`CODEX_HOME` and bound the synthetic home over the passwd home directory. The
history held one `token_usage_record` written from the upstream test fixture's
shape. The SSH probes replaced `/usr/bin/ssh` inside the namespace only, through
a temporary overlay, with a script that runs the 0.82.0 or 0.83.0 binary on the
same synthetic history. This verifies schema and merge behavior, not SSH
authentication or connectivity. Synthetic cookies and keys entered the
supported writers through stdin. Plasma's decoder ran under Node with stubbed
`Guards` and `SafeText` helpers. Source inspection used the exact 0.83.0 tag
and the official 0.82.0...0.83.0 comparison.
