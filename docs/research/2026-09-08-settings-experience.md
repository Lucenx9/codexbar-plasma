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

Visual review uses synthetic fixtures only. The captures use Plasma's native
controls with the OpenGL renderer:

| Surface | Before | After |
| --- | --- | --- |
| General | [Original form](../settings/2026-09-08/before-settings-general.png) | [Focused form](../settings/2026-09-08/settings-general.png) |
| Panel | [Combined Display form](../settings/2026-09-08/before-settings-display.png) | [Live preview and panel options](../settings/2026-09-08/settings-panel.png) |
| Popup | Shared the Display form | [Content and provider options](../settings/2026-09-08/settings-popup.png) |
| Notifications | Shared the General form | [Thresholds and alerts](../settings/2026-09-08/settings-notifications.png) |
| Diagnostics | Separate connection/override/debug pages | [One diagnostics page](../settings/2026-09-08/settings-diagnostics.png) |
| Privacy | Identities always visible | [Anonymous account picker](../settings/2026-09-08/privacy-provider.png) |

The PR verification section records the executed tests.
