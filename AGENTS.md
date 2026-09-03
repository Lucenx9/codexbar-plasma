# Agent instructions

This repository is exclusively the standalone KDE Plasma widget for CodexBar.

In this repository, **plugin**, **widget**, **plasmoid**, and **applet** all mean
the KDE Plasma frontend. The official macOS CodexBar product is a separate app
and is never the implementation target of work in this repo.

## Project boundaries

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

## Sources of truth and parity

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

## Working style

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

## Repository workflow

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

## CLI and data safety

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
- `contents/ui/main.qml`: the applet composition root. Owns CLI process/nonce
  lifecycles, refresh and account coordination, selected state, configuration
  updates, external effects, and the adapters the popup binds to.
- `contents/ui/*.js`: pure trust-boundary, normalization, presentation, and
  decision modules. Their public behavior is covered directly by `tests/tst_*.qml`.
- `contents/ui/components/CompactRepresentation.qml`: the panel representation.
- `contents/ui/components/FullRepresentation.qml`: the popup - tab switcher,
  overview, provider details, status badges, bars, credits, cost sections.
- `contents/ui/components/`: presentation-only QML components used by the panel, popup, and config pages.
- `contents/ui/configGeneral.qml`: general widget settings.
- `contents/ui/configProviders.qml`: provider enablement and actions. Owns their
  CLI process lifecycle, QML state, prompts, configuration writes, and effects.
- `contents/ui/config/*.js`: pure provider-config protocol and command-planning
  modules, with direct adversarial QtTests.
- `contents/config/main.xml`: persisted Plasma configuration schema.
- `contents/icons/`: applet and provider icons.
- `scripts/`: static regression checks.
- `scripts/lib/`: shared helpers for those checks, including the QML surface manifest.

## Agent-readable code rules

- Before changing behavior, read the nearest existing implementation, config
  schema, and static test that cover that behavior. Do not infer contracts from
  filenames alone.
- Make names carry the contract: include provider/source/account/window/unit
  where ambiguity is likely, and use boolean names that read clearly in `if`
  statements.
- Keep helper names honest. `build*`, `format*`, `provider*Url`, `*Rows`, and
  `*Text` helpers should stay side-effect free. `refresh*`, `load*`, `parse*`,
  `select*`, `set*`, and `process*` helpers may mutate state.
- Before implementing non-trivial behavior, identify its owning QML surface,
  input contract, external effects, and cheapest behavioral test seam. Put pure
  parsing, normalization, presentation, planning, or transition logic in a
  focused JS module in the same change; do not land it in a QML page for a later
  extraction.
- Make a pure module's public interface the behavioral test surface. A protocol
  boundary accepts untrusted input and returns bounded validated data; a decision
  boundary accepts explicit observations/options and returns semantic results,
  intents, or opaque next state. It must not read root properties, localize text,
  or perform effects.
- Keep DataSource and CLI process/nonce/timer lifecycle, configuration writes,
  prompts, URL opening, notifications, and other effects in the owning QML
  surface. QML adapts inputs, commits returned state, localizes semantic results,
  and performs those effects.
- When multiple surfaces consume one CLI envelope, share its low-level bounded
  record/envelope contract and keep surface-specific projections separate. Do
  not duplicate raw parsing or force distinct UI semantics through one lossy
  high-level result.
- Extract only when the interface hides real complexity. Avoid pass-through
  controllers, callback-heavy modules that mirror root state, and declarative
  file splits driven only by line count.
- Complete the seam with the feature: use direct adversarial QtTests for the
  pure interface and surface assertions for QML wiring, effect ownership, and
  lifecycle ordering. Do not pin private helper names or body decomposition once
  behavior is covered directly.
- Treat CLI JSON as a contract. When adding a field, update the normalizer,
  the UI surface, the relevant static check, and docs/TODO if behavior changes.
- Prefer small named helpers over repeated inline JavaScript in delegates,
  timers, and DataSource callbacks.
- Prefer small presentation-only QML components for repeated or bulky UI blocks.
  Pass normalized data and an explicit parent API object such as `applet` or
  `configPage`; keep command execution, nonce/process lifecycle, configuration
  writes, and effects in the owning page.
- Put non-obvious lifecycle state in names: `connected*`, `pending*`,
  `*Memo`, `*Revision`, `*Initialized`. Update that state close to the side
  effect it represents.
- Comments should explain why a workaround, contract, or lifecycle rule exists.
  Do not comment obvious assignments or restate the QML type.
- Provider identity data is easy to drift. When adding a provider, check
  provider keys, CLI aliases, title, color, docs/dashboard/login URLs, icon
  asset, and `scripts/test_provider_icons.sh`.
- Give durable QML wiring and effect rules cheap surface assertions in `scripts/`;
  cover pure behavioral rules with direct QtTests instead of body searches.
- Keep `AGENTS.md` short and practical. Add rules only after repeated friction
  or a real bug, and prefer pointing to canonical local examples over copying a
  full style guide.

## Current TODO mirror

