# Linux parity review at CodexBar 0.85.0

Checked 2026-11-22 against Plasma commit
[`770c7c31`](https://github.com/Lucenx9/codexbar-plasma/commit/770c7c3134d26ebf4360ca07905981382afdc94d).
[CodexBar 0.85.0](https://github.com/steipete/CodexBar/releases/tag/v0.85.0),
commit `5dd48cab770a326691b25a124d37ffee12c5f7ac`, was published 2026-11-21 at
17:35:10 UTC. This is the only stable release since the
[0.84.0 review](2026-11-10-macos-parity-0.84.0.md). The
[tagged comparison](https://github.com/steipete/CodexBar/compare/v0.84.0...v0.85.0)
covers 85 commits. [TODO.md](../../TODO.md) owns follow-up work. The installed
CLI reports 0.84.0 and was used only to read its version. The full audit baseline
remains [0.56.2](2026-09-01-macos-parity-0.56.2.md).

## Linux CLI contract changes

- `config providers --format json --json-only` lists 115 providers. Google
  Developer Program (`googledeveloper`) and TrustedRouter (`trustedrouter`)
  are the new IDs. Each record includes a `setup` object. Copilot, OpenAI API,
  Azure OpenAI, DeepInfra, and ElevenLabs declare routes with platforms, methods,
  inputs, hints and, where applicable, capabilities or command text. Other
  entries return an unknown status with empty routes. The widget reads the
  existing `authentication` record and currently discards the new guidance.
  The `setup` data can augment read-only hints. Keep command text display-only
  and use the widget's existing supported writers for setup actions.
- Compared with the verified 0.84.0 registry, OpenAI API adds
  `OPENAI_ORGANIZATION_ID`, MiMo adds an API mode and key writer with
  `MIMO_API_KEY` and `MIMO_TOKEN_PLAN_REGION`, and SiliconFlow adds Web mode
  and a cookie writer. TrustedRouter and MiMo accept synthetic API keys
  through `config set-api-key --stdin`. Google Developer Program and SiliconFlow
  accept synthetic cookies through `config set-cookie --stdin`.
- Notion AI and Helmcode reject the Web source on Linux even after a synthetic
  cookie is saved. Their new authenticated usage remains unverified.
- Scoped usage with the four synthetic credentials exited 139 with empty
  output on glibc and musl in the offline sandbox. The glibc dashboard probe
  with those providers configured also exited 139. With a clean config,
  `dashboard --no-cost --identity redacted --timeout 1` returned schema 1
  with no `cost` field. The credential writes were verified. Network dispatch,
  the cause of exit 139, and authenticated output remain unverified.
- Standard `cost` with `--days 7 --format json --json-only` for Claude and Pi
  now emits project records with names, amounts, and optional paths and nested
  breakdowns. Synthetic Claude history emits 110 native tokens for
  `project-alpha` and 97 mirrored Pi tokens for `Unknown project`. Standalone
  Pi history emits 97 tokens for `project-beta`. On 0.84.0 both providers
  reported their respective provider totals with empty project lists.
  Plasma's normalization of the captured 0.85.0 JSON preserves the names and
  amounts for display and discards paths and nested source records.
- `cost --group-by session` produces session rows in text for Pi and native
  Claude, with an omission notice for mirrored Pi/OMP history on Claude.
  The grouped JSON still provides project totals and omits session rows.
  A session breakdown needs a typed JSON contract and stable identity.

## Plasma scope

- The new macOS Models view suggests a cross-provider view of the existing
  Plasma model breakdowns. Plasma currently exposes models inside each provider
  row, with separate currencies and partial-history limits.
- Upstream provider fetching, pricing, cache and refresh performance changes
  stay in the CLI. The new `serve` account selector, dashboard flags, macOS
  Keychain flows, and the separate Linux Quick View layout do not change the
  CLI commands or UI controls used by Plasma.

## Carried blockers rechecked

- The CLI rejects `config providers --descriptors`, `config action`,
  `config set-currency`, `usage --account-stdin`, and `cost --account`.
  The cost provider list still excludes Cursor.
- WorkBuddy's User-Agent, SiliconFlow's base URL, and MiMo's region have no
  writer in the current commands. The Azure OpenAI enterprise host and
  workspace ID and the OpenAI API organization ID are refused. DeepSeek
  rejects `config set-api-key`.
- Offline Codex status still emits the indicator, description, and URL.
  With no local OpenCode Go history, the CLI still returns a successful cost
  payload with unavailable totals. An empty session snapshot returns `[]`.
- An approved synthetic `audit-fixture` plugin returns a named quota and
  warning detail through `plugins fetch`. Scoped `usage` exits 1 with
  `provider: cli` and `error.kind: args` for the unknown ID. Earlier versions
  returned a Codex error for the same request. `config enable` rejects the
  custom ID as well.
- Synthetic 210,000-token Codex histories cost $0.50 on Standard and $3 on
  Ultrafast. The emitted cost JSON contains no tier field.
- One dated Codex transcript produces a schema 2 ledger with 200,000 input and
  10,000 output tokens in a direct `sessions` directory. The same transcript
  under a symlinked session root produces an empty ledger with `partial: false`.

## Probe environment

The official glibc x86_64 archive passed its published SHA-256 check
(`adaa5c7b4e09e26b135e5b958705a746189b289ade7fc3c26b1d0538259572a5`), as did
the musl x86_64 archive
(`65193fdc78f23d407592318b13b307782aea87721aa4eb25e525aaa7aefe19dc`).
Probes used `bwrap --unshare-all` with the real user directories hidden, an empty
credential environment, no external network, and synthetic inputs.
