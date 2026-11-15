# Agent instructions

This repository contains only the standalone KDE Plasma frontend for CodexBar.
Widget, applet, plasmoid, and plugin refer to that frontend here.

## Project boundaries

- Work on the applet. Official macOS and local upstream/fork trees are read-only
  references unless the user explicitly requests an upstream change. Parity work
  authorizes comparison and Plasma implementation. Keep Swift and Xcode out.
- Provider logic, authentication, config parsing, fetching, and JSON contracts
  belong in the upstream `codexbar` CLI. Use supported commands; never hand-edit
  CLI config JSON or add provider scraping/auth logic to QML.
- Verify required fields/actions in a released official Linux CLI. Record missing
  contracts in [TODO.md](TODO.md), with the verified version, and stop that part
  at the frontend boundary. Complete independent in-scope work.
- Prefer generic CLI-described fields/actions. Unknown providers and optional
  fields degrade gracefully; static metadata is a tested fallback.

## Read for the task

Read only the relevant sections and their implementation links before editing.

| Task | Required reference |
| --- | --- |
| Panel, popup, settings UI, or design review | [Design](DESIGN.md) |
| QML, JavaScript, config, tests, packaging, or runtime diagnosis | [Development](docs/development.md), then the owning implementation, config schema, and nearest regression check |
| Feature behavior, providers, CLI contracts, or parity | Relevant [usage](docs/usage.md) section, [contract/evidence index](docs/README.md), and [TODO](TODO.md) |
| New official release or parity review | [Release maintenance](docs/development.md#upstream-release-maintenance) and [parity-review skill](.claude/skills/parity-review/SKILL.md) |
| Documentation | [Documentation index](docs/README.md) and [maintenance](docs/development.md#documentation-and-work-tracking) |
| Agent instructions or skills | Also [instruction maintenance](docs/development.md#maintaining-agent-instructions) |
| Catalogs or user-facing strings | [Translations](docs/translations.md) |
| PR creation or update | Every section of the [PR template](.github/pull_request_template.md) |

For a new release, update TODO without a reminder, covering every release since
its last review. Track useful Linux/Plasma equivalents and official CLI blockers.

## Sources of truth

1. Plasma code, config schema, tests, and documented decisions define support.
2. Released official Linux CLI contracts define consumable data and actions.
3. Official macOS supplies product/UX references for Plasma-native equivalents.
4. Local forks and experimental branches are comparisons unless selected as target.

Pin comparisons to exact versions, tags, or commits. Separate installed CLI,
upstream main, and fork observations. Classify parity gaps as implementable in
Plasma now, blocked on an official CLI contract, or macOS-only/non-goal. Swift
models and screenshots do not prove CLI output. TODO owns remaining parity work;
linked issues supply discussion, not a second inventory.

Before relying on external APIs, framework/tool behavior, security guidance, or
uncertain technical assumptions, check current official/primary web sources.
Apply them to supported versions within the source order above. Cite material
decisions and state verification limits.

## Working style

- Evaluation requests authorize inspection and an answer. Change requests
  authorize the smallest complete implementation, preserving existing safeguards.
- Proceed with reversible in-scope work. Ask before destructive actions,
  meaningful cost, or external publication unless already authorized, and when
  ambiguity materially changes the result. Session authorization persists.
- Inspect `git status` and `git diff` before editing and handoff. Preserve
  unrelated changes; stage only intended files. Avoid unrelated cleanup,
  dependencies, abstractions, and formatting churn.
- Delegate substantial independent work with disjoint ownership while continuing
  useful work yourself.
- Keep repository prose in technical English. Answer in the user's language
  with changes, verification, and exact blockers or required action. Say when
  no action is needed.

## Architecture and data safety

Before code changes, follow the [implementation reference](docs/implementation.md),
including its ownership, behavioral contracts, and QML conventions.

- QML owners manage processes, timers/nonces, config writes, prompts, URLs,
  notifications, and effects. Focused pure JS modules accept explicit inputs
  and return bounded data, intents, or next state. They read no root properties,
  localize no text, and perform no effects. Extract only real complexity.
- Validate untrusted CLI output, descriptors, caches, labels, URLs, and status
  text: shapes, types, bounds, command allowlists, and URL schemes. Optional
  enrichment failures must preserve healthy provider data.
- Never expose secrets in logs, UI, fixtures, persisted data, or command lines,
  including shell positional arguments piped to stdin. Use supported CLI stdin
  secret flows and redacted results. Only `promptDescriptorSecret` may carry a
  secret, read inside its script; generic writers reject `kind === "secret"`.
  AI Insights keys stay in Python and Secret Service, never QML.
- Keep timeout, disconnect, retry, nonce, and stale-result guards beside process
  lifecycles. Late results cannot replace newer refresh/account state. Share
  guards through `contents/ui/Guards.js`.
- Preserve persisted config keys, the standard package shape, `PlasmoidItem`
  root, and `i18n`/`i18np` for user-facing text. Test pure public behavior with
  adversarial QtTests; use surface assertions for wiring and effect ownership.

## Verification and delivery

Follow [repository maintenance](docs/development.md#repository-maintenance) before
editing and delivery, and [delivery and CI](docs/development.md#delivery-and-ci)
after every push or authorized merge. Required outcomes:

- Affected code, config, tests, tooling, translations, metadata, guides, and TODO
  agree. Run the narrow check while iterating, then `make check`. Report exact
  failures, skips, and unavailable tools as coverage limits.
- Code changes pass the documented CodeScene MCP gates before committing;
  unsupported files and unavailable analysis are reported separately.
- Packaging changes also pass `make package`. Component/delegate extraction
  requires local installation and recent Plasma-log inspection per
  [runtime verification](docs/runtime-verification.md#runtime-verification).
- Deliver through a PR on a `codex/` branch with a Conventional Commit title.
  Direct push requires explicit authorization for this task and cannot bypass
  branch protection. Follow checks to their final result for the delivered SHA.
  Merge and release publication require authorization.
- Discover the CLI with `command -v codexbar`. A release requires green checks,
  `make package`, and the [release skill](.claude/skills/release/SKILL.md);
  its artifact is `dist/codexbar-plasma.plasmoid`.

## Documentation hygiene

[Documentation maintenance](docs/development.md#documentation-and-work-tracking)
owns guide/TODO updates, changelog rules, index coverage, and evidence retention.
Apply it in the same change without a reminder. Keep one owning document per
fact; summarize and link elsewhere. Update existing sections before adding files.
Temporary captures, logs, probes, plans, and review reports go in ignored
`dist/review/` or the OS temp directory. Keep README images synthetic.

Keep this file within the enforced 16 KiB budget. Add rules only after an observed
failure or repeated friction; move task-specific procedure behind a conditional
pointer. Keep `CLAUDE.md` as the single `@AGENTS.md` import.