Keep this in sync with `TODO.md` when feature parity decisions change. Current
parity baseline: `docs/research/2026-09-01-macos-parity-0.56.2.md`, pinned to
upstream v0.56.2 and probed with the checksum-verified official Linux CLI
0.56.2 release asset. The audit compared the verified v0.55.0 and v0.56.2
binaries in isolated accounts. The provider catalog and the `config providers`,
`usage`, and `sessions` contracts remain compatible. The `cost` command now
supports Antigravity token-only local history. The audit did not install or
replace a host CLI.

- Provider-specific editing should come from a stable CLI descriptor, not
  duplicated provider-specific config logic in QML. The Providers page renders
  descriptor fields/actions from `docs/cli-provider-settings-descriptor.md` for
  generic source mode, API key, cookie source/manual cookie, enterprise/base
  URL, workspace/project ID, region, AWS profile/auth mode, and boolean extras.
  That descriptor is a proposal, not shipped: on CLI 0.56.2
  `config providers --descriptors` fails with `Unknown option --descriptors` and
  the plain payload has no `descriptor` key, so the path is dormant and the page
  falls back to enable/disable, `set-api-key` and links. Keep that fallback
  working; do not add provider-specific QML to work around the gap.
  Missing controls include token-account add/edit/remove, provider-specific
  auth mode nuances, organization/team, metric, and quota threshold editors.
  IBM Bob can use the existing single-key command, but its token-account editing
  still needs generic CLI field/actions. Fireworks 0.54.0 and later
  auto-discovers its single account slug from the API key, so Plasma enables the
  generic single-key setup path; multi-account slug editing remains blocked on a
  generic field/action descriptor.
- Provider onboarding improvements should stay CLI-backed: dashboard actions
  can come from the descriptor and login/account links are fine as fallbacks,
  but browser-cookie import, local-file, OAuth/device-flow, CLI-auth setup, and
  token-account workflows need JSON-described CLI actions before QML grows real
  controls.
- Generic CodexBar 0.48.1 `usage.details` rows and bounded bar/line charts are
  surfaced, with legacy dashboard KPI/summary payloads retained as a
  compatibility fallback. Richer provider-specific layouts, billing summaries,
  usage breakdowns, credits history, and model/request/token sections should
  wait for stable CLI presentation fields. A plain `usage.credits` balance has
  no generic allowance, so it stays meter-free. The optional Codex-only
  `credits.codexCreditLimit` record is normalized into finite non-negative
  amounts, clamped percentages, and bounded reset metadata. Show its meter only
  for that validated nested record; never apply its denominator to a plain credit
  balance.
- Quota warning thresholds are user-configurable and bounded by
  `contents/ui/QuotaThresholds.js`; the notification level and the usage-bar
  markers both read them, so neither may hardcode a percentage. Changing a
  threshold must reset the threshold-derived notification memo, but must keep
  the provider status baseline: a settings change is not a status transition,
  and dropping the baseline either re-announces an ongoing incident or swallows
  one that starts while the provider is still refreshing. That decision lives in
  `contents/ui/NotificationMemo.js` and is covered behaviourally by
  `tests/tst_notification_memo.qml`; keep it there instead of reinlining it in
  `main.qml`, which owns only the memo property and the notification call.
  Per-provider thresholds stay blocked on the CLI descriptor.
- `codexbar sessions --json-v2` feeds a bounded local Sessions tab. Normalize
  only safe display fields; never retain, render, open, or follow `cwd`,
  `transcriptPath`, IDs, or PIDs. Remote/SSH host focus is macOS-only.
- Existing detail and cost charts support pointer and keyboard inspection; the
  Usage & Spend tab adds bounded range and heatmap views. CodexBar 0.55.0 Kiro
  overage, z.ai BigModel CN balance, and Cursor Grok Bot data already fit the
  generic detail, provider-cost, and extra-window paths. Antigravity local token
  history now comes from Linux `cost`; it is not priced spend, so Plasma keeps
  its token charts separate from unavailable dollar amounts. Cursor local or
  dashboard cost remains blocked because the Linux command still rejects
  Cursor. Grok period-only responses no longer become false zeroes, but an
  explicit unknown row with reset metadata needs a generic CLI window contract.
  Credits history, plan utilization history, and session-equivalent forecasts
  must wait for stable CLI history payloads.
- `costHistoryMetric` switches every cost chart between cost and tokens from the
  same `cost` payload; never add a CLI call for the metric, and keep the bar
  scale reading the selected metric. `historyCoverageIsEstablished` drives the
  "still collecting" note, and a missing flag counts as established.
- CLI 0.56.2 cost `coverage` counters and `provenance` are normalized by
  `ProviderNormalizer.normalizeCostTrustMetadata`; provider and global totals
  use `CostPresentation.costTrustSummary` to qualify estimated, partial, or
  approximate amounts and render one shared notice. Keep missing legacy metadata
  quiet, keep pricing coverage separate from `historyCoverageIsEstablished`, and
  never expose raw provenance values in QML. Project breakdowns remain future
  work: discard local `path` values and keep only bounded display fields.
  Antigravity now emits token-only history through the same generic envelope.
  It normally omits dollar amounts, but CLI 0.56.2 uses zero as the
  established-empty sentinel even though its renderer says costs are
  unavailable. `normalizeCostDaily` and `normalizeCostModels` preserve absent
  costs; `normalizeProviderCostTotals` masks that provider sentinel until the
  CLI exposes explicit cost availability. Token charts render while cost totals
  and cost-mode charts remain unavailable.
