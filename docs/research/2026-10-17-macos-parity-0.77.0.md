# Linux parity review at CodexBar 0.77.0

Checked 2026-10-17 against Plasma commit
[`232e688`](https://github.com/Lucenx9/codexbar-plasma/commit/232e6886516345a274625c9f642d7b7433a733e7).
The official reference is [v0.77.0](https://github.com/steipete/CodexBar/releases/tag/v0.77.0),
commit `d235901d4fc51f9421f43838e8a60f567bd6038e`, published
2026-10-16 at 17:36:07 UTC. This covers the stable release since the
[0.76.0 review](2026-10-15-macos-parity-0.76.0.md), including unresolved findings.
It does not replace the full [0.56.2 audit](2026-09-01-macos-parity-0.56.2.md).
[TODO.md](../../TODO.md) owns follow-up work. No feature is implemented here.
No installed `codexbar` was present on the review machine, and none was
installed or replaced.

## Release coverage

| Release | Published | Commit | Linux-relevant changes |
| --- | --- | --- | --- |
| [0.77.0](https://github.com/steipete/CodexBar/releases/tag/v0.77.0) | 2026-10-16 | `d235901d4fc51f9421f43838e8a60f567bd6038e` | Future AGI and Munito bundled plugins; an explicit Gemini app web source that changes Gemini Auto on Linux; Auto quota ranking by projected depletion; Spend layout items; per-account Claude config directories for local cost; tcr pools through the claude-swap adapter; opt-in `shareUsageWithCLI` app-cache fallback; CLI-owned provider fixes (Antigravity tier labels, Qwen Cloud Team, OpenCode Go v2 history, bounded Codex titles, cheaper history scans). Sleep inhibitors, Dock rescans, confetti, Settings navigation, the HTTP server pane, WidgetKit snapshots, and Claude desktop sessions are macOS app behavior. |

## Linux CLI contract changes

- `config providers --format json --json-only` returns 106 records with the
  same four keys: `provider`, `displayName`, `enabled`, `defaultEnabled`.
  `futureagi` (`Future AGI`) and `munito` (`Munito`) are the additions, both
  disabled by default. Help changes only in the provider lists; `config`,
  `set-api-key`, `set-source`, `sessions`, `serve`, and `cards` help are
  otherwise identical to 0.76.0.
- Munito accepts `config set-api-key --provider munito --stdin` with a
  synthetic key, enables the provider, and its usage fetch then reaches the
  network (`NSURLErrorDomain error -1003` inside the network-less sandbox).
  Without a key it reports no available fetch strategy. Single-key setup is
  therefore reachable through the supported writer, but Plasma's setup
  allowlist and static metadata do not include Munito yet.
- Future AGI needs an API key and a secret key. `set-api-key` stores
  `FI_API_KEY`, after which usage fails with `Future AGI requires both
  FI_API_KEY and FI_SECRET_KEY.` Setting `FI_SECRET_KEY` only in the process
  environment moves the same probe to the network attempt, so the secret is an
  environment-only field. `--label` and `--workspace-id` still fail as
  z.ai-only. Like FLORA, setup stays blocked on a released writer.
- Gemini now lists `api`, `auto`, and `web` sources; 0.76.0 rejected
  `set-source --source web` with `Supported sources: api, auto`. The web source
  runs the bundled `gemini-web` plugin, which needs browser cookies, so Linux
  Web usage reports `selected source requires web support and is only
  supported on macOS`.
- Gemini Auto regressed on Linux. With an empty or synthetic Gemini CLI home,
  0.76.0 Auto reached the CLI OAuth strategy (`Not logged in to Gemini`),
  while 0.77.0 Auto fails before any strategy with the macOS-only web error.
  The explicit API source still reaches the OAuth strategy. At the tag,
  `GeminiProviderDescriptor` resolves Auto to the CLI OAuth strategy only,
  but the Linux gate `sourceModeRequiresWebSupport` in
  `CLIUsageCommand.swift` treats Auto as web for every provider whose
  `sourceModes` contain `.web`. The `browserSupportExemption` covers only Web
  with a manual cookie source. A signed-in Gemini CLI user on Auto, the default,
  therefore loses usage on Linux 0.77.0; saving the API source through the
  supported `set-source` writer (Plasma's Source mode control) avoids the gate.
  No authenticated Gemini login was available, so the signed-in case is
  established from the gate order in source plus the unauthenticated probes.
- The Gemini app web source emits five-hour and weekly windows (300 and 10,080
  minutes) where the CLI source emits Pro, Flash, and Flash Lite lanes. Upstream
  relabels by window length; Plasma labels Gemini lanes statically. On Linux
  that source is reachable only with a manual cookie, which has no supported
  writer.
- `shareUsageWithCLI` is accepted by `config validate` on both versions and
  leaves Linux usage output unchanged. At the tag, the Linux
  `callerHasGraphicSession` always answers true and the fallback reader is
  disabled, so `source: codexbar-app` and `ageSeconds` are never emitted on
  Linux. The cache is written only by the macOS app.
- Token accounts gain an optional `claudeConfigDirectory` used for Claude local
  cost. The token-account CLI only preserves an existing value; no released
  writer sets it.
- `usage --provider all --format json --json-only` returned 106 providers in
  registry order on three isolated probes with the same order hash. Against
  0.76.0 the only changed per-provider results are the Gemini Auto error and
  the two new providers.
- The Linux x86_64 archive adds six bundle resources (`futureagi`, `gemini-web`,
  and `munito`, each `.js` and `.ts`); `THIRD_PARTY_NOTICES` and the flat
  `CodexBar_CodexBarCore.bundle/` layout are unchanged. The managed installer's
  `unpack` at the reviewed Plasma commit accepted the verified archive (115
  resources), and `release_assets` accepted the glibc and musl assets for both
  architectures, the largest at 95,021,953 bytes.

## Plasma comparison

- Auto quota ranking (#4491): the macOS app now ranks Auto windows and the
  highest-usage icon by exhausted windows first, then the shortest projected
  depletion before reset, then highest usage. Plasma's `ProviderAutoSelect`
  ranks providers by their highest used percentage only, and the automatic lane
  keeps primary-first order. Plasma already consumes CLI pace records
  (`paceOnTop`, `paceEtaSeconds`), verified in official Linux output by the
  [Claude detail contract](2026-10-15-claude-details-0.76.0.md). This extends
  the existing automatic-selection candidate in TODO; it is not a new CLI
  contract.
- Spend layout items (#4530): Plasma panel elements are identity, status, text,
  and meters, and text modes cover percent, pace, both, reset time, and run-out.
  No panel item shows a provider spend budget, although Plasma already derives
  an allowance from `providerCost` used and limit for the popup. This is a
  Plasma-native presentation candidate, not a missing CLI contract.
- "Plan renews" wording (#4540): Plasma already labels subscription renewal
  and expiration dates as `Plan renews on` and `Plan expires on`.
- Six-day work week (#4548): Linux usage JSON has no work-day pace option. The
  CLI text dashboard reads `weeklyProgressWorkDaysFromDefaults()`, a macOS app
  preference. Plasma never extrapolates pace, so work-week pace stays blocked on
  an official field.
- User plugins in the switcher and Overview (#4471): Plasma's generic discovery
  and unknown-provider fallback already list registry providers.

## Carried-forward blockers rechecked

- `config providers --descriptors` still fails with `Unknown option
  --descriptors`; `config action` remains an unknown subcommand. Generic
  settings, onboarding, display currency, and the Claude Platform, Parallel,
  Helmcode, TypeSafe, and other cookie-only setups remain blocked.
- ClinePass labels and FLORA/Future AGI workspace or secret fields still fail as
  z.ai-only options.
- Cursor cost still fails and lists Antigravity, Claude, Codex, Muse Code, and
  Pi. Empty Codex cost keeps the 17-key shape with no service-tier fields.
- Empty Pi usage retains `estimated` confidence and null quota windows; idle
  `sessions --json-v2` returns `[]`.
- Claude Platform credits, OAuth email, throughput, imported incomplete costs,
  reset credits, funded-credit flags, stable detail IDs, and other
  authenticated candidates retain their earlier evidence.

## Excluded from the Linux backlog

- Claude Code sleep-inhibitor release, Dock rescans, confetti timing, Settings
  Back/Forward, the HTTP usage server pane, the Homebrew update recovery,
  cookie-permission guidance, inactive-display dimming, and the Indonesian
  Keychain prompt are macOS app behavior. Linux keeps the existing `serve`
  command, whose help is unchanged.
- Reading Claude usage from the Claude desktop app session (#4494) depends on
  the macOS desktop app. The `shareUsageWithCLI` app cache is disabled on
  Linux, as shown above.
- WidgetKit snapshot details (#4546, #4529) change the macOS widget extension.
  Plasma reads CLI usage details directly.
- Antigravity paid-tier labels, Qwen Cloud Team parsing, OpenCode Go v2
  history, bounded Codex fallback titles, cheaper history scans, rejected
  Codex browser sessions, and Claude Platform usage links are CLI or provider
  fixes. They need no Plasma parser change while their JSON contracts stay
  stable.

## Unverified in this review

No authenticated provider output or external network call was performed.
Munito and Future AGI windows, details, and spend rows, the Gemini app source,
signed-in Gemini Auto, tcr and claude-swap account pools, per-account Claude
local cost, OpenCode Go v2 local totals, Claude Cloud credits in Linux details,
and restored Antigravity reset times remain unobserved in official Linux
output. Earlier credential-dependent candidates remain open. These limits are
reflected in [TODO.md](../../TODO.md).

## Probe method

The official Linux x86_64 archive matched its release SHA-256 file and the
GitHub asset digest:
`a9c30b8b56ec2fc8526b63ba472f31989605c7e01c2c65ac95b4abf20b7e54d4`.
The 0.76.0 archive was verified the same way for side-by-side probes. Every
CLI probe used `bwrap --unshare-all`, tmpfs over `/home`, `/root`, `/run`, and
`/tmp`, a cleared environment, and temporary home/config/cache paths. Host
credentials, history, network, and IPC were inaccessible. Each process had a
25-second external deadline; none timed out. Synthetic keys entered through
stdin, never argv; config writes used official commands except for the
synthetic Gemini CLI files and the `shareUsageWithCLI` validation config.
Sources were inspected only at the exact release tag. The installer check
imported Plasma's `managed_cli` module and ran `unpack` into a temporary
directory without activating it. Temporary archives and probe results remain
in ignored `dist/review/077/`; they are not product files.
