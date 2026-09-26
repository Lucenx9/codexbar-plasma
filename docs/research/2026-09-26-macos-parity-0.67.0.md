# Linux parity review at CodexBar 0.67.0

Checked 2026-09-26 against Plasma commit
[`5e2ebf3`](https://github.com/Lucenx9/codexbar-plasma/commit/5e2ebf3).
The macOS reference is official
[`v0.67.0`](https://github.com/steipete/CodexBar/releases/tag/v0.67.0),
commit [`e0286a895055e60ddaefa6a5f176f246aa2f05e4`](https://github.com/steipete/CodexBar/commit/e0286a895055e60ddaefa6a5f176f246aa2f05e4),
published 2026-09-26 at 00:48:11 UTC.

This is a release-delta review for useful Linux behavior. It covers the one
stable release published after the
[0.66.0 review](2026-09-24-macos-parity-0.66.0.md) and does not repeat the full
[0.56.2 contract audit](2026-09-01-macos-parity-0.56.2.md). Current open parity
work belongs in [TODO.md](../../TODO.md).

## Release coverage

| Release | Published | Commit | Linux-relevant observations |
| --- | --- | --- | --- |
| [0.67.0](https://github.com/steipete/CodexBar/releases/tag/v0.67.0) | 2026-09-26 | `e0286a895055e60ddaefa6a5f176f246aa2f05e4` | Registry adds `aixy`, `raycast`, and `xkiro` for 87 records; `cost --period month-to-date\|all` and the `reportingPeriod`/`historyLabel` cost fields (#2087, #2859, #1708); macOS-only `config preferences export\|import` (#1282); opt-in LiteLLM model activity (#3432) and Claude Admin workspace spend (#2350); Grok product shares (#3975); Sakana AI as a bundled plugin. |

## Linux CLI contract changes since 0.66.0

- **CLI help (verified in emitted output).** Between the 0.66.0 and 0.67.0
  Linux assets, `--help`, `usage --help`, and `cost --help` gain `aixy`,
  `raycast`, and `xkiro` in the `--provider` allowlist. `cost --help` adds
  `[--period month-to-date|all]`. `config --help` adds `config preferences
  export [--file <preferences.json>]` and `config preferences import --file
  <preferences.json> [--json]`, described as transferring "allowlisted UI
  settings on macOS". `sessions --help` changes only its version line.

- **Registry membership (verified in emitted output).** `config providers
  --format json --json-only` returns 87 records with the unchanged keys
  `provider`, `displayName`, `enabled`, and `defaultEnabled`. The three
  additions (`Aixy`, `Raycast`, `xKiro`) are all `defaultEnabled: false`, and no
  existing record changed.

- **Setup reachability (verified in emitted output).** With a synthetic key:

  | Provider | `config set-api-key --stdin` | Default `usage` |
  | --- | --- | --- |
  | `xkiro` | `enabled: true` | `provider` error: `xKiro returned HTTP 401.` |
  | `aixy` | `enabled: true` | `provider` error: `Aixy rejected the API key. Check its expiry or revocation.` |
  | `raycast` | `raycast does not support config API keys.` | `runtime` error: `selected source requires web support and is only supported on macOS.` |

  xKiro and Aixy therefore join the widget's API-key setup. Raycast reads
  Chrome or manual website cookies through a macOS-only web source, so it stays
  metadata-only on Linux, like Helmcode and TypeSafe.
  Aixy's self-hosted base URL (`enterpriseHost`, `AIXY_BASE_URL`) has no CLI
  writer, like Bifrost's gateway and llmman's daemon URL.

- **Aixy output through a loopback fixture (verified in emitted output).**
  `AIXY_BASE_URL` accepts plain HTTP on loopback, so a static
  `/v1/usage` fixture with three synthetic budgets exercised the official
  plugin without an account. The record carries:
  - `rateWindowLabels: {"primary": "Budget", "secondary": "Secondary budget"}`.
  - `primary` and `secondary` windows for the two most constrained known
    budgets, each with `usedPercent`, `resetsAt`, `windowMinutes`, and a
    `resetDescription` naming the budget and its remaining amount. A lifetime
    budget has no reset and moves to `extraRateWindows`.
  - `details` sections `Aixy key`, `Applicable budgets` (rows with `progress`,
    `usageValue`, and a `secondaryValue`), and `Last 7 days · this key`.
  - `providerCost` with `used`, `limit: 0`, and the period
    `Last 7 days · attributed`, and `dataConfidence: "estimated"`.

  Plasma renders these fields generically and already shows a spend-only
  `providerCost` without a meter. Its lane table now titles Aixy's lanes
  `Budget` and `Secondary budget`, and xKiro's primary lane
  `Daily free tokens` from the upstream descriptor, in the user's language.
  xKiro calls the fixed origin `https://api.xkiro.com`, so its payload is
  unverified.

- **Cost reporting periods (verified in emitted output).** With an empty Pi
  history, 0.67.0 adds `reportingPeriod` and `historyLabel` to every `cost`
  record:

  | Arguments | `reportingPeriod` | `historyLabel` | `historyDays` |
  | --- | --- | --- | --- |
  | `--days 30` | `rolling:30` | `Last 30 days` | 30 |
  | `--period month-to-date` | `month-to-date` | `Month to date` | 26 |
  | `--period all` | `all` | `All` | 739887 |
  | `--period month-to-date --days 7` | `rolling:7` | `Last 7 days` | 7 |

  0.66.0 rejects `--period` with `Unknown option --period` and emits neither
  field. 0.67.0 rejects other values with `--period must be month-to-date or
  all.`, and `--days` wins when both are passed. `--period all` reports the
  days since year 1 as `historyDays`, so a consumer must bound it. Codex,
  Claude, Antigravity, and Muse records carry the same two fields for
  `--days 30`.

  0.66.0 omitted `historyLabel` from these records, but Plasma already
  preferred a CLI label over its own. With 0.67.0 every cost row would read
  the English `Last 30 days`. The widget now drops the CLI label for a
  `rolling:N` period and keeps its localized title.

- **UI preferences are macOS-only (verified in emitted output).** `config
  preferences export` fails on Linux with `UI preferences import/export
  requires macOS`.

## Carried-forward blockers, rechecked at 0.67.0

- **Generic provider-settings descriptors are still absent.** `config providers
  --descriptors` fails with `Unknown option --descriptors`. Two more opt-in
  settings now lack a writer: LiteLLM model activity
  (`LITELLM_MODEL_USAGE_ENABLED`) and Claude Admin workspace spend
  (`ANTHROPIC_ADMIN_WORKSPACE_SPEND`).
- **There is still no generic `config action` command.** `config action` fails
  with `Unknown subcommand 'action' for command 'config'`.
- **Cursor cost is still rejected.** `cost --provider cursor` returns
  `cost is only supported for Antigravity, Claude, Codex, Muse Code, Pi.`
- **Display currency has no Linux setter.** The twelve currencies added for
  macOS spend estimates (#3984) come with no `config` subcommand or cost flag.

## Excluded from the Linux backlog

These 0.67.0 items are macOS-only or already covered by Plasma:

- Portable UI preferences and provider-switcher shortcuts (#1282, #3457), Stay
  Awake (#2740), Burn Down widgets (#3097), menu-bar layout pins, the Usage &
  Spend ledger's Show all control (#3998), and the Codex System Account
  app-server restart (#3990) are macOS app surfaces. Plasma has its own
  settings, pace forecasts, and cost rows.
- Credential-expiry notifications (#2512) are account-scoped app alerts. No
  Linux `usage` field reports a credential expiry, so Plasma has nothing to
  schedule a notice from.
- Plugin checkpoints (#3170), the Sakana AI plugin migration, QuickJS-NG 0.17.0
  (#3987), cookie-denial persistence (#3986), and the OpenRouter, Antigravity,
  Mistral, OpenCode Go, and Codex history fixes are CLI-owned and surface
  through existing fields.

## Unverified in this review

- **xKiro and Raycast payloads.** xKiro needs a real key against its fixed
  origin. Raycast is unreachable on Linux.
- **LiteLLM model activity, Claude Admin workspace spend, and Grok product
  shares** need accounts. LiteLLM source adds a `Model activity · 30d UTC`
  `details` section, which Plasma's generic details path would render.
- Items carried from the [0.66.0 review](2026-09-24-macos-parity-0.66.0.md#unverified-in-this-review)
  remain unmeasured.

## Probe method

The official `CodexBarCLI-v0.67.0-linux-x86_64.tar.gz` and
`CodexBarCLI-v0.66.0-linux-x86_64.tar.gz` assets were downloaded from their
releases. Both matched their published SHA-256 files
(`31ed1fa4…cdeb521eb3` for 0.67.0). They were extracted into a temporary
directory, and the installed CLI was not replaced. Every command ran under
`env -i` with `HOME`, `XDG_CONFIG_HOME`, and `XDG_CACHE_HOME` pointed at empty
temporary directories and no credential environment passed. All keys were
synthetic. The Aixy fixture was a static `python3 -m http.server` on
`127.0.0.1`.

As in the 0.66.0 review, Codex, Claude, Antigravity, and Muse `cost` discovery
can still reach host history despite the temporary `HOME`. Those runs were used
only for the `historyLabel`, `reportingPeriod`, and `historyDays` fields, and no
account data from them is recorded here. No unknown provider name was passed.

## Bundled metadata added for the three new providers

The upstream descriptors at `v0.67.0` declare a brand color and a dashboard for
each addition, and no status page. Icons are original glyphs with no vendor
mark.

| Provider | Display name | Brand color | Dashboard | Docs |
| --- | --- | --- | --- | --- |
| `aixy` | Aixy | `#123650` | `https://dash.aixy-gateway.com` | `aixy.md` |
| `raycast` | Raycast | `#FF6363` | `https://www.raycast.com/settings` | `raycast.md` |
| `xkiro` | xKiro | `#52C99B` | `https://xkiro.com` | `xkiro.md` |
