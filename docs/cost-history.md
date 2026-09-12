# Cost history and daily models

The provider popup shows Today and the selected period side by side. History,
period models, and projects expand on demand. Cost errors and pricing notices
remain visible when the details are collapsed.

## Data and display rules

- Day models come from the selected `cost.daily[].modelBreakdowns[]` record.
  Missing day models never fall back to period totals.
- Display at most six models per day and report truncation. Period models also
  expose truncation and an explicit empty state.
- Missing costs and token counts remain unknown. Measured zero stays zero;
  filling calendar gaps only fills metrics actually observed in the snapshot.
- The global activity heatmap preserves calendar gaps between measured days.
  Unavailable days occupy empty cells, so filtering missing amounts never shifts
  weekday rows. Its visible span and week count include those gaps, bounded to
  the newest 365 calendar days. Legacy non-date labels retain sequence order.
- Model names are strings. Numeric names are not coerced into display labels.
  Tied model amounts use the label as a stable ordering tiebreaker.
- Standard/Fast totals remain blocked on an official CLI contract. No service
  tier is inferred from model names or amounts.

These rules are implemented in
[ProviderNormalizer.js](../contents/ui/ProviderNormalizer.js),
[CostPresentation.js](../contents/ui/CostPresentation.js), and
[ProviderCostSection.qml](../contents/ui/components/ProviderCostSection.qml).

## Selection rules

Hover previews stay inside the chart. Pointer or keyboard selection pins a day
without fetching data. A background refresh retains the pinned date even when
its chart position changes; a missing or ambiguous date clears the pin.
`sourceIndex` cannot identify a day across different snapshots.

Provider, account, and history range changes clear the pin and expanded details,
including when cached data is reused. Account identity follows the account
picker's canonical label, including organization-only identities. Metric changes
clear the pin but preserve explicitly expanded period details. Period efficiency
stays in the period view, available through All days; it is not shown as a daily
figure. A single measurable day remains selectable to inspect its models.

## History, trust, and project totals

`costHistoryMetric` selects cost or tokens across charts from the same loaded
payload; the selected metric also controls bar scaling. Metric and day selection
must not add CLI calls. `historyCoverageIsEstablished` controls the collecting
history notice; a missing flag counts as established for legacy payloads.

`ProviderNormalizer.normalizeCostTrustMetadata` bounds `coverage` and `provenance`.
`CostPresentation.costTrustSummary` qualifies provider and global amounts with
one shared notice. Missing legacy metadata stays quiet. Keep pricing coverage
separate from history collection coverage and never expose raw provenance in QML.

`normalizeCostProjects` retains bounded names and optional amounts, discarding
paths and nested source records. Preserve unknown amounts and duplicate names;
keep provider currencies separate. Signal truncation at 128 inspected projects
per provider or 128 displayed rows overall. Project rows never contribute to
provider or global totals. The [usage guide](usage.md#costs-and-history) describes
the range/metric controls and expandable presentation.

Official CLI 0.56.2 emits Antigravity token-only history through the generic cost
envelope. Absent costs stay absent in daily/model normalization. Its established
empty snapshot uses zero dollar totals despite costs being unavailable, so
`normalizeProviderCostTotals` masks that provider sentinel until an official
availability field exists. Token charts remain usable while cost totals and
cost-mode charts stay unavailable. Cursor cost is rejected by that Linux release;
neither case authorizes provider fetching or source parsing in QML. The scoped
[0.57.0 probes](research/2026-09-09-macos-parity-0.57.0.md#scoped-official-linux-probes)
confirm Cursor is still rejected; they do not retest established-empty
Antigravity history.

Track [explicit cost availability](../TODO.md#cost-availability),
[Cursor Linux cost](../TODO.md#cursor-cost), and
[service-tier totals](../TODO.md#service-tier-totals) in TODO.

## Pinned CLI evidence

The scoped implementation used official CodexBar v0.56.8, commit
`6ef82690b4a718a21fac42b72a102df07e475509`, and its
[`CLICostCommand.swift`](https://github.com/steipete/CodexBar/blob/6ef82690b4a718a21fac42b72a102df07e475509/Sources/CodexBarCLI/CLICostCommand.swift).
The existing daily model fields are `modelName`, `cost`, and `totalTokens`.
This adds no command or provider-specific source and does not replace the full
[0.56.2 parity baseline](research/2026-09-01-macos-parity-0.56.2.md).

The official Linux x86_64 release archive was checksum-verified with SHA-256
`ab98788e12840e5689ae505bf62731e0ea0db1c77e63dceda1589b6e795ac5b8`.
An isolated probe with two synthetic days and two models ran
`cost --provider codex --days 7 --format json --json-only --refresh --provider-native-only`
without network access. It exited 0 with empty stderr. The fixture and recorded
output are linked in the
[historical probe report](https://github.com/Lucenx9/codexbar-plasma/blob/92679f99ce5d5479f4f87edde051fff91e30b91f/docs/reviews/popup-cost-details/README.md).

## Regression coverage

[Normalizer tests](../tests/tst_provider_normalizer.qml) and
[presentation tests](../tests/tst_cost_presentation.qml) cover the data rules.
The popup smoke scenarios cover pinned-day refreshes, reordering, missing days,
cached account changes, ranges, missing token counts, and incomplete models.
Run `make check` for logic and wiring, and `make smoke` for the real applet with
synthetic data. Executed check results belong in the PR.
