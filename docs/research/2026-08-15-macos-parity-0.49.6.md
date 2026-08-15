# CodexBar macOS parity at 0.49.6

Checked 2026-08-15. Read-only comparison of the official `steipete/CodexBar`
product against the Plasma baseline. Supersedes
[`2026-08-10-macos-parity-progress.md`](./2026-08-10-macos-parity-progress.md),
which was pinned to v0.49.1 and is now five releases behind.

## Pinned scope

| Reference | Exact revision | Date |
| --- | --- | --- |
| Plasma baseline | local `bdc6cc433d1344868311d55008f57e09be1221dc` (tag `v0.2.16`) | 2026-08-15 |
| Official baseline | [`v0.49.6`](https://github.com/steipete/CodexBar/releases/tag/v0.49.6), commit [`0f66c32ecb69f35bccdd4e135cb0c7a6afd1dfb6`](https://github.com/steipete/CodexBar/commit/0f66c32ecb69f35bccdd4e135cb0c7a6afd1dfb6) | published 2026-08-14 09:28 UTC |
| Previous pinned baseline | `v0.49.1`, commit `ae1111e39912642da33c6f1bf6647ce1ab3f2883` | 2026-08-10 |
| Installed Linux CLI | `codexbar` **0.49.6** on the owner machine | probed 2026-08-15 |

v0.49.6 is the latest upstream release at the time of writing, and the installed
CLI matches it. Unlike the previous report, every CLI claim below is a live
probe of that exact binary rather than a source reading.

## Verdict

Provider *data* is at parity. Provider *configuration* is not, and the reason is
unchanged: the machine-readable settings/action descriptor still does not exist
in the released CLI. Releases 0.49.2 through 0.49.6 added no new CLI JSON or
settings contract.

## Live CLI probes

```
$ codexbar --version
CodexBar 0.49.6

$ codexbar config providers --format json --json-only | jq 'length'
69

$ codexbar config providers --format json --json-only | jq -r '[.[] | keys] | add | unique | join(", ")'
defaultEnabled, displayName, enabled, provider

$ codexbar config providers --descriptors --format json --json-only
[{"provider":"cli","error":{"kind":"args","code":1,"message":"Unknown option --descriptors"},"source":"cli"}]
```

`codexbar config` exposes only `validate | dump | providers | enable | disable |
set-api-key`. There is no `config set` and no `config action`.

Two consequences worth recording precisely, because the previous report and
`TODO.md` were easy to misread as "descriptors work today":

1. The `--descriptors` flag is rejected, **and** the plain `config providers`
   payload carries no `descriptor` key at all. The contract is absent, not
   partially shipped.
2. The Plasma Providers page implements
   [`docs/cli-provider-settings-descriptor.md`](../cli-provider-settings-descriptor.md),
   which is a **proposed** contract. That code is correct but dormant. The
   `Unknown option --descriptors` string is matched by
   `isDescriptorUnsupportedMessage()` in `contents/ui/configProviders.qml`, so
   the page retries without the flag and degrades to the legacy path. Verified
   against the exact error text above.

In practice, Plasma provider configuration today is: enable/disable,
`set-api-key`, and docs/dashboard/login links.

## Consumed stable contract: Agent Sessions

`codexbar sessions --json-v2` works on 0.49.6 and returns records that the
frontend now bounds and normalizes:

```
$ codexbar sessions --json-v2
[{"projectName":"...","host":"...","lastActivityAt":"2026-08-15T04:21:01Z",
  "pid":2102466,"source":"cli","id":"0ea0996c-...","provider":"claude",
  "transcriptPath":"/home/..."}]
```

The stable `AgentSession` schema makes `sessionName`, `startedAt`, and
`lastActivityAt` optional, so individual records can omit any of them. The
local Sessions tab retains only provider, project/session name, host, source,
state, and one activity timestamp. It follows the CLI table fallback of
`lastActivityAt ?? startedAt` for the timestamp and ordering. It deliberately
drops `cwd`, `transcriptPath`, IDs, and PIDs. Remote/SSH host focus stays
macOS-only.

## macOS frontend surfaces Plasma does not have

The authoritative settings pane list is `SettingsPane` in
[`Sources/CodexBar/PreferencesSelection.swift`](https://github.com/steipete/CodexBar/blob/v0.49.6/Sources/CodexBar/PreferencesSelection.swift):
`general`, `iCloudSync`, `usageSpend`, `notifications`, `menuBar`, `menu`,
`advanced`, `hooks`, `plugins`, `about`, `debug`, `provider:<id>`. Plasma has
five pages: General, Providers, Display, Advanced, Debug.

### Plasma-native items

| Gap | Official evidence | Plasma consequence |
| --- | --- | --- |
| Configurable quota thresholds | `QuotaWarningSettingsViews.swift`, plus a dedicated `notifications` pane | Implemented through bounded shared thresholds that drive both notifications and usage-bar markers. |
| Local Agent Sessions list | `AgentSessionsStore.swift` plus the `sessions --json-v2` probe above | Implemented as a bounded global tab; path/ID fields are discarded. |
| Chart hover/selection | `ChartBarHoverSelection.swift` | Implemented for cost and generic detail charts with pointer and keyboard inspection. |
| Panel composition | `MenuBarLayout.swift`, `MenuBarLayoutEditor.swift`, `MenuBarLayoutRenderer.swift`, `StatusComponentsMenuView.swift` | Implemented as a persisted, sanitized element order while retaining the existing visibility controls. |
| Spend dashboard | `SpendDashboardModel.swift`, `SpendActivityHeatmap.swift`, `PreferencesSpendDashboardPane.swift` | Implemented from `cost --days` with 7/30/90-day ranges, an interactive chart, and bounded heatmap. |
| Predictive pace warnings | `PredictivePaceWarnings.swift`, `HistoricalUsagePace.swift` | Implemented as an opt-in transition warning from the CLI's current `pace.willLastToReset` and `pace.etaSeconds` fields; no local history is fabricated. |
| Click-to-copy values | `ClickToCopyOverlay.swift` | Implemented for bounded session names/details. |
| Menu-bar pace reserve token | 0.49.6 shows the weekly reserve after 1% of the window has elapsed | Panel-only presentation; `pace` data is already consumed. |
| Ollama `auto`/`web` on Linux | 0.49.6: "allow the `auto` and `web` usage sources on Linux when a non-empty manual Cookie header is configured, while keeping automatic browser-cookie imports gated to supported platforms" (#2919) | A CLI-side unblock the widget should simply inherit. Worth a runtime check that the source override reaches it. |

### Blocked on an official Linux CLI contract

| Gap | Why it remains blocked at 0.49.6 |
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
| CLI-auth login handoff | `CodexLoginRunner`, `ClaudeLoginRunner`, `CursorLoginRunner`, `GeminiLoginRunner`, `TerminalApp.swift`. Plasma only opens a URL. Needs a JSON-described action; token and cookie stores must stay in the CLI. |

### macOS-only or non-goals

WidgetKit, Sparkle, Keychain/Full Disk Access consent UI, Dock behavior
(`DockIconController.swift`), AppKit status-item layout details, remote SSH
window focus, iCloud sync, and `ScreenConfettiOverlayController.swift`.

## Provider catalog

The Plasma fallback catalog and `scripts/test_provider_icons.sh` list 69
provider IDs; the installed 0.49.6 CLI reports 69. `fireworks.svg` and
`ibmbob.svg` exist and are covered by the icon regression. The two-provider sync
recommended by the previous report is complete.

## 0.49.2 to 0.49.6 summary

No new provider IDs, no new CLI JSON or settings contract. The releases are
macOS presentation fixes plus provider data fixes. Because 0.49.0 moved both
platforms onto the same QuickJS plugin engine, the data fixes (Codex early
weekly reset, OpenCode pay-as-you-go, Grok web billing, Amp Megawatt/Gigawatt
renewals, Antigravity untouched-family hiding, Ollama cookie recovery) reach
Plasma by upgrading the CLI, with no QML work. One Linux-specific CLI
reliability fix landed in 0.49.6: per-request URLSession teardown during
Antigravity localhost requests could crash `serve` daemons and one-shot usage
runs (#2243).

## Recommended parity decision

Keep provider configuration blocked at the frontend boundary and do not grow
provider-specific QML. The next evidence-backed Plasma work, in order:

1. configurable quota warning thresholds;
2. chart hover/selection on the charts that already render;
3. local Agent Sessions list against `sessions --json-v2`;
4. configurable panel element composition.

Items 1, 2 and 4 need no upstream change. Item 3 consumes a contract that has
been stable since at least 0.49.1 and has never been used.
