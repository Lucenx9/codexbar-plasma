# Linux parity review at CodexBar 0.82.0

Checked 2026-10-27 against Plasma commit
[`3f67915`](https://github.com/Lucenx9/codexbar-plasma/commit/3f679155dd28f1abd2c42a83dd3924f788130ec7).
The official reference is [v0.82.0](https://github.com/steipete/CodexBar/releases/tag/v0.82.0),
commit `7749f7b94ae8f1b84b9ffb2046643cec810f4078`, published
2026-10-26 at 23:41:31 UTC. This covers the only stable release since the
[0.81.0 review](2026-10-25-macos-parity-0.81.0.md), including its unresolved
findings. It does not replace the full [0.56.2 audit](2026-09-01-macos-parity-0.56.2.md).
[TODO.md](../../TODO.md) owns follow-up work. This review implements no feature.
The installed `codexbar` command was neither executed against host data nor
replaced.

## Release coverage

| Release | Published | Commit | Linux-relevant changes |
| --- | --- | --- | --- |
| [0.82.0](https://github.com/steipete/CodexBar/releases/tag/v0.82.0) | 2026-10-26 23:41:31 UTC | `7749f7b94ae8f1b84b9ffb2046643cec810f4078` | `config set-cookie` and `config clear-credential` writers (#4765); Command Code saved subscription sessions selectable with `--account` (#4774); OpenCode Go reuses the active OpenCode CLI login (#4771); Kimi monthly Total breakdown (#4759); Codex fixed 30-day window pace (#4766); optional plugin detail-row `pace` (#4776); WorkBuddy paid-cycle resets (#4767); opt-in OpenCode history in Codex cost (#4757, app setting). |

## Linux CLI contract changes

- The isolated glibc and musl binaries report `CodexBar 0.82.0`. The
  registry is unchanged: 110 records with the same IDs, names, defaults, and
  four keys. Top-level, `usage`, `cost`, `sessions`, and `plugins` help are
  unchanged apart from the version line. `config` help adds two subcommands.
- `config set-cookie --provider <id> (--cookie <header>|--stdin) [--no-enable]`
  writes `cookieHeader`, sets `cookieSource` to `manual`, and enables the
  provider unless `--no-enable` is passed. JSON output is
  `{provider, enabled, configPath}` and never echoes the cookie; text output is
  `Config: stored manual cookie for <name> and enabled`. An empty value fails
  with `Missing cookie. Pass --cookie <header> or pipe it with --stdin.`
  (`kind: args`, exit 1). Providers whose fetchers read no manual config cookie
  are refused with `<id> does not support config cookies.` (for example
  `openrouter`). 0.81.0 rejects the subcommand as unknown.
- 49 of 110 providers accept `set-cookie`: abacus, alibaba, alibabatokenplan,
  amp, augment, claude, claudeplatform, codex, commandcode, copilot, cursor,
  deepseek, devin, factory, gemini, grok, helmcode, hyper, kimi, lithosai,
  longcat, manus, mimo, minimax, mistral, muse, museai, notion, ollama,
  opencode, opencodego, parallel, perplexity, qoder, qwencloud, raycast,
  replicate, sakana, stepfun, t3chat, tinyapi, traecn, typesafe, venice,
  windsurf, workbuddy, xapi, zed, zoommate. Windsurf takes its session bundle
  as compact single-line JSON.
- Acceptance does not mean Linux can fetch with the cookie. After a synthetic
  cookie, Auto usage reaches the provider's network fetch or its own cookie
  validation for claude, claudeplatform, commandcode, cursor, mistral, ollama,
  opencodego, parallel, raycast, tinyapi, traecn, typesafe, and xapi. Gemini
  Auto still picks the CLI OAuth strategy, and Gemini `--source web` reaches
  the network. Helmcode, Abacus AI, DeepSeek, Alibaba, and Manus still fail
  with `selected source requires web support and is only supported on macOS`
  under both Auto and `--source web`. Kimi and Copilot report `No available
  fetch strategy`. The same config file gives identical usage results on
  0.81.0, so 0.82.0 adds the writer and does not change the runtime gate.
- `config clear-credential --provider <id> [--api-key] [--cookie]` removes
  `apiKey` and `cookieHeader` (both without flags) and returns
  `{provider, cleared, configPath}`; `cleared` is empty when nothing was stored.
  Enablement, `source`, `cookieSource`, and token accounts are unchanged, so
  manual cookie mode stays selected after its header is cleared. An unknown
  provider fails with `Unknown or missing provider` (exit 1).
- Plasma has no cookie setup or credential removal action. `set-api-key` still
  refuses mistral and claudeplatform, so the new writer is the only supported
  way to configure those providers on Linux. This turns the manual-cookie part
  of the provider-settings blocker into implementable work, gated on 0.82.0
  and limited to providers whose Linux fetch reads the cookie.
- Command Code: Auto uses the selected saved subscription session, then an API
  key, then browser cookies. Explicit `--account`, `--account-index`, or
  `--all-accounts` selects saved sessions and web billing. The sessions are
  token accounts with no CLI writer; `set-cookie` writes the single
  `cookieHeader`, not a labeled account. Plasma's existing account selection
  is expected to list them, but no authenticated output was observed.
- OpenCode Go can report `source: "cli"` or `"local+cli"` when it reuses the
  OpenCode CLI login. Plasma shows the CLI source string; not observed here.
- Kimi adds a `Total usage` named window and a `Total usage` detail section
  splitting Kimi Code from other features. Both use existing generic fields.
- Detail-row `progress` gains optional `expectedUsed`, in the units of `used`,
  for a native pace marker. Only plugin rows set it, from a `pace` fraction;
  no bundled plugin uses it. `UsageDetails.normalizeSections` keeps
  `progress.fraction` only. Because the usage path still routes custom plugin
  IDs to Codex, no Plasma gap is recorded for it yet.
- Codex windows reported as fixed 30 days compute pace over 43,200 minutes.
  Plasma consumes the CLI's pace fields and needs no change.

## Plasma comparison

- New implementable gap: manual-cookie setup and credential clearing through
  the two new writers, for providers whose Linux fetch reads a manual cookie.
  Needs a version gate, the secure stdin prompt, a per-provider allowlist
  backed by probes, and no cookie in logs or diagnostics.
- The usage guide now tells users that the CLI writers exist and the widget
  does not offer them yet, including for Parallel and Claude Platform.
- Plugin menu-bar metric choice (#4781) is a macOS app preference stored with
  menu-bar layout settings; it changes no snapshot JSON. Plasma picks its own
  panel row, already tracked by the Auto panel-text decision.
- The Codex OpenCode local-history setting is an app preference with no CLI
  flag; `cost` help is unchanged.

The pinned source comparison is
[0.81.0...0.82.0](https://github.com/steipete/CodexBar/compare/v0.81.0...v0.82.0).
Relevant contract owners at 0.82.0 are the
[cookie writer](https://github.com/steipete/CodexBar/blob/7749f7b94ae8f1b84b9ffb2046643cec810f4078/Sources/CodexBarCLI/CLIConfigCookieCommand.swift),
the [credential clearer](https://github.com/steipete/CodexBar/blob/7749f7b94ae8f1b84b9ffb2046643cec810f4078/Sources/CodexBarCLI/CLIConfigClearCredentialCommand.swift),
the [CLI configuration guide](https://github.com/steipete/CodexBar/blob/7749f7b94ae8f1b84b9ffb2046643cec810f4078/docs/cli-configuration.md),
and the [detail row model](https://github.com/steipete/CodexBar/blob/7749f7b94ae8f1b84b9ffb2046643cec810f4078/Sources/CodexBarCore/ProviderDetailSection.swift).

## Carried-forward blockers rechecked

- `config providers --descriptors` is still an unknown option. `config action`
  is still an unknown subcommand.
- Cursor cost is still rejected; the supported list is unchanged. `cost
  --account synthetic` and `usage --account-stdin` still fail as unknown options.
- ClinePass `--label` still fails as a z.ai-only token-account option.
- `config set-currency` is still an unknown subcommand.
- `sessions --json-v2` still returns `[]` in the empty sandbox.
- `ProviderStatusPayload` (`CLIPayloads.swift`) is unchanged since 0.81.0.
- Custom-provider routing was not reprobed; `plugins` help is unchanged and
  the 0.81.0 result stands.
- The prior authenticated candidates remain open.

## Excluded from the Linux backlog

- Cursor encrypted app tokens through the Safe Storage Keychain item, the
  Alibaba/Qwen Keychain skip, separate automatic update checks and installs,
  the reorder Undo banner fade, hidden Version rows for web-only providers,
  Trae CN Visible usage item names, the WorkBuddy mascot, and the plugin
  menu-bar metric picker are macOS app behavior.

## Unverified in this review

No authenticated provider requests or external network calls were made. Real
manual-cookie fetches for any provider, Command Code saved sessions, the
OpenCode Go CLI-login source, the Kimi Total breakdown, Codex 30-day pace,
WorkBuddy resets, and plugin detail-row pace in `plugins fetch` output remain
unobserved. Custom-provider routing was not reprobed. aarch64 binaries were
not executed. The 0.81.0 unverified list carries over.

## Probe method

Official assets matched their published SHA-256 files:

- 0.82.0 glibc x86_64: `de1b083e0ddce2b92eb2e2d45026f3f88d889d974876e81fde9df7d83e19363e`.
- 0.82.0 musl x86_64: `4717dcd0ab9e45c57372a04c01a3e224e5883ea3cfaa71c8a475b2f90ff7d03a`.
- 0.81.0 glibc and musl x86_64 archives also passed their checksum files for
  the help, registry, and same-config usage comparisons.

Every CLI execution used `bwrap --unshare-all`, tmpfs over `/home`, `/root`,
`/run`, and `/tmp`, a cleared environment, and temporary home/config/cache
paths, with a 30-second outer deadline. Host credentials, history, network, and
IPC were inaccessible. Synthetic cookies and keys entered the supported writers
through stdin or `--cookie`. The 0.81.0 comparison reused the config file
written by 0.82.0 inside the sandbox; no config JSON was hand-edited. Source
inspection used the exact 0.82.0 tag and the official 0.81.0...0.82.0
comparison.
