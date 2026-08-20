# TODO

Parity baseline: `docs/research/2026-08-20-macos-parity-0.54.0.md`, pinned to
upstream v0.54.0 and probed against the installed CLI 0.54.0.

- Provider-specific editable settings: the Providers page renders generic
  fields/actions from `docs/cli-provider-settings-descriptor.md` without
  provider-specific QML branches. Declared coverage includes source mode, API
  key, cookie source/manual cookie, enterprise/base URL, workspace/project ID,
  region, AWS profile/auth mode, and boolean extras. That descriptor is still a
  *proposal*: on CLI 0.54.0 `config providers --descriptors` returns
  `Unknown option --descriptors` and the plain payload carries no `descriptor`
  key, so the whole path is dormant and the page degrades to enable/disable,
  `set-api-key` and docs/dashboard/login links. Keep that fallback working.
  Missing controls once the CLI ships the contract include
  token-account add/edit/remove, provider-specific auth mode nuances,
  organization/team editors, provider metric pickers, and quota thresholds. Do
  not duplicate macOS Swift provider settings logic in QML; extend
  `codexbar config` first. IBM Bob can use the existing single-key command, but
  its token-account editing still needs generic CLI field/actions. Fireworks
  0.54.0 auto-discovers its account slug from the API key, so a follow-up can
  enable the generic single-key setup path without a separate slug editor.
- Provider onboarding parity: descriptor-backed dashboard actions are supported,
  and legacy login/account/dashboard/docs links remain as fallbacks. Add safer
  setup actions for providers that need browser-cookie import, local app files,
  OAuth/device-flow handoff, CLI-auth setup, or token-account workflows when the
  CLI can describe and execute those actions in JSON.
- Dashboard extras: the widget now surfaces the generic CodexBar 0.48.1
  `usage.details` rows and bounded bar/line charts, with legacy KPI/summary
  payloads retained as a compatibility fallback. Add richer sections only when
  the CLI extends that stable presentation contract. Missing examples include
  billing summaries, usage breakdowns, credits history, and richer
  provider-specific model/request/token sections.
- Credits allowance: `usage.credits` reports `remaining`, `updatedAt`, and
  `events` only. With no allowance or plan total, the Credits section prints the
  balance without a meter; the meter it replaced scaled against a hardcoded 1000
  credits and so filled for reasons the payload never described. Restore a meter
  only when the CLI reports the matching allowance.
- Cost history plots either cost or tokens through `costHistoryMetric`; the
  selector drives the range chart, the heatmap, and the per-provider bars from
  one `cost` payload, so it must never add a CLI call. `historyCoverageIsEstablished`
  drives the "still collecting" note; a missing flag means established.
- Cost truthfulness: CLI 0.54.0 emits `coverage` counters and `provenance`, plus
  bounded project breakdown inputs. The widget does not consume them yet.
  Normalize them before adding richer spend presentation so partial, estimated,
  unmetered, or unpriced totals do not look exact. A future Projects view must
  discard the emitted local `path` and retain only bounded display fields.
- Quota warning thresholds are configurable through `quotaWarningPercent` and
  `quotaCriticalPercent`, bounded by `contents/ui/QuotaThresholds.js`, and drive
  both the notification level and the usage-bar markers. Per-provider thresholds
  stay blocked on the CLI descriptor. Do not reintroduce literal percentages at
  a call site; `limitResetArmThreshold` is a separate reset-detection knob and
  is deliberately not tied to the warning step. Changing a threshold resets the
  threshold-derived notification memo but keeps the provider status baseline: a
  settings change is not a status transition. That decision lives in
  `contents/ui/NotificationMemo.js` and is covered by
  `tests/tst_notification_memo.qml`; keep it there rather than reinlining it in
  `main.qml`.
- Local Agent Sessions are consumed through `codexbar sessions --json-v2` in a
  bounded, refreshable global tab. Only safe display fields are normalized;
  `cwd`, `transcriptPath`, IDs, and PIDs are neither retained nor rendered.
  Remote/SSH host focus stays macOS-only.
- Existing detail and cost charts now support hover, click selection, and
  keyboard inspection. The global Usage & Spend tab adds 7/30/90-day cost
  ranges and a bounded activity heatmap. Credits history, plan-utilization
  history, and session-equivalent forecasts still need stable CLI history
  payloads; do not infer history from one snapshot.
- Panel element composition now has a persisted, sanitized order for identity,
  status, usage text, and provider meters. Visibility remains controlled by the
  existing Plasma-native display settings. The `runOut` display mode shows the
  predicted duration only while the CLI pace forecast reports exhaustion before
  the reset; keep it tied to `paceWarningActive` instead of the percent used.
  The macOS weekly reserve token remains open. CLI 0.54.0 also adds conditional
  menu-bar rules and direct primary/secondary/tertiary lane tokens; these are
  implementable from existing normalized data only through a Plasma-native rule
  model and configuration UI, not by copying the Swift persistence model.
- Translations: gettext template extraction is in place. Add real `.po`
  catalogs, compiled catalog packaging, and translator contribution docs when
  localization work starts.
- Predictive pace warnings are opt-in and consume the CLI `pace` forecast; they
  silently prime the current state and notify only on a new projected
  exhaustion. Consider reset-imminent notifications only if they remain quiet,
  configurable, and tied to clear state transitions.
- Provider drift checks: the Plasma fallback catalog covers all 69 provider IDs
  released in CodexBar v0.49.1 and re-verified on 0.54.0, while retaining
  fork-only compatibility assets.
  When upstream releases providers, sync provider keys, CLI aliases, titles,
  colors, docs/dashboard/login URLs, icon assets, and
  `scripts/test_provider_icons.sh`.
- Plasma release channel: the GitHub Release updater is in place. If the widget
  is published through KDE Store, prefer KDE Store/KNewStuff/Discover for that
  channel instead of inventing a parallel updater.
- Platform-specific non-goals: do not port macOS-only surfaces directly
  (WidgetKit, Sparkle, Keychain/Full Disk Access UI). Add only Plasma/Linux
  equivalents that provide real value and keep provider/auth logic in the CLI.
