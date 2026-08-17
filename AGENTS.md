# Agent Instructions

This repository is exclusively the standalone KDE Plasma widget for CodexBar.

In this repository, **plugin**, **widget**, **plasmoid**, and **applet** all mean
the KDE Plasma frontend. The official macOS CodexBar product is a separate app
and is never the implementation target of work in this repo.

## Project Boundaries

- Work only on the Plasma applet in this repository unless the user explicitly
  requests a separate upstream CLI change. A request for macOS parity authorizes
  comparison and Plasma implementation only; it does not authorize editing the
  macOS app, the upstream CLI, or a sibling/fork workspace.
- Treat the official macOS app as a read-only product, behavior, terminology,
  and UX reference. Recreate only useful Plasma-native equivalents backed by an
  official CLI contract; do not translate Swift/AppKit/WidgetKit code into QML.
- Keep this repo small. It should contain only the Plasma applet, packaging helpers, tests, and docs.
- Do not copy the macOS app, Swift sources, Xcode projects, or full upstream CodexBar tree into this repo.
- Provider logic, authentication, config parsing, quota fetching, and JSON contracts belong in the upstream `codexbar` CLI.
- If a local upstream/fork workspace exists, keep it read-only unless the user
  explicitly asks for an upstream change in the current task. Use it only for
  comparison, syncing provider maps, or drafting CLI contract proposals.
- If the Plasma frontend needs new provider data, prefer extending the CLI JSON contract upstream. Do not hand-edit CodexBar config JSON from QML except through supported CLI commands.
- If the official Linux CLI does not expose the required data or action, record
  the gap as an upstream contract requirement and stop at the frontend boundary.
  Do not fill the gap with provider scraping, authentication, or config parsing
  in QML.

## Sources of Truth and Parity

Use this order when sources disagree:

1. The current Plasma implementation, config schema, tests, and documented
   repository decisions define what this repo currently supports.
2. The released official `codexbar` Linux CLI and its documented JSON contracts
   define what the frontend may consume.
3. The official macOS app defines product inspiration and parity candidates,
   not frontend architecture or data contracts.
4. Local forks and experimental branches are comparison material only unless
   the user explicitly selects them as a target.

- Pin comparisons to an exact CLI/app version, tag, or commit. Do not mix an
  installed CLI, upstream `main`, and a local fork and report the result as one
  coherent release.
- Classify every macOS parity gap as one of: **Plasma-native and implementable
  now**, **blocked on an official CLI contract**, or **macOS-only/non-goal**.
- Confirm a field or action exists in official Linux CLI output before designing
  UI around it. Swift view models, screenshots, and filenames are not contracts.
- Prefer generic CLI-described fields, actions, detail rows, and charts over
  provider-specific QML branches. Unknown providers and unknown optional fields
  should degrade gracefully rather than break the whole popup.
- Keep static provider metadata as fallback presentation data only. When the CLI
  exposes canonical metadata, consume it and retain cheap drift tests for any
  remaining fallback map.

## Working Style

- Finish the full requested scope. Progress notes and plans do not substitute
  for implementation. If one part is genuinely blocked, complete every
  independent part and state the exact blocker in one sentence.
- Distinguish questions from change requests. Answer requests to evaluate,
  explain, or diagnose without modifying files. Verbs such as `fix`,
  `implement`, `change`, `add`, `remove`, and `refactor` authorize the smallest
  complete in-scope change.
- Act by default when a step is reversible, low-cost, and clearly in scope. Use
  available tools to inspect files, search code, read documentation, reproduce
  bugs, compare implementations, make scoped edits, and run tests before asking
  the user for missing details. Fix safe, in-scope problems instead of returning
  them as user to-dos.
- Ask first when an action reaches an external audience, is destructive or hard
  to undo, can create meaningful cost, or when plausible interpretations would
  produce materially different results.
- Prefer the smallest complete solution. Avoid unrelated cleanup, abstractions,
  features, dependencies, formatting churn, and architecture changes. Never
  reduce the requested scope silently.
- Understand the surrounding implementation and existing conventions before
  changing established behavior. Preserve compatibility, tests, safeguards,
  error handling, and unexpected behavior unless evidence or the request shows
  that they must change.
- Parallelize independent work only when it saves meaningful time. Use subagents
  only for substantial independent tasks, keep their files and logical areas
  disjoint, and continue useful main-thread work while they run.
- Apply the normal verification for the change: focused tests, linting, type
  checks, builds, reproduction, and diff inspection as appropriate. Avoid
  redundant passes. Never claim a check passed when it failed or was not run;
  state the specific reason when verification is unavailable.
- Communicate in direct technical English with short sentences and paragraphs.
  During longer tasks, report only useful new progress. Keep the final response
  short: what changed, whether it worked, and what the user must do next. Say
  explicitly when no action is needed. When a choice remains, present at most
  two good options, explain the practical difference, and recommend one.

