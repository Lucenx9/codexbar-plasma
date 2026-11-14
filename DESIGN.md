# CodexBar Plasma design

CodexBar Plasma should feel like a precise instrument in the desktop panel:
quick to read, quiet while healthy, and explicit when data needs attention.
Linear is the primary reference for hierarchy and density. Raycast informs
interaction speed; Vercel informs visual restraint; Stripe informs the
explanation of complex data. KDE supplies the actual interaction and theme
system.

This is the design direction and review guide for the standalone Plasma applet.
It does not ship a redesign or change settings, defaults, CLI contracts, or
feature availability. Rules below are acceptance criteria for future UI work,
not a claim that every current theme and control has passed an accessibility
audit. The [usage guide](docs/usage.md) owns supported behavior,
[Development](docs/development.md) owns implementation and delivery, and
[TODO](TODO.md) owns remaining Linux parity work.

## Evidence and reference priority

Implementation baseline: Plasma commit
[`5b5075c82269e38504bbdd31e5e98d0aa28f99a1`](https://github.com/Lucenx9/codexbar-plasma/tree/5b5075c82269e38504bbdd31e5e98d0aa28f99a1),
reviewed 2026-11-07 alongside its components, theme helpers, configuration,
tests, and maintained guides. Website references are dated observations, not
versioned specifications. The applications' marketing pages are inspiration;
their implementation libraries are not dependencies for this widget.

When references disagree, use this order: truthful data and safe actions,
accessible Plasma behavior, clear task hierarchy, then visual resemblance.
The reference choices are a preference, not an industry ranking or award claim.

The following official sources were accessed on 2026-11-07. The final column
is our interpretation for Plasma, not a requirement stated by the source.
Public documentation and design articles were reviewed; authenticated product
dashboards were not inspected.

| Reference | Sourced observation | Application to CodexBar Plasma |
| --- | --- | --- |
| **Linear, primary** | The [March 2026 refresh](https://linear.app/now/behind-the-latest-design-refresh) prioritizes task content, quieter separators, and predictable action placement. | Let quota values and context lead; group with alignment and spacing before adding more chrome. |
| **Vercel** | [Geist Colors](https://vercel.com/geist/colors) separates background, border, text, hover, and active roles. | Use consistent semantic roles mapped to Plasma tokens, with distinct interaction states and restrained edges. |
| **Stripe** | [App design guidance](https://docs.stripe.com/stripe-apps/design) favors platform consistency and separates contextual content from focused workflows. | Keep routine usage readable; give setup, credentials, and complex explanations appropriate dedicated surfaces. |
| **Raycast** | Its [UI API](https://developers.raycast.com/api-reference/user-interface) provides List/Detail/Form surfaces, contextual keyboard actions, and loading feedback. | Favor scannable rows, fast access, keyboard parity, and useful content during refresh. |
| **Framer** | [Reduced motion settings](https://www.framer.com/help/articles/reduced-motion-settings/) disable movement effects for users preferring less motion. | Animate state feedback purposefully and honor Plasma's animation settings. |
| **Figma** | The [UI3 account](https://www.figma.com/blog/our-approach-to-designing-ui3/) describes revising floating panels and tooltip-dependent state after user feedback. | Spend the small popup's space on information; keep important state and labels discoverable without hover. |
| **Resend** | Its [design handbook](https://www.resend.com/handbook/design/how-we-think-about-design) connects design decisions to code and iteration in the final medium. | Judge polish in actual QML and real states, using shared implementation tokens. |
| **Attio** | [Workspace navigation](https://attio.com/help/reference/productivity-collaborating/navigating-your-workspace) combines contextual quick actions with pointer and keyboard access. | Keep secondary actions contextual and reachable without crowding the quota summary. |
| **Cursor** | The [Cursor 2.0 introduction](https://cursor.com/blog/2-0) organizes the interface around outcomes while retaining deeper access. | Start with available quota, reset, and required action; disclose operational detail when needed. |
| **Supabase** | Its [empty-state pattern](https://supabase.com/design-system/docs/ui-patterns/empty-states) distinguishes initial and zero-result states and considers loading layout shifts. | Give loading, missing setup, unavailable data, and measured zero different meanings and useful next steps. |

Native behavior follows [KDE accessibility guidance](https://develop.kde.org/hig/accessibility/)
and [Qt Quick accessibility guidance (Qt 6.8)](https://doc.qt.io/qt-6.8/accessible-qtquick.html):
standard controls, meaningful semantics, visible focus, keyboard access,
alternate color schemes, larger text, and animation-disabled testing take
precedence over borrowed styling. These references do not call for a new
command palette, sidebar, web animation framework, or branded font in the applet.

## Product principles

1. **Read before acting.** The panel answers which provider needs attention.
   Overview compares providers; a provider page explains its quotas and resets;
   Usage & Spend explains historical activity. Keep setup and diagnostics in
   their administrative surfaces.
2. **Density through alignment.** Align labels, values, tracks, and related
   metadata before shrinking text. Use disclosure for optional detail. Keep
   warnings that affect interpretation visible when their detail is collapsed.
3. **Stable geometry.** Refreshing, selecting a tab, hovering, or changing a
   number must not move neighbouring controls. Preserve focus and scroll
   position where the current interaction contract requires it.
4. **Meaning before decoration.** Provider identity, selection, freshness,
   confidence, and severity are different signals. A brand color must not make
   a healthy quota look critical, and a selected tab must not look exhausted.
5. **Respect the desktop.** Follow the user's font, palette, scale, animation
   settings, and panel orientation. Dark screenshots express the preferred
   reference mood; light and custom Plasma themes remain first-class targets.

## Visual system

Use the existing shared properties in [main.qml](contents/ui/main.qml) and the
theme helpers in [ThemeContrast.js](contents/ui/ThemeContrast.js). Extend a
shared role when a repeated need exists; avoid adding a per-section palette,
font family, radius, or opacity scale.

| Role | Native source or existing token | Design rule |
| --- | --- | --- |
| Canvas and surfaces | `Kirigami.Theme.backgroundColor`, `alternateBackgroundColor` | Let Plasma own the popup chrome. Use subtle surfaces to group controls; avoid a card around every row. |
| Main text | `Kirigami.Theme.textColor`, `defaultFont` | Preserve the user's font. Use normal weight for reading and medium/demibold for meaningful hierarchy. |
| Supporting text | `secondaryTextOpacity` (0.7) | Metadata is quieter, but still readable against the rendered background. This opacity is not a contrast guarantee for custom themes. |
| Supporting values | `valueTextOpacity` (0.85) | Values remain stronger than their labels without competing with primary quota percentages. |
| Selection and focus | Theme `highlightColor`, `highlightedTextColor`, `focusColor` | Keep selected, hovered, pressed, and keyboard-focused states distinguishable. |
| Provider identity | Existing provider icon and readable accent helpers | Keep brands recognizable; use the generic fallback for unknown providers and the existing monochrome policy in Monochrome mode. |
| Severity | Existing quota/status helpers and theme warning/negative roles | Use the configured thresholds and actual status evidence. Never assign a fixed alert hue solely to match a reference site. |
| Spacing | `Kirigami.Units.smallSpacing`, `largeSpacing`, `gridUnit` | Tight gaps bind a label to its value; larger gaps separate providers or tasks. Use the same rhythm in comparable sections. |
| Corners | `roundedSurfaceRadius`, `nestedSurfaceRadius` | Preserve concentric inset rounding; reserve pill geometry for meters and existing compact badges. |
| Tracks | `meterTrackHeight`, `compactMeterTrackHeight` | Detail quotas lead; list-row meters support scanning. Keep parallel tracks aligned. |
| Icons | `Kirigami.Units.iconSizes`, theme action icons | Size the visual glyph independently from its usable button area. Keep provider assets separate from action icons. |
| Motion | `Kirigami.Units.shortDuration`, `longDuration` | Use native durations for feedback and bounded value changes; complete immediately when animations are disabled. |

### Typography and color

Use the theme font throughout. Section titles use the existing heading
components; quota labels use demibold body text; primary quota percentages use
the existing modest enlargement (1.15 times the default point size). Supporting
timestamps, resets, units, and qualifiers use the theme's small font. Avoid
uppercase tracking, oversized dashboard totals, and monospace as a decorative
identity. Request tabular digits for changing percentages, totals, and chart
readouts when the theme font supports them.

Align quota titles, fitting inline resets, and percentages on a shared baseline.
Keep percentages flush with the meter's end. Let long names elide or wrap
according to their role; keep the complete value available through the existing
tooltip and accessible description patterns. Do not shrink text to force a fit.

Target at least 4.5:1 for ordinary text and 3:1 for meaningful non-text controls,
focus indicators, and meter marks against adjacent colors. Measure composited
colors, including opacity and selection tints. The existing accent correction
defaults to non-text contrast; colored text needs the text contrast target.
Decorative hairlines do not carry essential information alone. These targets
adapt [WCAG text contrast](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)
and [non-text contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html)
as design checks; they are not a widget-wide conformance claim.

Keep a restrained neutral base with local provider accents. Use text and icon
meaning alongside severity color. Avoid fixed dark hex palettes, external
fonts, luminous gradients behind data, glass effects inside the popup, and
decorative brand-colored shadows.

## Surface composition

The following is a semantic layout, not literal UI copy or an additional view:

```text
Panel:     provider icon + quota pair   provider icon + quota pair
Popup:     Overview | Usage & Spend | Sessions | provider tabs
           View title / provider identity                 Refresh
           Identity and measurement metadata
           Quota name · reset                         percentage
           [proportional quota track + meaningful markers]
           Pace / confidence / freshness when applicable
           Secondary sections, disclosures, provider actions
Settings:  Preview or context → common choices → advanced options
```

### Panel

Keep Provider colors and Monochrome geometrically consistent. Group each provider's icon
and its primary/secondary capsules; preserve the configured selected-provider
text grouping and custom order. Healthy Monochrome meters use the theme text color;
warning and critical meaning remains visible in both styles. Provider groups
need more separation than elements within a group.

Respect the current horizontal and vertical layouts. Horizontal-only text must
not become a vertical stack of abbreviated labels. A single available quota is
centered; a measured zero keeps an empty track; an absent quota is omitted.
Retain existing tiny-positive-fill safeguards without making a low reading
look substantially filled. Keep the accessible quota description independent
of how few pixels the capsule occupies.

### Popup navigation and provider details

Use one navigation strip. Selection uses the theme's selection/focus language;
the gauge under a provider icon represents usage independently. Overflow gets
reachable scroll controls, and focused tabs reveal themselves immediately.
Preserve manual keyboard activation, stable tab widths, and the existing
standard popup height across populated views. Content scrolls inside the view;
navigation and view headers stay reachable. Empty/setup states may stay compact.

Place provider identity, optional account/plan, measurement time, and refresh
above the quota body. Keep quota label, percentage, and track together. A reset
may sit beside its label only when the complete row fits with its reserved
actions and safety margin; otherwise place it below. Long pace text wraps
without forcing the percentage out of view or oscillating the reset placement.

Group related secondary data under existing disclosures. Keep provider actions
separate from usage facts. Hiding a row changes presentation only; it must not
change fetching, thresholds, notification semantics, or the panel's data.

Keep informational explanations on the canvas rather than inside message
surfaces. Place cost provenance and exclusions in a collapsed disclosure below
the totals; retain amount qualifiers and an explicit partial-data label outside
the explanation. Missing chart history belongs in the chart area. Reserve
message surfaces for failures with recovery actions.

### Overview, history, and sessions

Overview prioritizes provider identity and named quota comparisons. Keep
independent pools visible; a low session value must not obscure an exhausted
weekly quota. Let spacing distinguish providers without surrounding each
number with another surface.

Usage & Spend keeps provider, metric, and range controls above the
scrollable content. Current quotas and reset windows belong in Overview and
provider details. Compact mode stacks the chart and provider rows; expanded
mode can place them side by side. Each provider row discloses its own short,
ranked model list; the provider dropdown owns chart filtering. Keep token
composition in provider details and the activity heatmap in a disclosure.
AI questions stay in a separate, optional disclosure
whose scope is explicitly independent of the chart filters. Totals, dates, and units explain the chart; hover is a preview, and
keyboard selection is a persistent way to inspect a day. Reserve readout space
so inspection does not resize the chart. Keep estimated/partial/unavailable
cost explanations near the figures they qualify, and keep currencies separate.
Use the existing [cost history contract](docs/cost-history.md) for bounds and
selection semantics.

Sessions remain a compact list: name/state first, provider/activity metadata
second. Preserve stable rows during refresh. Do not expose filesystem paths or
turn session rows into unsupported remote-focus actions. Optional AI Insights,
sharing, and identified-token views retain their documented scope and privacy
rules; this guide does not authorize new analysis or data collection.

### Settings

Use PlasmaComponents in the popup and Kirigami/Qt Quick Controls in settings.
Keep the existing settings categories. Prefer native labeled controls,
aligned form rows, concise helper text, and progressive disclosure. The Panel
preview uses the real renderer with synthetic data and stays visible above
scrolling options. Opening advanced options must preserve pending values.

Explain immediate CLI/provider writes separately from Apply/Cancel widget
settings. A visually cleaner flow must not conceal that difference. Keep
destructive credential actions explicit and preserve existing confirmations.
Unavailable contract-backed editors remain unavailable with useful supported
setup or documentation paths.

## Interaction and data states

| State | Presentation | Interaction rule |
| --- | --- | --- |
| First load, no measurement | Compact loading feedback; no invented percentage or zero total | Keep navigation and setup context usable. |
| Refresh with existing data | Keep the current data and refresh button footprint; show bounded busy feedback | Preserve focus; respect existing in-flight guards. |
| Fresh measured zero | Empty quota track or explicit zero amount in the correct unit | Treat zero as data, including in chart inspection. |
| Missing optional data | Omit the optional section or state unavailability where it matters | Do not create a balance meter without an allowance denominator. |
| Retained last-known quota | Identify it as last known with its original measurement age | Preserve cache expiry and account isolation; never imply freshness after a failed retry. |
| Partial provider failure | Keep healthy providers and useful retained measurements visible | Scope the notice and retry action to the actual failure. |
| Offline or timed out | Explain the connection problem near affected data | Preserve documented retry/reconnect behavior and usable local sources. |
| CLI missing / no configured providers | Distinct CLI setup or provider setup message and supported action | Direct users to the correct settings task. |
| Incident or quota warning | Meaningful severity text/icon beside the affected provider or quota | Keep status independent of quota freshness; unknown status is not a recovery. |
| Privacy enabled | Apply the existing redacted presentation to labels, tooltips, copy/share actions, and new notifications | Do not reveal concealed identity through a secondary surface. |

For exact retention, timeout, notification, and privacy behavior, follow the
[usage guide](docs/usage.md#data-freshness). Styling cannot redefine unknown as
zero, infer a price, reconstruct unsupported history, or turn provider prose
into an authentication action. New data and actions require verified released
Linux CLI contracts; record blockers in TODO rather than designing active
controls around speculative fields.

Keyboard access follows the visual task order. Tabs use Left/Right and
Home/End to move focus, then Enter/Space to activate. Keep native Tab/Shift+Tab
navigation through actions and existing chart/heatmap key handling. Every
interactive icon has an accessible name, visible focus, and its action label
available on focus as well as hover. A hover-revealed action must also be
reachable and visible from the keyboard. When disclosure removes a focused
control, return focus to a sensible visible owner.

Animations explain hover, selection, loading, or a measured change. Keep
keyboard focus reveal immediate. Avoid entrance choreography, bounce, pulsing
healthy quotas, and count-up totals that delay reading. Disabled animations
must preserve the same final state and feedback without waiting for motion.

## Applying and reviewing a UI change

Read the owning component, normalization/presentation helper, config schema,
and nearest regression check before changing a surface. Keep effects in the
owning QML page and non-trivial pure decisions in focused JS modules, following
[the implementation reference](docs/implementation.md#ownership-and-implementation). Do not install
web component systems or translate website CSS into QML.

A visual change is reviewable when the relevant checks demonstrate:

- The main task is readable before disclosure; optional detail and warnings
  have clear priorities.
- Breeze Light, Breeze Dark, and a custom palette preserve text, focus, meter,
  and severity distinctions. Inspect composed colors, not just token values.
- Narrow layouts, enlarged fonts, right-to-left layout, fractional scaling,
  long translations, and long untrusted labels preserve controls and values.
- Panel changes work horizontally and vertically, at the small panel sizes and
  content combinations covered by the existing panel matrix.
- Pointer and keyboard paths both work, focus survives refresh, and disabling
  animations preserves completion. Check assistive names/roles and descriptions.
- Relevant empty/loading/error/stale/partial/zero/privacy states match their
  semantic meaning; an optional failure does not erase healthy data.
- Synthetic before/after captures and applicable QtTests or wiring checks
  support the change. Screenshots do not prove keyboard or screen-reader behavior.

Use existing checks such as `tst_theme_contrast.qml`, `tst_usage_row_layout.qml`,
`tst_popup_tab_strip.qml`, and `tst_interactive_chart.qml` for their respective
contracts. Follow [runtime verification](docs/runtime-verification.md#runtime-verification),
the [panel matrix](docs/smoke-tests.md#panel-configuration-matrix), and
`make check` as applicable. State actual failures, skipped checks, and unavailable
tools. Keep temporary review captures in ignored `dist/review/`; update the
maintained guides and synthetic product images only when delivered behavior
changes.
