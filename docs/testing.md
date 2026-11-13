# Regression checks and CI

Use this guide to choose regression checks, maintain the CI image, and inspect CI
reports. [Development](development.md) owns checkout setup and delivery. Graphical
scenarios are documented in [Smoke tests](smoke-tests.md).

## Regression checks

Use direct adversarial QtTests for pure public behavior. Assert QML wiring,
effect ownership, and lifecycle ordering statically. Use runtime checks where
static checks cannot establish the behavior. Avoid assertions on private helper
names or body decomposition when public behavior is already covered.

Provider alias, CLI argument, documentation, dashboard, login, status and
brand-color fallback contracts run through the public `ProviderIdentity`
functions in `tests/tst_provider_metadata.qml`. Keep these expected outputs independent of
the production tables; do not parse their source layout in parity checks.
Required colors must expose three finite numeric channels in `0..1`; QML theme
ownership, delegation and fallback checks remain in `test_theme_boundaries.sh`.

Before adding a static assertion, and before keeping an existing one, break the
behavior it describes and confirm a QtTest or Python test goes red. A fragment
whose behavior is already covered that way is removed, not duplicated: it fails
on a rename that changes nothing and passes on an edit that changes behavior.

`scripts/lib/qml_surfaces.py` defines QML/JS file groups for the Makefile,
hardening checks, and translation extraction. Existing globs cover new files;
add a glob only for a new directory. `scripts/test_qml_hardening.sh` rejects
uncovered QML/JS files.

- Use `require_in_surface` / `reject_in_surface` in shell, or `Surface.require`,
  `Surface.function_body`, and `Surface.id_block` in Python, for rules applying
  to the whole applet or config page. Moving code between files then preserves
  the check. Use `*_in_file` only for actual per-file contracts, such as safe
  icon fallback in each delegate.
  Shell assertions fail on unknown or empty groups and source discovery/read
  errors, including unreadable wildcard directories and negative assertions.
  Missing optional directories still match no files. `tests/test_qml_surfaces.py`
  covers the loader and actual shell helpers.
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

`test_cost_sections.py` checks provider disclosure focus-frame bounds and
keyboard/pointer activation with the KDE desktop style at narrow and normal
widths in LTR/RTL layouts. `tst_disclosure_button.qml` separately preserves the
settings-only alignment with neighbouring check boxes.

`tst_popup_tab_strip.qml` checks manual keyboard activation and mirrored arrow
navigation, including wrapping and Home/End. Resize and label-growth cases keep
an unselected focused tab visible; focus outside navigation stays untouched.
Hidden and disabled tabs remain outside the native focus chain.

`tst_visual_layout.qml` also destroys a container holding a dynamic provider
detail section and fails on JavaScript warnings during teardown. The progress
track must retain its theme color without reading a section that has already
been destroyed.

Run the relevant check during iteration, then the required `make check` gate.
Read its output for tool failures and skips. CI uses the pinned Plasma image in
[the workflow](../.github/workflows/ci.yml), with explicit import warnings and
QtTests configured to reject skips. A local machine missing QML modules may
provide less coverage; report what actually ran.

Every check is a separate `make` target, so iteration can run one of them
directly: `make check-security-regressions`, `make check-qml-logic`, or
`make check-python-test_usage_controller` for a single Python module.
`make -n check` lists the whole set. `make check` runs them concurrently across
the available cores, because most Python modules start their own
`qmltestrunner` and a sequential suite leaves the machine idle. `--output-sync`
keeps each target's output together, so a failure is still attributable to one
check.
Use `make check JOBS=2` where memory or cores are constrained, and read the
final result rather than the first lines: concurrent targets keep running after
another one fails.

