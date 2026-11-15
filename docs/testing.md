# Regression checks and CI

Use this guide to select checks, maintain the CI image and interpret reports.
[Development](development.md) owns setup and delivery;
[Implementation](implementation.md) records invariants;
[Smoke tests](smoke-tests.md) owns graphical scenarios and captures.

## Regression checks

During iteration, run the narrowest relevant target. Before delivery, run
`make check` and read the complete result, including tool failures and skips.
Each check is a separate Make target; `make -n check` lists the current suite.

```sh
make check-qml-logic
make check-python-test_usage_controller
make check-security-regressions
make check
```

`make check` runs independent targets concurrently because most Python modules
start their own `qmltestrunner`. Output stays grouped per target. Use
`make check JOBS=2` on constrained machines. Other targets continue after a
failure, so the final exit/result matters.

### Select behavioral coverage

| Change | Start with | What the check establishes |
| --- | --- | --- |
| Pure parsing, planning or normalization | Owning `tests/tst_*.qml`; `make check-qml-logic` | Public results, input immutability and adversarial bounds |
| Process/controller lifecycle | Owning `tests/test_*.py`; `make check-python-<module>` | Production controller, executable-engine behavior, cancellation and stale replies |
| Notification/CLI termination | `test_cli_process_bounds.py`, owning controller checks | Actual child termination, separately from UI retirement |
| Provider identity or setup | `tst_provider_metadata.qml`, capability/protocol tests, `check-feature-parity`, `check-provider-icons` | Independent expected identities, gates and QML delegation |
| Cost normalization | `tst_cost_response.qml`, worker/context tests, `make benchmark-cost` | Public financial semantics, thread delivery and separate performance limits |
| Settings or layout | Owning component/settings QtTests and geometry checks | Real controls, focus, sizing, locales and layout directions |
| Localization | `make check-i18n-catalog`; [Translations](translations.md) | Catalog arguments and executed presentation adapters |
| CLI/provider credentials | [Provider credentials](provider-credentials.md) checks | Stdin-only secrets, process cleanup and released-command boundaries |
| AI helper or data contract | [AI Insights](ai-insights.md) checks | Allowlist, private handoff, fake wallet/service and cancellation |
| Editorial docs or CI scope | `check-python-test_documentation`, `check-python-test_ci_scope` | Indexed files, local paths and fail-closed coverage selection |
| Packaging | `make package` | Curated archive contents; it does not establish runtime behavior |

Read the owning test before editing; filenames are navigation, not a substitute
for the fixture's assertions. Test pure interfaces directly. Use surface checks
for wiring, effect ownership and lifecycle ordering, and runtime checks for what
static assertions cannot prove. Avoid private-name/body-layout assertions when
public behavior already covers the contract. Break the claimed behavior to
confirm the behavioral check fails before adding another source assertion.

Expected provider identity/color outputs must stay independent of production
tables. Colors require three finite channels in `0..1`; theme delegation belongs
to `test_theme_boundaries.sh`. Controller fixtures use isolated synthetic CLI
executables and real Qt event loops, never credentials or provider history.
Do not shorten production deadlines just to make timeout coverage faster:
usage takes about 145 seconds, account/session scans about 80–90 seconds and
widget-update coverage about a minute. Read each test's outer timeout when
investigating loaded-runner failures.

### Shared source assertions

`scripts/lib/qml_surfaces.py` defines file groups shared by checks, translation
extraction and the Makefile, including `.mjs` dependencies used by both QML and
WorkerScript. Add new directory/extension globs there;
`test_qml_hardening.sh` rejects uncovered sources.

- Use shell `require_in_surface`/`reject_in_surface`, or Python `Surface.require`,
  `function_body` and `id_block`, for rules applying across an owner. Reserve
  `*_in_file` for actual file-specific contracts. Unknown/empty groups and
  discovery/read errors fail; absent optional directories may match no files.
- Use `require_definition_where_used` for unqualified helpers. A declaration
  elsewhere cannot satisfy the caller's scope; `applet.foo(...)` also checks
  the page root. A global text search misses broken cross-file callers.
- Shared `hasOwnKey`, `isUnsafeObjectKey`, `copyObject` and `shellQuote`
  bindings delegate through `Guards.js` to `Guards.mjs`. Keep validation shared
  with WorkerScript rather than copying it into config pages.

