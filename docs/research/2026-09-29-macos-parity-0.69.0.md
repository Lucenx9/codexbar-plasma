# Linux parity review at CodexBar 0.69.0

Checked 2026-09-29 against Plasma commit
[`d0a10dd`](https://github.com/Lucenx9/codexbar-plasma/commit/d0a10dd).
The macOS reference is official
[`v0.69.0`](https://github.com/steipete/CodexBar/releases/tag/v0.69.0),
commit [`48ded68da6932a4fe5de9037d06c4ac48bd36e90`](https://github.com/steipete/CodexBar/commit/48ded68da6932a4fe5de9037d06c4ac48bd36e90),
published 2026-09-28 at 18:43:30 UTC.

This is a release-delta review for useful Linux behavior. It covers the two
stable releases published after the
[0.67.0 review](2026-09-26-macos-parity-0.67.0.md) and does not repeat the full
[0.56.2 contract audit](2026-09-01-macos-parity-0.56.2.md). Current open parity
work belongs in [TODO.md](../../TODO.md).

## Release coverage

| Release | Published | Commit | Linux-relevant observations |
| --- | --- | --- | --- |
| [0.68.0](https://github.com/steipete/CodexBar/releases/tag/v0.68.0) | 2026-09-27 | `7998bf66c796befcb91c38e6b1096e702e511481` | Mistral manual `Cookie` header accepted on Linux (#4024) and the Vibe Monthly Plan window in `usage` text output (#4025); ClinePass browser-session reuse (#4026), Muse Code web-team quota (#4011), Venice Clerk sessions (#3940); Abacus bundled-plugin migration (#4047); Codex session naming (#4020); Nous-billed ledger costs (#4008); Cursor all-history date range (#4028). |
| [0.69.0](https://github.com/steipete/CodexBar/releases/tag/v0.69.0) | 2026-09-28 | `48ded68da6932a4fe5de9037d06c4ac48bd36e90` | Notion AI, ZoomMate, and LongCat bundled-plugin migration (#4098, #4059); empty-config tolerance (#4081); cost-cache and All-history scan efficiency (#4053, #4092, #4045); Claude saved limit resets in `usage` details (#4048); Kimi blocked windows and z.ai Coding Plan explanations (#4091); Antigravity Starter quotas (#4084); TypeSafe menu-bar balance (#4050); token-history model names (#4056); Grok token totals (#4093). |

## Linux CLI contract changes since 0.67.0

- **Registry and help (verified in emitted output).** `config providers
  --format json --json-only` returns the same 87 records with the unchanged
  keys `provider`, `displayName`, `enabled`, and `defaultEnabled` on both
  0.68.0 and 0.69.0; no ID was added, removed, or renamed, and no record
  changed its flags. `--help`, `usage --help`, `cost --help`, `config --help`,
  `sessions --help`, and `config providers --help` differ between 0.68.0 and
  0.69.0 only in the version line. The cost flags still include
  `[--period month-to-date|all]`, and no help text names a display-currency
  setter. No new provider metadata is needed.

- **Mistral manual cookie now reaches Linux (verified in emitted output).**
  With a synthetic `cookieSource: manual` / `cookieHeader` entry in the
  isolated config file, `usage --provider mistral` behaves differently across
  the boundary:

  | CLI | `usage --provider mistral` |
  | --- | --- |
  | 0.67.0 | `runtime` error: `selected source requires web support and is only supported on macOS.` |
  | 0.68.0, 0.69.0 | `provider` error: `Could not resolve host: admin.mistral.ai` (the sandbox has no network; the CLI attempts the fetch) |

  This confirms #4024. The upstream
  [Mistral guide](https://github.com/steipete/CodexBar/blob/main/docs/mistral.md)
  documents this Manual mode as the only Linux path. It does not make Mistral
  set up through supported commands: `config set-api-key --provider mistral`
  still fails with `mistral does not support config API keys.`, and no writer
  exists for `cookieSource`/`cookieHeader`. The frontend must not write those
  fields by hand, so Mistral setup stays in the provider-settings blocker.

- **Setup reachability of the touched providers (verified in emitted output
  on 0.69.0, each with a fresh isolated config and a synthetic key).**

  | Provider | `config set-api-key --stdin` | Default `usage` |
  | --- | --- | --- |
  | `venice` | `enabled: true` | `provider` network error (fetch attempted) |
  | `clinepass` | `enabled: true` | `provider` error: `ClinePass network error: Could not resolve host: api.cline.bot` |
  | `kimi`, `zai`, `v0` | `enabled: true` | `provider` network errors (fetch attempted) |
  | `muse` | `muse does not support config API keys.` | `No available fetch strategy for muse.` |
  | `abacusai` | `abacusai does not support config API keys.` | `runtime` macOS-only web error |
  | `notion`, `zoommate`, `longcat` | `<provider> does not support config API keys.` | `runtime` macOS-only web error |
  | `typesafe`, `helmcode` | `<provider> does not support config API keys.` | `runtime` macOS-only web error; `--source api` still answers `Source 'api' is not supported for <provider>.` |

  The Abacus (#4047) and Notion AI / ZoomMate / LongCat (#4098, #4059)
  bundled-plugin migrations keep host-owned cookie sessions, so their Linux
  reachability is unchanged. ClinePass browser reuse (#4026), the Muse Code
  web-team quota (#4011, cookies Off by default), and Venice Clerk sessions
  (#3940) all need browser sessions with no Linux import. TypeSafe's menu-bar
  balance (#4050) leaves its Linux usage gate unchanged.

- **Cost envelopes are unchanged (verified in emitted output).** Empty-history
  Pi and Claude `cost` records on 0.68.0 and 0.69.0 carry the same key sets as
  0.67.0, including `reportingPeriod` and `historyLabel`. `--period all`
  still reports the days since year 1 as `historyDays` (739890 on 2026-09-29),
  so the #4045 All-history fix is internal only and the widget's 365-day chart
  bound stays. The Pi `usage` record keeps the keys `provider`, `source`, and
  `usage`.

- **Empty config files are tolerated (verified in emitted output on 0.69.0).**
  An empty or whitespace-only `codexbar/config.json` behaves like a missing
  file: `usage --provider pi` returns its normal record (#4081). A malformed
  non-empty file still fails with a `kind: "config"` error. Plasma's checksum
  watcher and generic error path need no change.

- **Sessions and UI preferences are unchanged (verified in emitted output).**
  `sessions --json` and `sessions --json-v2` still emit `[]` when idle, and
  `config preferences export` still fails with `UI preferences
  import/export requires macOS`.

## Carried-forward blockers, rechecked at 0.69.0

- **Generic provider-settings descriptors are still absent.** `config providers
  --descriptors` fails with `Unknown option --descriptors`. The Mistral
  manual-cookie runtime fix adds a concrete Linux-readable case with no
  writer, alongside the existing cookie, URL, workspace, and opt-in cases.
- **There is still no generic `config action` command.** `config action` fails
  with `Unknown subcommand 'action' for command 'config'`.
- **Cursor cost is still rejected.** `cost --provider cursor` returns
  `cost is only supported for Antigravity, Claude, Codex, Muse Code, Pi.`
  The #4028 all-history date-range fix targets macOS Usage & Spend refreshes,
  not the Linux cost allowlist.
- **Display currency has no Linux setter.** No 0.68.0 or 0.69.0 help text
  names one.

## Excluded from the Linux backlog

These 0.68.0 and 0.69.0 items are macOS-only or already covered by Plasma:

- One-click Homebrew cask upgrades (#3994), menu-bar stability, status-item
  identity, and startup diagnostics (#4021, #3201, #3377), Control Center
  hosting, corrupt position rejection (#4082), the Refresh-row icon (#4057),
  menu-bar layout simplification (#3999), sidebar health dots (#4009), merged
  and stacked icon labels (#4030), switcher tabs for user plugins (#4074),
  and the Mistral widget metric picker (#4038) are macOS app surfaces.
- The Codex control-socket restart (#3990, #4018), Usage Dashboard routes
  (#4004), web dashboard Used/Remaining preferences (#4013), and Stay Awake
  teardown (#4068) are macOS app behavior. Plasma has its own settings and
  Codex rows.
- Usage & Spend session naming, ranking, and privacy masking (#4020),
  Nous-billed ledger inclusion (#4008), priced-spend partial estimates
  (#4052), Grok token totals (#4093), the Grok billing breakdown (#4041),
  and observed token-history model names (#4056) are macOS surfaces over
  CLI-owned aggregation; the Linux cost and sessions envelopes verified here
  are unchanged, and Plasma keeps its own privacy projection and rankings.
- Credential-race retries, plan-baseline resets, published catch-up totals
  (#4088, #3635, #3389, #4087, #3508), Claude credential recovery (#4089,
  #3395), the Keychain stall bound (#3249), cost-cache reuse and compaction
  (#4053, #4092, #3882), priority-day proportionality (#4045), the Kimi CLI
  credential guidance (#4086, #4063), Antigravity MCP cleanup (#4077), the Pi
  directory marker (#4067), adaptive-refresh detection (#4090, #4069),
  browser-session cookie merging (#4059, #4098), plugin POST/calendar host
  capabilities, and the Xcode 26.3 toolchain fixes (#4058, #4079, #4070) are
  CLI-owned and surface through existing fields.
- Keeping each widget's last good reading after failed refreshes (#4095,
  #3500) matches the widget's existing quota cache, which already retains
  measurements for 24 hours across failures.
- Scrubbing credential-shaped variables from test output (#4097) is
  CLI-owned; `config dump` already redacts stored credentials by default.

## Unverified in this review

- **Mistral allowance windows on Linux.** The Included API and Vibe Monthly
  Plan windows (#4025) need a subscription plus the manual cookie. Now that
  Linux attempts the fetch, authenticated output would show the window shape
  Plasma renders. Tracked in TODO for a Linux reproduction.
- **Claude saved limit resets** in `usage` details (#4048) need a Web-source
  account. Plasma's generic details path would render them.
- **Kimi Code blocked windows** without fresh quota or pace (#4091), **z.ai
  Coding Plan** empty/unsupported shapes (#4091), and **Antigravity Starter**
  weekly allowances with explicit window cadence (#4084) need accounts. The
  Antigravity item joins the existing quota-window verification candidate in
  TODO; the others would render through generic windows or error text.
- **TypeSafe balance and token-history model names** in Linux JSON (#4050,
  #4056) need cookie or history fixtures. TypeSafe stays behind the
  macOS-only web gate, and Grok cost stays outside the Linux allowlist.
- Items carried from the [0.67.0 review](2026-09-26-macos-parity-0.67.0.md#unverified-in-this-review)
  remain unmeasured.

## Probe method

The official `CodexBarCLI-v0.68.0-linux-x86_64.tar.gz`,
`CodexBarCLI-v0.69.0-linux-x86_64.tar.gz`, and (for the Mistral
before/after comparison) `CodexBarCLI-v0.67.0-linux-x86_64.tar.gz` assets
were downloaded from their releases. All three matched their published
SHA-256 files (`2d95728a…8c20eee49` for 0.68.0, `89a244a6…3630b734e1d5` for
0.69.0, `31ed1fa4…cdeb521eb3` for 0.67.0). They were extracted into a
temporary directory, and the installed CLI was not replaced.

Every command ran under `bwrap --unshare-all` with tmpfs mounts over `/home`,
`/root`, `/run`, and `/tmp`, an empty temporary `HOME`, `XDG_CONFIG_HOME`,
and `XDG_CACHE_HOME`, a cleared environment, and no network access, so cost
discovery could not reach host history. The Mistral cookie and empty-config
probes used synthetic isolated config files only. All keys were synthetic,
and no account data is recorded here.

One probe passed the registry ID `abacus` where the CLI allowlist expects
`abacusai`; the CLI answered with a `codex` record instead of an error. No
other unknown or misspelled provider name was passed, and the reachability
table above uses the allowlist names.
