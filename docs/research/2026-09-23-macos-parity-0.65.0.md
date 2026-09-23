# Linux parity review at CodexBar 0.65.0

Checked 2026-09-23 against Plasma commit
[`392eff5`](https://github.com/Lucenx9/codexbar-plasma/commit/392eff5).
The macOS reference is official
[`v0.65.0`](https://github.com/steipete/CodexBar/releases/tag/v0.65.0),
commit [`20a70d955d4744c795fefd720ff617da9d18480c`](https://github.com/steipete/CodexBar/commit/20a70d955d4744c795fefd720ff617da9d18480c),
published 2026-09-23 at 06:33:22 UTC.

This is a release-delta review for useful Linux behavior. It covers the one
stable release published after the
[0.64.1 review](2026-09-22-macos-parity-0.64.1.md) and does not repeat the full
[0.56.2 contract audit](2026-09-01-macos-parity-0.56.2.md). Current open parity
work belongs in [TODO.md](../../TODO.md).

## Release coverage

| Release | Published | Commit | Linux-relevant observations |
| --- | --- | --- | --- |
| [0.65.0](https://github.com/steipete/CodexBar/releases/tag/v0.65.0) | 2026-09-23 | `20a70d955d4744c795fefd720ff617da9d18480c` | Registry adds `bifrost`, `hyper` (Charm Hyper), and `gitkraken` (GitKraken AI) for 80 records; labeled Kimi, Doubao, and OpenCode Go accounts; plugin windows preserve unknown usage and detail rows keep numeric progress; `last30Days*` cost fields stay scoped to 30 days on longer histories (#3824); Codex Priority pricing on Linux (#3820). |

## Linux CLI contract changes since 0.64.1

- **CLI help is unchanged apart from the provider list (verified in emitted
  output).** `--help`, `config --help`, `usage --help`, and `cost --help` from
  the 0.64.1 and 0.65.0 Linux assets differ only in the `--provider` allowlist,
  which gains `bifrost`, `hyper`, and `gitkraken`. No new flag or subcommand
  appears.

- **Registry membership (verified in emitted output).** `config providers
  --format json --json-only` returns 80 records with the unchanged keys
  `provider`, `displayName`, `enabled`, and `defaultEnabled`. The three
  additions are all `defaultEnabled: false`. `usage --provider gk` answers as
  `gitkraken`, confirming the upstream CLI alias.

- **Linux reachability differs per addition (verified in emitted output).**
  `config set-api-key --stdin` accepts a synthetic key for all three and returns
  `enabled: true`. What happens next differs:

  | Provider | Default `usage` with a synthetic key | Consequence for Plasma |
  | --- | --- | --- |
  | `gitkraken` | `provider` error: `GitKraken access token expired or was rejected.` | Usable through the supported key setup. |
  | `hyper` | `runtime` error: `selected source requires web support and is only supported on macOS.` `--source api` instead yields the `provider` error `Charm Hyper API key rejected (HTTP 401).` | The key is stored but the default source cannot use it. Plasma's source mode is global, so a per-provider source needs the settings contract. |
  | `bifrost` | `provider` error: `No available fetch strategy for bifrost.` | Also needs a gateway base URL, stored as `enterpriseHost`, which no CLI command writes. |

  The Hyper result contradicts its upstream guide, which says Linux Auto can
  fall back to the API key. The CLI source gate exempts only a manual cookie
  source, so Auto stops before the key is tried.

- **Bifrost reads `BIFROST_BASE_URL` from the environment (verified in emitted
  output).** With the variable pointing at a loopback port that refuses
  connections, the error becomes
  `Bifrost quota request could not reach the configured gateway.` A user can
  therefore reach Bifrost by exporting the variable into the Plasma session.
  The widget does not set it, because that would be provider configuration
  outside the CLI.

- **Token-account writes are still z.ai-only (verified in emitted output).**
  `set-api-key --label` for `doubao`, `opencodego`, `kimi`, and `hyper`, and
  `--workspace-id` for the optional GitKraken organization ID, all fail with
  `Token-account options are only supported for --provider zai.` The labeled
  Kimi, Doubao, and OpenCode Go accounts added in 0.65.0 are written by the macOS
  account editor only. Plasma already lists and selects any token accounts the
  CLI reports.

- **Detail-row numbers and unknown named windows reach Linux JSON (verified in
  emitted output).** Bifrost is self-hosted and accepts a loopback HTTP base URL,
  so a synthetic quota response from a local server exercised the official
  plugin path without an account. The emitted `usage` record contains:
  - `details[].rows[]` with `progress: {"used": 0.25, "total": 1}` and
    `usageValue`. An over-budget row caps `progress.used` at 1, while the text
    value stays uncapped. Model rows carry `usageValue` without `progress`. None
    of these rows has an `id`.
  - `extraRateWindows[]` entries with `usageKnown: false`, `usedPercent: 0`, and
    retained `resetsAt`/`windowMinutes` for a reset-only request limit, plus a
    `Key inactive` marker with the same flag for an inactive key.
  - `primary`, `secondary`, `providerCost`, and `identity` in the existing
    shapes.

  Plasma already treats `usageKnown === false` on extra windows as unknown
  rather than 0% (`ProviderSnapshot.js`). `UsageDetails.js` still drops
  `progress` and `usageValue`, so this evidence makes detail-row progress bars
  implementable.

- **Cost schema is unchanged (verified in emitted output).** The key set of
  `cost --provider codex --days 45` is identical between the 0.64.1 and 0.65.0
  assets, and no tier field appears alongside the Priority pricing fix. Claude,
  Codex, and Pi emit `totals` beside `last30DaysCostUSD`/`last30DaysTokens`;
  Antigravity and Muse Code emit neither. Plasma reads `totals` first and uses
  the `last30Days*` values only when `totals` is absent. The #3824 scoping
  change therefore does not affect current output. It was not observed directly:
  the local history spans 15 days.

## Carried-forward blockers, rechecked at 0.65.0

- **Generic provider-settings descriptors are still absent.** `config providers
  --descriptors` fails with `Unknown option --descriptors`.
- **There is still no generic `config action` command.** `config action` fails
  with `Unknown subcommand 'action' for command 'config'`.
- **Cursor cost is still rejected.** `cost --provider cursor` returns
  `cost is only supported for Antigravity, Claude, Codex, Muse Code, Pi.`

## Excluded from the Linux backlog

These 0.65.0 items are macOS-only or already covered by Plasma:

- Zed browser-session billing, Devin browser discovery, and code-signature
  caching all rely on macOS browser import or Keychain.
- Menu-bar chip wrapping, the Help menu link, and remembered compact account
  cards are macOS layout details.
- The Omarchy logo change belongs to upstream's own Linux bar. It bundles SVG
  assets and adds no CLI field. Plasma already shows a bundled icon for each
  provider.
- Claude redraw handling, Codex reset confirmation, the Antigravity and
  OpenCode Go account fixes, claude-swap history, LiteLLM month-to-date spend,
  and Moonshot plugin parity are CLI-owned. They surface through existing
  fields.

## Unverified in this review

- **Linux quota windows (#3785, #3799)** and **Cursor's Grok Bot allowance**
  remain unmeasured, as recorded in the
  [0.64.1 review](2026-09-22-macos-parity-0.64.1.md#unverified-in-this-review).
- **Charm Hyper and GitKraken payloads** need real accounts. Their plugins call
  fixed HTTPS origins, so the loopback fixture used for Bifrost does not apply.
  The Hyper guide describes a balance-only `details` row with `usageValue`.

## Probe method

The official `CodexBarCLI-v0.65.0-linux-x86_64.tar.gz` and
`CodexBarCLI-v0.64.1-linux-x86_64.tar.gz` assets were downloaded from their
releases. Both matched their published SHA-256 files
(`fb4fa6c0…71022ca` for 0.65.0). They were extracted into a temporary
directory, and the installed CLI was not replaced. Every command ran under
`env -i` with `HOME`, `XDG_CONFIG_HOME`, and `XDG_CACHE_HOME` pointed at empty
temporary directories and no credential environment passed. All keys were
synthetic. The Bifrost fixture was a static JSON file served by
`python3 -m http.server` on `127.0.0.1`.

One limit on this isolation applies to `cost`. The local Codex reader found the
host's session history despite the temporary `HOME`. That output was used only
for key sets and record presence. No amounts, model names, or dates from it are
recorded here.

## Bundled metadata added for the three new providers

The upstream descriptors at `v0.65.0` declare a brand color and a setup guide
for each addition, and no status page for any. Icons are original glyphs with
no vendor mark.

| Provider | Display name | Brand color | Dashboard | Docs | CLI alias |
| --- | --- | --- | --- | --- | --- |
| `bifrost` | Bifrost | `#33C09E` | none (self-hosted gateway) | `bifrost.md` | none |
| `gitkraken` | GitKraken AI | `#179287` | `https://gitkraken.dev/account#ai-usage` | `gitkraken.md` | `gk` |
| `hyper` | Charm Hyper | `#FF60FF` | `https://hyper.charm.land` | `hyper.md` | none |

Only GitKraken joins the widget's API-key setup allowlist. Setup would store a
key for Hyper and Bifrost that their Linux default path cannot use.
