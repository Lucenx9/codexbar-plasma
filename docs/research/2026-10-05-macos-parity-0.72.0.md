# Linux parity review at CodexBar 0.72.0

Checked 2026-10-05 against Plasma commit
[`b3edc4d`](https://github.com/Lucenx9/codexbar-plasma/commit/b3edc4d).
The macOS reference is official
[`v0.72.0`](https://github.com/steipete/CodexBar/releases/tag/v0.72.0),
commit [`cfee869f3181379dd074adb9feeb5f19a994356a`](https://github.com/steipete/CodexBar/commit/cfee869f3181379dd074adb9feeb5f19a994356a),
published 2026-10-04 at 19:33:35 UTC.

This is a release-delta review for useful Linux behavior. It covers the four
stable releases published after the
[0.69.0 review](2026-09-29-macos-parity-0.69.0.md) and does not repeat the full
[0.56.2 contract audit](2026-09-01-macos-parity-0.56.2.md). Current open parity
work belongs in [TODO.md](../../TODO.md).

## Release coverage

| Release | Published | Commit | Linux-relevant observations |
| --- | --- | --- | --- |
| [0.70.0](https://github.com/steipete/CodexBar/releases/tag/v0.70.0) | 2026-09-30 | `fcaffd75ace3790cca3b768ae3fd3293281692ce` | Plan Usage remaining-quota burndown for Codex and Claude (#4085); 16 provider brand-color refreshes (#4075); Mistral event/zone/tier pricing, Antigravity and Codex model aliases, Cyber fallback rates, Mistral Monthly Plan menu-bar metric (#4076, #4094, #4072); redacted process environments in diagnostics (#4106); CLI probe timeout cleanup (#4108). |
| [0.71.0](https://github.com/steipete/CodexBar/releases/tag/v0.71.0) | 2026-10-02 | `cb5f0cbe88615a441272c6f9e44675bf594a3fa3` | Muse (`museai`) and LithosAI (`lithosai`) registry additions (#4042, #4196); Antigravity per-account quotas through private sessions (#4103) with Hub client identity (#4102); opt-in reset notifications (#4138); Cursor Linux serve stale-cookie fix (#4137); Claude unmeasured session placeholders as unavailable (#4107); Claude model-scoped weekly quota fallback (#4126); OpenCode migrated workspace quota (#4131); third-window metric fallback (#4128). |
| [0.71.1](https://github.com/steipete/CodexBar/releases/tag/v0.71.1) | 2026-10-03 | `c04fc93f91f17984d9dff93a556e553e750f2c1c` | Codex weekly quota recovery after reset (#4210); Codex/Claude/Pi/Grok scan efficiency (#4200, #4202, #4121, #4209); Cursor Grok Bot mid-week pace restore (#4221); status-request ordering (#4175); Command Code cookie-name normalization (#4192); per-provider browser names in cookie guidance (#4215). |
| [0.72.0](https://github.com/steipete/CodexBar/releases/tag/v0.72.0) | 2026-10-04 | `cfee869f3181379dd074adb9feeb5f19a994356a` | WorkBuddy (`workbuddy`) registry addition (#4226, #4227); Claude claude.ai web source allowed on Linux with a manual `sessionKey` cookie (#4241); Grok purchased Extra Usage Credits in `usage` JSON (#4239, #4243); LithosAI prepaid balance in menu layouts (#4230); Claude promotional cloud-session credits separated from prepaid credits in CLI output (#4194, #4214); Antigravity extra profile homes opt-in (#4177); Antigravity 2.19.1 OAuth client-credentials discovery (#4229); empty Antigravity unknown-model rows hidden (#4246); Codex resumed-session recovery (#3303, #4195); Claude saved limit-reset credits in OAuth usage (#3895, #4232); Muse full-catalog browser import (#4215). |

## Linux CLI contract changes since 0.69.0

- **Registry grows to 90 records (verified in emitted output).** `config
  providers --format json --json-only` returns 90 records on 0.72.0 against 87
  on 0.69.0, with the unchanged keys `provider`, `displayName`, `enabled`, and
  `defaultEnabled`. The additions are `museai`, `lithosai`, and `workbuddy`;
  no ID was removed or renamed and no record changed its flags. `--help`,
  `usage --help`, `cost --help`, `config --help`, `sessions --help`, and
  `config providers --help` are otherwise identical across the boundary apart
  from the version line and the three new IDs in the `--provider` allowlist.
  No new flag exists, and no help text names a display-currency setter.

- **The three new providers are cookie-only and macOS-gated (verified in
  emitted output on 0.72.0, each with a fresh isolated config and a synthetic
  key).** `config set-api-key --stdin` answers `<provider> does not support
  config API keys.` for `museai`, `lithosai`, and `workbuddy`, and default
  `usage` answers the `runtime` macOS-only web error for all three. They are
  metadata-only on Linux, like Helmcode, TypeSafe, and Raycast before them.
  Plasma's `supportsApiKeySetup` allowlist already excludes them, so settings
  offers no dead key action; this change bundles their fallback name, original
  icon, upstream dashboard, docs link, and descriptor brand color, with direct
  tests and catalog updates.

- **Claude manual web sessions now reach Linux (verified in emitted output
  before and after).** With a synthetic `cookieSource: manual` /
  `cookieHeader: sessionKey=sk-ant-SYNTHETIC-VALUE` entry in the isolated
  config file, `usage --provider claude` behaves differently across the
  boundary:

  | CLI | `usage --provider claude` |
  | --- | --- |
  | 0.69.0 | `provider` message: `No available fetch strategy for claude.` |
  | 0.72.0 | `provider` error: `Could not resolve host: claude.ai` (the sandbox has no network; the CLI attempts the fetch) |

  This confirms #4241 and matches the upstream Claude guide, which documents
  the manual `sessionKey` cookie as the only Linux web path with browser
  import remaining macOS-only. Without the cookie both builds report no
  available strategy. It does not make Claude set up through supported
  commands: no writer exists for the cookie fields and the frontend must not
  write them by hand, so Claude setup joins Mistral in the provider-settings
  blocker. Mistral's manual-cookie fetch was re-verified attempting
  `admin.mistral.ai` on 0.72.0, and `config set-api-key --provider mistral`
  still refuses.

- **Cost and usage envelopes are unchanged (verified in emitted output).**
  Empty-history `cost` records for Antigravity, Claude, Pi, Grok, and Codex
  carry identical 17-key sets on 0.69.0 and 0.72.0, including
  `reportingPeriod` and `historyLabel`. The Grok purchased-credits balance
  (#4239, #4243) and the Claude promotional-credit separation (#4194, #4214)
  need funded accounts to appear; neither is observable in empty output, and
  both join the verification candidates below. `--period all` still reports
  its year-1 day count as `historyDays` (739896 on 2026-10-05, six days after
  the 739890 reading, so the scan-efficiency fixes are internal only and the
  widget's 365-day chart bound stays).

- **Empty config files are still tolerated (verified in emitted output on
  0.72.0).** An empty `codexbar/config.json` behaves like a missing file:
  `usage --provider pi` returns its normal local record (#4081 holds).

- **Sessions and UI preferences are unchanged (verified in emitted output).**
  `sessions --json` and `sessions --json-v2` still emit `[]` when idle, and
  `config preferences export` still fails with `UI preferences
  import/export requires macOS`.

## Carried-forward blockers, rechecked at 0.72.0

- **Generic provider-settings descriptors are still absent.** `config providers
  --descriptors` fails with `Unknown option --descriptors`. The Claude manual
  `sessionKey` runtime opening adds a second concrete Linux-readable case with
  no writer, alongside Mistral and the existing cookie, URL, workspace, and
  opt-in cases; the Antigravity extra profile homes opt-in (#4177) is a third
  config-gated case awaiting authenticated evidence.
- **There is still no generic `config action` command.** `config action` fails
  with `Unknown subcommand 'action' for command 'config'`.
- **Cursor cost is still rejected.** `cost --provider cursor` returns
  `cost is only supported for Antigravity, Claude, Codex, Muse Code, Pi.`
- **Display currency has no Linux setter.** No 0.70.0 through 0.72.0 help text
  names one.

## Excluded from the Linux backlog

These 0.70.0 through 0.72.0 items are macOS-only or already covered by Plasma:

- The Plan Usage burndown view (#4085), Usage & Spend project/chat grouping
  and title privacy (#4247, #4172), empty unknown-model row hiding (#4246),
  long statistics heading wraps (#4193), the Usage & Spend title/Refresh row
  fix (#4064), provider reordering in separate icons (#4125), the shared
  third-window metric fallback (#4128), and the Mistral Monthly Plan menu-bar
  picker (#4072) are macOS app surfaces. Plasma renders whatever quota windows
  arrive through its generic lanes and keeps its own panel/popup composition.
- The 16 brand-color refreshes (#4075) and the widget accent resync (#4199)
  do not change Plasma's own bundled palette; the three new providers are
  bundled here with their upstream descriptor colors.
- Opt-in reset notifications (#4138) are macOS app notifications. Plasma keeps
  its own notification planner; whether reset-imminent notices add value is
  already a separate verification candidate in TODO.
- Keychain permission retries and credential-cache recovery (#4231, #3395,
  #4242), SweetCookieKit browser support with automatic import (#4215), Muse
  full-catalog import, and Firefox import staying unavailable are macOS-only
  credential surfaces. Linux keeps the documented manual-cookie paths, which
  remain without a supported writer.
- Redacted diagnostics environments (#4106), CLI probe timeout cleanup
  (#4108), status-request ordering (#4175), cost-scan efficiency and cache
  reuse (#4200, #4201, #4202, #4209, #4053-class follow-ups), resumed-session
  recovery (#3303, #4195), Codex quota recovery after reset (#4210),
  Antigravity token mapping and schema limits (#4124, #4133), Pi/OMP counters
  (#4121, #4176), Codex local-history catch-up (#3508), Muse Code blank-email
  team matching (#4228), Command Code cookie-name normalization (#4192), and
  the Claude MCP/usage-insights parsing guards (#4083, #4112) are CLI-owned
  aggregation, parsing, or recovery behavior surfacing through the existing
  fields; the Linux envelopes verified here are unchanged.
- Mistral event/zone/tier pricing, Antigravity and Codex model aliases, Cyber
  fallback rates, and Sol estimate preservation (#4076, #4094) are CLI-owned
  pricing inside unchanged cost records. Mistral, Antigravity model histories,
  and Cyber stay outside the Linux cost allowlist or inside existing keys.
- The community KDE widget docs link (#4117) needs no widget change.
- The Cursor Linux serve stale-cookie fix (#4137) and the Cursor Grok Bot
  mid-week pace restore (#4221) target Cursor sessions and the macOS card;
  Cursor cost stays outside the Linux allowlist and Cursor usage still needs
  an account to observe.

## Unverified in this review

- **New 0.72.0 credit/allowance balance fields on Linux.** The Grok purchased
  Extra Usage Credits balance, the Claude promotional cloud-session credit
  separation, and the Claude saved limit-reset credits in OAuth usage (#4239,
  #4243, #4194, #4214, #3895, #4232) need funded accounts. Plasma's generic
  balance/details path would render them only once their shapes are known.
  Tracked in TODO for an authenticated Linux reproduction.
- **Claude manual-cookie allowance windows on Linux.** Now that 0.72.0
  attempts the claude.ai fetch with a manual `sessionKey`, authenticated
  output would show the session/weekly/quota window shapes Plasma renders.
  Tracked in TODO.
- **Antigravity per-account quotas and extra profile homes.** Saved Google
  accounts served through private sessions (#4103), the 2.19.1 OAuth
  client-credentials recovery (#4229), and the opt-in extra profile homes
  (#4177) need signed-in accounts. The existing quota-window candidate in
  TODO now names these shapes for the same reproduction.
- **Mistral allowance windows on Linux** (carried from 0.69.0), **Kimi/z.ai
  window explanations**, and the **0.64.x quota-window** items remain
  unmeasured and stay in TODO.
- Items carried from the [0.69.0 review](2026-09-29-macos-parity-0.69.0.md#unverified-in-this-review)
  remain unmeasured.

## Probe method

The official `CodexBarCLI-v0.72.0-linux-x86_64.tar.gz` and (for the Claude
before/after comparison) `CodexBarCLI-v0.69.0-linux-x86_64.tar.gz` assets
were downloaded from their releases. Both matched their published SHA-256
files (`1772b5a2…b78b70` for 0.72.0, `89a244a6…3630b734e1d5` for 0.69.0).
They were extracted into a temporary directory, and the installed CLI was
not replaced.

Every command ran under `bwrap --unshare-all` with tmpfs mounts over `/home`,
`/root`, `/run`, and `/tmp`, an empty temporary `HOME`, `XDG_CONFIG_HOME`,
and `XDG_CACHE_HOME`, a cleared environment, and no network access, so cost
discovery could not reach host history. The Mistral and Claude cookie probes
used synthetic isolated config files built from the CLI's own redacted
`config dump` shape with synthetic cookie values only. All keys were
synthetic, and no account data is recorded here.

A Gemini cross-check of the release classification was attempted through the
available model delegation path, but the harness rejected the delegation call,
so the classification above rests on the verified probes and the review
precedent alone.
