# TODO

- Provider-specific editable settings: the Providers page now includes a
  redacted settings inspector and CLI command hints. Add real editor controls
  only when the CLI exposes a stable settings descriptor matching
  `docs/cli-provider-settings-descriptor.md`. The missing controls include
  source/auth mode pickers, cookie source/manual cookie fields, API key fields,
  enterprise/base URL fields, region/workspace/project/org/team fields,
  token-account add/edit/remove, provider metric pickers, and quota thresholds.
  Do not duplicate the macOS Swift provider settings logic in QML; extend
  `codexbar config` first.
- Provider onboarding parity: keep login/account/dashboard/docs links, but add
  safer setup flows for providers that need manual browser cookies, local app
  files, OAuth/device-flow handoff, or CLI-auth setup when the CLI can describe
  those actions in JSON.
- Dashboard extras: the widget now surfaces generic KPI/summary rows from CLI
  dashboard payloads. Add richer provider-specific dashboard layouts only when
  the CLI exposes stable presentation fields. Missing examples include Codex
  web dashboard extras, provider billing summaries, usage breakdowns, credits
  history, and provider-specific model/request/token sections.
- Interactive history charts: add hover/selection and credits/plan utilization
  history when the CLI exposes stable history payloads. Consider compact
  burn-down/history views as Plasma equivalents to the macOS WidgetKit widgets,
  but avoid heavy delegate work in QML.
- Translations: gettext template extraction is in place. Add real `.po`
  catalogs, compiled catalog packaging, and translator contribution docs when
  localization work starts.
- Notification refinements: consider reset-imminent notifications if they stay
  quiet and configurable. Keep status, quota, reset, and update notifications
  tied to clear state transitions and user-visible settings.
- Provider drift checks: upstream CodexBar currently has 53 provider IDs, and
  the Plasma icon set covers them. When upstream adds providers, sync provider
  keys, CLI aliases, titles, colors, docs/dashboard/login URLs, icon assets, and
  `scripts/test_provider_icons.sh`.
- Plasma release channel: the GitHub Release updater is in place. If the widget
  is published through KDE Store, prefer KDE Store/KNewStuff/Discover for that
  channel instead of inventing a parallel updater.
- Platform-specific non-goals: do not port macOS-only surfaces directly
  (WidgetKit, Sparkle, Keychain/Full Disk Access UI). Add only Plasma/Linux
  equivalents that provide real value and keep provider/auth logic in the CLI.
