# Linux parity TODO

This is the current list of useful Linux/Plasma work relative to the official
CodexBar macOS app. The agent updates it with every new stable upstream release
and every change that implements or invalidates an entry. Follow
[release maintenance](docs/development.md#upstream-release-maintenance).
Issues linked below preserve discussion; this file owns parity status.

## Review baseline

- Last release reviewed: [CodexBar 0.60.5](https://github.com/steipete/CodexBar/releases/tag/v0.60.5),
  commit `2ac2323629ce0e3b3759707013aeb4a6c77161c1`, checked 2026-09-18.
- Coverage: release changes from 0.59.0 through 0.60.5 against Plasma
  `c69b0a0481bbf2373087658f620e0ffeab854429`. The
  [0.60.5 review](docs/research/2026-09-18-macos-parity-0.60.5.md) verifies the
  new cost `incompleteRequestCount` contract in official Linux output; the
  [0.60.4 review](docs/research/2026-09-16-macos-parity-0.60.4.md) records the
  earlier release delta and source comparison. Usage JSON schemas are
  unchanged; shared payload structs gained optional credit-availability and
  detail-row fields awaiting authenticated output evidence.
- Full CLI baseline remains the [0.56.2 audit](docs/research/2026-09-01-macos-parity-0.56.2.md).
  Later probes verify only their named cases. Older blockers below retain their
  last verified version; source inspection is not authenticated output evidence.

## Implementable on Linux

### Incomplete cost requests

- [ ] Mark the individual history and model rows whose requests the CLI
  excluded, now that the range total says how many were left out. The official
  counts also arrive per `daily[]` entry and per `daily[].modelBreakdowns[]`
  record, while the popup rows still read as complete measurements. Done when a
  row states its excluded requests without parsing display text, keeps measured
  and unknown amounts distinct, and stays legible in the narrow popup.
  Evidence: [0.60.5 review](docs/research/2026-09-18-macos-parity-0.60.5.md#linux-cli-contract-changes-since-0604).

### Popup usage row visibility

- [ ] Hide and restore individual popup usage rows per provider, mirroring the
  macOS 0.58.0 visible-row choice as a Plasma-local display preference. Panel
  rows already have visibility rules; popup provider cards expose only fixed
  section toggles, and no CLI contract is required. Done when rows can be
  hidden and restored without affecting fetching, alerts, or the panel, with
  the choice persisted and previewed in settings.
  Evidence: [0.58.0 comparison](docs/research/2026-09-11-macos-parity-0.58.0.md).

## Blocked on official Linux CLI contracts

These are useful Linux features once the named contract exists. Do not fill
these gaps with provider scraping, auth flows, or config parsing in QML.

### Provider settings

- [ ] Enable generic settings and token-account editing through official
  descriptors and writes. Linux 0.60.4 still rejects `config providers
  --descriptors` (69 records, same four keys); its provider records have no
  descriptor. Keep existing
  enable/disable, supported single-key setup, and link fallbacks working.
  The [proposal](docs/cli-provider-settings-descriptor.md) covers source mode,
  keys/cookies, URLs, workspace/project, region, AWS profile/auth mode, and
  booleans. Remaining editors include token accounts, auth nuances,
  organization/team, metric, per-provider thresholds, and Fireworks multi-account
  slug editing. Done when the named controls have released generic contracts
  and tested Plasma support. [Prior discussion #167](https://github.com/Lucenx9/codexbar-plasma/issues/167).

### Provider onboarding

- [ ] Add CLI-described browser-cookie import, local-file setup, OAuth/device
  flow, CLI-auth setup, and token-account actions. Linux 0.60.4 still has no
  generic `config action` command (`set-api-key` remains the sole writer).
  Done when supported actions expose validated
  prompts/results and handle cancellation, failure, and stale responses in
  Plasma. Preserve current key/link setup. [Prior discussion #168](https://github.com/Lucenx9/codexbar-plasma/issues/168).

### Rich usage and credit allowances

- [ ] Consume generic billing/pricing details, richer model/request/token usage,
  credit allowances, and unknown-usage windows with reset metadata. These gaps
  were verified at 0.56.2; authenticated cases remain unverified through 0.60.4.
  Source-observed but unverified at 0.60.4: `creditsAvailable`/`balanceIsWorkspace`
  on `credits` and `openaiDashboard`, Copilot seat-entitlement rows with stable
  IDs, and `details` rows carrying `progress`/`usageValue` (Copilot, Antigravity).
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
  0.60.4 still rejects Cursor and lists Antigravity, Claude, and Codex as supported;
  the descriptor gate keeps the new cookie-source availability errors unreachable.
  Done when a released Linux command emits supported cost data and Plasma tests
  cover its amounts, currencies, and trust metadata.
  [Prior discussion #171](https://github.com/Lucenx9/codexbar-plasma/issues/171).

### Service-tier totals

- [ ] Show Standard/Fast totals from explicit official tier fields. The scoped
  0.56.8 daily-model check established no service-tier contract. The 0.57.0 and
  0.60.4 empty cost probes do not establish one either. Done when official Linux output
  identifies tiers and bounded amounts with tested legacy fallback. Never infer
  tier from models, prices, or tokens. [Cost evidence](docs/cost-history.md#pinned-cli-evidence);
  [prior discussion #172](https://github.com/Lucenx9/codexbar-plasma/issues/172).

### Cost availability

- [ ] Replace the Antigravity-specific unknown-cost fallback with explicit
  official availability metadata. At 0.56.2, established-empty history used zero
  despite unavailable costs. The 0.57.0, 0.58.0, and 0.60.4 Antigravity fresh-history
  probes omit cost totals, and the Claude probes report measured zeros;
  none verifies that established-empty case. The 0.60.4 OpenCodex
  unpriced-instead-of-zero change affects values within the unchanged cost schema.
  Linux 0.60.5 adds verified `incompleteRequestCount` counts, which explain
  requests excluded from an amount but do not mark an unavailable total; that
  contract is tracked as its own implementable entry above.
  Done when verified
  Linux fields distinguish unavailable from measured zero, with old-payload compatibility and
  usable token charts. [Prior discussion #173](https://github.com/Lucenx9/codexbar-plasma/issues/173).

### Structured localization

- [ ] Localize opaque provider/incident/error/reset text and pace headroom through
  official identifiers or typed fields. The remaining contract gap is carried
  from 0.56.2; authenticated output has not been exhaustively rechecked through
  0.60.4.
  Known states and structured pace forecasts already translate. At 0.60.4 the
  only newly structured row data is numeric (`progress`/`usageValue` with
  optional stable `id`); labels stay opaque. Done when
  supported fields use catalogs with placeholder/plural checks and bounded
  unknown-value fallbacks. [Translation guide](docs/translations.md);
  [prior discussion #174](https://github.com/Lucenx9/codexbar-plasma/issues/174).

### Display currency

- [ ] Offer display-currency selection and conversion through an official Linux
  contract. The 0.56.2 audit records no display-currency setter or descriptor;
  the scoped 0.57.0, 0.58.0, and 0.60.4 config probes expose neither. Plasma currently
  displays the CLI-emitted currency. Done when released settings and converted
  amounts define currency, rate provenance, and unavailable-conversion behavior,
  with tested Plasma selection/display. Keep conversion and exchange-rate
  acquisition in the CLI and preserve separate currencies until then.
  [Pinned blocker](docs/research/2026-09-01-macos-parity-0.56.2.md#blocked-on-an-official-linux-cli-contract).

### Automatic balance text

- [ ] Show a typed money/points balance when automatic panel text has no quota.
  macOS 0.57.0 uses provider-specific prose parsing for several cases. A generic
  official Linux amount, unit/currency, and availability contract is missing.
  At 0.60.4 the source-observed `balanceIsWorkspace`/`creditsAvailable` fields
  cover Codex workspace balances only; Copilot seat-credit data travels in
  `details` rows with stable IDs instead. Both await authenticated Linux output.
  Done when the widget can display
  that record without parsing provider text,
  overriding a real quota, or treating a balance as an allowance.
  [Source comparison](docs/research/2026-09-09-macos-parity-0.57.0.md#automatic-balance-text-needs-a-generic-contract);
  [0.60.4 evidence](docs/research/2026-09-16-macos-parity-0.60.4.md#linux-cli-contract-changes-since-0580).

## Verify before accepting implementation work

These are unresolved Linux candidates, not confirmed missing features.

- [ ] Verify `credits.balanceReadSucceeded`, `creditsAvailable`, and
  `balanceIsWorkspace` (also on `openaiDashboard` with `accountID`) in official
  Linux output. 0.60.4 source widens the flag to cap-only/omitted balances and
  the dashboard hides credits unless the read succeeded, while Plasma still
  reads `remaining` without any flag. Reproduce failed reads, confirmed zero,
  cap-only, hidden-workspace-pool, and workspace-balance data safely, then
  classify and specify the normalization change.
  [Source evidence](docs/research/2026-09-16-macos-parity-0.60.4.md#linux-cli-contract-changes-since-0580).
- [ ] Verify `details` rows carrying `id`, `progress{used,total}`, and
  `usageValue` in official Linux output (source-observed for Copilot
  seat-credit rows with stable IDs and Antigravity local rows at 0.60.4).
  Reproduce rows with and without the numeric fields safely, then specify the
  bounded Plasma rendering (progress bars from numbers, no display-string
  parsing) and whether stable IDs can back per-row popup visibility. macOS
  0.60.5 reads the `copilot-seat-credits` row's `progress` as a switcher
  used-percent fallback, which does not establish a quota cadence.
  [Source evidence](docs/research/2026-09-16-macos-parity-0.60.4.md#linux-cli-contract-changes-since-0580).
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
  cases still need the named official CLI probes. At 0.60.4 the token-account
  label helper preserves `accountID`, but the Claude usage payload still carries
  no account email (`usage.identity` holds only `providerID`), so the frontend
  cannot show a Claude account email.
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
