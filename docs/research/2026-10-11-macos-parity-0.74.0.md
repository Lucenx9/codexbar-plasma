# Linux parity review at CodexBar 0.74.0

Checked 2026-10-11 against Plasma commit
[`7a5945a`](https://github.com/Lucenx9/codexbar-plasma/commit/7a5945a690c4a6fbc8f03954136766a5f92d6872).
The official reference is
[`v0.74.0`](https://github.com/steipete/CodexBar/releases/tag/v0.74.0),
commit [`c2f22ccf8751efc8fe697bfe4714769107965274`](https://github.com/steipete/CodexBar/commit/c2f22ccf8751efc8fe697bfe4714769107965274),
published 2026-10-10 at 08:49:41 UTC.

This release-delta review covers the one stable release after the
[0.73.0 review](2026-10-07-macos-parity-0.73.0.md). It does not replace the full
[0.56.2 contract audit](2026-09-01-macos-parity-0.56.2.md). Current work belongs
in [TODO.md](../../TODO.md); this PR records evidence without implementing it.

## Release coverage

| Release | Published | Commit | Linux-relevant observations |
| --- | --- | --- | --- |
| [0.74.0](https://github.com/steipete/CodexBar/releases/tag/v0.74.0) | 2026-10-10 | `c2f22ccf8751efc8fe697bfe4714769107965274` | Nine bundled-plugin registry additions: Tavily, Linkup, TinyApi, Exa, Cosmic AI, Aerostack, Sail Research, Sofya (#4346, #4347, #4348, #4351, #4354, #4355, #4357, #4358) and X API (#4127); Cursor reads `cursor-agent` logins on Linux (#4397); Claude plan renewal/expiration dates in CLI JSON (#4324); Ollama API-key balance endpoint and credit wallets (#4399, #4370); JetBrains top-up credits (#4372); Qwen Cloud Team plans (#3711); OpenCode Go most-constrained automatic quota (#3349); `serve --all-accounts` and `/accounts` discovery (#3890, #4326); `serve` procfs, RPC pipe, and heap fixes (#4377, #4367, #4374); private Linux desktop Quick View (#3973); CLI-owned Claude, Codex, Pi, and Notion parsing fixes. |

## Linux CLI contract changes since 0.73.0

- **Registry grows from 91 to 100 records (verified in emitted output).** The
  additions are `tavily`, `linkup`, `tinyapi`, `exa`, `cosmic`, `aerostack`,
  `sailresearch`, `sofya`, and `xapi`, each with `defaultEnabled: false` and
  `enabled: false`. Existing records are identical after key sorting, and every
  record still has only `provider`, `displayName`, `enabled`, and
  `defaultEnabled`. The `usage` and `cost` help lists gain the same nine names.
  Linux reachability, with synthetic keys sent through `set-api-key --stdin`:
  - Tavily, Linkup, Aerostack, Sail Research, and Sofya store a single key,
    enable the provider, and attempt their fixed HTTPS hosts under both `auto`
    and `--source api`; the sandbox has no network, so each fails with a
    transport error.
  - Exa and Cosmic AI store the key but then fail before any request:
    `Set the Exa API key ID in Scope or EXA_API_KEY_ID; this is not the service key.`
    and `Set a Cosmic Project ID in Settings or COSMIC_PROJECT_ID.` With
    `EXA_API_KEY_ID` or `COSMIC_PROJECT_ID` in the environment, the fetch is
    attempted. `--workspace-id` is refused with the z.ai-only token-account
    error, so the second field has no CLI writer.
  - TinyApi and X API refuse config API keys (`does not support config API
    keys`). Their default source returns `selected source requires web support
    and is only supported on macOS`, and `--source api` is unsupported.

  Plasma bundles fallback metadata for the 91 providers in the 0.73.0
  registry; the new IDs fall back to generic artwork. Fallback metadata and
  API-key setup for the five complete single-key providers are **implementable
  now**. The Exa and Cosmic second fields belong to the descriptor blocker;
  TinyApi and X API are **macOS-only** at this release and must not gain a dead
  key action. Their pinned descriptors (for example
  [Exa](https://github.com/steipete/CodexBar/blob/v0.74.0/Sources/CodexBarCore/Providers/Exa/ExaProviderDescriptor.swift))
  supply the dashboards. These plugins emit balances only as `details` rows,
  apart from Tavily, Cosmic AI, and Aerostack windows and X API cost.

- **Subscription dates reach Linux usage output (verified in emitted output).**
  The shared `UsageSnapshot` encodes optional ISO-8601
  `usage.subscriptionRenewsAt` and `usage.subscriptionExpiresAt`. A loopback
  sub2api fixture with `subscription.expires_at` produced
  `usage.subscriptionExpiresAt: "2026-11-30T00:00:00Z"` on both 0.73.0 and
  0.74.0, next to its daily window, so the fields predate this release for
  bundled plugins; at 0.74.0, Chutes, LiteLLM, Muse (muse.ai), Neuralwatt,
  Nous, Raycast, sub2api, Zed, and ZenMux set them. 0.74.0 adds Claude dates (#4324) and two flags,
  `subscriptionRenewsAtIsDateOnly` and `subscriptionExpiresAtIsDateOnly`,
  encoded only when `true` for a `yyyy-MM-dd` billing value; see the pinned
  [snapshot source](https://github.com/steipete/CodexBar/blob/v0.74.0/Sources/CodexBarCore/UsageFetcher.swift).
  Plasma reads neither field, so these dates never appear in the popup.
  macOS shows them beside, but separate from, quota resets. Displaying
  emitted dates is **implementable now**. Claude dates come from
  `claude.ai/api/.../subscription_details` and require the manual `sessionKey`
  cookie, which still has no Linux writer; the date-only flags were not
  observed.

- **Cursor reaches cursor.com with a `cursor-agent` login (verified before and
  after).** With a synthetic unsigned JWT in
  `$XDG_CONFIG_HOME/cursor/auth.json` and Cursor enabled, 0.73.0 returns
  `No Cursor session found...` while 0.74.0 attempts the API (`Cursor API
  error: Could not resolve host: cursor.com`). An `accessToken` that is not a
  JWT is ignored by both. In fresh isolated accounts, 3 of 6 default runs and
  3 of 8 runs with `--web-timeout 5` instead stalled idle until an external
  20–30 second bound, and one unbounded first attempt ran for more than three
  minutes; repeated Tavily and 0.73.0 Ollama requests in the same namespace
  failed immediately. Plasma bounds usage commands at 120 seconds. Usage
  rendering is generic, and Cursor cost remains rejected. Whether the stall
  happens on a host without network or with a real login is unverified.

- **Usage account enumeration is unchanged (verified in emitted output).**
  0.74.0 routes `usage --all-accounts` through a shared collector and adds
  transport-private `dashboardAccount` fields that are never encoded. With
  two synthetic z.ai team token accounts, both versions emit the same records
  (`account`, `error`, `provider`, `source`) with labels `Synthetic A` and
  `Synthetic B`. Codex `--all-accounts` without credentials is unchanged.

- **`serve` gains account discovery (verified in emitted output; non-goal).**
  0.73.0 answers `GET /accounts` with 404; 0.74.0 returns
  `{"schemaVersion":1,"accounts":[]}` for an empty config and one
  `token-account` record (`id`, `provider`, `source`, `label`, `active`) per
  configured z.ai token account, with 404 `account not found` for an unknown
  ID. `serve --all-accounts` adds per-account `accounts` arrays to dashboard
  snapshots with neutral `Account 1` labels and a generic error unless
  `--identity full` is set. Plasma invokes one-shot `usage`/`cost`, owns its
  account cache, and never runs `serve`; the server and its leak fixes are a
  **non-goal**.

## Carried-forward blockers, rechecked at 0.74.0

- `config providers --descriptors` still returns `Unknown option --descriptors`
  (100 records, same four keys). No new provider exposes a descriptor.
- `config action` still returns an unknown-subcommand error; `config --help`
  is unchanged apart from the version line.
- `config set-source` behaves as at 0.73.0: Codex `api` and `auto` writes emit
  the same five keys, `pi --source web` lists only `auto`, and unknown sources
  fail. Per-provider source controls remain implementable.
- ClinePass `set-api-key --label` still fails with
  `Token-account options are only supported for --provider zai.`
- `cost --provider cursor` still refuses Cursor with the unchanged supported
  list: Antigravity, Claude, Codex, Muse Code, and Pi.
- Empty cost records keep 17 keys for Codex, Claude, and Pi and 12 for
  Antigravity; Grok is still rejected. Empty Pi usage keeps `provider`,
  `source`, and `usage` (`dataConfidence`, null `primary`/`secondary`/`tertiary`,
  `updatedAt`). `cost --provider pi --period all` reports `historyDays: 739902`
  on both versions; the 365-day chart bound remains needed.
- No inspected help exposes a display-currency setter. `config preferences
  export` remains macOS-only, `codex-accounts list` still returns
  `Managed Codex account commands are only available on macOS.`, and idle
  `sessions --json-v2` still emits `[]`.
- Langdock still returns the macOS-only web runtime error; the new Chrome and
  Safari profiles (#4390) do not open a Linux path.
- The 0.73.0 top-level `resetCredits` payload source is unchanged in
  `CLIPayloads.swift`; it remains unverified in emitted output.
- Older authenticated/history/tier/availability/localization blockers retain
  their last measured versions. This scoped probe does not establish that
  those fields are absent in every authenticated 0.74.0 payload.

## Excluded from the Linux backlog

- The Accounts WidgetKit widget, minute-only live widget dates, and widget
  percentage placement (#3938, #4361) are macOS widgets. Plasma's popup already
  lists and selects accounts from `usage --all-accounts`.
- Following the frontmost app in the merged icon (#3961), the Settings
  placeholder Dock fix (#4101), coarse-wheel Overview scrolling (#4398), the
  About website link (#4325), and Homebrew update notices and upgrades
  (#4327, #4375) are macOS app behavior.
- The menu-bar pace sign option (#4394) flips a signed macOS layout token.
  Plasma words pace as `in reserve`/`in deficit` and `at pace`/`behind pace`,
  so no sign exists to flip. The weekly reserve candidate stays in TODO.
- Color by provider (#4321) is already covered: Plasma's Standard panel style
  colors icons and capsules by provider brand, with independent warning
  colors, and Minimal is the monochrome alternative.
- Codex saved-account settings with cached usage and refresh controls (#4310),
  managed-account credential resolution and home retention (#4360, #4342),
  first-refresh error display (#4364), Claude Keychain/credential-change
  guidance (#3395), Plan Usage history across token rotation (#4322), and
  Enterprise Extra usage in Compact Overview (#4320) are macOS app, account,
  or layout effects. Plasma keeps its own account cache and renders extra
  windows that the CLI emits.
- Usage & Spend tool operations, turn throughput, latency and duration,
  hour-mode and annual activity performance, catch-up clearing, chart
  bucket inspection, and APFS clone writes (#4363, #4304, #4380, #4328, #4379,
  #4329, #4396) are macOS presentation or storage. The empty cost envelope
  is unchanged, so no new Linux history field was established.
- Claude tall inline panels and insights-only fallback errors (#4392, #4083),
  Codex commented-out endpoint overrides (#4330), Pi unreadable-environment
  history (#4365), Notion workspace recovery (#4341), Codex turn-ID memory
  sharing (#3323), and cookie-refresh profile filtering are CLI-owned parsing,
  configuration, or performance fixes. They need no QML port.
- The private Linux desktop app's compact Quick View (#3973), Omarchy labels
  and caps (#3794), Starbridge integration links (#4371), localized macOS app
  catalogs (#4223), Pi artwork (#4366), and the upstream CI path gate (#4373)
  are separate frontends, artwork, or upstream development. Plasma owns its
  catalogs and original icons.

## Unverified in this review

- **Claude subscription dates and the date-only flags** (#4324). Producing them
  needs a signed-in Claude account with a manual `sessionKey` cookie and
  network access to `claude.ai`. The generic date fields are verified through
  sub2api only.
- **Authenticated quota and credit changes:** the Ollama API-key monthly window
  and purchased-credit row from `https://ollama.com/api/balance` (#4399) and
  cookie wallets (#4370), JetBrains top-up credits (#4372), Qwen Cloud Team
  plans (#3711), and the new plugins' windows and balances. Their hosts are
  fixed in the plugin code, so no loopback fixture could stand in for them.
  Source shows standard windows and `details` rows that Plasma's generic path
  renders.
- **Cursor `cursor-agent` usage.** A real login is needed to compare its
  windows with Cursor.app or cookie sessions and to check the Grok Bot
  allowance candidate. The intermittent idle stall was reproduced only in a
  network-less namespace.
- **OpenCode Go automatic quota** (#3349). macOS now picks the most constrained
  five-hour, weekly, or monthly window for automatic menu-bar text and the
  switcher. Plasma's automatic capsules show primary and secondary. Compare
  with real data before changing automatic selection.
- The 0.73.0 reset-credit and partial-priced cost candidates carry forward
  unchanged; no live inventory or nonempty mixed-priced history ran here.

## Probe method

Both official Linux x86_64 archives matched their release SHA-256 files:

- 0.74.0: `fac8b2c474e4e37a2b067224437cb182693411ebf639441cd0facbb57bf086b1`.
- 0.73.0: `a84f556c7ecebc8e606e0a34ee0d121626f72d7afc1e3adf5746410bc10f9611`.

The extracted assets ran under `bwrap --unshare-all`, with tmpfs mounts over
`/home`, `/root`, `/run`, and `/tmp`, a cleared environment, temporary `HOME`,
`XDG_CONFIG_HOME`, and `XDG_CACHE_HOME`, a fresh state directory per scenario,
and no host network/IPC or provider history. Synthetic keys entered through
stdin, never command-line arguments; the only synthetic environment values
were the Exa/Cosmic IDs and the sub2api loopback base URL. The sub2api fixture
and `serve` ran on loopback inside the same sandbox call as their probes, and
`serve` used a synthetic dashboard token. The Cursor login was a synthetic
unsigned JWT file. Config changes used supported CLI commands. No CLI was
installed on the review host, and none was replaced. The desktop asset was not
launched. Temporary outputs remain in the OS temporary directory.