## Repository Workflow

- Before editing, identify the requested Plasma surface, its owning QML file,
  the config entry if any, the CLI payload involved, and the nearest regression
  check. If the requested behavior belongs upstream, report that boundary before
  writing frontend code.
- Preserve user changes in a dirty worktree. Review `git diff` and `git status`
  before handing off, and call out unrelated pre-existing changes rather than
  incorporating them silently.
- Add tests at the cheapest useful layer: normalization/contract assertions for
  data changes, static QML assertions for durable UI rules, and runtime checks
  only when static checks cannot establish the behavior.
- Run the narrowest relevant check while iterating, then the repository-required
  checks before completion. Packaging and runtime checks count only when they
  were actually performed.
- When a parity decision changes, update `TODO.md` and the mirror below in the
  same change so future agents do not revive a rejected port or obsolete gap.

## CLI and Data Safety

- Treat CLI stdout, stderr, descriptors, cached payloads, labels, URLs, and
  provider-controlled status text as untrusted input. Validate shapes, types,
  bounds, command allowlists, and URL schemes before use.
- Never log, display, persist, or pass through raw API keys, cookies, bearer
  tokens, auth headers, or unredacted diagnostics. Secret entry must use supported
  CLI stdin flows and redacted result contracts.
- A secret must never appear anywhere in a command line, including as a shell
  positional argument piped to stdin: `/proc/<pid>/cmdline` is world-readable
  while the child runs. Only `promptDescriptorSecret` may carry a secret, because
  it reads the value inside the script. Generic field writers must reject
  `kind === "secret"` instead of growing a stdin channel.
- Keep command nonce, timeout, disconnect, retry, and stale-result handling close
  to each external process lifecycle. A late process result must not overwrite a
  newer refresh or account selection.
- Preserve partial healthy data when one provider or optional enrichment fails;
  surface the scoped error without clearing unrelated provider snapshots.

## Layout

- `metadata.json`: Plasma applet metadata.
- `contents/ui/main.qml`: panel, popup, provider details, status badges, bars, account selection.
- `contents/ui/components/`: presentation-only QML components used by the panel, popup, and config pages.
- `contents/ui/configGeneral.qml`: general widget settings.
- `contents/ui/configProviders.qml`: provider enablement and provider actions.
- `contents/config/main.xml`: persisted Plasma configuration schema.
- `contents/icons/`: applet and provider icons.
- `scripts/`: static regression checks.

## Agent-Readable Code Rules

- Before changing behavior, read the nearest existing implementation, config
  schema, and static test that cover that behavior. Do not infer contracts from
  filenames alone.
- Make names carry the contract: include provider/source/account/window/unit
  where ambiguity is likely, and use boolean names that read clearly in `if`
  statements.
- Keep helper names honest. `build*`, `format*`, `provider*Url`, `*Rows`, and
  `*Text` helpers should stay side-effect free. `refresh*`, `load*`, `parse*`,
  `select*`, `set*`, and `process*` helpers may mutate state.
- Keep parsing, normalization, presentation rows, and UI rendering separated.
  For new provider data, add/adjust a normalization helper before wiring QML
  controls directly to raw JSON.
- Treat CLI JSON as a contract. When adding a field, update the normalizer,
  the UI surface, the relevant static check, and docs/TODO if behavior changes.
- Prefer small named helpers over repeated inline JavaScript in delegates,
  timers, and DataSource callbacks.
- Prefer small presentation-only QML components for repeated or bulky UI blocks.
  Pass normalized data and an explicit parent API object such as `applet` or
  `configPage`; keep CLI commands, parsing, nonce/process lifecycle, and config
  writes in the owning page unless there is a focused plan and test coverage.
- Put non-obvious lifecycle state in names: `connected*`, `pending*`,
  `*Memo`, `*Revision`, `*Initialized`. Update that state close to the side
  effect it represents.
- Comments should explain why a workaround, contract, or lifecycle rule exists.
  Do not comment obvious assignments or restate the QML type.
- Provider identity data is easy to drift. When adding a provider, check
  provider keys, CLI aliases, title, color, docs/dashboard/login URLs, icon
  asset, and `scripts/test_provider_icons.sh`.
- Every new UI rule that agents might accidentally break should get a cheap
  static assertion in `scripts/` before relying on manual review.
- Keep `AGENTS.md` short and practical. Add rules only after repeated friction
  or a real bug, and prefer pointing to canonical local examples over copying a
  full style guide.

## Current TODO Mirror

Keep this in sync with `TODO.md` when feature parity decisions change. Current
parity baseline: `docs/research/2026-08-16-macos-parity-0.50.0.md` (upstream
v0.50.0, probed against the installed CLI 0.50.0).

