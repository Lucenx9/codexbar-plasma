# Popup visual review

The review started with the installed widget in the current Plasma theme.
These comparisons render the repository at `07bdf8d` and the proposed changes
in `plasmawindowed`, using identical synthetic provider and cost snapshots.
They contain no live accounts or usage data.

| Before | After | Change |
| --- | --- | --- |
| ![Overview before](popup-overview-before.png) | ![Overview after](popup-overview-after.png) | Rows size to their content, with more padding and a chevron that indicates navigation. |
| ![Provider before](popup-provider-before.png) | ![Provider after](popup-provider-after.png) | Account and plan share an identity line; the update time has its own line. |
| ![Spend before](popup-spend-before.png) | ![Spend after](popup-spend-after.png) | History filters have their own row, leaving room for the total. |

Every popup refresh action uses the native button's footprint while displaying
a busy indicator. Overview rows show an explicit keyboard focus outline and
clear it when the user switches to the mouse. Direct QtTests cover activation,
busy state sizing, focus changes, and account visibility after reopening.

The design follows the existing Plasma colors, fonts, and spacing units. The
Emil design engineering and Apple design skills informed grouping, hierarchy,
and immediate feedback. No CLI contract or persisted setting changes.

The light-theme check uses Breeze Light, a 14-point body font, and a 12-point
small font in an isolated preview configuration.

![Overview with larger text in Breeze Light](popup-overview-large-text-light.png)

## Settings

The same review covers General, Providers, and Display. These screenshots use
an isolated Plasma configuration and the same synthetic roster of four enabled
and two disabled providers. Provider loading is replaced only in the temporary
preview package. No provider credentials or live account data are included.

| Before | After | Why |
| --- | --- | --- |
| ![General before](settings-general-before.png) | ![General after](settings-general-after.png) | Bound supporting text lets the native form place labels beside controls when space permits. Notifications and update options indent beneath their parent setting. The history window includes its day unit. |
| ![Providers before](settings-providers-before.png) | ![Providers after](settings-providers-after.png) | Settings and diagnostics start collapsed, making all four enabled example providers visible. Provider links and the immediate-save notice remain available. |
| ![Display before](settings-display-before.png) | ![Display after](settings-display-after.png) | Provider icons replace inactive drag handles. Panel visibility controls precede ordering, arrow buttons have tooltips, and help describes only the selected text mode. |

The General form was checked at frame widths of 690, 818, and 1100 pixels.
It switches to stacked labels in a narrow window, while supporting text wraps
inside the form. The Defaults explanation no longer extends beyond the page.

![General defaults with wrapped text](settings-general-defaults-after.png)

The additional light-theme check uses a 14-point body font and 12-point small
font. The settings disclosure follows the user's body font.

![General with larger text in Breeze Light](settings-general-large-text-light.png)

[Providers with larger text in Breeze Light](settings-providers-large-text-light.png)

Provider disclosure and selection, and provider reordering were exercised in
the preview. An injected diagnostic error survived collapsing and reopening
the details. Opening details does not fetch diagnostics. The disclosure is a
native checkable control and retains the existing CLI-backed options and
redacted diagnostics behind it. No configuration schema or CLI contract changed.

## Panel, empty states, and Debug

This additional comparison uses commit `74558da` as its before state. It renders
the actual QML components with identical synthetic fixtures in `plasmawindowed`.
The panel gallery uses horizontal rows of 24, 32, and 48 logical pixels, a vertical
representation, and a loading row. The chart deliberately supplies a long value
and label at the final point of a narrow plot.

| Before | After | Why |
| --- | --- | --- |
| ![Panel and chart before](edge-panel-chart-before.png) | ![Panel and chart after](edge-panel-chart-after.png) | The incident dot remains square and centered instead of stretching with the panel. Long chart values elide within their allotted width and preserve the point label. |
| ![Sessions error before](edge-sessions-error-before.png) | ![Sessions error after](edge-sessions-error-after.png) | An empty error state absorbs the remaining height, keeping tabs, the heading, and refresh at the top. The same correction covers an initial CLI error. |
| ![Empty Sessions before](edge-sessions-empty-before.png) | ![Empty Sessions after](edge-sessions-empty-after.png) | A containing item fills the view while the native placeholder retains its natural size. This also fixes empty provider and Usage & Spend views. |
| ![Debug before](settings-debug-before.png) | ![Debug after](settings-debug-after.png) | The provider filter aligns with its actions and output. A terminal icon identifies diagnostics without implying an active error. The field retains an accessible label. |

The empty-state wrappers preserve the grouped icon, message, and explanation;
stretching the Kirigami placeholder itself would separate those elements.
[Empty providers](edge-empty-providers-after.png) and
[empty Usage & Spend](edge-spend-empty-after.png) use the same layout rule.

| Check | Result |
| --- | --- |
| Panel composition | Inspected icon/text/meter combinations, four providers, long text, loading, and incidents at the sizes above. |
| Fractional scaling | Inspected isolated Qt render scales of 125% and [150%](edge-panel-chart-150-after.png), without changing the host display scale. |
| Many provider tabs | Traversed 16 providers with native arrow-key input, then selected the final long-name tab with Space. The focused tab scrolls into view and retains its focus outline: [screenshot](edge-tabs-keyboard-after.png). |
| Sessions | Checked empty, loading, timeout, and [25 long-name sessions](edge-sessions-long-after.png). Names elide and the list scrolls vertically. |
| Usage feedback | Checked no data, initial loading, missing CLI, partial provider failure with retained data, and unavailable local cost history. |
| Settings | Checked Debug and Advanced in the native window. Advanced needed no change. Earlier General, Providers, and Display comparisons remain above. |
| Direct interaction checks | QtTests cover meter activation by keyboard and pointer, chart keyboard and pointer inspection, empty chart selection, the three panel dot sizes, and the Sessions heading in empty/loading/error states. |

The new tests reproduced five failures against the previous code (three panel
sizes, chart overflow, and Sessions error layout). The final `make check` passes
550 QtTests and 3 desktop-style checks with no failures or skips. QML lint,
ShellCheck, static checks, catalog validation, and AppStream validation pass.
Packaging and the installed-widget runtime check are recorded in the PR.

`plasmoidviewer` is unavailable on this host. Panel variants were checked using
the actual compact component in the native gallery, rather than by rearranging
the user's live desktop panels. The native checks supplement the earlier light
theme and larger-text comparisons; no claim is made about every Plasma theme.
