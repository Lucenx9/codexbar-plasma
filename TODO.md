# Linux parity TODO

This is the current list of useful Linux/Plasma work relative to the official
CodexBar macOS app. The agent updates it with every new stable upstream release
and every change that implements or invalidates an entry. Follow
[release maintenance](docs/development.md#upstream-release-maintenance).
Issues linked below preserve discussion; this file owns parity status.

## Review baseline

- Last release reviewed: [CodexBar 0.66.0](https://github.com/steipete/CodexBar/releases/tag/v0.66.0),
  commit `e665cbf64976839dc947e70a942ba8226388d4c9`, checked 2026-09-25.
- Coverage: release changes from 0.65.0 through 0.66.0 against Plasma
  `26a877f`. The
  [0.66.0 review](docs/research/2026-09-25-macos-parity-0.66.0.md) verifies the
  DevPass, Atlas Cloud, Vercel AI Gateway, and llmman registry additions and
  their API-key setup, llmman usage through a loopback daemon fixture, and that
  CLI config writes now keep user plugin entries; the descriptor, config-action,
  and Cursor cost blockers are unchanged. The
  [0.65.0 review](docs/research/2026-09-23-macos-parity-0.65.0.md) verifies the
  Bifrost, Charm Hyper, and GitKraken AI registry additions and which of them
  Linux can reach. It uses a loopback Bifrost fixture to verify detail-row
  `progress`/`usageValue` and unknown named windows in official Linux output,
  and confirms that the descriptor, config-action, token-account, and Cursor
  cost blockers are unchanged; the
  [0.64.1 review](docs/research/2026-09-22-macos-parity-0.64.1.md) verifies the
  Helmcode, v0, and TypeSafe registry additions and the Crof retirement, that
  only v0 accepts the supported `set-api-key` writer while the other two are
  cookie-only and unreachable on Linux, and that the descriptor and generic
  config-action blockers are unchanged; the
  [0.63.0 review](docs/research/2026-09-21-macos-parity-0.63.0.md) verifies
  the Pi registry growth with local token history and estimated costs, the
  still-rejected Cursor cost and provider-settings descriptor probes, and
  confirms that usage, sessions, and config envelopes are otherwise unchanged;
  the [0.62.0 review](docs/research/2026-09-20-macos-parity-0.62.0.md) verifies
  Muse token history in official Linux cost output, the Codex-only `--remote`
  and `--summary-only` cost modes, the `usage_updated` hook event, and
  confirms that usage, sessions, and config envelopes are unchanged; the
  [0.61.0 review](docs/research/2026-09-18-macos-parity-0.61.0.md) records the
  registry growth to 74 providers; the
  [0.60.5 review](docs/research/2026-09-18-macos-parity-0.60.5.md) verifies the
  cost `incompleteRequestCount` contract in official Linux output; the
  [0.60.4 review](docs/research/2026-09-16-macos-parity-0.60.4.md) records the
  earlier release delta and source comparison. Shared payload structs retain
  optional credit-availability and detail-row fields awaiting authenticated
  output evidence.
- Full CLI baseline remains the [0.56.2 audit](docs/research/2026-09-01-macos-parity-0.56.2.md).
  Later probes verify only their named cases. Older blockers below retain their
  last verified version; source inspection is not authenticated output evidence.

## Implementable on Linux

### Incomplete cost requests

- [ ] Mark the individual history and model rows whose requests the CLI
  excluded, now that the range total says how many were left out. The official
  counts also arrive per `daily[]` entry and per `daily[].modelBreakdowns[]`
  record. Quota-week subtotals already use the daily count to mark lower bounds;
  individual popup rows still read as complete measurements. Done when a
  row states its excluded requests without parsing display text, keeps measured
  and unknown amounts distinct, and stays legible in the narrow popup.
  Evidence: [0.60.5 review](docs/research/2026-09-18-macos-parity-0.60.5.md#linux-cli-contract-changes-since-0604).

### CLI lane labels as fallback

- [ ] Title a usage lane from the CLI's `rateWindowLabels` when the widget's
  localized table has no entry for that provider. Unlisted providers get
  the generic `Session`, `Weekly`, or `Opus`, which is wrong for balance,
  memory, or plan-credit lanes; llmman's memory lane reached the popup as
  `Session` until this review added a table entry. The field is present in
  official Linux output since at least 0.65.0 (`{"primary": "Memory"}` for
  llmman at 0.66.0). Done when a bounded, validated CLI label replaces only the
  generic fallback, localized table entries still win, and an absent or
  malformed label keeps today's behavior.
  Evidence: [0.66.0 review](docs/research/2026-09-25-macos-parity-0.66.0.md#linux-cli-contract-changes-since-0650).

### Popup usage row visibility

- [ ] Hide and restore individual popup usage rows per provider, mirroring the
  macOS 0.58.0 visible-row choice as a Plasma-local display preference. Panel
  rows already have visibility rules; popup provider cards expose only fixed
  section toggles, and no CLI contract is required. macOS 0.62.0 extends its
  Visible usage items to titled provider detail sections, which informs the
  row set a Plasma equivalent should cover. Done when rows can be
  hidden and restored without affecting fetching, alerts, or the panel, with
  the choice persisted and previewed in settings.
  Evidence: [0.58.0 comparison](docs/research/2026-09-11-macos-parity-0.58.0.md);
  [0.62.0 review](docs/research/2026-09-20-macos-parity-0.62.0.md#linux-cli-contract-changes-since-0610).

## Blocked on official Linux CLI contracts

These are useful Linux features once the named contract exists. Do not fill
these gaps with provider scraping, auth flows, or config parsing in QML.

### Provider settings

- [ ] Enable generic settings and token-account editing through official
  descriptors and writes. Linux 0.66.0 still rejects `config providers
  --descriptors` (84 records, same four keys); its provider records have no
  descriptor. Helmcode and TypeSafe make this concrete: both are cookie-only,
  both refuse `--source api`, and their documented `cookieSource`/`cookieHeader`
  config path has no supported writer, so they stay metadata-only on Linux.
  0.65.0 adds three more cases. Charm Hyper stores a key, but its default
  source demands web support on Linux, and it works only with `--source api`
  while Plasma's source mode is global. Bifrost needs a gateway base URL
  (`enterpriseHost`) with no CLI writer; the CLI reads `BIFROST_BASE_URL` from
  the environment instead. The optional GitKraken organization ID has no writer
  either, and neither has llmman's non-default base URL (`LLMMAN_HOST`, 0.66.0).
  `--label` and `--workspace-id` remain z.ai-only, so the new labeled Kimi, Doubao, and OpenCode Go accounts cannot be created from Linux.
  0.61.0 adds an `azureOpenAIAPIVersion` config extension value with no
  supported CLI writer, which the frontend must not reach by editing the config
  file. Keep existing enable/disable, supported single-key setup, and link
  fallbacks working.
  The [proposal](docs/cli-provider-settings-descriptor.md) covers source mode,
  keys/cookies, URLs, workspace/project, region, AWS profile/auth mode, and
  booleans. Remaining editors include token accounts, auth nuances,
  organization/team, metric, per-provider thresholds, and Fireworks multi-account
  slug editing. Done when the named controls have released generic contracts
  and tested Plasma support. [Prior discussion #167](https://github.com/Lucenx9/codexbar-plasma/issues/167).

### Provider onboarding

- [ ] Add CLI-described browser-cookie import, local-file setup, OAuth/device
  flow, CLI-auth setup, and token-account actions. Linux 0.66.0 still has no
  generic `config action` command (`set-api-key` remains the sole writer; the
  `usage_updated` hook event is CLI automation surface, not a setup
  action). Done when supported actions expose validated
  prompts/results and handle cancellation, failure, and stale responses in
  Plasma. Preserve current key/link setup. [Prior discussion #168](https://github.com/Lucenx9/codexbar-plasma/issues/168).

### Rich usage and credit allowances

- [ ] Consume generic billing/pricing details, richer model/request/token usage,
  credit allowances, and unknown-usage windows with reset metadata. These gaps
  were verified at 0.56.2; authenticated cases remain unverified through 0.60.4.
  Source-observed but unverified at 0.60.4: `creditsAvailable`/`balanceIsWorkspace`
  on `credits` and `openaiDashboard`, Copilot seat-entitlement rows with stable
  IDs, and `details` rows carrying `progress`/`usageValue` (Copilot, Antigravity).
  0.65.0 verifies the detail-row numbers and `usageKnown: false` named windows
  with reset metadata in official Linux output through Bifrost. Plasma keeps
  those windows unknown instead of 0% and draws detail-row `progress` meters.
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
  0.66.0 still rejects Cursor and lists Antigravity, Claude, Codex, Muse
  Code, and Pi as supported;
  the descriptor gate keeps the new cookie-source availability errors unreachable.
  Done when a released Linux command emits supported cost data and Plasma tests
  cover its amounts, currencies, and trust metadata.
  [Prior discussion #171](https://github.com/Lucenx9/codexbar-plasma/issues/171).

### Service-tier totals

- [ ] Show Standard/Fast totals from explicit official tier fields. The scoped
  0.56.8 daily-model check established no service-tier contract. The 0.57.0 and
  0.60.4 empty cost probes do not establish one either, and 0.62.0 computes
  quota windows in-process without emitting tier fields. The 0.65.0 Codex
  Priority pricing fix leaves the cost key set unchanged. Done when official Linux output
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
  contract is tracked as its own implementable entry above. Linux 0.62.0 nils
  out invalid model-breakdown and daily totals instead of emitting them, which
  keeps unknown amounts out of the JSON without supplying an explicit
  unavailable-versus-zero field.
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
  The 0.65.0 Charm Hyper guide describes a balance-only `details` row with a
  bare `usageValue` and an HC display string, which is not a typed unit. The
  0.66.0 Atlas Cloud and Vercel AI Gateway plugins likewise report USD balances
  only as `details` row text.
  Done when the widget can display
  that record without parsing provider text,
  overriding a real quota, or treating a balance as an allowance.
  [Source comparison](docs/research/2026-09-09-macos-parity-0.57.0.md#automatic-balance-text-needs-a-generic-contract);
  [0.60.4 evidence](docs/research/2026-09-16-macos-parity-0.60.4.md#linux-cli-contract-changes-since-0580).

## Verify before accepting implementation work

These are unresolved Linux candidates, not confirmed missing features.

- [ ] Adopt `qmlformat` once it can format this tree readably. Measured at
  6.11.2 on 2026-09-23. With wrapping disabled, its default, it joins wrapped
  expressions into lines up to 2570 characters. Any `MaxColumnWidth` rewraps by
  splitting inside comparisons and aligning continuations under the open
  parenthesis, such as `incidentProvider` and `!== null` on separate lines; at
  120 it still leaves 359 lines over the limit, up to 241 characters. The
  earlier segfault at 140 or less was unbounded recursion on regular expression
  literals wider than the limit; those literals are now built from strings, and
  every file formats at 100 or more, while four test files still crash at 80.
  [QTBUG-131686](https://qt-project.atlassian.net/browse/QTBUG-131686) closed
  for 6.11 with `// qmlformat off` comments only, which disable formatting
  rather than keep line breaks. Rewrapping also breaks
  `test_feature_parity.sh` and `test_process_lifecycle.sh`, which still match
  source text literally. CI runs 6.11.1; no running container runtime was
  available to compare its output. Done when a release keeps or improves manual
  expression line breaks, formats every file readably, and produces the same
  output on the CI image.
- [ ] Verify the 0.64.x Linux quota-window changes in official Linux output.
  0.64.0 claims Linux omits synthetic or unmeasured quota and reports only
  measured provider-specific windows (#3785); 0.64.1 claims each Antigravity
  quota pool is listed once with its family label (#3799). Both would change
  the window array the popup renders, and Plasma currently renders whatever
  windows arrive. The probe account has no enabled provider returning quota, so
  neither was observed. Reproduce with a signed-in Antigravity account and one
  other quota provider, then classify whether any normalization changes.
  [Unverified at 0.64.1](docs/research/2026-09-22-macos-parity-0.64.1.md#unverified-in-this-review).
- [ ] Verify whether Cursor's 0.64.1 Grok Bot allowance reaches Linux `usage`
  output, and under which key. The release adds a `Grok Bot %` menu-bar layout
  token; a corresponding rate window would be a normal extra window for Plasma,
  while a macOS-only token is a non-goal. Unmeasured without a Cursor account.
  [Unverified at 0.64.1](docs/research/2026-09-22-macos-parity-0.64.1.md#unverified-in-this-review).
- [ ] Verify `credits.balanceReadSucceeded`, `creditsAvailable`, and
  `balanceIsWorkspace` (also on `openaiDashboard` with `accountID`) in official
  Linux output. 0.60.4 source widens the flag to cap-only/omitted balances and
  the dashboard hides credits unless the read succeeded, while Plasma still
  reads `remaining` without any flag. Reproduce failed reads, confirmed zero,
  cap-only, hidden-workspace-pool, and workspace-balance data safely, then
  classify and specify the normalization change.
  [Source evidence](docs/research/2026-09-16-macos-parity-0.60.4.md#linux-cli-contract-changes-since-0580).
- [ ] Verify stable `details` row `id` values in official Linux output
  (source-observed for Copilot seat-credit rows at 0.60.4). The numeric
  `progress`/`usageValue` fields are verified at 0.65.0, but the Bifrost rows
  used there carry no `id`. Reproduce Copilot rows safely, then decide whether
  stable IDs can back per-row popup visibility. macOS
  0.60.5 reads the `copilot-seat-credits` row's `progress` as a switcher
  used-percent fallback, which does not establish a quota cadence.
  [Source evidence](docs/research/2026-09-16-macos-parity-0.60.4.md#linux-cli-contract-changes-since-0580).
- [ ] Verify the Grok reset-credit detail row in official Linux output. 0.61.0
  source emits an untitled `details` section holding one `Limit Reset Credits`
  row valued `N available` from shared Core fetch strategies, gated on the
  pre-existing `requiresOptionalUsageCompleteness` fetch-context flag. Plasma's
  generic details path already keeps an untitled section that carries rows, so
  confirm with authenticated output whether the row reaches CLI JSON before
  deciding that no work is required. The companion `grokResetCredits` property
  is live-only and never encoded.
  [Source evidence](docs/research/2026-09-18-macos-parity-0.61.0.md#linux-cli-contract-changes-since-0605).
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
interactive cost/token charts and local aggregate usage sharing as PNG/text,
with separate currencies and no subscription-fee inference. Claude 0.57.0
`--breakdown` is text-only; existing JSON daily/model views already consume its
underlying data.

macOS-only features do not enter this backlog. The [release review](docs/research/2026-09-09-macos-parity-0.57.0.md#excluded-from-the-linux-backlog)
records exclusions. Provider parsing, pricing, authentication, and scanning
fixes are CLI-owned; a new upstream implementation is not a missing QML port.
