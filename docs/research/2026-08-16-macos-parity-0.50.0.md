# CodexBar macOS parity at 0.50.0

Checked 2026-08-16. Read-only comparison of the official `steipete/CodexBar`
product against the Plasma baseline. Supersedes
[`2026-08-15-macos-parity-0.49.6.md`](./2026-08-15-macos-parity-0.49.6.md),
which was pinned to v0.49.6 and went stale within a day: v0.50.0 was published
on 2026-08-15 at 07:40 UTC, a few hours before that report was written.

## Pinned scope

| Reference | Exact revision | Date |
| --- | --- | --- |
| Plasma baseline | local `23999ca3dda5ddde18c56686158f4063faddfaa1` (tag `v0.2.16`) plus the change that ships this report | 2026-08-16 |
| Official baseline | [`v0.50.0`](https://github.com/steipete/CodexBar/releases/tag/v0.50.0), commit [`0e453c4a5b2a13ce69f5400190e62a630e3b4240`](https://github.com/steipete/CodexBar/commit/0e453c4a5b2a13ce69f5400190e62a630e3b4240) | published 2026-08-15 07:40 UTC |
| Previous pinned baseline | `v0.49.6`, commit `0f66c32ecb69f35bccdd4e135cb0c7a6afd1dfb6` | 2026-08-15 |
| Installed Linux CLI | `codexbar` **0.50.0**, upgraded from 0.49.6 on the owner machine | probed 2026-08-16 |

v0.50.0 is the latest upstream release at the time of writing, and the installed
CLI was upgraded to match it before probing. Every CLI claim below is a live
probe of that exact binary.

## Verdict

Unchanged in substance: provider *data* is at parity, provider *configuration*
is not, and the machine-readable settings/action descriptor still does not exist
in the released CLI. What did change is that v0.50.0 added two menu-side
presentation features whose data the Linux CLI already emits, so both were
implementable without any upstream work. Both are now implemented.

## Live CLI probes

```
$ codexbar --version
CodexBar 0.50.0

$ codexbar config providers --format json --json-only | jq 'length'
69

$ codexbar config providers --format json --json-only | jq -r '[.[] | keys] | add | unique | join(", ")'
defaultEnabled, displayName, enabled, provider

$ codexbar config providers --descriptors --format json --json-only
[{"error":{"message":"Unknown option --descriptors","kind":"args","code":1},"provider":"cli","source":"cli"}]
```

`codexbar config` still exposes only `validate | dump | providers | enable |
disable | set-api-key`. There is no `config set` and no `config action`. The
descriptor contract is absent, not partially shipped, so
[`docs/cli-provider-settings-descriptor.md`](../cli-provider-settings-descriptor.md)
remains a proposal and the Providers page keeps degrading to enable/disable,
`set-api-key`, and docs/dashboard/login links.

## Newly consumed in this change

Both items come from the v0.50.0 release notes and needed no new CLI contract.

### Cost/token switch on the daily charts (#2930)

`codexbar cost` already emits per-day token counts next to per-day cost, on
0.49.6 and 0.50.0 alike:

```
$ codexbar cost --days 7 --format json --json-only | jq '.[0].daily[0] | keys'
["cacheReadTokens","date","inputTokens","modelBreakdowns","modelsUsed","outputTokens","totalTokens"]
```

The widget already normalized those tokens but plotted only cost. The Usage &
Spend tab now carries a Cost/Tokens selector next to the range selector, and the
selected metric drives the range chart, the activity heatmap, and the seven-day
per-provider `costHistoryRows` bars. The choice persists through
`costHistoryMetric`.

macOS also marks incomplete local history as refreshing. The payload exposes
`historyCoverageIsEstablished`, which the widget had never read; the Spend tab
now shows a bounded informational note while the local scan is still filling the
requested window, so short early bars are not misread as low spend. A missing
flag is treated as established, so older CLIs do not trigger a false warning.

### Compact run-out forecast token (#2865)

macOS added a menu-bar token that shows only the predicted duration. The pace
fields it needs (`willLastToReset`, `etaSeconds`) were already consumed for
predictive notifications. The panel gains a `runOut` display mode that reuses
the existing `paceWarningActive` / `paceEtaText` helpers, so it renders a
duration only when the CLI actually predicts exhaustion before the reset and
stays empty otherwise. Verified on the live panel: with a Codex weekly window
reporting `Runs out in 46m`, the panel token read `Codex 45 minutes`.

## Inherited from the CLI upgrade, with no QML work

Because 0.49.0 moved both platforms onto the same QuickJS plugin engine, the
v0.50.0 provider fixes reach Plasma by upgrading the binary: Grok weekly credit
window labelling (#2929), Codex rate-limit guidance on Bedrock and other custom
backends (#2679), Codex Business monthly credit remaining (#2926), the
Gemini-to-Antigravity migration path (#2808), and suppression of provider status
transport errors until a real status fetch succeeds (#2925).

One part of #2926 does not apply here: the Plasma provider tab meter is bound to
`visible: providerTab.meter >= 0` regardless of selection, so the selected tab
never lost its quota indicator.

The Cursor local-session work in v0.50.0 is macOS-only.

## macOS frontend surfaces Plasma does not have

The authoritative settings pane list is `SettingsPane` in
[`Sources/CodexBar/PreferencesSelection.swift`](https://github.com/steipete/CodexBar/blob/v0.50.0/Sources/CodexBar/PreferencesSelection.swift):
`general`, `iCloudSync`, `usageSpend`, `notifications`, `menuBar`, `menu`,
`advanced`, `hooks`, `plugins`, `about`, `debug`, `provider:<id>`. Plasma has
five pages: General, Providers, Display, Advanced, Debug.

### Plasma-native items

| Gap | Official evidence | Plasma consequence |
| --- | --- | --- |
| Configurable quota thresholds | `QuotaWarningSettingsViews.swift`, plus a dedicated `notifications` pane | Implemented through bounded shared thresholds that drive both notifications and usage-bar markers. |
| Local Agent Sessions list | `AgentSessionsStore.swift` plus `sessions --json-v2` | Implemented as a bounded global tab; path/ID fields are discarded. |
| Chart hover/selection | `ChartBarHoverSelection.swift` | Implemented for cost and generic detail charts with pointer and keyboard inspection. |
| Panel composition | `MenuBarLayout.swift`, `MenuBarLayoutEditor.swift`, `MenuBarLayoutRenderer.swift` | Implemented as a persisted, sanitized element order while retaining the existing visibility controls. |
| Spend dashboard | `SpendDashboardModel.swift`, `SpendActivityHeatmap.swift` | Implemented from `cost --days` with 7/30/90-day ranges, an interactive chart, and bounded heatmap. |
| Predictive pace warnings | `PredictivePaceWarnings.swift`, `HistoricalUsagePace.swift` | Implemented as an opt-in transition warning from `pace.willLastToReset` and `pace.etaSeconds`; no local history is fabricated. |
| Click-to-copy values | `ClickToCopyOverlay.swift` | Implemented for bounded session names/details. |
| Cost/token chart switch | v0.50.0 #2930 | Implemented; see above. |
| Run-out forecast token | v0.50.0 #2865 | Implemented as the `runOut` panel display mode; see above. |
| Menu-bar pace reserve token | 0.49.6 shows the weekly reserve after 1% of the window has elapsed | Still open. Panel-only presentation; `pace` data is already consumed. Distinct from the run-out token. |
| Ollama `auto`/`web` on Linux | 0.49.6 #2919 allows those sources when a non-empty manual Cookie header is configured | A CLI-side unblock the widget inherits, but selecting the source needs the absent settings descriptor. |

### Blocked on an official Linux CLI contract

| Gap | Why it remains blocked at 0.50.0 |
| --- | --- |
| Per-provider settings editors | No `--descriptors`, no `descriptor` key, no `config set`. See the probes above. macOS equivalents are `PreferencesProviderDetailView.swift`, `PreferencesProviderSettingsRows.swift`, `PreferencesProviderSettingsMetrics.swift`. |
| Token-account add/edit/remove | `config set-api-key` still accepts account options only for z.ai. Affects IBM Bob and every multi-account provider. |
| Fireworks onboarding | Needs `accountSlug` in addition to the API key; no setter exists. Fireworks stays display-only for already-configured accounts. |
| Notion browser onboarding | Automatic browser-cookie discovery is macOS-compiled. Plasma must not read browser sessions. Manual cookie remains the only path. |
| Provider metric and threshold pickers | `PreferencesProviderSettingsMetrics.swift` has no CLI equivalent. |
| Plugin management | `plugins list` is text-only, approvals are interactive, and settings/secrets have no JSON action descriptor. |
| Hooks | `hooksEnabled` / `hookRules` in `PreferencesHooksPane.swift`; no CLI contract owns them. |
| Credits history, plan-utilization history, usage breakdown, storage breakdown | `CreditsHistoryChartMenuView.swift`, `PlanUtilizationHistoryChartMenuView.swift`, `UsageBreakdownChartMenuView.swift`, `StorageBreakdownMenuView.swift`. No stable history payloads in the CLI. |
| Session-equivalent forecast | `SessionEquivalentForecast.swift` requires plan-utilization history and multiple samples. A single current rate-window snapshot is not enough. |
| CLI-auth login handoff | `CodexLoginRunner`, `ClaudeLoginRunner`, `CursorLoginRunner`, `GeminiLoginRunner`. Plasma only opens a URL. Needs a JSON-described action; token and cookie stores must stay in the CLI. |

### macOS-only or non-goals

WidgetKit, Sparkle, Keychain/Full Disk Access consent UI, Dock behavior,
AppKit status-item layout details, remote SSH window focus, iCloud sync,
Cursor's read-only local app session, and the confetti overlay.

## Provider catalog

The Plasma fallback catalog and `scripts/test_provider_icons.sh` list 69
provider IDs; the installed 0.50.0 CLI reports the same 69 and adds none. No
sync is needed.

## Recommended parity decision

Keep provider configuration blocked at the frontend boundary and do not grow
provider-specific QML. Remaining evidence-backed Plasma work, in order:

1. the menu-bar pace reserve token, the last purely presentational panel gap;
2. nothing else until the CLI ships either the settings descriptor or a stable
   history payload. Every other open item depends on one of those two.
