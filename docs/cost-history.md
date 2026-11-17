# Cost history and daily models

This reference owns cost normalization, selection, trust, and identified-request
contracts. The [usage guide](usage.md#costs-and-history) describes the controls;
[implementation](implementation.md) describes process ownership.

## Global analysis

`UsageAnalysis.js` projects normalized snapshots into Usage & Spend without new
CLI calls, price sources, or account attribution. Provider filters scope costs,
tokens, models, and the heatmap. A pinned day scopes the detail rows, while
headline totals retain the selected period. Projects remain in provider details.

Aggregation inspects up to 256 snapshots. The separate 128-series drawing bound
does not limit total validation. Missing or duplicate dates are unavailable;
a duplicate in any metric-eligible provider invalidates that day's aggregate
readout and pin. Foreign-currency providers cannot invalidate a money readout
they do not contribute to. Healthy provider lines remain visible.

`ChartLines.mjs` preserves calendar spacing, breaks lines at unavailable dates,
and uses monotone curves without new extrema. Time runs oldest to newest from
left to right in both layout directions. Currency selection precedes visual
provider ordering. Model rankings are computed separately for cost and tokens
before the six-model cap; privacy removes names while retaining both rankings.
Expanded rows survive refreshes and day selection without fetching data.

Weekly comparisons require fourteen complete days before today, a scan reaching
today, unambiguous dates, and finite amounts. Money also requires complete
pricing; unpriced history can still support a token comparison. Excluded
incomplete requests invalidate either comparison. Comparisons never fetch extra
history. Arithmetic uses unrounded weekly sums, including sub-cent values;
displayed money and AI payloads round to cents. Numeric comparisons survive
privacy projection. Model lists share a 128-row bound and mark truncation.

Current quotas remain independent of history filters. With local history
disabled, AI Insights can use current quotas without starting a cost scan.

## Provider details

Today means the local date of the CLI scan's `updatedAt`. If a retained snapshot
was scanned before today, its Today amounts become unavailable, including after
a failed refresh. Legacy snapshots without usable `updatedAt` retain their
Today amounts. Refresh errors and cost qualifiers remain visible beside
retained totals even when history details are collapsed.

## Data and display rules

The owning code is [ProviderNormalizer.mjs](../contents/ui/ProviderNormalizer.mjs),
[CostPresentation.mjs](../contents/ui/CostPresentation.mjs), and
[ProviderCostSection.qml](../contents/ui/components/ProviderCostSection.qml).

- Duplicate provider IDs prefer measured amounts, including zero, over an
  empty snapshot, then retain the first successful measurement. Failed siblings
  report errors without erasing successful amounts.
- Missing amounts remain unknown; measured zero stays zero. Calendar gap filling
  applies only to metrics observed in the snapshot. Duplicate dates, malformed
  rows, or a truncated scan prevent zero-day inference while preserving observed
  rows inside the selected period.
- Calendar keys must be `YYYY-MM-DD` strings. Impossible calendar dates are
  excluded from daily amounts and model totals; they still prevent zero-day
  inference. Objects and arrays cannot extend a range. Bounded non-date legacy
  labels retain sequence behavior and use aggregate bars in Usage & Spend.
- Day models come only from the selected daily record's `modelBreakdowns`, never
  period totals. Daily models are projected after calendar selection and row
  limits. Average-only rows skip that projection. Display at most six models
  per metric per day and mark truncated or empty model lists.
- **Month to date** and **All history** use CLI `cost --period`. String
  `reportingPeriod` identifies the range independently of its growing day count;
  malformed values retain the bounded legacy-label/day-range fallback.
  `--period all` reports days since year 1, so the frontend derives the window
  from the oldest eligible date through the scan date. Future dates cannot
  extend it. Without a usable scan date, recorded dates define the span.
- Charts and daily rows retain at most 365 days. Period models and averages use
  the full span within a 2,048-input-record scan budget; CLI totals retain their
  full scope. Sparse histories count eligible zero-activity dates without
  allocating a row per date. A date with any amount-bearing row is covered even
  if a sibling row has no amounts. Duplicate, unknown, or truncated input still
  prevents zero inference.
- Averages divide only measured days. A measured zero range averages to zero;
  an unmeasured range has no average. An incremental mean handles finite inputs
  whose sum overflows. Cost-per-million-token rates preserve finite results
  without overflowing intermediate scaling. Unrepresentable rates are omitted
  without changing underlying totals.
- Global and daily sums outside the numeric range are unavailable. Overflow in
  one date or metric leaves other dates, measured zeros, and the other metric
  usable. Bar scaling preserves finite proportions for large values.
- The recent-history list shows the newest seven days and both available
  amounts; the selected metric controls filtering and scaling. Its peak names
  the highest visible day. Local-history summaries, rows, chart readouts, and
  derived averages/rates show positive sub-cent costs as explicit
  less-than-one-cent text rather than zero. Partial quota-week sums retain their
  numeric sub-cent precision because they are lower bounds, not complete amounts.
  Live provider balances retain
  two-decimal money formatting; raw amounts and aggregate arithmetic are unchanged.
- The heatmap uses unfiltered calendar dates, preserving gaps and incomplete
  boundary weeks. It spans at most 365 days, follows the locale's first weekday,
  and is hidden for spans of seven days or fewer. Zero days are selectable;
  unavailable days are not. Non-date legacy labels retain unlabelled sequence
  rows. Month labels appear only when they fit their calendar span.
- Model names must be strings and break tied amounts by label. Sharing ranks
  tokens from the full bounded period aggregation before the six-row cost cap,
  retaining cheap and unpriced models, omitted-row counts, and incomplete-scan
  markers through privacy projection.
- Standard/Fast totals require an official CLI contract. Model names and amounts
  cannot establish a service tier.

## Selection rules

The account picker selects usage quotas. Local cost history is the CLI's scan
for the provider and range, independent of that picker. Usage labels cannot
establish account attribution.

A pin identifies a calendar date, never `sourceIndex`. Refreshes retain it as
rows move; a missing or ambiguous date clears it. Month-to-date and All-history
ranges retain their identity as the day count grows. Metric and day selection
operate on loaded data without CLI calls.

In provider details, provider, account, or range changes clear the pin and
expanded period details, including when cached data is reused. Metric changes
clear the pin but preserve explicitly expanded period details. In Usage & Spend,
range or metric changes clear both selected and hovered dates. Period efficiency
remains a period value, never a daily figure.

Pointer, keyboard, and calendar activation share the selected day. Chart Escape
or All days clears it and retains chart focus. Calendar arrows inspect, while
Enter, Space, or accessibility activation pins a measured day. Calendar Escape
clears a pin first; with no pin it propagates to close the popup. Hover previews
stay inside the plot and scroll viewport, with full detail available by pinning.

## History, trust, and project totals

`costHistoryMetric` changes chart scaling and amount order from the same payload.
`historyCoverageIsEstablished` qualifies history completeness independently of
pricing coverage; legacy payloads without it remain supported.

`normalizeCostTrustMetadata` bounds `coverage`, `provenance`, and
`incompleteRequestCount`. `CostTrust.costTrustSummary` supplies semantic notices;
raw provenance never reaches QML. Missing legacy metadata stays quiet.
Closing a notice records its semantic dismissal. Collapsing it, hiding a tab,
or recreating the popup does not. A changed count alone cannot revive a dismissed
warning. A different provider or semantic warning collapses its explanation.

Excluded incomplete requests qualify tokens even if money is unavailable or
the pricing notice was dismissed. Unpriced costs alone do not make measured
tokens partial. Today uses only the matching day's exclusion count; stale-day
suppression applies after midnight, including in privacy mode. Quota-week
subtotals remain partial for stale trailing days, a last day scanned before
today, or days with excluded requests. New usage quotas cannot establish missing
cost history.

Money notices and totals use one currency. Foreign-currency snapshots with
finite costs are excluded from that pricing notice, though their tokens can
contribute to the token total. `CostTrust.incompleteTokenRequests` separately
sums bounded exclusions for positive token totals across all currencies.
Daily-only cost data cannot create a notice about a range total.

`CostCurrency.spendCurrency` selects the first measured currency in displayed
provider order, testing totals before daily rows. Zero counts as measured;
token-only metadata cannot override a measured currency. Fallbacks are existing
totals, then the first daily row, then USD. Daily rows without a currency default
to USD; totals without one inherit the selected currency. Privacy validates
currencies as three uppercase letters, including whole-range averages. An
invalid average currency suppresses money without suppressing token averages.

Official CLI 0.60.5 emits `incompleteRequestCount` on payloads, totals, days,
and model breakdowns, omitting it when nothing was excluded. It counts requests
without final usage, not an amount to add back. Aggregate counts within the
coverage bound, including model breakdowns without amounts. A fully incomplete
day omits `totalCost` and `totalTokens`, so it remains unknown. Counts survive
privacy projection.

`normalizeCostProjects` retains bounded names and optional amounts, preserving
unknown values and duplicate names while discarding paths and nested source
records. It inspects at most 128 projects per provider and displays at most
128 rows overall, marking truncation. Projects never contribute to provider or
global totals, and provider currencies remain separate.

Antigravity's established empty token-only snapshot uses zero dollar totals even
when costs are unavailable. `normalizeProviderCostTotals` masks that sentinel
until an official availability field exists. Muse Code also supplies token-only
history with monetary fields absent. Keep absent costs unavailable and tokens
usable. No frontend provider fetching or source parsing is authorized by these
shapes. Remaining blockers are [cost availability](../TODO.md#cost-availability),
[Cursor cost](../TODO.md#cursor-cost), and
[service-tier totals](../TODO.md#service-tier-totals).

## Identified-request subtotals

The manual [identified Codex section](usage.md#identified-codex-token-subtotal)
has its own [decoder](../contents/ui/IdentifiedTokens.js) and
[controller](../contents/ui/controllers/IdentifiedTokensController.qml).
It starts only on an explicit local or local + SSH action. Context changes,
timeouts, and destruction retire requests without replacements. Ordinary
history, charts, sharing, and AI Insights neither start nor consume these scans.

The decoder validates the exact UTC window, schemas 1 and 2, safe integer
counts, and at most 50,000 records or conflict IDs per ledger. The shared 4 MiB
frontend JSON limit is stricter than the CLI's 32 MiB transport limit; oversized
results are unavailable, never truncated. Duplicate IDs and unsafe sums are
rejected. Only aggregate counts and the optional API-price estimate leave the
decoder. Unknown or mixed schemas have a separate compatibility outcome.
Schema 2 validates optional model/pricing-mode fields and requires
`includedInPlan`, without calculating prices.

A local ledger sums input plus output outside `conflictingIDs`. With SSH, the
CLI owns deduplication. The frontend validates reports and the emitted subtotal;
a single available source must match its own aggregate. Exit 1 can retain an
available source, while exit 0 can still exclude requests. Availability and
request completeness are independent. With no source, `subtotal` may be omitted.
Only one requested SSH host is accepted; extra or unrequested reports fail.

For schema 2 envelopes, `costUSD` becomes separate `apiEstimateUSD`, never a
cost-history total or account-wide amount. `unpricedRequestCount` is a safe
integer no greater than accepted requests. A non-null estimate is finite,
nonnegative, and requires no unpriced requests; null requires at least one.
An empty known subtotal has a zero estimate. Bare local ledgers and schema 1
expose neither estimate nor unpriced count.

GNU `timeout` sends TERM at 110 seconds and KILL after five more, before the
120-second controller deadline. A waiting shell preserves supervision after
Plasma disconnects its source. Missing `timeout` fails closed.

## Pinned CLI evidence

These scoped checks do not replace the
[0.56.2 full audit](research/2026-09-01-macos-parity-0.56.2.md).

- [0.84.0 review](research/2026-11-10-macos-parity-0.84.0.md), 2026-11-10:
  official Linux 0.83.0 and 0.84.0 both emitted one schema 2 request with 111
  tokens. A symlinked `sessions` root instead emitted an empty ledger with
  `partial: false`, an undetectable omission still
  [CLI-blocked](../TODO.md#identified-history-discovery). Ordinary costs regain
  symlinked history in 0.84.0. Absent OpenCode Go history omits amounts rather
  than reporting zero.
- [0.83.0 review](research/2026-11-01-macos-parity-0.83.0.md), 2026-11-01:
  glibc x86_64 archive SHA-256
  `e278eb0a1b6d620b5c84c157dfb16860a82477af6ec7330b6b6fb5c7f2729b5b`.
  Bubblewrap hid host data, cleared the environment, and disabled networking.
  A synthetic request emitted 1,100 tokens with `model: "gpt-5"`,
  `pricingMode: null`, and `includedInPlan`. A synthetic SSH executable verified
  deduplication, source metadata, `costUSD: null`, and `unpricedRequestCount: 1`.
  No real SSH, authenticated data, or nonzero estimate was verified. The pinned
  [`CodexRequestSubtotal` contract](https://github.com/steipete/CodexBar/blob/348e2fa8d36ae8e452739ca07a79e83ab9d25e98/Sources/CodexBarCore/Providers/Codex/CodexRequestLedger.swift)
  defines an API-equivalent estimate over accepted requests.
- Official Linux 0.76.0, source commit
  `2d8b1409a1649dce60f3610ebe4eab52b92545de`, checked 2026-10-18 under hidden
  homes, an empty environment, and disabled networking. The binary matched the
  checksum-verified [0.76.0 review](research/2026-10-15-macos-parity-0.76.0.md).
  `cost --provider codex --account synthetic-account --format json --json-only`
  exited 1 with `Unknown option --account` (`kind: args`).
  [Account-scoped costs](../TODO.md#account-scoped-local-costs) remain blocked.
- [0.75.0 verification](research/2026-10-15-codex-contracts-0.75.0.md): native
  mixed priced/unpriced history retains priced USD subtotals and measured
  tokens; fully unpriced history omits money. Synthetic historical scanner-cache
  rows verify known-model partial subtotals; imported incomplete rows remain
  unverified. Identified local/SSH subtotals had no prices at this version.
- [0.72.0](research/2026-10-05-macos-parity-0.72.0.md#linux-cli-contract-changes-since-0690)
  and [0.69.0](research/2026-09-29-macos-parity-0.69.0.md#linux-cli-contract-changes-since-0670):
  `--period all` still reports days since year 1 (739896 on 2026-10-05 and
  739890 on 2026-09-29). Scanner fixes do not remove the 365-day frontend bound.
- [0.67.0 review](research/2026-09-26-macos-parity-0.67.0.md#linux-cli-contract-changes-since-0660):
  `reportingPeriod` is `rolling:N`, `month-to-date`, or `all`, with an English
  `historyLabel`. Plasma localizes rolling ranges and uses CLI labels for others.
- [0.62.0 probes](research/2026-09-20-macos-parity-0.62.0.md#scoped-official-linux-probes):
  a Muse Code `model_completed` turn produced exact session/daily/model tokens
  with all money absent. Checksum-verified asset SHA-256:
  `11b88fef999f18cd7fd8b52e52a7fb3eb90e84eaf9fc98a1d4bc5d4170353513`.
  Cursor costs remained rejected, as in the
  [0.57.0 probes](research/2026-09-09-macos-parity-0.57.0.md#scoped-official-linux-probes).
  Neither check retested Antigravity's established-empty sentinel from 0.56.2.
- [0.60.5 probes](research/2026-09-18-macos-parity-0.60.5.md#scoped-official-linux-probes):
  verified emitted incomplete-request counts and their omission semantics.
- Official v0.56.8, commit `6ef82690b4a718a21fac42b72a102df07e475509`:
  [`CLICostCommand.swift`](https://github.com/steipete/CodexBar/blob/6ef82690b4a718a21fac42b72a102df07e475509/Sources/CodexBarCLI/CLICostCommand.swift)
  emits daily `modelName`, `cost`, and `totalTokens`. The Linux x86_64 archive
  matched SHA-256 `ab98788e12840e5689ae505bf62731e0ea0db1c77e63dceda1589b6e795ac5b8`.
  An isolated two-day/two-model probe ran
  `cost --provider codex --days 7 --format json --json-only --refresh --provider-native-only`
  without networking, exiting 0 with empty stderr. Its
  [fixture and output](https://github.com/Lucenx9/codexbar-plasma/blob/92679f99ce5d5479f4f87edde051fff91e30b91f/docs/reviews/popup-cost-details/README.md)
  remain in history.

## Regression coverage

Data entry points are [normalizer](../tests/tst_provider_normalizer.qml),
[presentation](../tests/tst_cost_presentation.qml), and
[response](../tests/tst_cost_response.qml) QtTests. The
[controller tests](../tests/test_cost_context.py) exercise real CLI lifecycles.
Run `make check` for logic and wiring, and `make smoke` for synthetic applet
scenarios. Follow [testing](testing.md) for check selection; put executed results
in the PR.