- Panel element composition has a persisted, sanitized order for identity,
  status, usage text, and meters. Keep existing visibility settings working.
  The `runOut` display mode stays tied to `paceWarningActive`, so it prints a
  duration only when the CLI predicts exhaustion before the reset. The weekly
  reserve token remains open. CLI 0.54.0 conditional and direct-lane tokens are
  optional Plasma-native work; do not copy the macOS persistence model.
- Gettext template extraction exists. Real `.po` catalogs, compiled catalog
  packaging, and translator contribution docs should come with localization
  work.
- Predictive pace warnings are opt-in, CLI-backed, silently primed, and tied to
  a new projected-exhaustion transition. Other notification refinements should
  stay quiet, configurable, and tied to clear state transitions.
- The fallback catalog covers the 69 provider IDs released in CodexBar v0.49.1
  and retains fork-only compatibility assets. Re-verified against the official
  0.56.2 Linux CLI: it reports the same 69 and adds none. OpenRouter changed its
  canonical dashboard action to `https://openrouter.ai/activity`; the fallback
  and its drift assertion now use that URL. No other provider identity metadata
  changed. Future drift syncs should cover provider keys, CLI aliases, titles,
  colors, docs/dashboard/login URLs, icon assets, and
  `scripts/test_provider_icons.sh`.
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

## Plasma/QML guidelines

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
- `scripts/lib/qml_surfaces.py` is the single source list of QML/JS files, grouped
  into *surfaces* (`applet`, `providers`, one per config page, and `all`). The
  `Makefile`, `scripts/test_qml_hardening.sh`, and `scripts/update_translations.sh`
  all read it, so adding a file inside an existing glob needs no list edit. Add a
  glob only when a new directory appears; `test_qml_hardening.sh` fails if any
  QML/JS source on disk is not covered.
- Write static assertions with `require_in_surface` / `reject_in_surface` (bash)
  or `Surface.require` / `Surface.function_body` / `Surface.id_block` (python)
  when the rule belongs to the plasmoid runtime or a config page as a whole. Then
  moving code out of `main.qml` cannot break the check, so the safety net is not
  being edited in the same commit as the change it guards. Keep the `*_in_file`
  helpers only for genuine per-file contracts, such as "every one of these
  component delegates must declare a safe icon fallback".
- Assert a shared helper with `require_definition_where_used` (bash) or
  `Surface.require_definition_where_used` (python), never a plain
  `require_in_surface "function foo("`. QML and JS files share no function scope,
  so every file calling `hasOwnKey` unqualified must declare the name itself; a
  surface-wide search is satisfied by any one of them, and deleting the
  declaration that live callers depend on would pass. This requires the
  declaration in every file that calls the helper unqualified, and in the surface
  root when components reach it through `applet.foo(...)`. It still follows the
  code if the helper and its callers move together.
- The repeated declaration is a name binding, not a licence to repeat the logic.
  `hasOwnKey`, `isUnsafeObjectKey`, `copyObject`, and `shellQuote` delegate to
  `contents/ui/Guards.js`, so the prototype-pollution guard and the shell-quoting
  rule exist once and are covered by `tests/tst_guards.qml` rather than by
  searching each copy for the right fragment. A `.pragma library` module is
  reachable from every surface, config pages included, so reach for one before
  copying a body. `scripts/test_security_regressions.sh` fails if a guard
  implementation appears outside `Guards.js`.
- All user-facing text must go through `i18n` or `i18np`.
- Test with `make check` first. Use `plasmawindowed` or `plasmoidviewer` for
  quick widget checks when available. After extracting delegates or components,
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

Run this before handing off any repository change:

```sh
make check
```

`make check` is the required gate. It runs `qmllint`, `qmltestrunner`,
ShellCheck, and the `kpackagetool6` AppStream metadata check. If
`kpackagetool6` is unavailable, the command reports a skip. Do not report that
metadata check as passed.

Use the other QML tools for these narrower jobs:

- Use `qmlformat` on new files or in a dedicated formatting change, then inspect
  its diff. The existing tree has no formatter baseline, so do not reformat an
  existing file as part of unrelated work.
- Keep `qmlls` in the editor. Do not commit a machine-specific `.qmlls.ini` or
  treat language-server diagnostics as a replacement for `make check`.
- Run `qmlprofiler` only after reproducing a performance problem. Keep profiler
  traces out of the repository.
- Use `plasmoidviewer -a "$PWD" -l topedge -f horizontal` for a panel smoke
  test when `plasma-sdk` is installed. Use `plasmawindowed app.codexbar` for an
  installed-widget smoke test.

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

## CLI assumptions

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

## Release flow

1. Keep `main` green with `make check`.
2. Generate the distributable with `make package`.
3. Publish `dist/codexbar-plasma.plasmoid` in a GitHub Release.
4. Use the full fork workspace only for upstream sync work; this standalone repo is the public user-facing project.
