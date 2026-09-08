# Agent instructions

This repository contains only the standalone KDE Plasma widget for CodexBar.
Here, plugin, widget, plasmoid, and applet all mean the Plasma frontend.

## Project boundaries

- Work on this applet. The official macOS app and local upstream/fork workspaces
  are read-only references unless the user explicitly requests a separate
  upstream change. A macOS parity request authorizes comparison and Plasma
  implementation only. Keep Swift, Xcode, and the full upstream tree out of here.
- Provider logic, authentication, config parsing, quota fetching, and JSON
  contracts belong in the upstream `codexbar` CLI. Use supported CLI commands;
  never hand-edit its config JSON or add provider scraping/auth logic to QML.
- Confirm data and actions in the released official Linux CLI before designing
  UI around them. If the contract is missing, record the requirement in a
  [repository issue](https://github.com/Lucenx9/codexbar-plasma/issues) and stop
  that part at the frontend boundary.
- Prefer generic CLI-described fields and actions. Unknown providers and optional
  fields must degrade gracefully; static provider metadata is a tested fallback.

## Read for the task

Read these references before changing the corresponding area. Follow their
relevant sections; ordinary links here are on-demand reading, not bulk imports.

- For QML, JavaScript, configuration, tests, packaging, or runtime diagnosis, read
  [Development](docs/development.md). Then read the owning implementation, config
  schema, and nearest regression check before editing.
- For feature behavior, provider changes, CLI contracts, or macOS parity, read
  the relevant [usage guide](docs/usage.md), contract/evidence links in the
  [documentation index](docs/README.md), and related GitHub issues. Issues own
  work status; maintained guides own behavior and decisions. [TODO.md](TODO.md)
  is only an entry point, never a second status inventory.
- For documentation changes, read the [documentation index](docs/README.md).
  For agent instructions, also read
  [instruction maintenance](docs/development.md#maintaining-agent-instructions).
- For catalog or user-facing text changes, read
  [Translations](docs/translations.md).
- For PR creation or updates, complete every section of the
  [PR template](.github/pull_request_template.md).

## Sources of truth

1. The Plasma implementation, config schema, tests, and documented decisions
   define current support.
2. Released official Linux CLI contracts define what the frontend may consume.
3. The official macOS app supplies product and UX references only. Recreate
   useful Plasma-native behavior, without translating its implementation.
4. Local forks and experimental branches are comparison material unless the
   user selects them as the target.

Pin every comparison to an exact version, tag, or commit. Keep installed CLI,
upstream main, and fork observations separate. Classify each parity gap as
**Plasma-native and implementable now**, **blocked on an official CLI contract**,
or **macOS-only/non-goal**. Screenshots and Swift models are not CLI contracts.

## Working style

- Evaluation questions authorize inspection and an answer. Change requests
  authorize the smallest complete in-scope implementation. Preserve existing
  behavior and safeguards unless the request or evidence supports changing them.
- Complete independent work when one part is blocked; state the exact blocker.
  Proceed with reversible, low-cost steps already within the user's request.
- Ask before destructive actions, meaningful cost, or external publication
  unless already authorized. Ask when ambiguity would materially change the
  result. Existing authorization applies throughout the task.
- Preserve unrelated user changes. Inspect `git status` and `git diff` before
  editing and before handoff; stage only the intended changes.
- Avoid unrelated cleanup, dependencies, abstractions, and formatting churn.
  Delegate only substantial independent work, with disjoint ownership, while
  continuing useful work in the main task.
- Keep repository prose in technical English. Answer in the user's language
  with concise progress and a short result: changes, verification, blockers or
  required action. Say when no action is needed.

## Architecture and data safety

- Owning QML pages manage DataSource/CLI processes, nonce/timer lifecycles,
  configuration writes, prompts, URL opening, notifications, and other effects.
  Put non-trivial pure parsing, normalization, presentation, planning, and
  transition logic in focused JS modules in the same change.
- Pure modules accept explicit inputs and return bounded data, semantic results,
  intents, or opaque next state. They must not read root properties, localize
  text, or perform effects. QML adapts inputs, commits state, localizes, and acts.
- Test pure public interfaces with direct adversarial QtTests. Use surface
  assertions for QML wiring, effect ownership, and lifecycle ordering. Extract
  only when the interface hides real complexity; avoid pass-through controllers
  and callback modules that mirror root state.
- Treat CLI stdout/stderr, descriptors, cached payloads, labels, URLs, and status
  text as untrusted. Validate shapes, types, bounds, command allowlists, and URL
  schemes. Preserve healthy provider data when an optional enrichment fails.
- Never expose raw keys, cookies, bearer tokens, auth headers, or unredacted
  diagnostics in logs, UI, fixtures, or persisted data. Use supported CLI stdin
  secret flows and redacted results.
- Secrets must never appear in command lines, even as shell positional arguments
  piped to stdin: `/proc/<pid>/cmdline` exposes them. Only
  `promptDescriptorSecret` may carry a secret; it reads the value inside the
  script. Generic field writers must reject `kind === "secret"`.
- Keep timeout, disconnect, retry, nonce, and stale-result handling beside the
  process lifecycle. Late results must not replace a newer refresh or account
  selection. Share guard implementations through `contents/ui/Guards.js`.
- Preserve persisted config keys and the standard Plasma package shape. Keep
  the Plasma 6 root as `PlasmoidItem` and all user-facing text in `i18n`/`i18np`.

## Verification and delivery

- Deliver changes through a PR by default. A direct push is an exception only
  when explicitly requested for the current task; it does not authorize bypassing
  branch protections. Follow [delivery and CI](docs/development.md#delivery-and-ci)
  after every push and authorized merge. Own the checks through their final
  result, fix in-scope failures, and report the verified commit and any blocker.
- Use Conventional Commits for every PR title: `type(scope): description`, with
  scope optional. Choose the type for the final change, such as `fix`, `feat`,
  `docs`, or `ci`; follow [the title rules](docs/development.md#delivery-and-ci).
- Own consistency across the repository, without user reminders. For every
  change, follow [repository maintenance](docs/development.md#repository-maintenance)
  before editing and before delivery. A task is complete only when affected
  code, configuration, tests, tooling, translations, metadata, documentation,
  and work tracking agree with the delivered behavior.
- Run the narrowest relevant check while iterating, then `make check` before
  handing off any repository change. It includes QML lint/QtTests, ShellCheck,
  Python/static checks, and AppStream metadata validation.
- Report exact failures, skips, and unavailable tools. If `kpackagetool6` is
  absent, its metadata check is skipped, not passed. Use the actual check output
  to assess coverage; consult `.github/workflows/ci.yml` for the CI environment.
- For packaging changes, also run `make package`. For component/delegate
  extraction, install or upgrade the local plasmoid and inspect recent Plasma
  logs as described in [Development](docs/development.md#runtime-verification).
  Packaging and runtime checks count only when actually performed.
- Use `codexbar` as the default executable. Discover an absolute path with
  `command -v codexbar`; do not assume an installation-specific location.
- Publish only when authorized. A release requires green checks and
  `make package`; its artifact is `dist/codexbar-plasma.plasmoid`.

## Documentation hygiene

- For user-visible changes, update `CHANGELOG.md` under `Unreleased` in the same
  change. For release preparation or release tooling changes, follow
  [changelog and releases](docs/development.md#changelog-and-releases).
- Own documentation and issue maintenance as part of every change, without a
  user reminder. Before editing, identify affected guides and existing issues.
  Before handoff, reconcile them with the final diff and completion criteria.
  Follow [the maintenance workflow](docs/development.md#documentation-and-work-tracking),
  including for authorized direct commits to main. State documentation impact
  in the PR or commit body; use closing keywords only for fully completed work.
- When changing installation, updates, or requirements, update [README.md](README.md)
  in the same change. For user-visible behavior or defaults, update the affected
  [usage guide](docs/usage.md) sections and any affected README summaries or
  screenshots. For build, test, or contributor workflow changes, update
  [Development](docs/development.md). Check documented commands and examples
  against the implementation before marking the change complete.
- Keep maintained guides, CLI contracts, and lasting decisions in `docs/`.
  List every document and image in [docs/README.md](docs/README.md) with its purpose.
- Put temporary screenshots, logs, probe output, plans, and agent review reports
  in ignored `dist/review/` or the OS temp directory. Summarize results in the PR;
  promote only reusable findings into maintained documentation.
- Remove obsolete documents and update links when replacing them. Preserve
  pinned CLI evidence and unresolved decisions. Completed review histories and
  captures remain recoverable through Git history. Keep README images synthetic.
- Keep this file within the repository's 16 KiB budget. Add rules after a real bug
  or repeated friction; move task-specific detail behind a conditional pointer.
  The documentation tests in `make check` enforce that budget, the docs index,
  retired artifact directories, and local Markdown link targets.