`make check-workflows` runs [actionlint](https://github.com/rhysd/actionlint)
over `.github/workflows`, and `make check-python-lint` runs `pyflakes` over
`scripts` and `tests` for undefined names, unused imports, and invalid Python
escape sequences. Neither
reformats anything, so neither introduces style churn. `qmlformat` stays out of
the suite, but no longer because the checks pin formatting: the membership
assertions in `tests/test_ui_*.py` compare through `code_contains`, which
ignores anonymous-function spacing, statement-terminating semicolons, and line
breaks. Readability blocks adoption instead, as recorded in
[TODO.md](../TODO.md): with wrapping disabled, its default, `qmlformat` 6.11.2
joins wrapped expressions into lines as long as 2570 characters, and any
`MaxColumnWidth` splits comparisons across lines. `test_feature_parity.sh` and
`test_process_lifecycle.sh` also still match literally, so a setting that
rewraps differently breaks them. `qmlformat` recurses without bound on a
regular expression literal wider than `MaxColumnWidth`, so build long patterns
from strings with `new RegExp(...)` or match plain substrings instead.

The desktop-style QtTest run also checks provider reset countdowns, inline-reset
fit boundaries, and pace/reset wrapping. It covers mirrored layouts, fractional
font sizes, and enlarged text so fractional label widths cannot silently elide
a fitting countdown.

The `check-runtime` and `smoke-runtime` jobs pin a prebuilt Linux/amd64
Ubuntu 24.04/Neon toolchain by digest. [The image recipe](../ci/Dockerfile)
copies only the signed Neon repository configuration, archive key, CA bundle
and package priorities from the pinned official image into the pinned Ubuntu base, then
installs the explicit Qt/Plasma modules, tools, Mesa renderer and locales.
It does not carry the full Neon desktop. Archives use HTTPS; APT authenticates
indexes and package
hashes; failed refreshes stop image builds. PR jobs neither refresh APT nor
install dependencies. `/usr/local/share/ci-packages.txt` records installed
versions. `sha256sum --check --strict /usr/local/share/ci-inputs.sha256` verifies the
recipe and installer hashes against the checkout, so changing an input requires a new
validated image and matching pins in the same PR.

To rebuild locally from the repository root (add `--no-cache` when refreshing
packages without changing the recipe):

```sh
docker build --platform linux/amd64 -f ci/Dockerfile -t codexbar-plasma-ci:candidate .
docker run --rm --init --cpus 4 -v "$PWD:/workspace" -w /workspace \
  -e QMLLINT_FLAGS='--import warning --unqualified disable' \
  -e QML_TEST_REQUIRE_NO_SKIPS=1 codexbar-plasma-ci:candidate \
  bash -c 'sha256sum --check --strict /usr/local/share/ci-inputs.sha256 && make check JOBS=4 && make package'
docker run --rm --init --cpus 4 -v "$PWD:/workspace" -w /workspace \
  codexbar-plasma-ci:candidate bash -c \
  "xvfb-run -a -s '-screen 0 1280x1024x24' make smoke SMOKE_ARGS='--output dist/review/ci-image/smoke' && xvfb-run -a -s '-screen 0 1280x1024x24' python3 scripts/panel_matrix.py --output dist/review/ci-image/panel-matrix"
```

Run [CI image](../.github/workflows/ci-image.yml) manually on `main`, selecting
the trusted recipe branch or commit in its `revision` input, to build and
validate the full suite, packaging and graphics, then publish a candidate to
`ghcr.io/lucenx9/codexbar-plasma-ci-runtime`. It publishes the Linux/amd64 platform manifest with `docker push --platform
linux/amd64`, excluding the multi-platform index and attestation manifests.
This keeps the source-labelled runtime image as the initial package publication.
It uses unique build tags and reports the
registry digest in its summary; it never automatically changes consumer pins.
Once the workflow exists on `main`, a recipe PR can publish its candidate with:

```sh
gh workflow run ci-image.yml --ref main -f revision=codex/update-ci-image
```

[Dependabot](../.github/dependabot.yml) opens a monthly PR when the digest of
the pinned Ubuntu 24.04 base moves, with the seven-day version-update cooldown
described in [delivery and CI](development.md#delivery-and-ci); it ignores newer Ubuntu releases. It
excludes the Neon stage, which is pinned by digest without a tag. Re-resolve
the `user` tag by hand during every rebuild: KDE's registry prunes superseded
digests, so an old Neon pin stops resolving and the image build fails. Such a PR changes a recipe input, so its runtime jobs fail the
input-hash check by design. Publish a candidate from its branch, then pin the
reported digest in both runtime jobs of the same PR.

Create the initial package through the repository image workflow with
`GITHUB_TOKEN` so Actions access is assigned to this repository. The source
label records its repository association. A CLI publication alone did not grant
the runtime token access during bootstrap; do not assume that label presence
proves token access. Verify both GitHub runtime jobs after publication. If a
package was created outside Actions, grant this repository access under
[Manage Actions access](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility#ensuring-workflow-access-to-your-package)
in its package settings. Runtime jobs
pull with the ephemeral `GITHUB_TOKEN` and only `contents: read` and
`packages: read`; they need no PAT secret. Fork workflows retain read
permissions under [GitHub's token permission rules](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions).
[Repository-linked package access](https://docs.github.com/en/packages/learn-github-packages/about-permissions-for-github-packages#visibility-and-access-permissions-for-packages)
allows that token to download the image. The
package can remain private; making it public later enables anonymous local
pulls but is not required for CI. Publication is a maintenance operation
requiring authorization, separate from a widget release. Update both runtime job pins in
a PR and verify their GitHub results before merging. Rebuild when a recipe,
installer, base pin, or required toolchain changes; periodically refresh the
image for security fixes. Ordinary weekly CI validates the pinned environment
without publishing anything. Image builds still pull the large official Neon
source stage, but only rebuilds need it.

The lightweight lint job and the image builder use
[`scripts/install-actionlint.sh`](../scripts/install-actionlint.sh) to download
the official release binary and verify its pinned SHA-256 before installation.
Update the version and checksum together from the release's `checksums.txt`.
An unverified or unreachable archive fails installation. The prebuilt runtime
image carries this verified binary, so PR runtime jobs need no download.

`tests/test_account_refresh.py` runs production account-selection functions
against the real usage controller and an isolated CLI in Qt's event loop. It
counts refresh starts for cached/uncached accounts in single-provider and
aggregate modes. Its CLI fixture reproduces the Codex token-account rejection
and covers selected usage, repeat refresh, missing accounts, clearing the
selection, exact spacing, and late replies when account choices share a command.
`tests/test_usage_cache_account_selection.py` runs the production quota-cache
adapters and `selectAccount` against a stand-in configuration and restarts
them without the memory-only selection, covering sibling persistence after
accepted and failed refreshes, a return to the default account, and a late restore.
`tests/test_account_parse_containment.py` checks account
snapshot presentation and selection freshness.

`tests/test_provider_config_watcher.py` instantiates the watcher with real
checksum processes and a substituted transport for synchronous cached replies.
It covers source replacement, activation, malformed/retired replies, reentrant
observers, and explicit/XDG config paths with quoted filenames.
`tests/tst_provider_config_watch.qml` directly tests first/changed/unchanged
observations and input bounds. Surface checks preserve the minute poll and
cache-restore/invalidation ordering in the applet.

Panel preview spend checks also run under German and Italian locales; the
settings smoke compares the preview with the live monetary formatter.

`tests/tst_monthly_allowance.qml` covers monthly percentage allocation, invalid
inputs, local calendar boundaries, DST and privacy. Its snapshot-to-allowance
cases reject impossible dates, overflowing times and missing/invalid timezones
before and after privacy projection, while retaining valid leap days and offsets.
Both paths reuse the ISO-8601 validator in `SubscriptionDates.js` rather than
accepting `Date.parse` calendar rollover. The `monthly-allowance`
smoke scenario checks the production popup reading.

`tests/tst_provider_cost_presentation.qml` covers monetary panel budgets, malformed amounts, balance
precedence, percentage bounds, provider fallbacks, reset counts, metadata bounds,
and healthy quotas with invalid optional costs. `tests/test_provider_cost_presentation.py`
executes `ProviderCostDetails` directly against the compiled English fallback
and all five translation catalogs. The monthly-credit view test also calls that
component and renders the shared usage delegate. `tst_cost_text.qml`,
`tst_cost_presentation.qml` and `tst_provider_order.qml` cover labels, totals,
chart metrics, range filtering, scan coverage and provider ordering through
production interfaces, without rebuilding root presentation functions in a
fixture. Surface checks retain root input forwarding and keep plural-aware
localization in QML. The separate configuration-write fixture still exercises
the root setters with an isolated configuration object; it does not test
presentation logic.

`tests/test_quota_window_calendar.py` runs the quota-week calculation in UTC
and America/Santiago with a process timeout. Sparse history across a nonexistent
local midnight must terminate without discarding newer valid weeks or presenting
missing days as complete totals.

`tests/tst_overview_selection.qml` directly covers Overview eligibility,
placeholder suppression, the identity detail fallback chain, automatic and
stored selections, normalized detail/dashboard survivors with optional errors,
empty or malformed supplemental data, unlabeled empty charts versus preserved
section/chart headings and units, automatic-selection eligibility, aliased roster IDs,
unusable stored values, and unusable roster entries alongside the settings-page
toggles. `tests/tst_provider_auto_select.qml` covers malformed percentages,
missing data, provider cost competition, fractional usage, severity tie breaks, and
error-only providers. Surface checks pin both modules as pure.

`tests/tst_reset_presentation.qml` directly covers timestamp precedence, malformed
metadata, text bounds, minute/hour/day rounding, calendar and daylight-saving
boundaries, and compact reset labels. `tests/test_reset_presentation.py` exercises
the root adapters and production `UsageWindowText` component with all compiled
catalogs in UTC, Rome, and Los Angeles.
It checks local absolute dates in each catalog's word order and reactive clock,
display-mode, and privacy
bindings. `tests/tst_usage_window_text.qml` covers input preservation, pace-part
ordering, reset precedence and compatibility fallbacks. The localized CLI-label
adapter tests exercise ETA boundaries in all six catalogs; direct
`PacePresentation` QtTests cover the semantic duration results. The quota-reset
and provider-metadata integration tests keep their
production parsing path; surface checks enforce QML clock/localization ownership.
`tests/tst_time_labels.qml` checks Italian names, a 12-hour regional clock, and a
translated part order with explicit locales, and a surface check rejects literal
`Qt.formatDateTime` patterns in the applet.

`tests/test_notification_dispatcher.py` checks concurrent and repeated messages,
argument boundaries with synthetic `notify-send` executables, missing executables,
default-action activation through stdout, and the pre-action fallback without
capability, plus failure recovery through the real Plasma DataSource. A substituted transport
exercises synchronous and retired replies, reentrant completion, destruction,
and the production 10-second timer. Notifications have
process-bound coverage in `tests/test_cli_process_bounds.py` for ordinary and
clickable notifications and widget destruction through the real executable
engine. Both CLI and notification cases keep a TERM-resistant child while the
parent either exits on TERM or ignores it. The command interface also has
adversarial QtTests in `tests/tst_notification_command.qml`. Surface checks keep notification
policy and privacy in the applet and enforce registration and retirement ordering.
`tests/tst_update_notification_state.qml` covers trusted URLs, immutable action
maps, unsafe sources and replay. `tests/tst_update_notifications_controller.qml`
executes the production policy owner with a recording dispatcher, checking
privacy, independent switches, persistence order and source retirement. Existing
widget/CLI wiring tests exercise the same owner, and
`tests/test_update_notifications_controller.py` checks mixed update activations
through the real dispatcher with synthetic `notify-send` and privacy.
Missing optional KDE modules are reported as local skips and rejected by `QML_TEST_REQUIRE_NO_SKIPS=1`.

`tests/test_usage_controller.py` exercises the production executable source,
provider discovery/cache, bounded fallback concurrency, exact account/source
arguments, batched setting changes, retired replies, empty rosters, automatic
refresh, and recovery after the production 120-second deadlines. The three
command kinds time out concurrently; the test adds about 145 seconds to
`make check`. Its outer process timeout is 300 seconds to leave room for loaded
CI runners while keeping the production deadlines unchanged.
Missing optional KDE modules are reported as local skips and
rejected by `QML_TEST_REQUIRE_NO_SKIPS=1`. `tests/tst_usage_response.qml` covers
malformed siblings and identities, response bounds, measured zeros, scoped
provider identity, rejection of foreign-provider records, deduplication, and
redaction directly at the pure interface.
Surface checks protect process ownership and registration/retirement ordering.

`tests/test_accounts_controller.py` instantiates the production controller with
isolated CLI processes and real Plasma DataSource/timers. It covers concurrent
providers, duplicate suppression, quoted arguments, retained lists, successful
empty results, account availability and notice dismissal, context changes, reset, original
measurement timestamps, and recovery after the production 60-second timeout.
It adds about 90 seconds to `make check`; optional KDE modules may skip locally, while
`QML_TEST_REQUIRE_NO_SKIPS=1` rejects skips in CI. Direct tests in
`tests/tst_account_response.qml` cover malformed records, bounded replies,
redacted failures, and identity deduplication. `tests/tst_provider_snapshot.qml`
covers shared normalization independently of QML presentation.

`tests/test_provider_write_errors.py` exercises the production enable/disable
and API-key result handlers with empty and structured CLI error messages. It
checks that actions unlock, no successful write or revision is recorded, and a
generic failure remains visible.

`tests/test_provider_config_watcher.py` delivers a cached reply synchronously
during the production watcher connection, matching Plasma's shared-source
behavior. It checks that the new poll stays connected and retired replies are
ignored. `tests/test_secret_prompt_lifecycle.py` executes the generated secret
prompt commands with synthetic dialog and CLI processes and shortened timeouts.
Each phase gets three seconds, with two-second delays for successful late
replies: the combined flow exceeds one phase's deadline while allowing process
startup and scheduling time. Child shutdown is checked within two seconds of
the parent exiting, so asynchronous signal delivery cannot cause a false leak
failure. Cancellation, TERM/KILL escalation and stdin-only secret delivery
remain required. The production ledger deadline must cover both phases and
the disconnect margin.

`tests/test_sessions_controller.py` instantiates the production Sessions module
with temporary synthetic CLI executables and real Plasma DataSource/timers.
It checks visible refresh scheduling, interval changes, hidden and queued work,
duplicate requests, command isolation, retained snapshots, successful empty
responses, and the production 60-second timeout followed by recovery. Failed
processes with valid empty or populated JSON also preserve the last snapshot,
as do successful processes whose nonempty lists contain only unreadable records.
Failed scans record attempt completion separately from successful snapshot completion;
the full retry cooldown starts at the reply or timeout, even after a long scan.
Manual retry bypasses that cooldown, and a command change clears it. The test
adds about 80 seconds to `make check`, without changing private timers/state or
using provider credentials. Missing optional KDE modules are reported as a local
skip and rejected by `QML_TEST_REQUIRE_NO_SKIPS=1`. Surface checks preserve input
wiring, process ownership, and request registration/retirement ordering.
`tests/tst_session_response.qml` directly checks bounded, redacted response
outcomes and distinguishes failed output from a confirmed empty snapshot;
`tests/tst_session_refresh_policy.qml` checks exact scheduling boundaries.

`tests/tst_ai_insights.qml` and `tests/tst_ai_insights_snapshot.qml` cover the
pure AI Insights policy and snapshot allowlist. `tests/test_ai_insights.py` runs
the helper against a local HTTP server and fake `secret-tool` and `kdialog`
executables, and compiles the catalogs to run `main.qml`'s language adapter
through to the `--language` argument. Adversarial HTTP fixtures cover trickled
success/error bodies, disconnects, removed models, oversized/deeply nested JSON,
and malformed destinations. The server records only requests carrying the
helper's `User-Agent`, because desktop tools may probe any new local port.
A supervised production-helper fixture verifies
that killing its timeout owner also stops its wallet child.
`tests/test_ai_insights_controller.py`
runs the production controller through Plasma's executable DataSource with a
recording helper, including actual helper cancellation, endpoint/privacy/provider
changes in flight, the generation-phase deadline and its recovery, and GNU
timeout's native Qt crash result.
`tests/test_ai_insights_settings.py`
copies the settings page's helper-process functions into a QtTest with stubbed
processes to check
reply handling when the Ollama address or model changes and helper retirement
when disabled, wallet-status deadline handling, a second harness that
re-arms the Clear button when a new insight is stored after a clear, and a
third that creates the page's model handlers with a real editable combo, so
opening settings keeps the stored model and a popup pick still commits. None
of them contacts a real AI service, wallet, or key.
The smoke runner stages `scripts/smoke/fixture_ai_insights.py` as the package's
`scripts/ai-insights.py` for every scenario, so previews can never reach a real
service; the `ai-insights*` and `settings-ai-insights*` scenarios exercise the
card, language mismatch, failure, single-provider placement, and settings page.
`tst_ai_insights_view.qml` exercises the compact card, full answer, explicit
generation, keyboard activation, Back/Escape, and saved-answer context. The
successful insight smoke scenarios capture both `*-overview.png` and the
analysis page, and verify nonzero scroll restoration, tab changes, disabling
the feature, and navigation without generation.

`tests/test_widget_update_controller.py` instantiates the production updater
module and runs temporary executable fixtures through Plasma's real DataSource.
It checks overlapping requests, setting changes during a check, captured install
mode, invalid results, and cancellation at the production 60-second timeout
followed by a successful new request. Static checks preserve the stale-source
guard for any callback delivered after retirement. This adds about one minute to `make check`. Its only
substitute is the script URL; it neither contacts GitHub nor installs a release.
Missing optional KDE QML modules produce an explicit local test skip;
`QML_TEST_REQUIRE_NO_SKIPS=1` rejects that skip in CI. A runner failure remains
a failure even if its output also contains a skip.
The module's interface is settings, `checkNow()`, `runNow(install)`, read-only
runtime status, and result signals. The script URL is a local executable
dependency, not a widget setting. Internal request state and timers remain
inside the module.

`tests/tst_visual_layout.qml` checks panel meter centering with spare width in
both panel styles before and after resizing. It also clicks the real copy
button, checks the emitted text, and observes the confirmation icon and tooltip
through copied-state changes. Unicode preservation is covered through the public
normalizer and usage-detail interfaces.

The panel mirror check waits for a rendered frame before and after direction
changes. Fixture cleanup also waits for the KDE style transition duration before
QtTest destroys the temporary page, preserving warning failures during teardown.

`tests/tst_panel_settings_geometry.qml` records control positions after rendered
frames while the real Panel page initializes. It covers narrow/wide windows,
larger text, right-to-left layout, and scrolling through expanded options.
It requests redraws during observation, requires multiple rendered frames, and
compares both coordinates. Direction changes also check that the opposite
padding is restored.
`tests/tst_popup_notifications_geometry.qml` applies the same frame-based
opening check to the real Popup and Notifications pages, including the provider
roster arriving after the Popup page opens and mirrored padding restoration on
both pages. It also requires the viewport padding and, for the static
Notifications content, the content height to stay constant across frames.
It samples the Notifications color preview before and after pending threshold
edits, including coincident thresholds and the 1%/100% limits in both layout
directions. The preview uses sharp color boundaries, rather than a blended
gradient that would imply intermediate warning states.
The QML runner repeats both geometry files with the KDE desktop controls style
because its scrollbar reserves viewport width, unlike the default overlay style.
It also checks checkbox label text after the active style processes mnemonics,
so escaped ampersands and markup remain literal under both Qt and KDE styles.
Every runner invocation applies the strict no-skips check;
`tests/test_qml_runner.py` verifies skip and failure propagation across styles.

`tests/tst_settings_pages.qml` builds the real General and Notifications pages
and asserts the behavior the static ownership checks cannot reach: the global
defaults action leaves every resettable key at its schema default while its
confirmation stays pending until `saveConfig()`, the editable interval and
threshold fields keep their stored value when the typed text holds no number,
and the critical threshold follows the warning floor. Both pages must therefore
guard their applied-configuration reads, as Notifications already did, so a page
built outside a plasmoid resolves those bindings instead of raising a TypeError
that `failOnWarning` reports as a failure.

The same QtTest checks Diagnostics report collection/copy, explicit partial
results after timeouts, command-path reset and stale-source rejection, alongside
the accessible name of its command-path field. `SupportReport.js` accepts
explicit facts and produces a bounded English technical Markdown report; QML
owns module probes, localization, processes, clipboard and feedback. The
report omits resolved paths, retains only the selected/PATH CLI location
comparison, and omits whole error lines containing forward slashes or path-like
backslashes. This covers absolute, relative and tilde-qualified paths, Windows
drive roots and UNC shares, custom layouts and paths containing spaces
without guessing path boundaries. Local probe facts and the Diagnostics version
display retain their paths. Lines with prior credential-redaction markers are
omitted too, since that filtering may have consumed a path separator. JSON slash
escapes are normalized before filtering. Bounded JSON inspection decodes string
values and keys, including nested encoded payloads, to distinguish paths from
ordinary message escapes. Reports preserve those message escapes verbatim.
Inspection exceeding 512 values omits the line as `[redacted]`. Unstructured
backslashes, including a quoted directory's final separator and Unicode
backslash escapes, remain subject to the conservative path filter.
Common executable startup failures retain
only a fixed reason, never the personal path or library filename.
`SafeText.js` redacts secret-key and secret-access-key assignments alongside
the existing credential names, including environment-variable and SDK spellings.
It also matches keys whose quotes are backslash-escaped by one or more JSON
encodings, and removes the rest of the line after an escaped quoted value
instead of parsing where that value ends.
`tests/tst_safe_text.qml` checks the message and diagnostic adapters;
`tests/tst_support_report.qml` checks that the same values cannot reach shared
text or the Markdown report, and exercises the path separation above.
The offline `collect-support-report.py` helper reuses CLI version/ownership probes. Its only
CLI commands are `--version` and `config providers --format json --json-only`
(verified on official Linux CLI 0.67.0 and 0.73.0); the provider list discards
every field except enabled provider IDs.
`tests/test_support_report.py` and `tests/tst_support_report.qml` cover trust
boundaries, missing tools, privacy and fixed probes. No `diagnose`, raw config,
provider fetching, hardware/hostname fields or network requests enter collection.
The `settings-diagnostics*` smoke scenarios run that page inside an applet and
assert that it displays the package metadata version and associates the command
path's form label with the editable field. They also check that the command-path
row fits the visible page and stays within its 24-grid-unit bound. The narrow
scenario uses 420 pixels with 13-point text; this reproduces clipped controls
and explanations when the nested row cannot shrink with its parent form.

`make check` disables unqualified-name warnings because Plasma injects helpers
such as `i18n()` as context properties. It validates AppStream metadata when
`kpackagetool6` is available and reports a skip otherwise. On older local Plasma
packages without QML type metadata, import/type coverage may be partial; CI
supplies the metadata. To require CI's strict checks locally:

```sh
QML_TEST_REQUIRE_NO_SKIPS=1 make check QMLLINT_FLAGS='--import warning --unqualified disable'
```

CI runs smoke scenarios under Xvfb and retains screenshots and logs as
workflow artifacts. Popup `results.json` also records seconds per scenario,
including failures, for identifying expensive coverage before changing tests.
The independent `lint` job reports static failures before the Plasma image is
ready: ShellCheck, actionlint, Python lint, changelog, documentation and scope
policy tests, XML/JSON validation, and `make package`. The full suite retains
these checks too. The release publishing job uses the Ubuntu runner's build
tools without downloading Plasma; publication still requires both `check`
and `smoke` to succeed.

CI runs on every PR, push to `main`, and version tag. It also runs the full
suite and graphical smoke tests each Monday at 07:23 UTC and on manual runs:

```sh
gh workflow run ci.yml --ref main
```

The lightweight `scope` job compares the tested PR merge tree with its base
parent, or the full before/after range for a push to `main`. Only changes limited
to the editorial Markdown allowlist in `scripts/ci_scope.py` omit both Plasma
jobs (`check-runtime` and `smoke-runtime`). Fast checks and packaging still run.
Every `make check` target whose script reads an allowlisted Markdown file, such
as the README setup and registry-size contracts, also runs in the fast `lint`
job; `tests/test_ci_scope.py` fails when one is missing there.
Images, translations, code, tests, packaging, CI files, unknown paths, missing
history, and empty diffs keep full coverage. Tags, scheduled runs, and manual
runs always use the complete toolchain and graphics.

Required `check` and `smoke` jobs report either successful runtime tests or an
explicit editorial-only omission. `check` also requires successful fast checks.
Scope failures, missing results, cancelled required tests, and unexpected skips
fail their gates. Neither required check name nor branch protection changes.
The workflow has no path filter, so required checks always report a result,
following [GitHub's required-check guidance](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks).
Keep PR supersession cancellation, parallel `make check`, and separate runtime
jobs: splitting into more runners before measuring test bottlenecks would
repeat image pulls. Compare container startup, test durations and total workflow
wall time on the same coverage; concurrent job durations are not additive.

`tests/tst_interactive_chart.qml` checks that first pointer and keyboard
inspection preserve the plot position and chart height. It also checks that
leaving the plot or clearing its points preserves the reserved readout space,
and reads painted pixels after a theme text-color change with a fixed accent.
`tests/test_provider_tab_refresh.py` executes the production provider-tab
Repeater to verify that changed usage preserves its focused delegate and updates
its meter and accessible name. Reordered, replaced, and removed providers must
activate the current provider without binding or lifecycle warnings.

### Cost response performance

`make benchmark-cost` runs `tests/bench_cost_response.qml` directly through
QtTest, outside the parallel `make check` suite. CI runs it after that suite
in `check-runtime`. The fixture's `bench_` filename prevents directory-based
QtTest discovery from running it under concurrent correctness-test load.
Override `QMLTESTRUNNER` if Qt 6 is installed elsewhere.

The public `CostResponse.response` call is measured after one warm-up, with
nine samples averaging 20, 2 and 1 calls for the three fixtures. JSON fixture
construction and serialization happen before timing. Each fixture checks its
normalized result and logs the raw timings, median and budget. Median limits
are 100 ms for 30 days with four models per day, 1,000 ms for 365 days with
16 models per day, and 2,000 ms for All history with 2,048 days and 16 models
per day. These are coarse regression ceilings with scheduling headroom,
calibrated on Qt 6.8.2 on an Intel N95; they are not interaction-latency goals.
The benchmark excludes CLI I/O and rendering, so it cannot establish popup
frame latency or replace profiling a reproduced desktop stall.

Run on an otherwise idle machine for comparisons. Compare the same Qt build,
fixture, sample count and warm-up conditions; preserve all samples and record
kept and reverted experiments in the PR. A budget failure needs fresh baseline
measurements and investigation, not an automatic threshold increase.
Direct normalizer tests also reject model reads for discarded dates and
amount-only rows, giving a deterministic guard independent of CPU speed.
Cost-response tests count model reads across both All-history average paths
to ensure only the period summary inspects models outside the chart window.
`tst_cost_model_identity.qml` also covers shared currency validation in daily,
period and token-ranked models, including malformed/redacted values and
independent currencies across calls.

### Sticky CI report

After a pull-request CI run completes, [ci-report.yml](../.github/workflows/ci-report.yml)
publishes one English comment as `codexbar-review-bot[bot]`. Later runs update
the comment containing `<!-- codexbar-ci-report -->`; the publisher checks the
author as well as the marker. An unchanged report makes no write request.
This report supplements the existing Sonnet code review. Required `check`,
`smoke`, and `pr-title` checks still decide merge readiness.

`scripts/ci_report.py` owns event handling and publication. Its focused
`scripts/lib/ci_report_data.py`, `ci_report_github.py`, and `ci_report_markdown.py`
modules own validation/collection, credential-separated HTTP transport, and
comment rendering respectively. They keep the same trust boundaries in local
probes and Actions.

The comment shows the CI job conclusions, recorded popup successes/failures,
the panel-matrix record count, and links to the run and graphical artifacts.
Editorial-only runs explicitly explain their omitted runtime checks. A failed
or cancelled run still reports its job conclusions. Missing or rejected
measurements never become passing test results. Panel records can be partial
when capture fails; they are not a separate visual approval.

`scripts/ci_report.py collect` first runs in the unprivileged scope job, including
after coverage-selection failures. It records the original event's tested base
branch and SHA even for editorial-only runs. The smoke job then replaces that
record with runtime measurements, including after test failures. Both upload
`dist/ci-results.json` as the `ci-results` artifact for 30 days. Its ZIP contains
`ci-results.json` at the root. Schema version 2 records the run ID/attempt,
PR head SHA, tested base branch/SHA, tested merge SHA,
reported runtime-image and smoke-fixture fingerprints, popup scenario outcomes
and seconds, and panel record count. Screenshots and full logs keep their
existing seven-day retention. Missing or invalid artifacts still allow reporting
historical job status, with an explicit warning that the tested PR target could
not be verified. A record for a different current target is rejected.

The publisher first looks for measurements from a successful push CI run at
the exact PR base commit, then a recent successful base-branch run. It labels
the selected baseline in the comment. Timing deltas and new popup failures
appear only when both reports have the same schema, image/fixture fingerprints,
and scenario IDs. The fixture fingerprint includes the smoke harness, Makefile,
and CI workflow, so renderer, theme, language, or invocation changes suppress
incompatible comparisons. Scenario seconds include setup and process startup. They are
diagnostic smoke timings, not a Plasmoid update-latency benchmark or a regression
threshold. QtTest/Python totals, RAM usage, and code coverage are not collected
by this report. Check the job logs for individual test suites, and inspect
screenshots for visual quality.

The publishing workflow uses `workflow_run` after CI, with read-only Actions,
contents, and PR permissions for `GITHUB_TOKEN`. It checks out the repository's
default branch explicitly, runs the trusted publisher tests, and then creates a
repository-scoped GitHub App token with only `pull-requests: write` for comments.
It never checks out or executes the PR in this privileged job. ZIP input must
contain exactly one bounded JSON file; paths, symlinks, unknown fields,
unexpected types, duplicate scenario IDs, and invalid values are rejected.
Artifact download requests never forward the GitHub token to signed storage.
Measurement and tested-target data still come from the PR's CI and are not an
independent audit. Oversized measurement details are omitted from the comment
while job conclusions and artifact links remain available.

Before writing, the publisher verifies the CI workflow ID, completed PR event,
run attempt, head SHA, head repository/branch, associated open PR, and recorded
tested target. It uses the immutable target record from the CI artifact because
GitHub's PR fields on historical runs can change as the PR changes. Target changes
during preparation are checked again immediately before writing.
After a partial rerun it uses the latest job execution for each check. A retained
measurement must match the latest smoke job's attempt, which the report labels
when older than the overall run. Invalid JSON/compression and expired downloads
omit measurements while preserving job conclusions; unavailable baseline listings
or downloads do not abort publication.

A read-only source resolver derives a concurrency key from the head repository
ID and branch. Automatic events and manual dispatches for the same source share
that key, so comment creation cannot race. Different PR sources do not replace
each other's pending publishers. Each request reconciles to the latest completed
CI run for the source's current head, so a late stale request cannot discard a
newer pending report. A newer in-progress run is awaited instead. Runs from other
branches or forks at the same SHA cannot supersede this source. These
checks support PRs from forks without giving the fork CI write credentials.

Maintainer setup uses the existing GitHub App installation for this repository:

- Repository variable `CODEXBAR_REVIEW_APP_CLIENT_ID`: the App's client ID.
- Repository Actions secret `CODEXBAR_REVIEW_APP_PRIVATE_KEY`: its PEM private key.
- App repository permission **Pull requests: Read and write**. Install the App
  only on repositories it should review. The publishing token requests no
  other write permission.

Configure the secret from its protected file, without putting it in command
arguments or logs:

```sh
gh variable set CODEXBAR_REVIEW_APP_CLIENT_ID --repo Lucenx9/codexbar-plasma --body CLIENT_ID
gh secret set CODEXBAR_REVIEW_APP_PRIVATE_KEY --repo Lucenx9/codexbar-plasma < /path/to/private-key.pem
```

The workflow becomes automatic after it lands on the default branch. To
regenerate a report for a completed PR CI run after installation or a fix:

```sh
gh workflow run ci-report.yml --ref main -f run_id=RUN_ID
```

It still rejects stale, closed, ambiguous, or non-PR runs. Baselines become
available after a successful full CI push run produces the new artifact.
`tests/test_ci_report.py` covers artifact validation, transport credentials,
baseline compatibility, real job statuses, stale/retried runs, and bot-comment
creation, updates, and unchanged-body handling. The publisher tests run on both
the Plasma image's Python and the hosted runner's Python, including 3.14.
Malformed JSON can trigger decoder-specific rejection exceptions; the test
checks rejection without requiring one parser error to be raised first.
