# Linux parity review at CodexBar 0.80.0

Checked 2026-10-23 against Plasma commit
[`b7c8362`](https://github.com/Lucenx9/codexbar-plasma/commit/b7c83621246a74df94cc8713baca4b4ab4002d1e).
The official reference is [v0.80.0](https://github.com/steipete/CodexBar/releases/tag/v0.80.0),
commit `3e060a954d7310bf2125074024f0b0f8f91db4b0`, published
2026-10-23 at 02:36:13 UTC. This covers the only stable release since the
[0.79.0 review](2026-10-21-macos-parity-0.79.0.md), including its unresolved
findings. It does not replace the full [0.56.2 audit](2026-09-01-macos-parity-0.56.2.md).
[TODO.md](../../TODO.md) owns follow-up work. This review implements no feature.
The installed `codexbar` command was neither executed against host data nor
replaced.

## Release coverage

| Release | Published | Commit | Linux-relevant changes |
| --- | --- | --- | --- |
| [0.80.0](https://github.com/steipete/CodexBar/releases/tag/v0.80.0) | 2026-10-23 02:36:13 UTC | `3e060a954d7310bf2125074024f0b0f8f91db4b0` | Soniox and Trae CN providers; Copilot `config login` device flow; musl Codex cost-scan crash fix; monthly daily target; Claude Cowork deduplication and partial priced subtotals; Mythos pricing; Kiro offline probes; Grok, Kimi, Cursor, Tavily, OpenCode Go, Codex WAL, and Antigravity fixes; `serve` snapshot rebuild; Claude limits-unavailable state. |

## Linux CLI contract changes

- The isolated glibc and musl binaries report `CodexBar 0.80.0`. The fresh
  provider registry grows from 106 to 108 providers: `soniox` (Soniox) and
  `traecn` (Trae CN), both disabled by default. The record keys stay
  `provider`, `displayName`, `enabled`, `defaultEnabled`; no descriptor or icon
  data is exposed. Empty-account `usage --provider all --format json --json-only`
  returns 108 records. Top-level help changes only by these two provider IDs;
  config help adds `codexbar config login --provider copilot [--json]`.
- Soniox uses the existing single-key writer. Before setup, usage returns
  `No available fetch strategy for soniox`.
  `config set-api-key --provider soniox --stdin` with a synthetic key stores it
  and enables the provider; usage then reaches a network attempt that fails with
  `NSURLErrorDomain error -1003` without networking. The release-tag descriptor
  names an organization API key (`SONIOX_ORG_API_KEY`), rejects project keys,
  and reports the monthly budget from the API rather than a setting. Plasma's
  `supportsApiKeySetup` allowlist in `configProviders.qml` omits Soniox, so its
  key setup is implementable now.
- Trae CN rejects both `auto` and `web` sources on Linux with
  `selected source requires web support and is only supported on macOS`. Its
  signed-in dashboard source joins the existing browser-cookie onboarding
  blocker.
- `config login --provider copilot --json` is a released, provider-specific
  Linux setup command. Any other provider fails with an `args` error, `Use
  --provider copilot.` Without networking, it prints one JSON line,
  `{"status":"failed","error":"Could not resolve host: github.com"}`, and exits 1.
  The [release-tag command](https://github.com/steipete/CodexBar/blob/3e060a954d7310bf2125074024f0b0f8f91db4b0/Sources/CodexBarCLI/CLIConfigLoginCommand.swift)
  emits newline-delimited events with `status` (`authorization_pending`,
  `authorized`, `failed`), `verificationURI`, `userCode`, `expiresIn`, and
  `error`. Tokens never appear in events. SIGINT/SIGTERM cancel the flow, and
  the config write fails with `Config changed during login` when the file
  changed meanwhile. The pending and authorized events were not observed,
  because the sandbox has no network. A Plasma Copilot sign-in action over
  this command is implementable; it is not the generic `config action`
  contract, which remains absent.
- The musl crash fix is verified. With the upstream #4672 reproducer (one `{}`
  line in a dated Codex session file, `CODEX_HOME` inside the sandbox),
  `cost --provider codex --format json --json-only` exits 139 (SIGSEGV) on the
  0.79.0 musl x86_64 binary. It returns a valid empty Codex record on 0.80.0
  musl, and on glibc for both versions. The Codex cost record keeps its
  17 keys. Plasma's managed installer selects the musl asset on musl hosts, so
  Codex costs on those hosts need CLI 0.80.0 or later. No Plasma change is
  required.
- The monthly daily target is computed in the macOS app
  (`MenuCardView+MonthlyTarget.swift` over `UsagePace.dailyTarget`), not
  emitted by the Linux CLI. Its inputs are remaining percent or `quotaLimit`
  and `quotaUnit` with `resetsAt` for windows of 28 to 31 days, or descriptor
  inferred monthly durations, plus `providerCost` `used`, `limit`, monthly
  `period`, and `resetsAt`. Plasma already normalizes `windowMinutes`,
  `resetsAt`, and `usedPercent`. It drops `quotaLimit`, `quotaUnit`, and
  `providerCost.resetsAt`, and the descriptor pace capability is not exposed.
  This is a Plasma-native candidate, recorded for a bounded decision.
- The managed installer's `unpack` accepts both checksum-verified 0.80.0 x86_64
  archives (glibc and musl). `release_assets` accepts glibc and musl metadata
  for x86_64 and aarch64. These are validation and extraction checks, not
  activation.

## Plasma comparison

- Soniox API-key setup and the Copilot device sign-in are the two new
  implementable gaps. Copilot already has single-key setup in Plasma; the
  device flow must keep it, show the verification URI and code from events,
  and handle cancellation, failure, expiry, and the concurrent-change error
  without logging codes or reading config files in QML.
- Claude Cowork deduplication, Mythos pricing, partial priced subtotals,
  OpenCode Go v2 history, Codex WAL fallback, zero-usage chart days, Kiro
  offline probes, and Tavily/Kimi/Grok/Cursor/Antigravity fetch fixes belong to
  the CLI. They change emitted values within existing fields and do not justify
  provider parsing in QML.
- The Claude "limits unavailable" state after a successful response without
  quota windows and Cursor's X Subscription weekly pool change which windows
  an authenticated account emits. Plasma's existing generic window and
  spend-only handling should apply, but this needs authenticated Linux output.
- `codexbar serve` snapshot rebuilding does not affect Plasma, which does not
  use the HTTP dashboard.

The pinned source comparison is
[0.79.0...0.80.0](https://github.com/steipete/CodexBar/compare/v0.79.0...v0.80.0).
Relevant contract owners at 0.80.0 are the
[Copilot login command](https://github.com/steipete/CodexBar/blob/3e060a954d7310bf2125074024f0b0f8f91db4b0/Sources/CodexBarCLI/CLIConfigLoginCommand.swift),
the [Soniox descriptor](https://github.com/steipete/CodexBar/blob/3e060a954d7310bf2125074024f0b0f8f91db4b0/Sources/CodexBarCore/Providers/Soniox/SonioxProviderDescriptor.swift),
the [musl cost smoke test](https://github.com/steipete/CodexBar/blob/3e060a954d7310bf2125074024f0b0f8f91db4b0/Scripts/check-linux-cli-codex-cost-smoke.sh),
and the [daily target](https://github.com/steipete/CodexBar/blob/3e060a954d7310bf2125074024f0b0f8f91db4b0/Sources/CodexBar/MenuCardView+MonthlyTarget.swift).

## Carried-forward blockers rechecked

- `config providers --descriptors` is still an unknown option. `config action`
  is still unknown; with `--help` it prints config help, which is not an action
  contract.
- Cursor cost is still rejected; the supported list is unchanged (Antigravity,
  Claude, Codex, Muse Code, OpenCode Go, Pi). `cost --account synthetic` and
  `usage --account-stdin` still fail as unknown options.
- Gemini Auto and TypeSafe Auto still report the macOS-only web error. The
  Gemini API-source workaround remains necessary.
- ClinePass `--label`, Future AGI `--workspace-id`, and Vercel
  `--workspace-id` still fail as z.ai-only token-account options.
- `config set-currency` is still an unknown subcommand.
- Custom-provider routing is still broken. A synthetic `audit-fixture` plugin
  is listed by `plugins list` and, after sandbox approval, `plugins fetch
  audit-fixture --json` returns its 25% window and warning-severity row. Yet
  `usage --provider audit-fixture` returns `provider: codex` with `No available
  fetch strategy for codex`, plus the other enabled providers' records.
- `sessions --json-v2` still returns `[]` in the empty sandbox.
- The prior authenticated candidates (Claude Auto/adapter selection, Vercel
  personal budgets, Cursor additional spend, Grok billing, Antigravity buckets,
  Munito/Future AGI, claude-swap/tcr, Claude Platform, throughput, stable
  detail IDs, imported incomplete costs) remain open. Empty-account probes do
  not replace their pinned evidence.

## Excluded from the Linux backlog

- iCloud fleet usage, macOS 26 Liquid Glass Settings, menu-bar column
  alignment, merged-icon plugin lanes, cached title rendering, Layout editor
  and Highest-usage explanations, Settings history, WidgetKit unavailable
  messages, Claude Keychain recovery guidance, Pi branding, and app
  localization fixes are app-owned macOS behavior.
- The ccx companion is macOS-only. The community GTK front-end, the Linux
  desktop initial fallback, autostart preservation, and portable `make check`
  belong to other frontends or the upstream repository and create no Plasma
  requirement.
- Codex account registry diagnostics write to the app's debug log and are not
  a Linux CLI contract.

## Unverified in this review

No authenticated provider requests or external network calls were made. The
Copilot `authorization_pending` and `authorized` events, real Soniox balances
and budget meters, Trae CN credits, Kimi gift balances and lapsed Code
subscriptions, Grok zero-usage weekly Credits, Cursor X Subscription pools,
Tavily null pay-as-you-go limits, the Claude limits-unavailable state, Claude
Cowork totals, and Mythos pricing remain unobserved. aarch64 binaries were not
executed.

## Probe method

Official assets matched their published SHA-256 files and GitHub asset digests:

- 0.80.0 glibc x86_64: `2ca09574fb7e3bd69b806f8ad96163768d29326f67087b12ceac4bdfe091f5f5`.
- 0.80.0 musl x86_64: `3c29d0cae26bb55bd2f4d175cd047c18f369322ed097e3e9f647dda703c15076`.
- 0.79.0 glibc and musl x86_64 archives also passed their published checksum
  files for the registry and crash comparisons.

Every CLI execution used `bwrap --unshare-all`, tmpfs over `/home`, `/root`,
`/run`, and `/tmp`, a cleared environment, and temporary home/config/cache
paths, with a 30-second outer deadline. Host credentials, history, network, and
IPC were inaccessible. Plugin discovery uses the passwd-derived home, so the
synthetic plugin was copied into that path inside the tmpfs, never the host
home. Approval used a sandbox pseudo-terminal and the official prompt for the
synthetic `https://example.com` origin; the plugin makes no HTTP request. The
synthetic Soniox key entered the supported writer through stdin. No CLI config
JSON was hand-edited. Source inspection used the exact 0.80.0 tag and the
official 0.79.0...0.80.0 comparison.