- Provider-specific editing should come from a stable CLI descriptor, not
  duplicated provider-specific config logic in QML. The Providers page renders
  descriptor fields/actions from `docs/cli-provider-settings-descriptor.md` for
  generic source mode, API key, cookie source/manual cookie, enterprise/base
  URL, workspace/project ID, region, AWS profile/auth mode, and boolean extras.
  That descriptor is a proposal, not shipped: on CLI 0.50.0
  `config providers --descriptors` fails with `Unknown option --descriptors` and
  the plain payload has no `descriptor` key, so the path is dormant and the page
  falls back to enable/disable, `set-api-key` and links. Keep that fallback
  working; do not add provider-specific QML to work around the gap.
  Missing controls include token-account add/edit/remove, provider-specific
  auth mode nuances, organization/team, metric, and quota threshold editors.
  IBM Bob can use the existing single-key command, but its token-account editing
  and the required Fireworks account slug still need generic CLI field/actions.
- Provider onboarding improvements should stay CLI-backed: dashboard actions
  can come from the descriptor and login/account links are fine as fallbacks,
  but browser-cookie import, local-file, OAuth/device-flow, CLI-auth setup, and
  token-account workflows need JSON-described CLI actions before QML grows real
  controls.
- Generic CodexBar 0.48.1 `usage.details` rows and bounded bar/line charts are
  surfaced, with legacy dashboard KPI/summary payloads retained as a
  compatibility fallback. Richer provider-specific layouts, billing summaries,
  usage breakdowns, credits history, and model/request/token sections should
  wait for stable CLI presentation fields. `usage.credits` carries no allowance,
  so the Credits section prints the balance without a meter; do not reintroduce
  a meter with a hardcoded denominator.
- Quota warning thresholds are user-configurable and bounded by
  `contents/ui/QuotaThresholds.js`; the notification level and the usage-bar
  markers both read them, so neither may hardcode a percentage. Changing a
  threshold must reset the threshold-derived notification memo, but must keep
  the provider status baseline: a settings change is not a status transition,
  and dropping the baseline either re-announces an ongoing incident or swallows
  one that starts while the provider is still refreshing. Per-provider
  thresholds stay blocked on the CLI descriptor.
- `codexbar sessions --json-v2` feeds a bounded local Sessions tab. Normalize
  only safe display fields; never retain, render, open, or follow `cwd`,
  `transcriptPath`, IDs, or PIDs. Remote/SSH host focus is macOS-only.
- Existing detail and cost charts support pointer and keyboard inspection; the
  Usage & Spend tab adds bounded range and heatmap views. Credits history, plan
  utilization history, and session-equivalent forecasts must wait for stable
  CLI history payloads.
- `costHistoryMetric` switches every cost chart between cost and tokens from the
  same `cost` payload; never add a CLI call for the metric, and keep the bar
  scale reading the selected metric. `historyCoverageIsEstablished` drives the
  "still collecting" note, and a missing flag counts as established.
- Panel element composition has a persisted, sanitized order for identity,
  status, usage text, and meters. Keep existing visibility settings working.
  The `runOut` display mode stays tied to `paceWarningActive`, so it prints a
  duration only when the CLI predicts exhaustion before the reset.
- Gettext template extraction exists. Real `.po` catalogs, compiled catalog
  packaging, and translator contribution docs should come with localization
  work.
- Predictive pace warnings are opt-in, CLI-backed, silently primed, and tied to
  a new projected-exhaustion transition. Other notification refinements should
  stay quiet, configurable, and tied to clear state transitions.
- The fallback catalog covers the 69 provider IDs released in CodexBar v0.49.1
  and retains fork-only compatibility assets. Re-verified against the installed
  0.50.0 CLI, which reports the same 69 and adds none. Future drift syncs should
  cover provider keys, CLI aliases, titles, colors, docs/dashboard/login URLs,
  icon assets, and `scripts/test_provider_icons.sh`.
- The GitHub Release updater is current. If a KDE Store channel is added,
  prefer KDE Store/KNewStuff/Discover for that channel.
- Do not port macOS-only surfaces directly, including WidgetKit, Sparkle, and
  Keychain/Full Disk Access UI. Add only useful Plasma/Linux equivalents and
  keep provider/auth logic in the CLI.

Agent instruction references:

- OpenAI Codex AGENTS.md guide:
  https://developers.openai.com/codex/guides/agents-md
- OpenAI Codex best practices:
  https://developers.openai.com/codex/learn/best-practices
- Claude Code memory/instructions:
  https://docs.anthropic.com/en/docs/claude-code/memory
- GitHub Copilot repository instructions:
  https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/add-custom-instructions/add-repository-instructions
