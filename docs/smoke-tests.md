# Popup smoke tests and panel captures

The `usage-analysis` scenario checks provider/day selection, retaining the
provider filter through a history-range refresh, switching to Tokens, returning
to all providers, expanding the layout, and avoiding AI generation during
navigation. The `usage-analysis-models` and `usage-analysis-narrow` variants
inspect expanded model details and larger text in a compact window.
`ai-insights-no-history` verifies that the assistant opens directly with both
history sources disabled, without history controls or a cost scan.
The `ai-insights` scenarios exercise the integrated assistant with a synthetic helper. `readme-spend` captures its compact
resting state. Pure `tst_usage_analysis.qml` tests cover mixed currencies,
unknown/zero/duplicate dates, incomplete and sub-cent comparisons, model bounds, and provider
line projection (calendar gaps, zero values, readable scales, bounded monotone
curves, and finite extreme values).

Use these isolated graphical scenarios to inspect the popup, settings, and panel.
[Regression checks and CI](testing.md) describes the automated suite.
[Runtime verification](runtime-verification.md) covers the installed widget.

## Popup smoke tests

`popup-content` also expands and collapses Provider actions, checking that its
commands stay hidden initially and that the disclosure does not start a refresh.
Cost-chart QtTests cover the resting peak, keyboard inspection, metric changes,
measured zero and empty data. Provider-tab refresh tests also exercise
proportional gauge fills at zero, low and full quota percentages.
They also check unavailable quotas, centered icon-only tabs, and disclosure
focus recovery on account-only changes through the production selection key.
Activity-layout checks cover square cells and the width and 7/8-day and
35/36-day breakpoints, including changes in scrollbar visibility.

`tabs-icon-only` focuses a provider tab with text labels disabled and checks
that its tooltip includes both the full name and the quota description.

`tabs-overflow` checks the Overview subset count and keyboard tooltips for a
long provider title, alongside navigation across the overflowing strip.
It selects every production provider tab and returns to Overview, checking
after each layout pass that selection never changes any provider tab's width.
`legacy-dashboard` renders both summary columns and checks a long top-model
value stays within half its row, elides, and retains its complete tooltip text.
`test_usage_dashboard.py` also executes the production block at 240 and 540
pixels, checks equal summary-column widths with uneven text, and checks
full-text hover for truncated summary labels, summary values, and detail values.

