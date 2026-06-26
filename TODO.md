# TODO

- Provider-specific editable settings: the Providers page now includes a
  redacted settings inspector and CLI command hints. Add real editor controls
  for metric pickers, token-account fields, team/org/project options, and quota
  thresholds only when the CLI exposes a stable settings descriptor.
- Dashboard extras: surface Codex web/dashboard fields such as code-review
  remaining, usage breakdown, and credits history when the CLI exposes them.
- Interactive history charts: add hover/selection and credits/plan utilization
  history when the CLI exposes stable history payloads.
- Translations: add gettext/catalog workflow for the existing `i18n` strings.
- Notification refinements: consider reset-imminent notifications if they stay
  quiet and configurable.