- Cursor agent rules best practices:
  https://cursor.com/blog/agent-best-practices

## Plasma/QML Guidelines

- Keep the Plasma 6 root object as `PlasmoidItem`. Use `ContainmentItem`
  only for containment/panel/desktop code.
- Preserve the standard package shape: `metadata.json`, `contents/ui`,
  `contents/config/main.xml`, and `contents/config/config.qml` when config
  tabs are needed.
- Persistent settings belong in `contents/config/main.xml`; config pages bind
  them through `cfg_*` properties, and runtime code reads them through
  `Plasmoid.configuration`.
- Prefer Plasma-styled controls for widget UI: `PlasmaComponents` for the
  panel/popup surface and Kirigami/Qt Quick Controls in config pages.
- Use the right control for the setting: `CheckBox` for booleans, `SpinBox` or
  `Slider` for numbers, `TextField` for short strings, and `ComboBox` when
  there are more than three choices.
- Items default to 0x0. Always give visual children a real size through
  layouts, anchors, implicit sizes, or explicit compact dimensions.
- Use `Layout.minimum*`, `Layout.preferred*`, `implicitWidth`,
  `implicitHeight`, and `Kirigami.Units` instead of panel-size magic numbers.
- Prefer declarative bindings over imperative assignments. Keep bindings
  simple; move repeated or expensive calculations into small helper functions
  or cached properties.
- Avoid heavy JavaScript in delegates, compact panel rendering, timer paths,
  and data-source callbacks. Profile before doing performance refactors.
- Use anchors or layouts for relative positioning instead of binding `x`, `y`,
  `width`, or `height` to sibling geometry.
- Keep delegates small and stable. Do not add clipping, shaders, or nested
  layout work in repeaters unless there is a visible need.
- External `Repeater`/view delegate components must declare
  `required property var modelData` inside the component. Do not rely on the
  parent assigning `modelData` through an alias property; `qmllint` may miss the
  runtime scoping error.
- When adding or moving QML files, update every local QML source list:
  `Makefile` `QML_FILES`, `scripts/test_qml_hardening.sh`,
  `scripts/update_translations.sh`, and any static assertion in `scripts/`
  that was tied to the old file.
- All user-facing text must go through `i18n` or `i18np`.
- Test with `make check` first. Use `plasmawindowed` or `plasmoidviewer` for
  quick widget checks when available; after extracting delegates/components,
  install or upgrade the local plasmoid and check recent Plasma logs for
  `ReferenceError`, `TypeError`, and `SyntaxError`.
- Restarting or replacing `plasmashell` is a final runtime check, not the
  normal edit loop.

Primary references:

- KDE Plasma widget setup:
  https://develop.kde.org/docs/plasma/widget/setup/
- KDE Plasma widget properties:
  https://develop.kde.org/docs/plasma/widget/properties/
- KDE Plasma widget configuration:
  https://develop.kde.org/docs/plasma/widget/configuration/
- KDE Plasma widget testing:
  https://develop.kde.org/docs/plasma/widget/testing/
- KDE Plasma KF6 porting:
  https://develop.kde.org/docs/plasma/widget/porting_kf6/
- KDE Plasma QML API:
  https://develop.kde.org/docs/plasma/widget/plasma-qml-api/
- Qt QML best practices:
  https://doc.qt.io/qt-6/qtquick-bestpractices.html
- Qt Quick performance:
  https://doc.qt.io/qt-6/qtquick-performance.html

## Verification

Run this before committing QML, config, packaging, or README changes:

```sh
make check
```

For packaging changes, also run:

```sh
make package
```

For runtime verification on the local KDE session:

```sh
./install.sh
journalctl --user -u plasma-plasmashell.service --since '2 minutes ago' --no-pager \
  | rg -n 'app\.codexbar|CodexBar|ReferenceError|TypeError|SyntaxError|file://.*/app.codexbar'
```

Ignore unrelated Plasma logs from other widgets unless they mention `app.codexbar`.

## CLI Assumptions

The widget expects a working `codexbar` binary. Useful probes:

```sh
codexbar usage --format json --json-only
codexbar usage --provider codex --status --format json --json-only
codexbar usage --provider codex --all-accounts --format json --json-only
codexbar cost --format json --json-only
codexbar config providers --format json --json-only
```

Do not assume an installation-specific CLI path. Keep the widget default at
`codexbar` and use `command -v codexbar` when an absolute path is needed; AUR,
Homebrew, and release-tarball installs may resolve to different locations.

## Release Flow

1. Keep `main` green with `make check`.
2. Generate the distributable with `make package`.
3. Publish `dist/codexbar-plasma.plasmoid` in a GitHub Release.
4. Use the full fork workspace only for upstream sync work; this standalone repo is the public user-facing project.
