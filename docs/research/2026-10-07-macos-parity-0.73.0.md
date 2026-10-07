# Linux parity review at CodexBar 0.73.0

Checked 2026-10-07 against Plasma commit
[`6879315`](https://github.com/Lucenx9/codexbar-plasma/commit/68793150f15ef56044511bf012071735527f5c4e).
The official reference is
[`v0.73.0`](https://github.com/steipete/CodexBar/releases/tag/v0.73.0),
commit [`1d313fe50a361fc0a12383da0cdc11a75f59daa5`](https://github.com/steipete/CodexBar/commit/1d313fe50a361fc0a12383da0cdc11a75f59daa5),
published 2026-10-07 at 12:26:56 UTC.

This release-delta review covers the one stable release after the
[0.72.0 review](2026-10-05-macos-parity-0.72.0.md). It does not replace the full
[0.56.2 contract audit](2026-09-01-macos-parity-0.56.2.md). Current work belongs
in [TODO.md](../../TODO.md); this PR records evidence without implementing it.

## Release coverage

| Release | Published | Commit | Linux-relevant observations |
| --- | --- | --- | --- |
| [0.73.0](https://github.com/steipete/CodexBar/releases/tag/v0.73.0) | 2026-10-07 | `1d313fe50a361fc0a12383da0cdc11a75f59daa5` | Persistent `config set-source` (#4142, #4197); Langdock registry addition (#4171); ClinePass labeled-account claim (#4305); managed Codex accounts and dashboard snapshots (#3191, #4234, #4184); private Linux desktop snapshot enrichment (#4285); hooks `all`/`both` selectors (#4252); Kimi monthly/contradictory windows (#4306), Ollama Free quota (#4308), JetBrains top-up/log quotas (#4287, #4288), Antigravity consumer OAuth (#4293); Codex partial pricing, ledger deduplication, long-context/Priority pricing and catch-up fixes (#4273, #4278, #4279, #4270, #4274, #4276, #4289, #4290, #4296, #4302); imported incomplete models (#4299). |

## Linux CLI contract changes since 0.72.0

- **Persistent source writes are available (verified before and after).**
  0.72.0 rejects `config set-source` as an unknown subcommand. 0.73.0 accepts
  `config set-source --provider codex --source api --format json --json-only`.
  Its object carries `provider`, `displayName`, `enabled`, `source`, and
  `configPath`. A prior supported `config disable` leaves Codex disabled after
  this write. The redacted `config dump` then contains `source: api` for Codex;
  setting `auto` removes that property while leaving enablement unchanged.
  With a synthetic ClinePass key stored through `set-api-key --stdin`, setting
  its source to `api` preserves the redacted key and its enabled state.
  Unknown source names fail; `pi --source web` fails with supported sources
  listed as `auto`, without creating a Pi source override. Codex `web` is
  accepted, so source validation is provider-specific rather than a frontend
  guess about Linux fetch reachability. The registry still does not advertise
  a source-choice descriptor. Plasma currently has a global request override,
  not a persistent provider editor; this is **implementable now** with version
  checks, CLI-owned validation, safe failure handling, and the existing global
  override preserved. TODO separates it from the remaining generic-settings
  blocker.

- **Registry grows from 90 to 91 records (verified in emitted output).**
  Langdock is the sole addition, with `defaultEnabled: false` and
  `enabled: false`. Existing IDs and flags are unchanged. Every record still
  has only `provider`, `displayName`, `enabled`, and `defaultEnabled`.
  `set-api-key --provider langdock --stdin` refuses config API keys; default
  usage returns the macOS-only web runtime error, and explicit `--source api`
  is unsupported. Its pinned [descriptor](https://github.com/steipete/CodexBar/blob/v0.73.0/Sources/CodexBarCore/Providers/Langdock/LangdockProviderDescriptor.swift)
  selects one Edge profile and supplies the upstream icon, dashboard, and
  color. Plasma's provider-list normalizer accepts the emitted name and uses
  generic artwork for unknown providers. Bundled fallback metadata is
  **implementable now**; browser-profile setup and live Langdock data are
  **macOS-only** at this release and must not gain a dead key action.

- **ClinePass labeled-key writes remain blocked (verified before and after).**
  Despite #4305's release wording, both official Linux assets reject
  `config set-api-key --provider clinepass --label 'Synthetic A' --stdin`
  with `Token-account options are only supported for --provider zai.` A second
  label fails identically. A single unlabeled ClinePass key succeeds on 0.73.0,
  but this does not create labeled token accounts. The released
  [config command](https://github.com/steipete/CodexBar/blob/v0.73.0/Sources/CodexBarCLI/CLIConfigCommand.swift)
  retains the restriction. Keep the token-account writer blocker and never
  implement the claim by editing config JSON.

- **Empty cost and usage envelopes are unchanged (verified in emitted output).**
  Codex, Claude, and Pi empty-history cost records have the same 17 keys on both
  versions. Antigravity has the same 12 keys and omits cost/token totals; Grok
  is rejected by `cost` on both versions. Empty Pi usage has unchanged keys
  (`provider`, `source`, `usage`, with null primary/secondary/tertiary windows).
  `cost --provider pi --period all` reports `historyDays: 739898` on both
  versions, two days after the 0.72.0 review's 739896; the widget's 365-day chart
  bound remains needed. Empty records cannot establish the new mixed-pricing
  semantics, provider quotas, or credit inventory.

- **Managed Codex commands remain macOS-only (verified in emitted output).**
  0.72.0 rejects `codex-accounts` as unknown; 0.73.0 registers it but
  `codex-accounts list --format json --json-only` returns
  `Managed Codex account commands are only available on macOS.` No promotion
  was attempted. One-shot `dashboard --timeout 2` emits schema version 1 with
  ordinary enabled-provider records; the isolated account has no managed Codex
  accounts. Managed account/dashboard enrichment is **macOS-only** for this
  release, not a new Linux account-management contract.

- **Private Linux desktop snapshots are a separate application contract.**
  #4285 enriches `codexbar-linux --snapshot`, through its private same-user
  socket, with plan, balances, extra usage, reset credits, pace, and opt-in
  cached spending. The pinned [Linux guide](https://github.com/steipete/CodexBar/blob/v0.73.0/Integrations/Linux/README.md)
  requires a running desktop app and describes its cache and redaction rules.
  Plasma invokes `codexbar usage`/`cost` directly and owns its process lifecycle;
  this separate desktop dependency is a **non-goal**. These snapshot fields
  do not prove that standard usage JSON emits equivalent data. The shared
  top-level reset-credit payload change is recorded below as unverified.

## Carried-forward blockers, rechecked at 0.73.0

- `config providers --descriptors` still returns `Unknown option --descriptors`.
  Source persistence now has a writer, but generic field metadata, cookies,
  base URLs, workspaces, other settings, and token-account editors remain
  blocked. No provider record gains a descriptor.
- `config action` still returns an unknown-subcommand error. `set-source` is a
  field writer, not browser import, OAuth/device setup, or a generic action.
- `cost --provider cursor` still refuses Cursor with the unchanged supported
  list: Antigravity, Claude, Codex, Muse Code, and Pi.
- The inspected top-level, usage, cost, and config help exposes no Linux
  display-currency setter. `config preferences export` remains macOS-only;
  idle `sessions --json-v2` still emits `[]`.
- Older authenticated/history/tier/availability/localization blockers retain
  their last measured versions. This scoped probe does not establish that
  those fields are absent in every authenticated 0.73.0 payload.

## Excluded from the Linux backlog

- Week/month spend grouping, hourly drill-down, source filters, amount inspector,
  statistics time-zone settings (#4298, #4185), activity-grid contrast/paging
  (#4297), and spend artwork (#4294) are macOS presentation surfaces. Existing
  Plasma daily/model/project views remain supported; no new Linux history or
  reporting-time-zone contract was established here.
- Extra-allowance menu-bar metric selection (#4207) and Nous automatic balance
  text (#4314) are macOS layouts. Plasma already renders extra quota windows;
  typed balance text remains tracked under the existing contract blocker.
- Managed Codex promotion safeguards (#4301), sibling macOS snapshot retention
  (#4307), Keychain prompt/cache recovery (#4257, #4271), and app quit-time
  config flushing (#4224) belong to macOS app/account effects. Plasma keeps its
  own account cache, stale-response guards, and immediate CLI config writes.
- Pricing thresholds and Priority evidence, ledger repairs, scan catch-up,
  single-build reports, streamed SQLite rows and Claude/Vertex history memory
  reduction (#4275, #4277, #4286, #4291), Vertex pagination bounds (#4318), Claude
  hooks suppression/configuration-error classification (#4292, #4225),
  Antigravity version-process reuse/pricing (#4254, #4258), and PTY diagnostics
  are CLI-owned parsing, pricing, safety, or performance. They need no QML port.
- Hooks watch selector normalization (#4252) belongs to CLI automation; Plasma
  owns its notification planner and does not invoke `hooks watch`. This review
  inspected its help but did not run a persistent watcher.
- Hosted CI sharding affects upstream development, not the widget's workflows.

## Unverified in this review

- **Top-level Codex reset-credit summary.** The pinned
  [CLI payload source](https://github.com/steipete/CodexBar/blob/v0.73.0/Sources/CodexBarCLI/CLIPayloads.swift)
  adds `resetCredits: {available, nextExpiresAt?}` projected from Codex inventory.
  Plasma currently reads `usage.codexResetCredits.availableCount`; tests cover
  that legacy path. Neither empty Pi output nor private desktop snapshots
  confirms live standard usage output. TODO requires an isolated reproduction
  with nonzero, zero, and expired inventory before accepting a normalization
  change or treating this summary as a verified contract.
- **Mixed-priced daily/model costs and imported incomplete model rows**
  (#4273, #4278, #4279, #4299). Empty records establish the envelope only. No
  synthetic recorded-history reproduction ran here. Plasma's incomplete-request
  counts and trust/sharing rules already exist; verify actual nonempty output
  before declaring their compatibility or a gap.
- **Authenticated quota/credit changes:** Kimi contradictory readings and Monthly
  Total (#4306), Ollama Free usage (#4308), JetBrains top-up/log fallback
  (#4287, #4288), and Antigravity consumer OAuth/re-sign-in behavior (#4293).
  No signed-in provider files or network were available inside the sandbox.
  These join the measured-window candidate in TODO. Older Claude, Mistral,
  Antigravity, Cursor, and credit/detail candidates remain unresolved.

## Probe method

Both official Linux x86_64 archives matched their release SHA-256 files:

- 0.73.0: `a84f556c7ecebc8e606e0a34ee0d121626f72d7afc1e3adf5746410bc10f9611`.
- 0.72.0: `1772b5a2f4d68b959cd969a8997e4141474959f5cc89adff15b134d075b78b70`.

The extracted assets ran under `bwrap --unshare-all`, with tmpfs mounts over
`/home`, `/root`, `/run`, and `/tmp`, a cleared environment, temporary `HOME`,
`XDG_CONFIG_HOME`, and `XDG_CACHE_HOME`, and no host network/IPC or provider
history. All synthetic keys entered via subprocess stdin, never command-line
arguments. Config changes used supported CLI commands; `config dump` was read
only in its default redacted form. The installed CLI was discovered with
`command -v codexbar` and was neither replaced nor used for account probes.
The desktop asset was not launched. Temporary outputs remain in ignored
`dist/review/` and the OS temporary directory.
