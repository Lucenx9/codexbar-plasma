# Agent Instructions

This repository is the standalone KDE Plasma widget for CodexBar.

## Project Boundaries

- Keep this repo small. It should contain only the Plasma applet, packaging helpers, tests, and docs.
- Do not copy the macOS app, Swift sources, Xcode projects, or full upstream CodexBar tree into this repo.
- Provider logic, authentication, config parsing, quota fetching, and JSON contracts belong in the upstream `codexbar` CLI.
- If a local upstream/fork workspace exists, use it only for comparison,
  syncing provider maps, or proposing CLI contract changes.
- If the Plasma frontend needs new provider data, prefer extending the CLI JSON contract upstream. Do not hand-edit CodexBar config JSON from QML except through supported CLI commands.

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

Keep this in sync with `TODO.md` when feature parity decisions change:

- Provider-specific editing should come from a stable CLI descriptor, not
  duplicated provider-specific config logic in QML. The Providers page consumes
  descriptor fields/actions from `docs/cli-provider-settings-descriptor.md` for
  generic source mode, API key, cookie source/manual cookie, enterprise/base
  URL, workspace/project ID, region, AWS profile/auth mode, and boolean extras.
  Missing controls include token-account add/edit/remove, provider-specific
  auth mode nuances, organization/team, metric, and quota threshold editors.
- Provider onboarding improvements should stay CLI-backed: dashboard actions
  can come from the descriptor and login/account links are fine as fallbacks,
  but browser-cookie import, local-file, OAuth/device-flow, CLI-auth setup, and
  token-account workflows need JSON-described CLI actions before QML grows real
  controls.
- Generic dashboard KPI/summary rows are surfaced from current CLI payloads.
  Richer provider-specific dashboard layouts, billing summaries, usage
  breakdowns, credits history, and model/request/token sections should wait for
  stable CLI presentation fields.
- Interactive history charts can build on the current cost history bars, but
  hover/selection, credits history, and plan utilization history should wait
  for stable history payloads and avoid heavy delegate work. Compact
  burn-down/history views may be useful Plasma equivalents to macOS widgets.
- Gettext template extraction exists. Real `.po` catalogs, compiled catalog
  packaging, and translator contribution docs should come with localization
  work.
- Notification refinements should stay quiet, configurable, and tied to clear
  state transitions.
- Provider drift checks should sync provider keys, CLI aliases, titles, colors,
  docs/dashboard/login URLs, icon assets, and `scripts/test_provider_icons.sh`.
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

On the owner machine, the AUR package normally installs the CLI at `/usr/bin/codexbar`.

## Release Flow

1. Keep `main` green with `make check`.
2. Generate the distributable with `make package`.
3. Publish `dist/codexbar-plasma.plasmoid` in a GitHub Release.
4. Use the full fork workspace only for upstream sync work; this standalone repo is the public user-facing project.