`empty-providers` and `usage-error` exercise the popup's setup and recovery
actions. `cli-missing` uses a nonexistent executable in the isolated temporary
directory and verifies actionable CLI guidance across Usage & Spend and Sessions,
without rendering their generic errors. `usage-recovery` retries a failed refresh
with retained quotas, checks that repeated activation cannot start another request, and waits for fresh
usage without rescanning cost history. `tests/test_usage_recovery.py` exercises
the production action handlers and message controls with keyboard activation,
observing refresh and native configuration actions at their effect boundaries.
They also exercise scrolling long missing-CLI messages, pointer and keyboard
access to recovery actions, and centered placement when setup content fits.
The missing-CLI state also offers direct preparation through the applet-owned
managed CLI controller. `tests/test_popup_cli_setup.py` exercises immediate
selection and refresh after installation or offline reuse, failures and retry,
timeout, late replies, command changes, and exclusion while usable data exists.
`tests/test_managed_cli.py` verifies that offline reuse rejects non-executable,
corrupt, version-mismatched, failed, or timed-out binaries without a release
request; the popup owner test checks that rejection never selects or refreshes.
The `cli-setup` smoke scenario activates the real popup button and waits for
provider data after the synthetic managed helper prepares a private fixture CLI.
`cli-setup-unusable` captures the rejected-copy message and checks that command
selection stays unchanged with no provider data.

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
python3 scripts/smoke_popup.py --scenario settings-providers --renderer opengl --theme dark --language it
```

`settings-providers-0840`, `settings-providers-0840-keys` and
`settings-providers-0840-cookie` capture validated Console import, SiliconFlow key
setup and WorkBuddy cookie setup. Each checks all four provider actions, including
Tripo, against a synthetic 0.84.0 inventory without sending credentials.

`settings-popup` and `settings-popup-narrow` verify the initially collapsed
hidden-item restore controls and that opening, restoring, and closing them keep
changes pending until Apply. Their captures show the resting collapsed state.
`tst_overview_settings.qml` covers keyboard disclosure, live singular/plural
counts, and the manual-only Overview checklist. Restore lists use plain Item
boundaries so FormLayout cannot query rebuilding delegates' attached size hints;
the keyboard restore checks also guard the Qt 6.11 layout crash reproduced
without these boundaries.

`--theme light` or `--theme dark` applies the Breeze color scheme to the
selected scenarios, except the README and `share-usage` captures, which always
use Breeze Dark. `--language` runs the selected
scenarios in one of the shipped translations. Both are review aids: settings
changes should be inspected in both themes and at least one long translation.

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
QML errors, recursive layout warnings, missing captures, early exits, and timeouts
fail the command. Nested-layout QtTests also use `failOnWarning` and exercise
provider details and project rows at narrow and normal popup widths.
`test_cost_sections.py` checks that expanded provider history has no trailing
project space when project data is absent or empty, including provider changes,
both metrics, collapsed details, and truncation-only project notices.
The quota-row tests exercise inline resets and their expanded fallback with
RTL, large fonts, pace, summaries and missing resets. `UsageRowLayout.js` owns
the pure safety-band transition so changing countdown text does not repeatedly
move a reset, including the inline separator's width and spacing.
`HeatmapNavigation.js` owns bounded, spatial navigation over the rendered
seven-row grid; `tst_heatmap_navigation.qml` covers missing days, padding,
mirrored columns and date identity. `test_cost_sections.py` dispatches keys
through the production heatmap, checks its single Tab stop and immediate
readout, reveals the grid in a short popup, preserves the full small theme font
for numeric labels, and covers refresh, removed dates and range/metric changes
without starting a scan. Marker tooltip tests keep used thresholds separate from mirrored
remaining percentages and omit markers at either endpoint. They exercise hover
entry and exit on all four sides of a thin track; keep paint clipping inside
the meter so it cannot cut off the hover handler's margin.
`tests/fixtures/ProviderUiStress.js` supplies realistic long identifiers, Unicode,
markup-like text, missing optional values, extreme budgets, and demo/empty/one/
1,000-row states. `tst_visual_layout.qml` renders these detail fixtures at 240,
320, 540, and 900 pixels, checks literal text and bounded meters, and confirms
that the existing normalizer caps 1,000 incoming rows at 24. Its hover tests
check full-text tooltips for quota titles, reset descriptions and chart headings,
including escaping and suppression when the text fits.
Screenshots still need visual review: this is not a pixel-comparison test and
does not exercise panel placement, key-event dispatch, or the real CLI.
Panel scenarios verify capsule count and clipping at small sizes, including
zero and absent quotas. `panel-vertical` and `panel-vertical-minimal` supply the
vertical form-factor input because `plasmawindowed` has no panel containment.
QtTests additionally exercise pointer/keyboard activation and resizing.
`settings-panel`, `settings-panel-information`, `settings-panel-advanced`, and
`settings-panel-narrow` verify pending preview changes, collapsed/expanded controls,
rendered quota capsules, and a 420-pixel layout with larger text and all additional
information enabled. `settings-general-updates` and `settings-general-updates-narrow` expand both
update groups and the optional identified subtotal, exercising the controls
hidden in the resting General page. These captures also assert that visible
help text stays inside the viewport, including after both groups expand. `settings-providers-default` captures the
initial provider surface without expanding diagnostics.
Wide provider captures use a fixed 900-pixel viewport because side-by-side
panes fill the visible page. `settings-providers-wide` renders 1440 pixels and
checks that both panes end together without scrolling and that the details keep
their readable maximum width.
`settings-ai-insights-stored-narrow` exercises the stored-key status and both
wallet actions at 420 pixels with larger text. The existing provider
captures deliberately expand it for inspection. Provider-list QtTests also
verify wide/stacked placement and keyboard access to rows beyond the viewport.
Every settings page has a capture, and each `-narrow`
variant renders at 420 pixels with 13-point text. `settings-providers` lists a
twelve-provider synthetic roster with the longest bundled title and an unknown
ID, then selects a provider and shows its redacted fixture diagnostics.
`providers-0740` checks artwork and documentation/dashboard actions for all nine
providers introduced in CLI 0.74.0, offers API-key setup only for the five
complete Linux flows, and captures Aerostack selected in the provider settings.
`settings-providers-error` and `settings-diagnostics-error` capture failed CLI
responses; the provider capture also requires an enabled Reload placeholder. `panel-information`, `panel-information-minimal`, and
`panel-information-single` capture grouped text at a 24-pixel panel height, including
selection of the second provider. QtTests exercise style selection, disclosure,
retained hidden values, defaults, custom order and filtered-meter fallbacks,
long-text bounds, exhausted grouped-text width, reordering after disclosure,
and activation through both text and meters. The live adapter limits meters to
four; a renderer stress test exceeds that limit to verify the zero-width guard
independently of theme dimensions. Early preview exits report the process exit
code in addition to the log path.
The staged smoke package exposes a temporary handle to the usage lifecycle for
synthetic clock and deadline probes; the installed production API stays read-only.
`usage-retention` exercises failed/partial refreshes, recovery, notification
suppression, and cache invalidation. It also verifies multiple extra windows
through cache decode, QML normalization, and re-encoding, including extra-only
and measured-zero quotas. Cost refreshes, range changes, account selection, and
cache restore must keep token costs hidden for stale usage.
Successful credits-only responses with old timestamps must preserve their
balance, including zero, through the next quota-expiry check.
`usage-cache-restart` launches two separate
widget processes with the same isolated settings and delays the second CLI
refresh to verify startup restoration from disk.
Synthetic payloads cover a subset of the CLI 0.56.2 contract; fixture dates
are relative to run time. Typography uses Noto Sans and Breeze icons.
The `popup-cost-refresh-error` scenario checks that failed cost refreshes keep
their error visible beside cached values, with details collapsed or expanded,
and exercises privacy, an initial failure without a cache, and recovery.

`popup-scroll` and `popup-scroll-large` exercise long account lists, provider
and global error messages, and scroll resets after provider or account changes
on the real applet. Same-account refreshes and privacy changes retain the
position. The larger variant doubles the font size. Both verify that the first
quota is visible with twenty account choices collapsed and that the disclosure
opens the full list. Recovery actions and the final account remain reachable,
and a global error stays first in each view's scroll area.
`tst_global_view_errors.qml` covers long
Spend/Sessions errors with retained data and empty/loading states, keyboard
refresh, privacy, and pinned headers. It also exercises the production Spend
chart's selected date through inserted, expired, and missing days, and clears
selection on range and metric changes without starting a scan.
`test_cost_sections.py` also checks the Usage & Spend provider totals in both
metric modes, including unknown versus zero, estimated costs, full-text hover,
240-pixel and mirrored layouts, and doubled label fonts.
The monthly credit regression in
`test_provider_cost_presentation.py` calls `ProviderCostDetails.creditLimitRow`
directly and renders the shared usage delegate to check that amounts remain
visible independently of popup pace. Root adapter forwarding is checked in
`test_ui_cost.py`. The `popup-cost-missing-tokens` smoke scenario executes
`spendTotalLine()` in the real applet and compares it with the provider snapshot's
cost total, so dropping the snapshots between selection and presentation fails
at the runtime boundary.

`make check` covers the runner's portable isolation and failure-handling tests
and lints the capture QML.
`test_provider_metadata.py` also passes a native Qt list through the production
snapshot adapter and hidden-section filters: nested lists received over a QML
signal must become JavaScript arrays before those filters consume them.
`tst_interactive_chart.qml` checks the painted peak guideline for both local
cost bars and CLI detail bars, while keeping line charts free of that guide.
It also checks the inspection guide through actual canvas pixels for hovered
and keyboard-selected bar and line points, including signed and all-zero data.
`tst_visual_layout.qml` verifies full-text readout tooltips with escaped markup,
immediate keyboard readouts, and tooltip suppression when values fit or disappear.
It also checks provider quota metadata returning between shared and stacked
lines on resize, including mirrored layouts, doubled text size, and unbroken
forecast text that must wrap inside the meter width.
`tst_popup_controls.qml` checks provider account/plan metadata returning between
shared and stacked lines on resize, with larger fonts, mirrored layouts, and
missing identity fields, while preserving full-text hover tooltips.
`make smoke` additionally requires the graphical environment and reports a
failure rather than silently skipping when that environment is unavailable.

## Panel configuration matrix

Capture all 32 combinations of Provider colors/Monochrome and the four content switches
(provider name, usage text, credits, meters) with one and four providers in
Breeze Light and Breeze Dark:

```sh
python3 scripts/panel_matrix.py --output dist/review/panel-matrix
```

Run it in a graphical Plasma session or prefix the command with `xvfb-run -a`.
It requires the same tools as the popup smoke runner plus both Breeze color
schemes. It always uses OpenGL so provider icon masks render their actual colors.
The synthetic CLI, applet installation, configuration, and D-Bus session are
isolated using the smoke runner. The installed widget and real credentials are
not used. The temporary applet runs the production normalization, settings
adapters, and compact renderer.

The default run saves 450 captures: 128 base combinations plus targeted cases
for all 24 element orders, five text formats with and without automatic quota
labels, explicit quotas, visibility rules,
missing data, long names, exhausted quotas, and 24/48/64-pixel panel heights.
The targeted cases also cover optional monetary spend budgets, spend-only
text and all six labelled-pace compositions in both styles, unavailable budgets, tiny readings, warning colors, stale quotas with
confidence and incident markers, and real pointer hover/press and keyboard-focus
states in both styles. `--vertical` adds 176 captures covering the base
combinations and those states on vertical panels. The capture harness uses
QtTest input events; it does not simulate interaction by changing visual colors.
Unavailable credits are tested with the four-provider fixture. Missing and
exhausted quotas are synthetic normalized snapshots within the isolated applet.

Four providers is the meter row the compact renderer caps at, so that batch is
where panel content competes for width and items are surrendered.

The runner rejects missing PNGs, clipped measured elements, incorrect base
text/capsule counts, and rendered text that is not one of the compositions the
renderer offered. It rejects an elided label only when a narrower composition
would have fitted: the narrowest composition has nothing left to surrender, so
eliding it is the documented last resort and passes.
`index.html` filters the gallery by theme/provider count/
orientation and base cases; `results.json` records configuration, text, and
geometry; `source.json` identifies the source digest and Git revision when
available. Captures require human visual review: passing assertions does not
establish typography or contrast quality. This is a bounded matrix, not every
possible font, scale factor, translation, provider payload, or rule threshold.

CI runs the horizontal matrix in `smoke-runtime` and uploads the `panel-matrix`
artifact. The popup artifact also includes `settings-panel-scrolled`, which
checks that the preview remains visible at the bottom of the expanded options.
The settings preview checks use translated percentages when run with `--language`,
including the space before the percent sign in French.
QtTests cover the corresponding identity fallback and fixed-preview behavior,
including the KDE desktop controls style and right-to-left layout.
