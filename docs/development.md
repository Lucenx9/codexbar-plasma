# Development

Read the relevant sections before changing QML, JavaScript, configuration,
tests, packaging, or runtime behavior. [AGENTS.md](../AGENTS.md) defines project
boundaries and required checks. The [usage guide](usage.md) describes supported
behavior; [TODO.md](../TODO.md) owns remaining Linux/Plasma parity work. All code
paths below are relative to the repository root.

## Work from a checkout

Install `make`, Python 3, GNU gettext, and the Plasma runtime requirements in
[the README](../README.md#requirements). The check suite also needs Qt 6 QML
lint/test tools, ShellCheck, `xmllint`, and `jq`. The pinned
[CI workflow](../.github/workflows/ci.yml) lists the complete test environment;
package names vary by distribution.

```sh
git clone https://github.com/Lucenx9/codexbar-plasma.git
cd codexbar-plasma
make check
make install
```

`make install` builds and installs the curated `.plasmoid` archive. Tests and
agent instructions are not installed. Reload Plasma after installing changed
QML, using the [runtime instructions](#runtime-verification).
For an existing checkout, `./install.sh` builds, installs, and restarts Plasma.

From this checkout, `make update` installs the latest immutable GitHub release
using the bundled helper. It does not pull Git changes or install local edits.
For those, use `make install` or `./install.sh`. Release-package users can use
[the widget's update settings](../README.md#update) without a checkout.

## Ownership and implementation

- `contents/ui/main.qml` owns applet processes, refresh/account coordination,
  selected state, configuration updates, and external effects. Its adapters
  supply the panel and popup.
- `contents/ui/components/CompactRepresentation.qml` renders the panel;
  `FullRepresentation.qml` in the same directory renders the popup. Components
  are presentation-only and receive normalized data plus an explicit parent API
  such as `applet` or `configPage`.
- `contents/ui/configProviders.qml` owns provider setup processes, prompts,
  configuration writes, and effects. Its pure protocol and command-planning
  modules live in `contents/ui/config/`.
- Pure applet modules live in `contents/ui/*.js`; their public interfaces have
  direct tests in `tests/tst_*.qml`. Configuration is declared in
  `contents/config/main.xml` and bound through `cfg_*` in config pages and
  `Plasmoid.configuration` at runtime.

Before changing behavior, identify its owning QML page, config entry, CLI input,
external effects, and cheapest behavioral test. Read the existing implementation
and tests. Preserve compatibility and unexpected behavior until evidence or the
request shows it should change.

When multiple pages consume one CLI envelope, share the bounded record/envelope
contract and keep page-specific projections separate. Avoid both duplicate raw
parsing and one lossy result that erases different UI semantics. For a new CLI
field, update normalization, rendering, relevant checks, and affected guides.
Reconcile the linked issue against its acceptance criteria.

Use names that identify provider, source, account, window, or unit when ambiguous.
`build*`, `format*`, `provider*Url`, `*Rows`, and `*Text` helpers stay pure;
`refresh*`, `load*`, `parse*`, `select*`, `set*`, and `process*` may mutate state.
Put non-obvious lifecycle state in names such as `connected*`, `pending*`,
`*Memo`, `*Revision`, and `*Initialized`, and update it beside its effect.
Comments explain a workaround or contract, rather than restating assignments.

For repeated JavaScript in delegates, timers, or callbacks, use named helpers.
For repeated or bulky UI blocks, use small presentation-only components.
Extraction must hide complexity, not merely reduce line count.

## Behavioral contracts to preserve

- Quota thresholds come from `QuotaThresholds.js`, shared by notifications and
  usage-bar markers. `limitResetArmThreshold` detects limit resets separately;
  it is not a warning threshold. `main.qml` resets opaque notification state
  through `NotificationPlanner.js`; its internal `NotificationMemo.js` preserves
  provider status baselines. Settings changes must not announce an ongoing
  incident again or swallow an incident arriving during refresh. Keep these
  decisions pure and covered by `tests/tst_notification_planner.qml` and
  `tests/tst_notification_memo.qml`. Predictive warnings prime silently and fire
  on a new projected-exhaustion transition.
- Sessions normalize display fields only. Discard `cwd`, `transcriptPath`, IDs,
  and PIDs; never render, open, or follow them. Remote/SSH host focus is a
  macOS-only non-goal.
- `PanelRules.js` evaluates the displayed quota without effects. Direct missing
  quotas stay omitted; `runOut` depends on `paceWarningActive`. Panel visibility,
  order, and metric settings preserve the minute clock and icon fallback and
  must not fetch data or change notification state.
- Privacy projects display records without changing cached snapshots or account
  command keys. Preserve config keys and pending defaults across all settings
  pages. `PopupRefreshPolicy.js` handles freshness and failed-attempt cooldown,
  including in-flight/queued work; opening the popup must not start cost scans.
  See the [settings decision record](research/2026-09-08-settings-experience.md).
- Validate `credits.codexCreditLimit` as finite non-negative amounts, clamped
  percentages, and bounded reset metadata. Its denominator belongs only to that
  nested record, never to a plain `usage.credits` balance.

## QML conventions

- Use `PlasmaComponents` for panel/popup controls and Kirigami/Qt Quick Controls
  in settings. Use `ContainmentItem` only for containment/panel/desktop code,
  not this applet's root.
- Keep `metadata.json`, `contents/ui`, `contents/config/main.xml`, and
  `contents/config/config.qml` in the standard package layout.
- Use checkboxes for booleans, spinboxes/sliders for numbers, text fields for
  short strings, and a combobox for more than three choices.
- Give visual children a size through layouts, anchors, implicit sizes, or
  explicit compact dimensions. Items otherwise default to 0x0.
- Use layout minimum/preferred sizes, implicit dimensions, and `Kirigami.Units`
  instead of panel-size magic numbers. Use anchors/layouts rather than bindings
  to sibling geometry.
- Prefer declarative bindings. Move repeated or expensive calculations into
  helpers or cached properties. Avoid heavy JavaScript in delegates, compact
  rendering, timers, and DataSource callbacks; profile before optimizing.
- Keep delegates stable. Add clipping, shaders, or nested layouts only for a
  visible need.
- External Repeater/view delegate components must declare
  `required property var modelData` inside the component. An alias assignment
  from the parent does not establish the delegate's scope; `qmllint` may miss
  the resulting runtime error.
- Use `qmlformat` for new files or a dedicated formatting change, then inspect
  the diff. Existing files have no formatter baseline, so preserve formatting
  during unrelated work.
- Keep `qmlls` in the editor. Machine-specific `.qmlls.ini` files stay out of Git;
  language-server diagnostics do not replace `make check`.

For translation/catalog changes, follow [Translations](translations.md).
The checks validate catalog coverage and arguments, then exercise the QML
session, pace, and count adapters against all compiled catalogs. Localized smoke
scenarios also verify these adapters through Plasma's actual translation domain.
When changing provider identity, check keys, CLI aliases, title, color,
docs/dashboard/login URLs, icon assets, and `scripts/test_provider_icons.sh`.
Repeat this comparison during official CLI release audits. The pinned 0.56.2
audit found the same 69 IDs as 0.55.0; the OpenRouter fallback already uses
`https://openrouter.ai/activity`. Treat the catalog as fallback presentation data
and use the [dated evidence](research/2026-09-01-macos-parity-0.56.2.md), not an
assumed current upstream count.

## Regression checks

Use direct adversarial QtTests for pure public behavior. Assert QML wiring,
effect ownership, and lifecycle ordering statically. Use runtime checks where
static checks cannot establish the behavior. Avoid assertions on private helper
names or body decomposition when public behavior is already covered.

`scripts/lib/qml_surfaces.py` defines QML/JS file groups for the Makefile,
hardening checks, and translation extraction. Existing globs cover new files;
add a glob only for a new directory. `scripts/test_qml_hardening.sh` rejects
uncovered QML/JS files.

- Use `require_in_surface` / `reject_in_surface` in shell, or `Surface.require`,
  `Surface.function_body`, and `Surface.id_block` in Python, for rules applying
  to the whole applet or config page. Moving code between files then preserves
  the check. Use `*_in_file` only for actual per-file contracts, such as safe
  icon fallback in each delegate.
- Use `require_definition_where_used` or
  `Surface.require_definition_where_used` for shared unqualified helpers.
  A declaration in another QML/JS file does not satisfy the caller's scope.
  These helpers also check the page root when components call `applet.foo(...)`.
  A plain search for `function foo(` anywhere in a group can miss broken callers.
- Local bindings for `hasOwnKey`, `isUnsafeObjectKey`, `copyObject`, and
  `shellQuote` delegate to `contents/ui/Guards.js`. Share the implementation
  through that `.pragma library` module, including in config pages.
  `tests/tst_guards.qml` covers behavior; `scripts/test_security_regressions.sh`
  rejects implementations duplicated elsewhere.

Run the relevant check during iteration, then the required `make check` gate.
Read its output for tool failures and skips. CI uses the pinned Plasma image in
[the workflow](../.github/workflows/ci.yml), with explicit import warnings and
QtTests configured to reject skips. A local machine missing QML modules may
provide less coverage; report what actually ran.

`make check` disables unqualified-name warnings because Plasma injects helpers
such as `i18n()` as context properties. It validates AppStream metadata when
`kpackagetool6` is available and reports a skip otherwise. On older local Plasma
packages without QML type metadata, import/type coverage may be partial; CI
supplies the metadata. To require CI's strict checks locally:

```sh
QML_TEST_REQUIRE_NO_SKIPS=1 make check QMLLINT_FLAGS='--import warning --unqualified disable'
```

CI also runs smoke scenarios under Xvfb and retains screenshots and logs as
workflow artifacts. Release publication requires both check and smoke jobs.
The `check` job always runs `make check` and `make package`. A lightweight
`scope` job compares the tested PR merge tree with its base parent, or the full
before/after range for a push to `main`. Only changes limited to the editorial
Markdown allowlist in `scripts/ci_scope.py` omit the `smoke-runtime` job.
Images, translations, code, tests, packaging, CI files, unknown paths, missing
history, and empty diffs keep graphical coverage. Tags always run it.

The required `smoke` job reports either successful graphical tests or an explicit
documentation-only omission in its summary. It fails if scope detection fails,
the runtime result is missing, or required smoke tests fail or are cancelled.
The workflow itself has no path filter, so required checks still report a result.
This follows [GitHub's required-check guidance](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks).

## Popup smoke tests

Run the popup smoke test from a graphical Plasma 6 session:

```sh
make smoke
```

This requires Python 3, GNU gettext, `plasmawindowed`, `dbus-run-session`, and
the Plasma, Kirigami, and KDE desktop control QML modules. README captures also
require the Breeze Dark color scheme. Localized scenarios use the UTF-8 locales
in the [translation guide](translations.md); CI generates them during setup.
The runner opens a temporary applet for each scenario, captures it, and closes
it automatically. List the available scenarios with:

```sh
python3 scripts/smoke_popup.py --help
```

Select one scenario or choose a new artifact directory:

```sh
make smoke SMOKE_ARGS='--scenario long-text'
python3 scripts/smoke_popup.py --scenario normal --output /tmp/codexbar-preview
python3 scripts/smoke_popup.py --scenario panel-minimal --renderer opengl
python3 scripts/smoke_popup.py --scenario readme-overview --renderer opengl --output /tmp/codexbar-readme
```

Use `--renderer opengl` on a graphical session with OpenGL for accurate provider
icon colors. The default software renderer checks layout and behavior, but does
not render Kirigami's icon color masking. Qt documents the software renderer's
[effect limitations](https://doc.qt.io/qt-6/qtquick-visualcanvas-adaptations-software.html).

The command prints the artifact directory, defaulting to `dist/smoke/run-*`.
Each scenario produces a PNG and a process log; `results.json` records pass or
failure. Existing output directories are never overwritten. The timeout is
30 seconds per scenario and can be changed with `--timeout 60`.

The runner copies the current applet into temporary XDG directories under a
separate applet ID and uses a private D-Bus session. It sets a synthetic CLI
path and disables updates and notifications before QML starts. It does not
install a package, use real provider accounts, change the installed widget's
settings, or restart Plasma. Temporary files and preview processes are removed
on completion, timeout, or interruption.

The capture component selects the real popup views and waits for the expected
state before using Qt's
[`grabToImage`](https://doc.qt.io/qt-6/qml-qtquick-item.html#grabToImage-method).
QML errors, missing captures, early exits, and timeouts fail the command.
Screenshots still need visual review: this is not a pixel-comparison test and
does not exercise panel placement, key-event dispatch, or the real CLI.
Synthetic payloads cover a subset of the CLI 0.56.2 contract; fixture dates
are relative to run time. Typography uses Noto Sans and Breeze icons.

`make check` covers the runner's portable isolation and failure-handling tests
and lints the capture QML.
`make smoke` additionally requires the graphical environment and reports a
failure rather than silently skipping when that environment is unavailable.

## Runtime verification

After extracting components/delegates, install or upgrade the widget and inspect
recent logs for `ReferenceError`, `TypeError`, and `SyntaxError`:

```sh
./install.sh
journalctl --user -u plasma-plasmashell.service --since '2 minutes ago' --no-pager \
  | rg -n 'app\.codexbar|CodexBar|ReferenceError|TypeError|SyntaxError|file://.*/app.codexbar'
```

Ignore unrelated widget logs unless they mention `app.codexbar`.
For a panel smoke check when plasma-sdk is installed:

```sh
plasmoidviewer -a "$PWD" -l topedge -f horizontal
```

Use `plasmawindowed app.codexbar.plasma` for an installed-widget check.
Restarting/replacing `plasmashell` is a final runtime check, not the edit loop.
Use `qmlprofiler` only after reproducing a performance problem, and keep traces
in ignored `dist/review/` or the OS temp directory.

## CLI probes and packaging

The widget expects a working `codexbar`. Probe the selected official version
when investigating a contract; keep raw account output out of logs and commits.

```sh
codexbar usage --format json --json-only
codexbar usage --provider codex --status --format json --json-only
codexbar usage --provider codex --all-accounts --format json --json-only
codexbar cost --format json --json-only
codexbar config providers --format json --json-only
codexbar sessions --json-v2
```

For packaging changes, run `make package` after `make check`.
Packaging needs Python 3 and GNU gettext. It compiles `po/*.po` to
`contents/locale/<language>/LC_MESSAGES/plasma_applet_app.codexbar.plasma.mo`
and includes the catalogs in the archive. Generated `.mo` files stay out of Git.
For string extraction and catalog updates, follow [Translations](translations.md).

The `PACKAGE_FILES` list in the Makefile defines the archive contents, including
README screenshots. Publishing the resulting `dist/codexbar-plasma.plasmoid`
in a GitHub Release requires user authorization.
If a KDE Store channel is introduced, use its KNewStuff/Discover update path for
that channel. WidgetKit, Sparkle, Keychain/Full Disk Access UI, and macOS app
implementation code remain outside this standalone Plasma repository.

## Delivery and CI

Use a `codex/` branch and a PR for repository changes. Direct pushes require an
explicit exception for the current task. A request to push directly does not
authorize weakening protection rules or bypassing failed checks.

Every PR title follows [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):
`type(scope): description`, with an optional scope and an
optional `!` before the colon for breaking changes. Allowed types are `feat`,
`fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, and
`revert`. Use a short description of the final change, for example
`fix(accounts): release stale requests` or `docs: clarify installation`.
Keep the title current when scope changes, and retain that format for the squash
commit. The `pr-title` check validates new and edited titles; title edits run
this small workflow without rerunning the full widget suite.

The default branch rules require a PR and successful GitHub Actions `check`,
`smoke`, and `pr-title` jobs, tested against the current base branch. The rules
also prevent
deletion and force pushes. Copilot review remains enabled; no additional human
approval count is required. The maintainer can merge their own PR once its
checks pass. Inspect the effective rules with:

```sh
gh api repos/Lucenx9/codexbar-plasma/rules/branches/main
```

The agent owns delivery through these completion criteria:

1. After each push, identify the exact commit and its GitHub runs. Follow the
   required checks and other applicable CI runs until they finish. Queued or
   running checks are pending, not a completed delivery. Results for an older
   commit do not validate a newer push.
2. Inspect failed jobs and fix failures caused by the change. Rerun a job only
   when evidence supports a transient infrastructure failure; repeated failures
   need diagnosis. Report an external blocker with the run link and failing job.
   Treat unexpected skips, cancelled runs, and missing required checks as
   unresolved. The release job is intentionally skipped on non-tag runs.
   A documentation-only `smoke-runtime` omission is expected only when the
   required `smoke` job confirms it. Superseded PR runs may be cancelled by
   concurrency; follow the replacement run for the latest commit. Main pushes
   and release runs are not cancelled when a newer run starts.
3. For a PR-only request, finish when the current PR checks pass and the PR body
   records their results. Report it as ready for review, not merged. Merge only
   when authorized; check the current head and base again before merging.
4. After an authorized merge or direct push, follow the runs for the resulting
   `main` commit too. Reconcile related issues and report the commit, final CI
   outcome, and any remaining blocker. Fix a post-merge failure through a PR
   unless the user explicitly authorizes another delivery route.

Keep progress updates brief while waiting. If the session is interrupted, leave
the exact commit, run links, and remaining checks in the handoff so work can
resume without treating pending CI as success. A recurring automation is needed
only when the user asks for monitoring beyond the active task.

## Changelog and releases

[CHANGELOG.md](../CHANGELOG.md) is the source of notable widget changes and
future GitHub release notes. It follows
[Keep a Changelog](https://keepachangelog.com/en/2.0.0/). History starts at 0.2.35,
using its published notes; earlier releases remain linked on GitHub.

For every user-visible change, the agent adds or revises an `Unreleased` entry
in the same commit. Describe the observable result and any upgrade action.
Group entries under Added, Changed, Deprecated, Removed, Fixed, or Security;
include only categories with entries. Group related commits into one useful
entry. Internal refactors, tests, and routine instruction edits need no entry
unless they affect users or contributors' supported workflows; explain that
decision in the PR or direct commit body. TODO owns future Linux parity work.

Before an authorized release:

1. Compare the diff since the last release with `Unreleased`, including direct
   commits to main. Correct omissions and remove claims that have not shipped.
2. Move the entries into `## X.Y.Z - YYYY-MM-DD`, leaving an empty
   `## Unreleased` first. Use the release date, keep versions newest first, and
   set `KPlugin.Version` in `metadata.json` to that same version. Add a full-diff
   link with absolute GitHub URLs so it works in both the package and release.
3. Run `make check`, `make package`, and
   `python3 scripts/changelog.py --tag vX.Y.Z`. Review the extracted notes before
   committing and pushing the matching tag. Tag publication needs authorization.

`make check` validates headings, categories, dates, ordering, and the newest
version against metadata. The tag workflow also requires an empty `Unreleased`
section and an exact tag match. It extracts the version's body into ignored
`dist/release-notes.md` and publishes it through the release action's
[`body_path`](https://github.com/softprops/action-gh-release#external-release-notes).
The archive includes the changelog. Keep published sections historical; prepare
new changes under `Unreleased` and correct factual errors explicitly. Existing
GitHub releases are not rewritten when this workflow is introduced.

These checks validate structure and release consistency. The agent must still
compare the final change with the entries to catch missing or misleading notes.

## Repository maintenance

The agent owns repository consistency in every task. Include dependent updates
in the same change, without waiting for the user to name each file.

Before editing, trace the affected behavior through its callers, configuration,
tests and fixtures, scripts, CI workflows, packaging and metadata, translations,
documentation and examples, TODO entries, and related issues. Inspect the
relevant files;
filename searches alone do not establish whether a dependency is affected.

Before delivery, review the final diff and search for old names, paths, commands,
defaults, and claims affected by the change. Update each dependent reference or
confirm that it remains valid. Regenerate affected tracked outputs through their
existing generators. Remove obsolete references when replacing an interface;
preserve compatibility requirements and pinned historical evidence.

Fix stale material discovered during the task when the correction is clear,
safe, and within scope. If it needs a separate decision, external contract, or
substantial unrelated work, record the evidence and remaining work in TODO for
Linux parity, or an existing/new issue for other work under the publication rules
in AGENTS.md. Report the exact blocker when issue publication is not authorized.
Complete independent work and make any unresolved inconsistency explicit at
handoff.

Completion requires consistent affected files, the applicable checks below, and
accurate TODO and related issue status after delivery. Passing tests alone does
not establish consistency. In the PR verification section or direct commit body, summarize the
dependent updates and any unresolved gaps. Version and dependency changes need
compatibility evidence; bump versions only as part of their actual update or
release workflow. A date change alone is not maintenance.

## Documentation and work tracking

[TODO.md](../TODO.md) is the current list of useful Linux/Plasma gaps relative
to the official macOS app. Keep implementable work separate from official CLI
blockers and explicitly unverified candidates. Guides describe supported
behavior. Issues can hold bug reports and discussion; a parity issue is a
reference, not a second checklist to maintain. Existing issue links preserve
context, and their migration alone does not complete the feature.

For every repository change, including authorized direct commits:

1. Read the relevant guides, TODO entries, pinned evidence, and linked discussion.
   Compare the requested behavior with current code and its tests.
2. Reconcile the final diff with those references. Update README for setup and
   requirements, the usage guide for behavior/defaults, and this guide for
   contributor workflows. Keep contracts in focused guides and maintain the
   docs index. Remove completed TODO entries in the implementing PR; retain
   remaining scope when delivery is partial. A documentation-only gap review
   does not count as implementation.
3. Run `make check` and applicable example/package checks. Inspect documented
   commands against their implementation. Review prose for accuracy as well as
   broken paths. Record documentation and TODO impact in the PR or direct
   commit body, including why no update is needed when they are unaffected.
4. Reconcile related issues after authorized delivery. Use `Closes #123` only
   when all acceptance criteria are met. For partial work use `Refs #123`.
   Keep implementation status in TODO; do not create an issue for every gap.

Keep proposal status visible inside each contract document, with exact verified
versions. Dated audits retain their findings; a successor names the evidence it
replaces. Current guides describe delivered behavior. During widget release
preparation, verify setup, requirements, defaults, and changed features against
those guides and TODO. Updating a date alone is not maintenance.

This follows [Google's documentation practices](https://google.github.io/styleguide/docguide/best_practices.html)
and [docs as code](https://www.writethedocs.org/guide/docs-as-code/).
[GitHub's closing-keyword rules](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue)
apply when a change reaches the default branch.

## Upstream release maintenance

On every new stable official CodexBar release, the agent updates TODO without
waiting for a user reminder. Apply the same process during an explicit parity
review. The daily agent monitor detects releases; these repository instructions
define the review. Instructions alone do not schedule execution.

1. Read TODO from the current default branch and check for an existing parity
   update PR. Read the official [release history](https://github.com/steipete/CodexBar/releases)
   through the newest stable release, including every release since the last
   reviewed version. Record exact tags/commits and dates. Ignore prereleases
   unless the user requests them. If nothing changed and no verification is
   pending, finish without a commit or notification.
2. Compare Linux-relevant changes with current Plasma code, schema, tests, and
   existing guides. Include fixes and changed contracts, not only new features.
   Recheck carried-forward blockers against official Linux CLI changes. Retain
   unresolved older gaps even when release notes do not mention them.
3. Classify each gap as implementable with the official Linux CLI, blocked on a
   named official contract, or excluded as macOS-only/not useful on Plasma.
   Keep only the first two in the actionable inventory. An unverified candidate
   stays in a separate verification section until there is enough evidence.
   For a blocker, state the missing field/action and the version last verified.
   A Swift view model or source declaration alone does not prove emitted Linux
   output. Keep auth, config parsing, provider fetching, and upstream edits out
   of the frontend task.
4. Probe changed contracts with a checksum-verified official Linux release asset
   in an isolated temporary account and cache, using synthetic inputs. Keep
   host credentials and provider files inaccessible, pass no credential
   environment, and do not replace the installed CLI. If an asset, tool, or
   account-free reproduction is unavailable, record the exact limitation. Keep
   the release reviewed separate from the last verified CLI contract, and never
   advance a full-audit baseline on the strength of a partial probe.
5. Update TODO in the same PR: add new gaps with evidence and a concrete done
   condition, remove already implemented ones, and revise resolved blockers.
   Keep TODO short enough to scan; link substantial reusable evidence in a
   dated research note and index it. Leave completed behavior in the guides and
   Git history. Preserve historical evidence, and update maintained claims that
   the new evidence supersedes.
6. Review the diff, run required checks, and open or update one Conventional
   Commit PR for the review. Follow its latest CI through completion under
   [delivery and CI](#delivery-and-ci). A scheduled review authorizes the TODO
   and documentation PR, not feature implementation or automatic merge.
   Reuse an existing update PR and report only a new release, meaningful result,
   failure, or required user action. Retry unresolved verification on later runs
   without opening duplicate PRs or repeating unchanged notifications.

A missed scheduled run must catch up from TODO's recorded version. A failed
fetch leaves that version unchanged. Report incomplete release coverage
explicitly and keep the last fully reviewed release as the next run's starting
point. For a partially verified contract, retain its earlier verified version.
The monitor runs through the local Codex scheduler; it needs this machine and
Codex available. Check the saved automation when changing its cadence or scope.

## Maintaining agent instructions

Keep permanent rules in AGENTS.md and Linux parity status in TODO. Add a rule for
an observed failure or repeated friction. Put task-specific details in the
relevant section of this guide and add a root pointer stating when to read it.
Maintain links and the [documentation index](README.md) in the same change.

The repository enforces a 16 KiB AGENTS.md budget, with a working target below
200 lines. These are local maintenance choices. Codex's default budget is
32 KiB across discovered project instructions, so leave room for other files.
See [Codex discovery](https://learn.chatgpt.com/docs/agent-configuration/agents-md).

OpenAI describes using a short instruction file as an index into maintained
docs. This motivates our conditional pointers, rather than a duplicate feature
inventory. See [OpenAI's engineering experience](https://openai.com/index/harness-engineering/).

Keep `CLAUDE.md` as the single `@AGENTS.md` import. Imports load their full
contents; adding imports for every guide would restore the context cost.
Anthropic recommends concise instructions, generally under 200 lines, rather
than imposing that as a loading limit. See [Claude memory](https://code.claude.com/docs/en/memory#write-effective-instructions).

Keep `.github/copilot-instructions.md` limited to review guidance and consistent
with AGENTS.md. GitHub assigns that file higher precedence than AGENTS.md;
repository prose cannot reverse product precedence. See
[GitHub instruction precedence](https://docs.github.com/en/copilot/concepts/prompting/response-customization#precedence-of-custom-instructions).

## QML references

- [KDE package setup](https://develop.kde.org/docs/plasma/widget/setup/)
- [Widget properties](https://develop.kde.org/docs/plasma/widget/properties/)
- [Configuration](https://develop.kde.org/docs/plasma/widget/configuration/)
- [Testing](https://develop.kde.org/docs/plasma/widget/testing/)
- [KF6 porting](https://develop.kde.org/docs/plasma/widget/porting_kf6/)
- [Plasma QML API](https://develop.kde.org/docs/plasma/widget/plasma-qml-api/)
- [Qt QML practices](https://doc.qt.io/qt-6/qtquick-bestpractices.html)
- [Qt Quick performance](https://doc.qt.io/qt-6/qtquick-performance.html)
