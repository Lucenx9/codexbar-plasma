# Linux parity review at CodexBar 0.79.0

Checked 2026-10-21 against Plasma commit
[`8826e05`](https://github.com/Lucenx9/codexbar-plasma/commit/8826e05cc68755131e111a7a6adaebbfc366e637).
The official reference is [v0.79.0](https://github.com/steipete/CodexBar/releases/tag/v0.79.0),
commit `b49d42eb53bbf79785b344492d594760dd163eac`, published
2026-10-20 at 23:29:02 UTC. This covers both stable releases since the
[0.77.0 review](2026-10-17-macos-parity-0.77.0.md), including its unresolved
findings. It does not replace the full [0.56.2 audit](2026-09-01-macos-parity-0.56.2.md).
[TODO.md](../../TODO.md) owns follow-up work. This review implements no feature.
The installed command resolves to `/usr/local/bin/codexbar`; it was neither
executed against host data nor replaced.

## Release coverage

| Release | Published | Commit | Linux-relevant changes |
| --- | --- | --- | --- |
| [0.78.0](https://github.com/steipete/CodexBar/releases/tag/v0.78.0) | 2026-10-19 18:29:35 UTC | `0276fd64a0efd0314ae995a5bdd6452aeb149561` | OpenCode Go local cost; Claude Auto OAuth priority and active claude-swap selection; Cowork cost transcripts; incremental Claude/Vertex caches; Pi token-only history; Grok billing; Vercel personal budgets; detail-row severity; custom plugin SVGs; account Overview and editing. |
| [0.79.0](https://github.com/steipete/CodexBar/releases/tag/v0.79.0) | 2026-10-20 23:29:02 UTC | `b49d42eb53bbf79785b344492d594760dd163eac` | Linux libxml2 removal, provider catalog IDs, TypeSafe User-Agent, desktop installer XDG fallback; Vercel budget identity; Cursor additional spend; Antigravity quota buckets/history; Claude cache memory; ILS display currency. |

## Linux CLI contract changes

- Both isolated binaries report the expected version. Their fresh provider
  registries contain the same 106 providers and four keys as 0.77.0:
  `provider`, `displayName`, `enabled`, `defaultEnabled`. Empty-account
  `usage --provider all --format json --json-only` returns 106 records in both
  versions. No registry descriptor or icon data is exposed.
- `readelf -d` shows `libxml2.so.2` in the 0.78.0 x86_64 glibc binary and no
  libxml2 dependency in 0.79.0. Both start on this host, which has libxml2.
  This verifies the artifact change, not an Ubuntu 26.04 installation.
- `cost --provider opencodego --format json --json-only` is accepted in both
  releases. With no local database it returns an `opencodego`, `source: local`
  error record with empty daily/projects arrays, rather than an argument error.
  A synthetic SQLite database in 0.79.0 produces USD 1.25, 150 tokens,
  input/output counts of 100/50, one daily/model breakdown, `rolling:30`,
  established coverage, and `listPriceEstimate` provenance. `--provider all`
  includes this record too. Plasma's production `CostResponse.response`
  consumes the captured record unchanged: an executed temporary QtTest confirms
  the total amounts and model label. `CostController` already forwards the
  selected provider and `CostResponse` accepts generic provider IDs, so this
  contract needs no new scanner or provider allowlist in Plasma.
- Detail-row `severity` is an optional typed value, independent of `progress`.
  A synthetic local plugin, approved through the official interactive
  `plugins fetch` command inside the sandbox, emits `severity: warning` in
  Linux JSON. The release-tag mapper accepts only `normal`, `warning`, and
  `critical`. Plasma's `UsageDetails.normalizeSections` currently drops this
  field. Supporting bounded severity and accessible indicators is implementable
  now, without deriving severity from a percentage.
- Catalog IDs work for the built-in alias case: `usage --provider azureopenai`
  returns `provider: azureopenai` and its missing-key error on 0.79.0.
  Custom-provider routing remains broken in the tested official artifact.
  A file declaring `audit-fixture` is listed by `plugins list`, and
  `plugins fetch audit-fixture --json` returns its 25% quota and warning row.
  Yet `usage --provider audit-fixture --format json --json-only` returns
  `provider: codex` and `No available fetch strategy for codex`, even after
  approval. This is an official CLI routing blocker, despite the #4643 release
  claim. Plasma must not fetch plugins separately or relabel that Codex record.
- Vercel personal budgets need `VERCEL_ACCESS_TOKEN` and `VERCEL_TEAM_ID`.
  With a synthetic token only, Linux 0.79.0 requests the Team ID. Supplying
  both as sandbox environment values reaches a network attempt, which fails
  with `NSURLErrorDomain error -1003` without networking. The supported
  `set-api-key --provider vercel --workspace-id team_fixture --stdin` writer
  still rejects the extra option as z.ai-only. The release-tag descriptor
  stores the token in `pluginSecrets` and the team in `workspaceID`, but neither
  has a supported dedicated writer. Personal-budget setup is therefore blocked;
  the existing single gateway-key path remains separate.
- The managed installer's `unpack` accepts both checksum-verified archives.
  `release_assets` accepts glibc and musl metadata for x86_64 and aarch64 for
  both releases. These are validation/extraction checks, not activation or
  execution on other architectures.

## Plasma comparison

- OpenCode Go local cost fits the existing generic daily/model/trust path.
  The synthetic request uses a local database fixture derived from the pinned
  upstream reader tests. No host OpenCode database or login was read.
- Detail severity is a confirmed Plasma-native gap. Inline SVG plugin icons
  are different: the provider registry has no icon payload, so the macOS icon
  manifest does not authorize QML to read plugin source files. Plasma retains
  its static/generic icon fallback.
- macOS Overview can now expand providers into account rows. Plasma's Overview
  projects selected provider snapshots; account choices remain in provider
  details. Record this as a candidate requiring authenticated multi-account
  Linux output and a bounded design, rather than assuming app caches are a
  portable CLI contract. Saved account editing/reordering remains blocked on
  official writers.
- The macOS Show window labels toggle is a product candidate, not a contract
  gap. Plasma already offers separate percent, pace, reset, and run-out text
  modes; evaluate a bare-percent option against its existing identification
  and accessibility behavior before accepting implementation work.
- Agent Sessions local-only mode and Tailscale discovery changes apply to the
  macOS remote-monitoring owner. The Linux `sessions --help` still advertises
  live local sessions only, and `sessions --json-v2` returns `[]` in the empty
  sandbox. Plasma's `SessionsController` already invokes that local command.
- Claude/Vertex cache writes, Cowork scanning, Pi cache scope/token-only pricing,
  Grok ACP billing, Antigravity fetching/history bounds, and Claude malformed
  weekly-limit handling belong to the CLI. Their fixes do not justify provider
  parsing or local history scanning in QML.

The pinned source comparison is
[0.77.0...0.79.0](https://github.com/steipete/CodexBar/compare/v0.77.0...v0.79.0).
Relevant contract owners at 0.79.0 are
[detail rows](https://github.com/steipete/CodexBar/blob/b49d42eb53bbf79785b344492d594760dd163eac/Sources/CodexBarCore/ProviderDetailSection.swift),
[Vercel setup](https://github.com/steipete/CodexBar/blob/b49d42eb53bbf79785b344492d594760dd163eac/Sources/CodexBarCore/Providers/Vercel/VercelProviderDescriptor.swift),
and the [OpenCode Go reader tests](https://github.com/steipete/CodexBar/blob/b49d42eb53bbf79785b344492d594760dd163eac/Tests/CodexBarTests/OpenCodeGoLocalUsageReaderTests.swift).

## Carried-forward blockers rechecked

- Both versions reject `config providers --descriptors`. On 0.79.0,
  `config action` is an unknown subcommand; invoking it with `--help` merely
  prints config help and is not evidence of an action contract.
- Both versions reject Cursor cost, now listing OpenCode Go alongside
  Antigravity, Claude, Codex, Muse Code, and Pi. Empty Codex cost retains its
  17-key envelope and no service-tier fields. `cost --account synthetic` still
  fails. Local costs remain independent of the selected usage account.
- 0.79.0 still rejects `usage --account-stdin`; private account selection
  remains blocked on a supported input contract or verified stable mapping.
- Gemini Auto still reports the macOS-only web error in both versions. The
  existing explicit API-source workaround remains necessary. TypeSafe Auto
  also remains macOS-gated with empty supported configuration; #4648 fixes
  requests after cookie setup, not the missing cookie writer.
- ClinePass `--label` and Future AGI `--workspace-id` still fail as z.ai-only
  in both releases. Descriptors/actions and multi-field writers remain absent.
  Vercel's new personal-budget setup joins that existing blocker.
- Both versions reject `config set-currency USD`. Adding ILS to the macOS
  preference does not provide a Linux currency-conversion contract.
- The prior Munito/Future AGI, claude-swap/tcr, per-account Claude cost,
  authenticated credit/billing, throughput, stable detail IDs, imported
  incomplete costs, and automatic-selection candidates remain open. This
  review does not replace their pinned evidence with empty-account probes.

## Excluded from the Linux backlog

- WidgetKit stale-extension replacement, Dock/menu layout internals, browser
  Local Storage memory improvements, hidden OpenAI WebView cancellation,
  macOS app settings navigation, and macOS currency preference UI are app-owned.
- The upstream Linux desktop installer XDG fix belongs to that installer.
  Plasma's managed CLI installer and widget updater are separate implementations;
  this review confirms release compatibility without copying installer logic.
- The DankMaterialShell widget link describes another desktop frontend. It
  creates no Plasma implementation requirement.

## Unverified in this review

No authenticated provider requests or external network calls were made. Claude
Auto OAuth priority and active adapter selection, Cowork transcript totals,
Grok billing, Cursor unified-account additional spend, Vercel real personal
budgets, TypeSafe authenticated requests, and Antigravity ordinary/model bucket
mapping remain unobserved. The last two releases change upstream behavior but
empty-account output cannot establish every emitted field or account identity.
The Overview and bare-percent candidates remain decisions, not accepted work.
Other architectures, musl execution, and a libxml2-free Ubuntu host were not run.

## Probe method

Official x86_64 glibc assets matched their published SHA-256 files and GitHub
asset digests:

- 0.78.0: `13a331f917a1bf60a26089b59d902087ad650d84797a654d52139429adc80f2d`.
- 0.79.0: `4a88cace99b235050215f66fd1f79f86a4f970c72d52c73f8d31ed607ed837a2`.

Every CLI execution used `bwrap --unshare-all`, tmpfs over `/home`, `/root`,
`/run`, and `/tmp`, a cleared environment, and temporary home/config/cache
paths, with a 30-second outer deadline. Host credentials/history, network and
IPC were inaccessible. Plugin discovery uses Foundation's passwd-derived home,
so its synthetic file was also copied into `/home/simone` inside the tmpfs,
never the host home. Approval used a sandbox pseudo-terminal and the official
prompt for the synthetic `https://example.com` endpoint; the plugin performs
no HTTP request. Synthetic keys entered supported writers through stdin;
optional Vercel environment values existed only inside the sandbox. No CLI
config JSON was hand-edited. Source inspection used the exact 0.79.0 tag and
the official 0.77.0...0.79.0 comparison. Temporary captures and QtTest files are
in ignored `dist/review/078/` and `dist/review/079/`.
