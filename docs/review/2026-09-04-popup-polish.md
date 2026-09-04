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
