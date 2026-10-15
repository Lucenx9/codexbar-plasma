# Linux parity review at CodexBar 0.75.0

Checked 2026-10-15 against Plasma commit
[`ca9f586`](https://github.com/Lucenx9/codexbar-plasma/commit/ca9f586f6ea2710eb425dfc9135ea76260a016eb).
The official reference is [v0.75.0](https://github.com/steipete/CodexBar/releases/tag/v0.75.0),
commit `4668969c8507d75e2f173b72a742c92f97e60344`, published
2026-10-14 at 00:59:30 UTC. This covers the stable release since the
[0.74.1 review](2026-10-14-macos-parity-0.74.1.md), including unresolved findings.
It does not replace the full [0.56.2 audit](2026-09-01-macos-parity-0.56.2.md).
[TODO.md](../../TODO.md) owns follow-up work. No feature is implemented here.
The installed `/usr/local/bin/codexbar` reports 0.74.1 and was not replaced.

## Release coverage

| Release | Published | Commit | Linux-relevant changes |
| --- | --- | --- | --- |
| [0.75.0](https://github.com/steipete/CodexBar/releases/tag/v0.75.0) | 2026-10-14 | `4668969c8507d75e2f173b72a742c92f97e60344` | Parallel, fal, FLORA; Command Code API authentication; OpenAI live throughput; identified Codex request subtotals; project-report partial-history notices; Auto-review pricing; JetBrains log parsing; browser imports and OpenCode Go caching. Claude spend-only meters and macOS menu/settings presentation also changed. |

## Linux CLI contract changes

- `config providers --json` returns 103 records with the same four keys:
  `provider`, `displayName`, `enabled`, `defaultEnabled`. Parallel, fal, and
  FLORA are new. Plasma's generic discovery remains usable, but their static
  names, links, colors, and original icons have no mappings in
  `ProviderIdentity.js` and `ProviderNames.qml`. Those mappings are
  implementable independently of authentication, with generic fallbacks retained.
- Command Code and fal accept `config set-api-key --stdin`. Command Code also
  accepts `config set-source --source api`; synthetic-key usage reaches
  `api.commandcode.ai` and fails DNS in the offline sandbox. fal reaches its
  API and fails DNS too. These prove supported setup and runtime reachability,
  not successful billing data. Plasma's `supportsApiKeySetup` excludes both,
  so adding the supported key actions is implementable now. Command Code's
  [descriptor](https://github.com/steipete/CodexBar/blob/v0.75.0/Sources/CodexBarCore/Providers/CommandCode/CommandCodeProviderDescriptor.swift)
  selects API in Auto when a key exists, otherwise web.
- FLORA accepts the key writer but usage requires `FLORA_WORKSPACE_ID`.
  `set-api-key --workspace-id` refuses it as z.ai-only. Its
  [plugin](https://github.com/steipete/CodexBar/blob/v0.75.0/Sources/CodexBarCore/Resources/Plugins/flora.js)
  emits generic detail rows for balance, member limits, and month-to-date spend.
  Workspace setup is blocked on a supported field writer; no config editing
  or environment-specific workaround belongs in QML. Parallel refuses both
  API-key setup and API source. Its browser-session setup remains blocked
  on generic cookie actions.
- `cost --identified-only --provider codex --json` is accepted. With no native
  history it exits 1 with `allSourcesAvailable: false`, `partial: true`, and
  a local report saying identified usage is unavailable. Help documents
  `--identified-end`, strong-identity deduplication across SSH histories,
  exclusion of legacy/unidentified usage, unavailable prices, and incompatibility
  with period/grouping/summary modes. This is a separate subtotal contract,
  not a replacement for existing Plasma cost refreshes. Positive, deduplicated,
  and partial remote output needs synthetic-history verification before UI design.
- Empty Codex cost still has 17 keys; `--group-by project` is accepted and
  yields an empty projects list. The project partial-history notice fix is
  in CLI text rendering, not a new JSON field. Auto-review pricing from
  October 6 and OpenCode Go scan caching belong to the CLI. No QML pricing or
  history scanner is justified. Pi `--period all` still reports year-1 history,
  `historyDays: 739906` on this probe date; existing bounded handling remains needed.
- OpenAI's [plugin](https://github.com/steipete/CodexBar/blob/v0.75.0/Sources/CodexBarCore/Resources/Plugins/openai.js)
  adds minute buckets and model/token throughput through its card mapper.
  [UsageSnapshot](https://github.com/steipete/CodexBar/blob/v0.75.0/Sources/CodexBarCore/UsageFetcher.swift)
  includes `throughput` in coding keys. This is source evidence only;
  authenticated Linux output, delayed/pending semantics, and manual per-credential
  rate-limit writers remain unverified. Plasma has no throughput normalization.

## Carried-forward blockers rechecked

- `config providers --descriptors` still fails with `Unknown option --descriptors`;
  `config action` remains unknown. Registry/help expose no display-currency
  descriptor or writer. Generic settings, onboarding, and currency stay blocked.
- ClinePass labeled stdin writes still reject token-account options as z.ai-only.
- Cursor cost still fails and lists Antigravity, Claude, Codex, Muse Code, and Pi.
- Empty Pi usage retains local estimated confidence and null quota windows;
  idle `sessions --json-v2` returns `[]`. Current Plasma already preserves and
  qualifies estimated confidence and supports subscription dates; the previous
  review's implemented gaps must not be reintroduced.
- Reset-credit inventory, mixed priced/unpriced history, funded credit flags,
  detail-row IDs, account identity, and older quota candidates retain their
  earlier evidence. Empty records cannot establish authenticated behavior.
  xAI optional invoice estimates and Command Code actual plan responses remain
  unverified; the new Command Code key path only removes its setup obstacle.

## Excluded from the Linux backlog

- Graphical menu tokens, stacked presets, two-row icons, Cursor lane tags,
  Cost menu renaming, meter restoration, Settings Undo/filter behavior, and
  macOS card error presentation are native app changes. Plasma already has
  its own panel meters and provider search; no direct port is required.
- Browser ordering, Keychain cooldowns, Files & Folders errors, Kimi Desktop
  sessions, TypeSafe/Charm Hyper imports, and JetBrains log parsing are CLI
  authentication/parsing responsibilities. Browser import changes do not supply
  the missing Linux setup writer/action.
- Claude's spend-only calendar-month meter is a presentation helper
  [claudeMonthlySpendWindow](https://github.com/steipete/CodexBar/blob/v0.75.0/Sources/CodexBarCore/Providers/Claude/ClaudeMonthlySpendWindow.swift).
  It infers UTC rollover from observation time. Do not infer an authoritative
  reset in Plasma; verify emitted spend/reset fields first.
- The macOS more-than-three Codex account refresh fix and native detail-tab
  retention change app refresh ownership, not a new standard CLI account schema.
  The Devin mark is upstream artwork; Plasma keeps its original icons.

## Unverified in this review

No authenticated provider output or network call was performed. Positive
Command Code/fal billing, FLORA workspace balances, Parallel cookies, OpenAI
throughput and rate-limit selection, Claude spend-only resets, and newer
JetBrains quotas need safe output evidence. Identified-request success and SSH
partial/deduplication cases need synthetic histories and a controlled remote
fixture. Auto-review pricing and mixed-price cost trust were source-reviewed
only. These limits preserve the earlier TODO verification candidates.

## Probe method

The official Linux x86_64 archive matched its release SHA-256 file:
`7920c8e42a64aa5dc249bdb3a745e8ec91a062cb2668b78dc9266dfffa0d7ad7`.
Every CLI probe used `bwrap --unshare-all`, tmpfs over `/home`, `/root`, `/run`,
and `/tmp`, a cleared environment, temporary home/config/cache, and a synthetic
home bind over `/home/simone` for passwd-based discovery. Host credentials,
history, network and IPC were inaccessible. Each process had a 25-second
external deadline; none timed out. Synthetic keys entered through stdin, never
argv; config writes used official commands. The sources were inspected at the
exact release tag. Temporary archives, scripts and probe results remain in
ignored `dist/review/075/`; they are not product files.
