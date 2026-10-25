# Linux parity review at CodexBar 0.81.0

Checked 2026-10-25 against Plasma commit
[`af775b8`](https://github.com/Lucenx9/codexbar-plasma/commit/af775b8a2e65fb3ff8aec59bd3d8a872907da0f6).
The official reference is [v0.81.0](https://github.com/steipete/CodexBar/releases/tag/v0.81.0),
commit `ee890b5f392e70d6e20162d3e95cf9f1be265b60`, published
2026-10-24 at 10:26:09 UTC. This covers the only stable release since the
[0.80.0 review](2026-10-23-macos-parity-0.80.0.md), including its unresolved
findings. It does not replace the full [0.56.2 audit](2026-09-01-macos-parity-0.56.2.md).
[TODO.md](../../TODO.md) owns follow-up work. This review implements no feature.
The installed `codexbar` command was neither executed against host data nor
replaced.

## Release coverage

| Release | Published | Commit | Linux-relevant changes |
| --- | --- | --- | --- |
| [0.81.0](https://github.com/steipete/CodexBar/releases/tag/v0.81.0) | 2026-10-24 10:26:09 UTC | `ee890b5f392e70d6e20162d3e95cf9f1be265b60` | abliteration.ai and Chatbox AI providers; Linux Auto web-support gate resolved per strategy (DeepSeek API key under Auto, and Gemini Auto); pipe-capture descriptor crash fix; passive Antigravity and CodeRabbit probes without CLI auto-updates; optional plugin window titles; plugin endpoint-not-configured error; Linux desktop launcher quoting (other frontend). |

## Linux CLI contract changes

- The isolated glibc and musl binaries report `CodexBar 0.81.0`. The fresh
  provider registry grows from 108 to 110 providers: `chatbox` (Chatbox AI)
  and `abliteration` (abliteration.ai), both disabled by default. The record
  keys stay `provider`, `displayName`, `enabled`, `defaultEnabled`.
  Empty-account `usage --provider all --format json --json-only` returns 110
  records. Top-level, `usage`, and `cost` help change only by these two
  provider IDs; `config`, `sessions`, and `plugins` help are unchanged apart
  from the version line.
- abliteration.ai and Chatbox AI use the existing single-key writer. Before
  setup, usage returns `No available fetch strategy for <id>`.
  `config set-api-key --provider <id> --stdin` with a synthetic key stores it
  and enables the provider; usage then reaches a network attempt that fails
  with `NSURLErrorDomain error -1003` without networking. The release-tag
  guides name `ABLITERATION_API_KEY` and `CHATBOX_LICENSE_KEY`; a saved key
  takes precedence. Chatbox expects a Chatbox **License Key** in the API-key
  field, not a provider API key, and the key can authorize AI requests.
  The descriptors label the lanes `Credits`/`Usage` (abliteration.ai) and
  `Plan`/`Top-up credits` (Chatbox AI), which reach Plasma through the existing
  `rateWindowLabels` field. Plasma's `supportsApiKeySetup` allowlist in
  `configProviders.qml` omits both, so their key setup is implementable now.
- The Linux web-support gate now runs after the fetch context is built and,
  for Auto, rejects a provider only when no non-web strategy is available
  ([#4749](https://github.com/steipete/CodexBar/commit/0827f30bf)).
  - DeepSeek: with a synthetic `DEEPSEEK_API_KEY` inside the sandbox, 0.80.0
    Auto fails with the macOS-only web error and 0.81.0 Auto reaches the API
    balance request (`Could not resolve host: api.deepseek.com`). Without a
    key, both versions keep the web error. `config set-api-key --provider
    deepseek` is still refused (`deepseek does not support config API keys`),
    so the key comes from the environment or a DeepSeek token account. Plasma
    has no DeepSeek setup and needs no change.
  - Gemini: 0.80.0 Auto still fails with the macOS-only web error. 0.81.0 Auto
    returns `Not logged in to Gemini. Run 'gemini' in Terminal to
    authenticate.` in the empty sandbox, the CLI OAuth strategy message that
    0.76.0 produced. The 0.77.0 Linux Gemini Auto regression is fixed in 0.81.0;
    the API-source workaround is needed only with CLI 0.77.0 through 0.80.0.
  - TypeSafe Auto and Trae CN Auto still fail with the macOS-only web error.
- Standard plugin windows accept an optional `title`. A synthetic local plugin
  approved inside the sandbox returns `"primary":{"title":"Requests",…,
  "resetDescription":"Resets monthly"}` from `plugins fetch audit-fixture
  --json`, with its `severity: warning` row. `rateWindowLabels` is derived from
  built-in descriptors only, so a user plugin's titles could reach Plasma only
  through the usage path, which still routes the custom ID to Codex (see
  below). No new Plasma gap is recorded for titles beyond that blocker.
- Unset plugin endpoint settings now fail with a configuration error
  (`Configure endpoint settings`) instead of a URL validation error. Plasma
  shows the CLI error text and needs no change.

## Plasma comparison

- abliteration.ai and Chatbox AI key setup are the new implementable gaps,
  alongside the still-open Soniox entry. Chatbox needs license-key wording.
- The Gemini Auto blocker is resolved by an official release. The usage guide
  keeps the API-source workaround for CLI 0.77.0 through 0.80.0 and tells users
  to switch back to Automatic after updating; Plasma still never rewrites the
  saved source.
- macOS 0.81.0 names the selected window in Auto percentage, pace, and reset
  tokens (`5h 84%`, `W +7%`) when several windows exist, behind the existing
  Show window labels option. This is app rendering in
  `MenuBarLayoutRenderer.swift`, not CLI output. Plasma's Auto panel text picks
  a row in `PanelDisplay.rowForMode` without naming its lane. This is a
  Plasma-native candidate, recorded for a bounded decision.
- The pipe-capture crash fix, passive `agy`/CodeRabbit probes without
  auto-update downloads, and Claude OAuth recovery belong to the CLI and
  change no emitted field. Plasma's periodic usage refreshes benefit without
  a change.
- Usage & Spend session search, sorting, and request inspection read app-side
  models (`SpendDashboardModel.swift`); `sessions` help and its empty-sandbox
  `--json-v2` output are unchanged, so no new Linux contract exists.
- Plugin refresh errors with last-good data and its age are app-side
  (`UsageStore+UserPlugins.swift`). Plasma already keeps its own cache and
  error presentation for CLI records.

The pinned source comparison is
[0.80.0...0.81.0](https://github.com/steipete/CodexBar/compare/v0.80.0...v0.81.0).
Relevant contract owners at 0.81.0 are the
[usage web-support gate](https://github.com/steipete/CodexBar/blob/ee890b5f392e70d6e20162d3e95cf9f1be265b60/Sources/CodexBarCLI/CLIUsageCommand.swift),
the [DeepSeek source-mode test](https://github.com/steipete/CodexBar/blob/ee890b5f392e70d6e20162d3e95cf9f1be265b60/TestsLinux/DeepSeekSourceModeTests.swift),
the [Chatbox guide](https://github.com/steipete/CodexBar/blob/ee890b5f392e70d6e20162d3e95cf9f1be265b60/docs/chatbox.md),
the [abliteration.ai guide](https://github.com/steipete/CodexBar/blob/ee890b5f392e70d6e20162d3e95cf9f1be265b60/docs/abliteration.md),
and the [plugin snapshot contract](https://github.com/steipete/CodexBar/blob/ee890b5f392e70d6e20162d3e95cf9f1be265b60/docs/plugins.md#snapshot-result).

## Carried-forward blockers rechecked

- `config providers --descriptors` is still an unknown option. `config action`
  is still an unknown subcommand.
- Cursor cost is still rejected; the supported list is unchanged (Antigravity,
  Claude, Codex, Muse Code, OpenCode Go, Pi). `cost --account synthetic` and
  `usage --account-stdin` still fail as unknown options.
- ClinePass `--label`, Future AGI `--workspace-id`, and Vercel
  `--workspace-id` still fail as z.ai-only token-account options.
- `config set-currency` is still an unknown subcommand.
- Custom-provider routing is still broken. After sandbox approval, `plugins
  fetch audit-fixture --json` returns the synthetic window, title, and warning
  row, yet `usage --provider audit-fixture` returns `provider: codex` with
  `No available fetch strategy for codex`.
- `sessions --json-v2` still returns `[]` in the empty sandbox.
- `usage --status` for Claude still emits only `indicator`, `description`,
  and `url` offline; no component tree.
- The prior authenticated candidates (Copilot pending/authorized events,
  Soniox meters, Kimi, Grok, Cursor X Subscription, Tavily, Claude
  limits-unavailable, the 0.78.0/0.79.0 set, Claude Platform, throughput,
  imported incomplete costs) remain open.

## Excluded from the Linux backlog

- Menu-bar stacked text weight, Sparkle Markdown release notes, Homebrew
  bundle repair, wide Settings windows on macOS 26, Claude Keychain MCP-only
  recovery, and Trae CN parent-domain cookie import are app-owned macOS
  behavior.
- The Linux desktop launcher quoting fix ([#4715](https://github.com/steipete/CodexBar/commit/d4207d4f6))
  belongs to the upstream GTK/desktop integration, not Plasma.
- The Kiro probe documentation changes no contract.

## Unverified in this review

No authenticated provider requests or external network calls were made. Real
abliteration.ai balances, Chatbox AI plan, reward, top-up, and image pools, the
DeepSeek API balance under Auto, a signed-in Gemini Auto fetch, and the
CLI-only effect of the pipe-capture and auto-update fixes remain unobserved.
aarch64 binaries were not executed. The 0.80.0 unverified list carries over.

## Probe method

Official assets matched their published SHA-256 files and GitHub asset digests:

- 0.81.0 glibc x86_64: `24f962e2f3edfc201738e3496b42cec74692b6e142e5c89ecbb93c61a7b9647d`.
- 0.81.0 musl x86_64: `c6fbce6d4450ba8a277e35045f4a155626b419938ec76e5886c7d50882bf901c`.
- 0.80.0 glibc and musl x86_64 archives also passed their published checksum
  files for the registry, help, DeepSeek, and Gemini comparisons.

Every CLI execution used `bwrap --unshare-all`, tmpfs over `/home`, `/root`,
`/run`, and `/tmp`, a cleared environment, and temporary home/config/cache
paths, with a 30-second outer deadline. Host credentials, history, network, and
IPC were inaccessible. The synthetic `DEEPSEEK_API_KEY` existed only inside the
sandbox. Plugin discovery uses the passwd-derived home, so the synthetic plugin
was written into that path inside the tmpfs, never the host home. Approval used
a sandbox pseudo-terminal and the official prompt for the synthetic
`https://example.com` origin; the plugin makes no HTTP request. Synthetic keys
entered the supported writer through stdin. No CLI config JSON was hand-edited.
Source inspection used the exact 0.81.0 tag and the official 0.80.0...0.81.0
comparison.
