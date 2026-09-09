# Settings experience

Reference: user-supplied screenshots of official CodexBar macOS **0.56.8 (139)**,
built September 7, 2026. Plasma comparison base: `8a064ea`. This is a frontend
settings change; the repository's verified official Linux CLI contract baseline
remains **0.56.2**. No new CLI fields, authentication actions or config writers
are introduced.

The five previously proposed settings improvements are implemented together:

| Before | After | Why |
| --- | --- | --- |
| Panel appearance could only be judged after Apply. | Panel shows the actual compact renderer with synthetic normal, near-limit, incident and missing-data scenarios. | Inspect order, visibility rules, style and metrics before saving. |
| General mixed refresh, thresholds, notifications and updates; Display mixed panel and popup controls. | General, Providers, Panel, Popup, Notifications and Diagnostics. CLI path and overrides sit with diagnostics. | Settings are grouped by the surface or behavior they affect. |
| Account and project/session identities remained visible during sharing. | Optional privacy mode masks presentation fields, tooltips and new notifications and disables session copying. | Share the widget without exposing those identities. |
| Quotas only followed periodic or manual refresh. | Optional refresh on opening the popup, only when stale. | Obtain recent quotas without starting a request on every opening. |
| Pace, credits and additional provider details appeared whenever supplied. | Three independent Popup switches, enabled by default. | Keep the popup focused on the information the user wants. |

All five are **Plasma-native and implementable now**, using existing normalized
data and supported refresh commands. Existing saved preferences remain valid.
The native Plasma configuration dialog owns Apply/Discard/Cancel between pages;
the global Restore all defaults action still prepares pending values.

Privacy mode is a display preference. It preserves cached data and real account
keys for selection. Unknown/provider-authored prose and preformatted billing
details are omitted, while numeric quota/cost data and valid reset timestamps
remain available. Numbered account/project/model/session labels are local to the
displayed list. Provider administration and Diagnostics are outside the mode.
It does not erase earlier desktop notifications or OS clipboard contents.

Refresh-on-open uses the quota interval as its freshness limit, with a five-minute
fallback when periodic refresh is off. Running or queued refreshes are retained.
Failed attempts get the same cooldown so open/close cycles cannot create a retry
loop. Manual refresh remains available; local history uses its existing schedule.

Provider auth/account editors, hook rule editors, provider-plugin permission
management and richer provider data remain **blocked on an official CLI contract**.
This PR does not turn the dormant descriptor proposal into a shipped contract.
iCloud, Keychain/Full Disk Access and Sparkle are **macOS-only/non-goals**; Plasma
keeps its existing update integration.

## Configuration lifecycle

The settings review checked Plasma's native configuration dialog in the supported
KDE neon image, package `plasma-workspace` version
`4:6.7.4-0zneon+24.04+noble+release+build94`. Its `pushReplace` replaces the
current page, and opening the next page supplies applied `cfg_*` values from
`Plasmoid.configuration`. Switching with unsaved changes prompts
Apply/Discard/Cancel. The pages do not share an unsaved transaction.

The Panel preview and Notifications page therefore read applied values from
other pages. General retains pending defaults so Restore all defaults can update
dependent controls before Apply. A shared cross-page pending store would model
a different lifecycle.

Privacy keeps Cursor's bounded numeric included-plan percentage available for
quota selection while hiding free-form billing text. Provider action menus use
raw capabilities with local labels, since removing URLs from that input would
remove valid actions. Display records and account command keys remain separate.

## Historical verification

The [PR #162 verification](https://github.com/Lucenx9/codexbar-plasma/pull/162)
records executed tests. The synthetic OpenGL
[captures and review notes](https://github.com/Lucenx9/codexbar-plasma/tree/92679f99ce5d5479f4f87edde051fff91e30b91f/docs/settings/2026-09-08)
remain available in Git history.

## Panel disclosure refinement

The follow-up against Plasma `d09e5b6` keeps the six-page structure and existing
configuration keys. Appearance and content choices remain visible; text format
appears only when usage text is enabled. A collapsed section contains quota,
order, visibility conditions, and automatic provider selection. Its summary
identifies effective non-default choices without discarding hidden preferences.
The section is named "Quota, order and visibility" so its contents are predictable.

This follows [KDE's progressive disclosure guidance](https://develop.kde.org/hig/powerful_when_needed/)
and [input-control guidance](https://develop.kde.org/hig/getting_input/).
Standard and Minimal use native radio buttons with descriptions. The existing
preset still selects monochrome styling, enables meters, and hides text; its
new label states those effects. Controls respond immediately, and expanding the
section introduces no animation or configuration write.

The live preview resolves a Repeater provider back to its synthetic source before
selecting quota rows. Qt can expose nested delegate arrays as sequence wrappers;
those must not make the pure array-based quota selector omit real preview data.
This changes no CLI parsing or live provider normalization.