Python membership assertions use `code_contains` to tolerate line breaks,
anonymous-function spacing and terminating semicolons. Some shell assertions
still match literally. `qmlformat` remains outside the suite: 6.11.2 can join
expressions into 2570-character lines with wrapping off, split comparisons with
wrapping on, and recurse indefinitely on a regex literal wider than
`MaxColumnWidth`. Long patterns can use `new RegExp(...)` strings or substring
checks. [TODO](../TODO.md) tracks formatter adoption; preserve surrounding
formatting in unrelated edits.

### Runtime styles, locales and exceptions

The QML runner repeats affected settings, geometry and popup tests under the KDE
desktop controls style, not just Basic. It also covers German/Italian number
formats, six shipped catalogs, enlarged/fractional fonts and mirrored layouts.
Date checks include UTC, Rome, Los Angeles and Apia; quota-week checks cover
Santiago's nonexistent local midnight. Keep the real style and clock boundary
when modifying these fixtures.

Geometry checks observe rendered frames, including initialization, direction
changes and delayed roster arrivals. Wait for KDE style transitions before
fixture destruction, retaining warning failures during teardown. A coordinate
sample before rendering cannot prove stable layout.

`qml_runtime_support.py` permits one exact Qt 6.11.1 initialization diagnostic in
cost-context/source-isolation tests:
`QObject::connect(QJSEngine, QtObject): invalid nullptr parameter`.
An empty dynamic WorkerScript reproduces it because
[`QtObject` connects `uiLanguageChanged`](https://github.com/qt/qtdeclarative/blob/v6.11.1/src/qml/qml/qqmlbuiltinfunctions.cpp#L267)
to [WorkerScript's null public engine](https://github.com/qt/qtdeclarative/blob/v6.11.1/src/qmlworkerscript/qquickworkerscript.cpp#L232).
The exception is version-specific and does not suppress runtime logging or weaken
worker outcomes. Recheck it on a Qt update; cancellation exceptions remain local
to their fixtures.

Secret-prompt fixtures give each phase three seconds and allow delayed successful
replies to exceed one phase's deadline. The production ledger covers both prompt
and writer plus disconnect margin. Child shutdown assertions allow bounded
asynchronous signal delivery but must fail when group cleanup is disabled.
AI smoke scenarios replace the helper with `fixture_ai_insights.py`, so no
preview reaches an actual service or wallet. Synthetic HTTP servers count only
the helper's User-Agent because desktop tools may probe new local ports.

### Required tools and CI scope

`check-workflows` runs actionlint; `check-python-lint` runs pyflakes on scripts
and tests, including invalid escape sequences. Neither reformats source.
`check-appstream` requires `kpackagetool6`. Missing local tools are skips, never
passes. Local Plasma packages can also lack QML type metadata; CI provides it.
Unqualified warnings are disabled because Plasma injects helpers such as `i18n()`.
To require strict import/skip handling locally:

```sh
QML_TEST_REQUIRE_NO_SKIPS=1 make check QMLLINT_FLAGS='--import warning --unqualified disable'
```

[CI](../.github/workflows/ci.yml) runs on PRs, main pushes, version tags, Monday
07:23 UTC and manual dispatch:

```sh
gh workflow run ci.yml --ref main
```

The fast `lint` job runs static checks and packaging before the Plasma image is
ready. `scope` compares the tested PR merge tree with its base parent, or the
full before/after main-push range. Only a diff limited to `scripts/ci_scope.py`'s
editorial Markdown allowlist omits `check-runtime` and `smoke-runtime`. Every
check reading those Markdown files must also run in fast lint;
`test_ci_scope.py` enforces that coverage.

Images, translations, code, tests, packaging, CI files, unknown paths, missing
history and empty diffs retain full runtime coverage. Tags, schedules and manual
runs always use the complete toolchain. Required `check`/`smoke` jobs report
successful runtime coverage or an explicit editorial-only omission; failures,
missing results, cancellations and unexpected skips fail. No workflow path
filter may leave required checks absent. See
[GitHub's guidance](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks).

Popup smoke `results.json` records per-scenario seconds, including failures;
CI retains screenshots/logs for seven days. Use these to locate costly coverage
before changing it. Keep parallel checks and separate runtime jobs; compare
startup, test and total wall times at equal coverage before adding runners.
Concurrent durations are not additive. Delivery/merge rules stay in
[Development](development.md#delivery-and-ci).

### CI image and dependencies

Both runtime jobs pin the same Linux/amd64 Ubuntu 24.04/Neon image by digest.
[ci/Dockerfile](../ci/Dockerfile) copies signed Neon repository configuration,
key, CA bundle and priorities into the pinned Ubuntu base, then installs explicit
Qt/Plasma tools, Mesa and locales without a full desktop. HTTPS/APT authentication
and failed-refresh handling remain required. PR jobs do not install dependencies
or refresh APT. Installed versions live in `/usr/local/share/ci-packages.txt`;
`ci-inputs.sha256` pins the recipe and installer to the checkout, so input changes
require a new validated image and matching workflow pins in the same PR.

Rebuild from the repository root. Add `--no-cache` to refresh packages without a
recipe change:

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

Publication requires authorization separately from a widget release.
[ci-image.yml](../.github/workflows/ci-image.yml), dispatched on main with a trusted
recipe revision, validates checks, packaging and graphics, then publishes a
uniquely tagged candidate to `ghcr.io/lucenx9/codexbar-plasma-ci-runtime`:

```sh
gh workflow run ci-image.yml --ref main -f revision=codex/update-ci-image
```

It pushes the Linux/amd64 platform manifest with `docker push --platform
linux/amd64`, excluding the index/attestation manifests. It reports the registry
digest without updating consumers. Pin that digest in both runtime jobs and
verify their GitHub results. A recipe PR's old image intentionally fails the
input-hash check until replaced. Re-resolve Neon's `user` tag on every rebuild:
KDE prunes old digests. Ordinary weekly CI validates without publishing.

Create the initial package through Actions with `GITHUB_TOKEN` so repository
access is assigned. The source label alone does not prove access; a package
created outside Actions may need
[Manage Actions access](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility#ensuring-workflow-access-to-your-package).
Runtime jobs use only `contents: read` and `packages: read`, with no PAT. A
repository-linked private package supports that token; public visibility only
adds anonymous local pulls. Verify fork permissions under
[GitHub's token rules](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions)
and [package access rules](https://docs.github.com/en/packages/learn-github-packages/about-permissions-for-github-packages#visibility-and-access-permissions-for-packages).

Workflow actions stay SHA-pinned with a release-version comment. Update both
from the referenced release. [Dependabot](../.github/dependabot.yml) groups Actions
updates weekly on Monday 09:00 Europe/Rome and checks Docker monthly at 09:00 in
the same timezone. Both apply a seven-day version-update cooldown; security
updates are exempt where supported, and Docker has no Dependabot security
updates. Docker stays on Ubuntu 24.04 and excludes untagged Neon, refreshed by
hand. For urgent Ubuntu fixes, rebuild and validate manually, then update both
runtime digests rather than waiting for the schedule.

`scripts/install-actionlint.sh` downloads the official binary and verifies a
pinned SHA-256. Update version/checksum together from `checksums.txt`; an
unreachable or unverified archive fails installation. The runtime image already
contains it. Rebuild on recipe, installer, base-pin or toolchain changes, and
periodically for security fixes.

### Cost response performance

`make benchmark-cost` runs `tests/bench_cost_response.qml` outside concurrent
`make check`; CI runs it afterward in `check-runtime`. Its `bench_` prefix avoids
ordinary directory discovery. Override `QMLTESTRUNNER` when Qt 6 is elsewhere.

The public `CostResponse.response` call is measured after one warm-up, using nine
samples averaging 20, 2 and 1 calls respectively. JSON construction/serialization
happens before timing; fixtures check normalized results and log raw samples,
median and budget.

| Fixture | Median ceiling |
| --- | --- |
| 30 days, four models/day | 100 ms |
| 365 days, 16 models/day | 1,000 ms |
| All history, 2,048 days, 16 models/day | 2,000 ms |

These are scheduling-tolerant regression limits calibrated on Qt 6.8.2/Intel N95,
not frame-latency goals. CLI I/O and rendering are excluded. Compare on an idle
machine with identical Qt build, fixtures, sample counts and warm-up. Preserve
samples and kept/reverted experiments in the PR. Investigate a failed budget
against a fresh baseline; do not raise it automatically.

Deterministic normalizer tests separately reject model reads for discarded dates
and amount-only paths. Cost-response tests count reads across All-history average
paths so only the period summary inspects models outside the chart window.
Model-identity tests cover shared currency validation and independence across
normalization calls.

### Sticky CI report

[ci-report.yml](../.github/workflows/ci-report.yml) publishes one English comment
as `codexbar-review-bot[bot]`. Later runs update the matching author and
`<!-- codexbar-ci-report -->` marker; unchanged bodies cause no write. The report
supplements Sonnet review. Required `check`, `smoke` and `pr-title` remain the
merge gates.

`scripts/ci_report.py` orchestrates validation/collection, credential-separated
HTTP transport and Markdown rendering through `scripts/lib/ci_report_*` modules.
The comment reports real job conclusions, popup outcomes, panel record count and
artifact/run links. Failed/cancelled runs still report conclusions; rejected or
missing measurements never become passes. Partial panel captures are not visual
approval. Editorial-only runs explicitly identify omitted runtime checks.

The unprivileged scope job records the immutable tested PR target even after a
coverage-selection failure; smoke replaces it with measurements, including on
failure. Both upload `ci-results` for 30 days, containing exactly one bounded root
`ci-results.json`. Schema 2 identifies run/attempt, PR head, tested base branch/SHA,
merge SHA, image/fixture fingerprints, scenario outcomes/seconds and panel count.
Invalid/unavailable artifacts preserve historical job status with a warning;
measurements for a different current target are rejected.

Baseline selection prefers a successful push at the exact base SHA, then a
recent successful base-branch run. Timing/failure comparisons require matching
schema, fingerprints and scenario IDs. The fixture fingerprint includes harness,
Makefile and workflow. Scenario seconds include process/setup cost; they are
smoke diagnostics, not widget latency or a regression threshold. The report
collects no QtTest/Python totals, RAM or code coverage. Inspect logs and images.

The privileged `workflow_run` publisher checks out only the trusted default
branch and runs its tests. Its `GITHUB_TOKEN` is read-only; a repository-scoped
GitHub App token gets only `pull-requests: write`. PR code never runs there.
ZIP validation rejects extra entries, paths, symlinks, unknown fields, bad types,
duplicate IDs and invalid values. Artifact downloads never forward credentials
to signed storage. Oversized details are omitted while conclusions/links remain.
Measurements from PR CI remain untrusted inputs, not an independent audit.

Before writing, validate workflow ID, completed PR event, attempt, head SHA,
source repository/branch, associated open PR and recorded tested target. Recheck
target immediately before writing: historical GitHub PR fields can change.
After partial reruns, use each job's latest execution and require measurements
from the latest smoke attempt, labelling any older overall attempt. Baseline
listing/download failures cannot abort publication of job status.

Concurrency keys combine head-repository ID and branch so manual/automatic
publishers for one source cannot race. Reconcile to that source's newest completed
CI run at its current head; wait for newer active runs. Same-SHA runs from other
branches/forks cannot supersede it. Fork CI receives no write credentials.

Maintainer setup uses the repository's existing GitHub App installation with
**Pull requests: Read and write**, limited to intended repositories. Set its
client ID variable and private-key secret without putting the key in arguments
or logs:

```sh
gh variable set CODEXBAR_REVIEW_APP_CLIENT_ID --repo Lucenx9/codexbar-plasma --body CLIENT_ID
gh secret set CODEXBAR_REVIEW_APP_PRIVATE_KEY --repo Lucenx9/codexbar-plasma < /path/to/private-key.pem
```

After the workflow reaches main, regenerate a completed PR run's report with:

```sh
gh workflow run ci-report.yml --ref main -f run_id=RUN_ID
```

Stale, closed, ambiguous and non-PR runs remain rejected. Baselines require a
successful full push run producing the artifact. `tests/test_ci_report.py` covers
these boundaries on the runtime image's Python and the hosted runner, including
3.14. Malformed-JSON assertions require rejection, not one decoder-specific
exception ordering.
