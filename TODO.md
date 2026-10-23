# Linux parity TODO

This is the current list of useful Linux/Plasma work relative to the official
CodexBar macOS app. The agent updates it with every new stable upstream release
and every change that implements or invalidates an entry. Follow
[release maintenance](docs/development.md#upstream-release-maintenance).
Issues linked below preserve discussion; this file owns parity status.

## Review baseline

- Last release reviewed: [CodexBar 0.80.0](https://github.com/steipete/CodexBar/releases/tag/v0.80.0),
  commit `3e060a954d7310bf2125074024f0b0f8f91db4b0`, checked 2026-10-23.
- Coverage: the [0.80.0 review](docs/research/2026-10-23-macos-parity-0.80.0.md)
  against Plasma `b7c8362` verifies the 108-provider registry, Soniox's
  reachable API-key setup, Trae CN's macOS-only web source, the new Copilot
  `config login` command's argument and offline failure events, the musl Codex
  cost crash in 0.79.0 and its fix in 0.80.0, managed-installer compatibility,
  and unchanged carried blockers, including custom-provider routing.
  Authenticated output and the Copilot pending/authorized events remain
  unverified.
- Earlier reviews: each dated note in the
  [documentation index](docs/README.md#maintained-references) records its own
  release coverage, probes, and unverified cases. Shared payload structs retain
  optional credit-availability and detail-row fields awaiting authenticated
  output evidence.
- Full CLI baseline remains the [0.56.2 audit](docs/research/2026-09-01-macos-parity-0.56.2.md).
  Later probes verify only their named cases. Older blockers below retain their
  last verified version; source inspection is not authenticated output evidence.

## Blocked on official Linux CLI contracts

These are useful Linux features once the named contract exists. Do not fill
these gaps with provider scraping, auth flows, or config parsing in QML.

### Private account selection

- [ ] Avoid passing account labels, which may be email addresses, in usage
  process arguments. Official Linux CLI 0.79.0 advertises `--account` and
  `--account-index`, but rejects `usage --account-stdin --format json --json-only`
  with `Unknown option --account-stdin` (isolated empty configuration,
  2026-10-21, exit 1). A private-input selector would close this exposure.
  Before choosing an index workaround, verify a supported mapping from the
  discovered account identities to CLI indexes across refreshes and config
  changes; the frontend currently deduplicates account options by identity.
  Do not infer that mapping from the rendered list order or edit CLI config.

### Provider settings

- [ ] Support FLORA workspace ID and Future AGI secret key setup once official
  writers exist. Linux 0.75.0 stores the FLORA key but requires
  `FLORA_WORKSPACE_ID` at runtime; `--workspace-id` remains z.ai-only. Linux
  0.77.0 stores Future AGI's `FI_API_KEY`, then refuses to fetch until the
  environment-only `FI_SECRET_KEY` is set; Plasma must not offer a half
  setup. Parallel refuses API-key/API source and needs the generic cookie
  action below. Done when released descriptors/writers
  enable safe setup without QML config editing.
  [Evidence](docs/research/2026-10-15-macos-parity-0.75.0.md#linux-cli-contract-changes);
  [Future AGI](docs/research/2026-10-17-macos-parity-0.77.0.md#linux-cli-contract-changes).

- [ ] Enable generic settings and token-account editing through official
  descriptors and writes. Linux 0.79.0 still rejects `config providers
  --descriptors` (106 records, same four keys); its provider records have no
  descriptor. Helmcode and TypeSafe make this concrete: both are cookie-only,
  both refuse `--source api`, and their documented `cookieSource`/`cookieHeader`
  config path has no supported writer, so they stay metadata-only on Linux.
  0.65.0 adds three more cases. Charm Hyper stores a key, but its default
  source demands web support on Linux, and it works only with `--source api`
  and Plasma now supports a persistent per-provider source choice. Bifrost
  needs a gateway base URL
  (`enterpriseHost`) with no CLI writer; the CLI reads `BIFROST_BASE_URL` from
  the environment instead. The optional GitKraken organization ID has no writer
  either, and neither has llmman's non-default base URL (`LLMMAN_HOST`, 0.66.0).
  0.67.0 adds Raycast, cookie-only with a macOS-only web source; Aixy's
  self-hosted base URL (`AIXY_BASE_URL`); and the opt-in LiteLLM model activity
  (`LITELLM_MODEL_USAGE_ENABLED`) and Claude Admin workspace spend
  (`ANTHROPIC_ADMIN_WORKSPACE_SPEND`), none of which has a writer.
  0.68.0 lifts the runtime gate for Mistral's manual cookie (#4024): with
  `cookieSource`/`cookieHeader` in the config file, Linux usage attempts the
  fetch instead of refusing as macOS-only (verified 0.67.0 vs 0.68.0);
  `set-api-key` still refuses mistral and no writer exists for the cookie
  fields, so setup stays blocked. 0.72.0 lifts the same gate for Claude's
  manual `sessionKey` cookie (#4241): with a synthetic manual cookie, Linux
  usage attempts `claude.ai` instead of reporting no available strategy
  (verified 0.69.0 vs 0.72.0); browser import stays macOS-only and no writer
  exists for the cookie fields, so setup stays blocked.
  0.76.0 adds Claude Platform with the same browser/manual-cookie boundary:
  its descriptor accepts a manual `Cookie` header containing `sessionKey`, but
  Auto/Web usage is macOS-only through supported configuration, API-key setup
  is refused, and no writer exists for the cookie fields.
  0.77.0 adds a Gemini app web source with the same boundary: Linux runs it
  only with a manual cookie, which has no writer. Its five-hour and weekly
  windows also need window-based labels instead of Plasma's static Gemini
  Pro/Flash/Flash Lite lanes before it is exposed. Token accounts gain a
  `claudeConfigDirectory` for Claude local cost with no writer either.
  0.74.0 adds Exa's API key ID (`EXA_API_KEY_ID`) and Cosmic AI's project ID
  (`COSMIC_PROJECT_ID`): both providers store a key, then refuse to fetch
  until that environment-only field is set, and `--workspace-id` is refused.
  TinyApi and X API are cookie-only with a macOS-only web source.
  `--label` and `--workspace-id` remain z.ai-only: Linux 0.74.1 rejects
  `set-api-key --provider clinepass --label` despite the release claim (#4305),
  and labeled Kimi, Doubao, and OpenCode Go accounts remain blocked too.
  0.78.0 adds Vercel personal budgets with a separate access token and Team
  ID. Linux 0.79.0 reaches that strategy with environment values, but still
  rejects `set-api-key --provider vercel --workspace-id` as z.ai-only and has
  no writer for `VERCEL_ACCESS_TOKEN`. The existing gateway-key setup is separate.
  Source persistence has the supported 0.73.0 `set-source` writer and
  version-gated Plasma controls; generic source descriptors and other field
  writers are absent.
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
  flow, CLI-auth setup, and token-account actions. Linux 0.80.0 still has no
  generic `config action` command (`set-api-key` and `set-source` are field
  writers; the `usage_updated` hook event is CLI automation surface, not a setup
  action). The Copilot-only `config login` is tracked as Plasma-native work
  below. Trae CN's signed-in dashboard source is macOS-only on Linux and joins
  the cookie case here. Done when supported actions expose validated
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
  history or session conversion rates from a current snapshot. The macOS
  0.77.0 five- and six-day work weeks change weekly pace in the app; Linux
  usage JSON has no work-day pace option, and the CLI text dashboard reads a
  macOS preference, so Plasma's CLI-sourced pace cannot follow them yet.
  [Prior discussion #170](https://github.com/Lucenx9/codexbar-plasma/issues/170).

### Gemini automatic source

- [ ] Restore Gemini usage under the default Auto source on Linux. Linux
  0.77.0 through 0.80.0 rejects Gemini Auto as a macOS-only web source before any strategy runs,
  where 0.76.0 reached the Gemini CLI OAuth strategy; the Linux web gate treats
  Auto as web for every provider that lists a web source, although Gemini Auto
  resolves only the OAuth strategy. The explicit API source still works, so
  affected users can save API in Plasma's Source mode control. Plasma must not
  rewrite the saved source silently. The API-source workaround is documented in
  docs/usage.md. Done when an official release lets Linux Gemini Auto reach
  the OAuth strategy again, verified in the isolated probe.
  [Original regression](docs/research/2026-10-17-macos-parity-0.77.0.md#linux-cli-contract-changes);
  [0.78.0/0.79.0 recheck](docs/research/2026-10-21-macos-parity-0.79.0.md#carried-forward-blockers-rechecked);
  [0.80.0 recheck](docs/research/2026-10-23-macos-parity-0.80.0.md#carried-forward-blockers-rechecked).

### Custom provider routing

- [ ] Restore custom catalog IDs in the official Linux usage path. Linux
  0.79.0 and 0.80.0 discover and fetch a synthetic `audit-fixture` plugin through
  `plugins list` and `plugins fetch`, but `usage --provider audit-fixture`
  returns a Codex error even after approval. Done when the released usage
  command preserves the requested custom identity and Plasma's existing
  discovery/normalization is verified against that output. Do not relabel the
  wrong provider or read plugin files in QML.
  [Evidence](docs/research/2026-10-21-macos-parity-0.79.0.md#linux-cli-contract-changes);
  [0.80.0 recheck](docs/research/2026-10-23-macos-parity-0.80.0.md#carried-forward-blockers-rechecked).

### Cursor cost

- [ ] Show Cursor cost history through the generic Linux `cost` path. Linux
  0.80.0 still rejects Cursor and lists Antigravity, Claude, Codex, Muse
  Code, OpenCode Go, and Pi as supported; the 0.74.0 `cursor-agent` login
  (#4397) changes usage authentication only;
  the descriptor gate keeps the new cookie-source availability errors unreachable.
  The 0.68.0 all-history date-range fix (#4028) targets macOS Usage & Spend
  refreshes, not the Linux cost allowlist.
  Done when a released Linux command emits supported cost data and Plasma tests
  cover its amounts, currencies, and trust metadata.
  [Prior discussion #171](https://github.com/Lucenx9/codexbar-plasma/issues/171).

### Account-scoped local costs

- [ ] Filter local cost history by the account selected in the widget only
  through a released official Linux CLI contract. An isolated 0.76.0 probe
  rejects `cost --provider codex --account synthetic-account --format json --json-only`
  with `Unknown option --account` (exit 1). The widget currently selects usage
  quotas independently of the provider's local history and explicitly labels
  Codex costs accordingly. Done when a supported selector and emitted identity
  establish attribution, with regressions for account changes and late cost
  replies. Do not infer identity from usage labels or scan provider logs in QML.
  [Evidence](docs/cost-history.md#pinned-cli-evidence).

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
  requests excluded from an amount but do not mark an unavailable total; the
  widget states those counts on range totals and rows. Linux 0.62.0 nils
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
  the scoped 0.57.0, 0.58.0, 0.60.4, 0.67.0, 0.69.0, 0.72.0, 0.73.0,
  0.74.0, 0.74.1, 0.75.0, 0.76.0, 0.77.0, and 0.80.0 config probes expose neither,
  although macOS 0.67.0 adds twelve spend-estimate currencies. Plasma currently
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
  only as `details` row text, as do the 0.74.0 Linkup, Sail Research, Sofya,
  Exa, and Ollama API-key credit rows (source-observed).
  The 0.76.0 Claude Platform source adds a typed `providerCost` prepaid balance,
  but authenticated Linux output is unverified and Plasma currently discards
  its explicit `balance` field. Do not infer balance semantics from its period
  text.
  Done when the widget can display
  that record without parsing provider text,
  overriding a real quota, or treating a balance as an allowance.
  [Source comparison](docs/research/2026-09-09-macos-parity-0.57.0.md#automatic-balance-text-needs-a-generic-contract);
  [0.60.4 evidence](docs/research/2026-09-16-macos-parity-0.60.4.md#linux-cli-contract-changes-since-0580).

## Plasma-native work with verified CLI contracts

- [ ] Preserve and present optional detail-row severity. Official Linux CLI
  0.79.0 `plugins fetch` emits `severity: warning` from a synthetic plugin;
  the typed contract allows `normal`, `warning`, and `critical`, independently
  of progress. `UsageDetails.normalizeSections` currently drops it. Done when
  bounded normalization, theme/accessibility presentation, privacy/cache paths,
  and direct QtTests preserve severity without inferring it from percentages.
  [Evidence](docs/research/2026-10-21-macos-parity-0.79.0.md#linux-cli-contract-changes).

- [ ] Add Soniox to the single API-key setup. Official Linux CLI 0.80.0
  accepts `config set-api-key --provider soniox --stdin`, enables the provider,
  and reaches its network fetch; the key must be an organization API key
  (`SONIOX_ORG_API_KEY`), not a project key. `supportsApiKeySetup` in
  `configProviders.qml` omits `soniox`. Done when Soniox offers the existing
  key setup with its organization-key guidance and docs link, covered by tests.
  [Evidence](docs/research/2026-10-23-macos-parity-0.80.0.md#linux-cli-contract-changes).
- [ ] Offer Copilot GitHub device sign-in through
  `codexbar config login --provider copilot --json`. Official Linux CLI 0.80.0
  advertises the command, rejects other providers with an `args` error, and
  prints a `failed` JSON event offline. The release-tag source defines
  token-free `authorization_pending` (verification URI, user code, expiry),
  `authorized`, and `failed` events, signal cancellation, and a
  config-changed conflict error. Done when Plasma starts the command only on
  request, shows the URI and code without logging them, handles cancel,
  failure, expiry, and stale replies, refreshes Copilot afterwards, keeps the
  existing key setup, and is tested with fixture event streams. Gate the action
  on the existing bounded CLI version probe, or an equivalent advertised
  capability, so it stays hidden below 0.80.0, with an older-version
  regression test.
  [Evidence](docs/research/2026-10-23-macos-parity-0.80.0.md#linux-cli-contract-changes).

## Verify before accepting implementation work

These are unresolved Linux candidates, not confirmed missing features.

- [ ] Evaluate the 0.78.0 all-account Overview and optional bare-percent panel
  text against Plasma's current provider/account navigation and accessibility.
  Verify authenticated Linux multi-account identities before choosing an
  account-row model. Done when each candidate has a bounded accept/reject
  decision and any accepted work has a concrete contract. Account editing
  remains in the generic-writer blocker above.
  [Comparison](docs/research/2026-10-21-macos-parity-0.79.0.md#plasma-comparison).
- [ ] Verify 0.78.0/0.79.0 authenticated changes for Claude Auto/adapter
  selection, Vercel personal budgets, Cursor unified-account additional spend,
  Grok billing, TypeSafe requests, and Antigravity ordinary/model quota buckets.
  Done when emitted Linux output establishes whether existing generic fields
  suffice; retain setup blockers until official writers exist.
  [Limits](docs/research/2026-10-21-macos-parity-0.79.0.md#unverified-in-this-review).
- [ ] Decide whether to show a daily target for monthly allowances. macOS
  0.80.0 divides the remaining allowance by local days until reset, in the
  app, for windows of 28 to 31 days and monthly `providerCost` budgets.
  Linux emits no target. Plasma has `windowMinutes`, `resetsAt`, and
  `usedPercent`, but drops `quotaLimit`, `quotaUnit`, and
  `providerCost.resetsAt`, and the descriptor's inferred monthly durations are
  not exposed. Done when a bounded accept/reject decision exists; any accepted
  work uses only emitted fields and keeps currencies and units separate.
  [Comparison](docs/research/2026-10-23-macos-parity-0.80.0.md#linux-cli-contract-changes).
- [ ] Verify 0.80.0 authenticated changes: Soniox balance and budget meter,
  Kimi gift balances and lapsed Code pools, Grok zero-usage weekly Credits,
  Cursor X Subscription weekly pool, Tavily null pay-as-you-go limits, and
  Claude's limits-unavailable state. Done when emitted Linux output shows
  whether Plasma's generic window, details, and spend paths suffice.
  [Limits](docs/research/2026-10-23-macos-parity-0.80.0.md#unverified-in-this-review).

- [ ] Verify authenticated Claude Platform output from an official Linux CLI
  once a supported cookie writer/action exists. Confirm primary API credits,
  purchased-credit and grant-expiry lanes, reset descriptions, billing details,
  organization identity, and `providerCost` balance/current-spend semantics.
  Plasma already consumes most generic fields, but it must not parse period
  prose or treat a prepaid balance as an allowance. Done when emitted output
  establishes whether the existing generic presentation is sufficient and any
  remaining balance contract is explicit.
  [Review](docs/research/2026-10-15-macos-parity-0.76.0.md).

- [ ] Verify 0.75.0 OpenAI `usage.throughput` output, minute/model buckets,
  delayed and pending minutes, and per-credential manual rate-limit contracts.
  Include nonzero audio breakdowns in daily/model and live totals: 0.75.0 fixes
  CLI double-counting because input/output totals already include audio.
  Plasma prefers explicit totals; verify their end-to-end preservation without
  adding audio breakdowns again.
  Source has an encoded throughput field, but no authenticated Linux output
  was observed. Verify Claude spend-only monthly caps/resets too; its macOS
  UTC rollover helper is not an emitted authoritative reset.
  Done when official output supports a bounded Plasma design or establishes
  the exact missing CLI contract.
  [Review](docs/research/2026-10-15-macos-parity-0.75.0.md).
- [ ] Verify imported incomplete model rows (#4299) against Plasma's cost trust
  and sharing rules. Linux 0.75.0 synthetic native history verifies mixed
  priced/unknown-model subtotals, fully unpriced amounts, token preservation,
  coverage and privacy-safe sharing; seeded historical scanner state also
  verifies known-model partial subtotals (#4273, #4278, #4279). Those shapes
  need no fix. Imported incomplete rows remain unverified: import depends on
  an application preference with no established supported Linux writer.
  Do not treat its source as emitted output or add config/cache manipulation to QML. Accept a
  frontend change only for a demonstrated mismatch; keep pricing in the CLI.
  [Verified scope and limits](docs/research/2026-10-15-codex-contracts-0.75.0.md#partial-priced-native-history).
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
  source text literally. Provider metadata expectations now run through public
  Qt/QML interfaces instead of parsing JavaScript tables, including CLI argument
  overrides and required brand-color presence. Icon mapping, remaining wiring
  checks and formatter readability blockers are still open. At that measurement,
  CI ran 6.11.1 and no container runtime was available to compare its output.
  Done when a release keeps or improves manual
  expression line breaks, formats every file readably, and produces the same
  output on the CI image.
- [ ] Verify the 0.64.x Linux quota-window changes in official Linux output.
  0.64.0 claims Linux omits synthetic or unmeasured quota and reports only
  measured provider-specific windows (#3785); 0.64.1 claims each Antigravity
  quota pool is listed once with its family label (#3799). Both would change
  the window array the popup renders, and Plasma currently renders whatever
  windows arrive. The probe account has no enabled provider returning quota, so
  neither was observed. 0.73.0 also changes Kimi contradictory-window
  reconciliation and its Monthly Total pool (#4306), Ollama Free monthly usage
  (#4308), and JetBrains top-up credit/log quota fallback (#4287, #4288); include these providers in the
  measured-window comparison. 0.69.0 adds grouped OAuth quotas with weekly-only
  Starter allowances and explicit window cadence (#4084), still unmeasured.
  Reproduce with a signed-in Antigravity account and one
  other quota provider, then classify whether any normalization changes.
  0.74.0 moves Ollama API-key mode to `/api/balance` with a monthly window
  (#4399) and adds Qwen Cloud Team windows (#3711); include them too.
  Cover the 0.73.0 consumer OAuth client change (#4293), the 0.71.0 per-account
  private-session quotas (#4103), the 0.72.0 2.19.1 OAuth client-credentials
  recovery (#4229), and the opt-in extra profile homes (#4177) in the same reproduction.
  [Unverified at 0.64.1](docs/research/2026-09-22-macos-parity-0.64.1.md#unverified-in-this-review);
  [0.69.0 addition](docs/research/2026-09-29-macos-parity-0.69.0.md#unverified-in-this-review);
  [0.72.0 shapes](docs/research/2026-10-05-macos-parity-0.72.0.md#unverified-in-this-review).
- [ ] Verify Mistral's Included API and Vibe Monthly Plan windows in official
  Linux `usage` output. 0.68.0 lifts the macOS-only runtime gate for the
  manual-cookie path (#4024), so a subscription with `cookieSource` and
  `cookieHeader` set should now return allowance windows on Linux. Reproduce
  with a Mistral subscription safely, then classify the window shape against
  Plasma's generic quota rendering.
  [Unverified at 0.69.0](docs/research/2026-09-29-macos-parity-0.69.0.md#unverified-in-this-review).
- [ ] Verify Claude web-source allowance windows in official Linux `usage`
  output. 0.72.0 attempts the claude.ai fetch with an explicitly configured
  manual `sessionKey` cookie (#4241), so a web subscription should now return
  session/weekly/quota windows on Linux. Reproduce with a Claude subscription
  and a synthetic manual cookie safely, then classify the window shape against
  Plasma's generic quota rendering.
  [Unverified at 0.72.0](docs/research/2026-10-05-macos-parity-0.72.0.md#unverified-in-this-review).
- [ ] Verify the new 0.72.0 credit balance fields in official Linux `usage`
  output: Grok purchased Extra Usage Credits, the Claude promotional
  cloud-session credit separation from prepaid credits, and the Claude saved
  limit-reset credits in OAuth usage (#4239, #4243, #4194, #4214, #3895,
  #4232), plus the 0.74.0 JetBrains top-up credits (#4372) and Ollama
  purchased-credit and wallet rows (#4399, #4370). Empty-history output
  carries none of them. Reproduce each with a
  funded account safely, then classify whether the generic balance/details
  path renders them or a normalization change is needed.
  [Unverified at 0.72.0](docs/research/2026-10-05-macos-parity-0.72.0.md#unverified-in-this-review).
- [ ] Verify whether Cursor's 0.64.1 Grok Bot allowance reaches Linux `usage`
  output, and under which key. The release adds a `Grok Bot %` menu-bar layout
  token; a corresponding rate window would be a normal extra window for Plasma,
  while a macOS-only token is a non-goal. Unmeasured without a Cursor account.
  [Unverified at 0.64.1](docs/research/2026-09-22-macos-parity-0.64.1.md#unverified-in-this-review).
- [ ] Verify Cursor usage through a Linux `cursor-agent` login (#4397). With a
  synthetic JWT in `$XDG_CONFIG_HOME/cursor/auth.json`, 0.74.0 attempts
  cursor.com where 0.73.0 reports no session. Without network, about half of
  fresh 0.74.0 runs stalled idle past 20–30 seconds, even with
  `--web-timeout 5`; Plasma's 120-second command bound still applies. Reproduce
  with a real login, offline and online, then classify the windows and
  whether the stall needs an upstream report or a Plasma message.
  [Evidence](docs/research/2026-10-11-macos-parity-0.74.0.md#linux-cli-contract-changes-since-0730).
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
  0.56.6 cases. Automatic panel capsules and Overview rows already show primary
  and secondary.
  Keep direct lane choices and independent quota pools. Include OpenCode Go,
  whose macOS 0.74.0 automatic text picks the most constrained five-hour,
  weekly, or monthly window (#3349). macOS 0.77.0 ranks Auto windows and the
  highest-usage icon by exhausted windows, then the shortest projected
  depletion before reset, then usage (#4491); Plasma's automatic provider
  ranks by highest used percentage: `ProviderAutoSelect.bestIndex` skips
  error-only entries (`OverviewProviders.isErrorOnly`) and breaks equal-usage
  ties by incident severity (`NotificationMemo.severityRank`). The panel lane
  order in `PanelDisplay.candidateRows` is primary, secondary, tertiary, with
  exceptions: Factory puts secondary before primary; Perplexity with an
  exhausted primary goes secondary, tertiary, primary; Cursor with an
  exhausted primary prepends the providerCost row. Plasma already receives CLI
  `paceOnTop`/`paceEtaSeconds`. Compare that rule using only CLI pace, never
  a local projection. Accept a change only
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
  no account email (`usage.identity` holds only `providerID`). The 0.76.0
  release says Claude OAuth accounts now include email, and Plasma already
  consumes `usage.identity.accountEmail`, but no authenticated Linux record was
  observed. Verify the emitted shape and multi-account behavior before closing
  this candidate. A scoped 0.76.0 source check shows Codex usage records use
  `CodexVisibleAccount.menuDisplayName`, which includes workspace labels and
  adds stable discriminators for collisions. A synthetic email-only record
  without that top-level account label is insufficient evidence for changing
  Plasma's selection keys. Authenticated Linux same-email workspace output
  remains unverified.
  [Projection source](https://github.com/steipete/CodexBar/blob/2d8b1409a1649dce60f3610ebe4eab52b92545de/Sources/CodexBarCore/Providers/Codex/CodexVisibleAccountProjection.swift);
  [usage source](https://github.com/steipete/CodexBar/blob/2d8b1409a1649dce60f3610ebe4eab52b92545de/Sources/CodexBarCLI/CLIUsageCommand.swift).
  [Release coverage](docs/research/2026-09-09-macos-parity-0.57.0.md#release-coverage).
- [ ] Evaluate a panel Spend item for providers that report a spend budget.
  macOS 0.77.0 adds Spend layout items and conditional rules (#4530). Plasma's
  panel has identity, status, text, and meter elements and no spend item,
  although the popup already derives an allowance from `providerCost` used and
  limit. Accept only a bounded design that keeps currencies separate, hides
  the item without a budget, and never treats a balance as an allowance.
  [Comparison](docs/research/2026-10-17-macos-parity-0.77.0.md#plasma-comparison).
- [ ] Verify the 0.77.0 claude-swap and tcr account pools, per-account Claude
  local cost directories, and Munito/Future AGI windows and spend rows in
  official Linux output. None was observable without accounts. Done when
  emitted output shows whether Plasma's generic account, details, and cost
  paths suffice. [Review](docs/research/2026-10-17-macos-parity-0.77.0.md#unverified-in-this-review).
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

Claude percentage-only reset and pace fields are supported through the generic
usage presentation, verified with official Linux CLI 0.76.0 in the
[focused contract probe](docs/research/2026-10-15-claude-details-0.76.0.md).
An absent forecast or reset is not reconstructed from a quota percentage.

macOS-only features do not enter this backlog. The [release review](docs/research/2026-09-09-macos-parity-0.57.0.md#excluded-from-the-linux-backlog)
records exclusions. Provider parsing, pricing, authentication, and scanning
fixes are CLI-owned; a new upstream implementation is not a missing QML port.
