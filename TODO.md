# Linux parity TODO

This is the current list of useful Linux/Plasma work relative to the official
CodexBar macOS app. The agent updates it with every new stable upstream release
and every change that implements or invalidates an entry. Follow
[release maintenance](docs/development.md#upstream-release-maintenance).
Issues linked below preserve discussion; this file owns parity status.

## Review baseline

- Last release reviewed: [CodexBar 0.57.0](https://github.com/steipete/CodexBar/releases/tag/v0.57.0),
  commit `45cda6084d6415795053624b80ca3f8c05026580`, checked 2026-09-09.
- Coverage: release changes from 0.56.2 through 0.57.0 against Plasma
  `3e818ae71dda1ccada2e8f8d662bb883c21d4da9`.
  The [review](docs/research/2026-09-09-macos-parity-0.57.0.md) records the
  intervening releases, source comparisons, and scoped Linux 0.57.0 probes.
- Full CLI baseline remains the [0.56.2 audit](docs/research/2026-09-01-macos-parity-0.56.2.md).
  Later probes verify only their named cases. Older blockers below retain their
  last verified version; source inspection is not authenticated output evidence.

## Implementable on Linux

### Spend freshness

- [ ] Refresh stale Usage & Spend data on tab revisit and calendar-day changes.
  Use the existing `cost` command and `CostRefreshPolicy.js`; preserve cached
  charts, in-flight guards, and failed-attempt cooldowns. Done when a stale view
  refreshes on return and across midnight without scans on metric/day selection.
  Evidence: [0.57.0 comparison](docs/research/2026-09-09-macos-parity-0.57.0.md#refresh-stale-spend-views-when-revisited).

## Blocked on official Linux CLI contracts

These are useful Linux features once the named contract exists. Do not fill
these gaps with provider scraping, auth flows, or config parsing in QML.

### Provider settings

- [ ] Enable generic settings and token-account editing through official
  descriptors and writes. Linux 0.57.0 still rejects `config providers
  --descriptors`; its provider records have no descriptor. Keep existing
  enable/disable, supported single-key setup, and link fallbacks working.
  The [proposal](docs/cli-provider-settings-descriptor.md) covers source mode,
  keys/cookies, URLs, workspace/project, region, AWS profile/auth mode, and
  booleans. Remaining editors include token accounts, auth nuances,
  organization/team, metric, per-provider thresholds, and Fireworks multi-account
  slug editing. Done when the named controls have released generic contracts
  and tested Plasma support. [Prior discussion #167](https://github.com/Lucenx9/codexbar-plasma/issues/167).

### Provider onboarding

- [ ] Add CLI-described browser-cookie import, local-file setup, OAuth/device
  flow, CLI-auth setup, and token-account actions. Linux 0.57.0 still has no
  generic `config action` command. Done when supported actions expose validated
  prompts/results and handle cancellation, failure, and stale responses in
  Plasma. Preserve current key/link setup. [Prior discussion #168](https://github.com/Lucenx9/codexbar-plasma/issues/168).

### Rich usage and credit allowances

- [ ] Consume generic billing/pricing details, richer model/request/token usage,
  credit allowances, and unknown-usage windows with reset metadata. These gaps
  were verified at 0.56.2; authenticated 0.57.0 cases remain unverified.
  Existing generic details/charts work. Done when each additional section has
  bounded official fields and tests, with unknown amounts distinct from zero.
  Plain credit balances need their own allowance before gaining a meter; the
  Codex monthly-cap denominator is not generic. [Prior discussion #169](https://github.com/Lucenx9/codexbar-plasma/issues/169).

### History and forecasts

- [ ] Display credit history, plan-utilization history, hourly activity, and
  session-equivalent forecasts when official history/forecast fields supply units
  and missing-data semantics. Last verified at 0.56.2. Done when supported histories have bounded
  normalization and views; retain any remaining types here. Never reconstruct
  history or session conversion rates from a current snapshot.
  [Prior discussion #170](https://github.com/Lucenx9/codexbar-plasma/issues/170).

### Cursor cost

- [ ] Show Cursor cost history through the generic Linux `cost` path. Linux
  0.57.0 still rejects Cursor and lists Antigravity, Claude, and Codex as supported.
  Done when a released Linux command emits supported cost data and Plasma tests
  cover its amounts, currencies, and trust metadata.
  [Prior discussion #171](https://github.com/Lucenx9/codexbar-plasma/issues/171).

### Service-tier totals

- [ ] Show Standard/Fast totals from explicit official tier fields. The scoped
  0.56.8 daily-model check established no service-tier contract. The 0.57.0 empty
  cost probe does not establish one either. Done when official Linux output
  identifies tiers and bounded amounts with tested legacy fallback. Never infer
  tier from models, prices, or tokens. [Cost evidence](docs/cost-history.md#pinned-cli-evidence);
  [prior discussion #172](https://github.com/Lucenx9/codexbar-plasma/issues/172).

### Cost availability

- [ ] Replace the Antigravity-specific unknown-cost fallback with explicit
  official availability metadata. At 0.56.2, established-empty history used zero
  despite unavailable costs. The 0.57.0 fresh-history probe omits amounts, but
  does not verify that established-empty case. Done when verified Linux fields
  distinguish unavailable from measured zero, with old-payload compatibility and
  usable token charts. [Prior discussion #173](https://github.com/Lucenx9/codexbar-plasma/issues/173).

### Structured localization

- [ ] Localize opaque provider/incident/error/reset text and pace headroom through
  official identifiers or typed fields. The remaining contract gap is carried
  from 0.56.2; authenticated 0.57.0 output has not been exhaustively rechecked.
  Known states and structured pace forecasts already translate. Done when
  supported fields use catalogs with placeholder/plural checks and bounded
  unknown-value fallbacks. [Translation guide](docs/translations.md);
  [prior discussion #174](https://github.com/Lucenx9/codexbar-plasma/issues/174).

### Display currency

- [ ] Offer display-currency selection and conversion through an official Linux
  contract. The 0.56.2 audit records no display-currency setter or descriptor;
  the scoped 0.57.0 config probes still expose neither. Plasma currently
  displays the CLI-emitted currency. Done when released settings and converted
  amounts define currency, rate provenance, and unavailable-conversion behavior,
  with tested Plasma selection/display. Keep conversion and exchange-rate
  acquisition in the CLI and preserve separate currencies until then.
  [Pinned blocker](docs/research/2026-09-01-macos-parity-0.56.2.md#blocked-on-an-official-linux-cli-contract).

### Automatic balance text

- [ ] Show a typed money/points balance when automatic panel text has no quota.
  macOS 0.57.0 uses provider-specific prose parsing for several cases. A generic
  official Linux amount, unit/currency, and availability contract is missing.
  Done when the widget can display that record without parsing provider text,
  overriding a real quota, or treating a balance as an allowance.
  [Source comparison](docs/research/2026-09-09-macos-parity-0.57.0.md#automatic-balance-text-needs-a-generic-contract).

## Verify before accepting implementation work

These are unresolved Linux candidates, not confirmed missing features.

- [ ] Verify `credits.balanceReadSucceeded` and separate purchased-balance
  freshness in official Linux output. 0.57.0 source encodes the flag, while
  Plasma currently reads `remaining` without it. Reproduce failed reads,
  confirmed zero, and cap-only data safely, then classify and specify the
  normalization change. [Source evidence](docs/research/2026-09-09-macos-parity-0.57.0.md#source-observed-contract-change-requiring-output-verification).
- [ ] Compare exhausted automatic text/popup quota selection with the exact
  0.56.6 cases. Automatic panel capsules already show primary and secondary.
  Keep direct lane choices and independent quota pools. Accept a change only
  after reproducing a useful difference with existing Linux fields.
  [Comparison](docs/research/2026-09-09-macos-parity-0.57.0.md#review-automatic-exhausted-quota-selection).
- [ ] Verify account identity and stale-data behavior against the 0.56.3–0.57.0
  changes: same-email workspaces, measurement timestamps, and transient
  multi-account failures. Compare official Linux records with Plasma account
  selection/cache tests before classifying a gap; retain CLI ownership of
  credential matching and recovery. Generic failed-refresh retention and redacted
  quota restoration are implemented; account identity and credential recovery
  cases still need the named official CLI probes.
  [Release coverage](docs/research/2026-09-09-macos-parity-0.57.0.md#release-coverage).
- [ ] Evaluate the weekly reserve indicator against a pinned macOS behavior and
  an official Linux field. Record accept/reject and, if accepted, a concrete
  display contract. Existing quota lanes and run-out forecasts are implemented.
  [Prior discussion #175](https://github.com/Lucenx9/codexbar-plasma/issues/175).
- [ ] Decide whether reset-imminent notices add value beyond current quota, pace,
  and completed-reset notices. Accept only quiet, opt-in, transition-based
  behavior backed by official timing data; otherwise remove the candidate.
  [Prior discussion #176](https://github.com/Lucenx9/codexbar-plasma/issues/176).

## Scope and completed behavior

The [usage guide](docs/usage.md) describes implemented Plasma behavior, including
panel composition with automatic dual-quota capsules and vertical provider meters,
settings preview/privacy, grouped panel text and expandable Panel options, local
sessions, notifications, and
interactive cost/token charts. Claude 0.57.0 `--breakdown` is text-only; existing
JSON daily/model views already consume its underlying data.

macOS-only features do not enter this backlog. The [release review](docs/research/2026-09-09-macos-parity-0.57.0.md#excluded-from-the-linux-backlog)
records exclusions. Provider parsing, pricing, authentication, and scanning
fixes are CLI-owned; a new upstream implementation is not a missing QML port.
