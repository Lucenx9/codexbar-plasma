# Panel budgets, automatic quotas, and monthly allowance

These are Plasma presentation decisions, verified on 2026-11-10 against the
released official Linux CLI 0.84.0. They implement bounded candidates from the
[0.77.0](research/2026-10-17-macos-parity-0.77.0.md#plasma-comparison) and
[0.80.0](research/2026-10-23-macos-parity-0.80.0.md#linux-cli-contract-changes)
comparisons. The [usage guide](usage.md#panel-and-popup) owns user instructions.

## Official Linux evidence

The `CodexBarCLI-v0.84.0-linux-x86_64.tar.gz` release asset was downloaded and
checked against its published SHA-256 file:
`724b0beb0d2769cfc6fc1558f2782b5b812eb73a140582b9716faf662adbaea0`.
The extracted executable reported `CodexBar 0.84.0`. The installed PATH command
reported 0.83.0; it was not replaced. Sources are the
[official release](https://github.com/steipete/CodexBar/releases/tag/v0.84.0)
and the [tagged Bifrost plugin](https://github.com/steipete/CodexBar/blob/v0.84.0/Sources/CodexBarCore/Resources/Plugins/bifrost.js).

`usage --provider bifrost --format json --json-only` ran against a temporary
loopback gateway with synthetic responses. Each run used a private HOME and XDG
directories, an absent `CODEXBAR_CONFIG`, and synthetic `BIFROST_API_KEY` and
`BIFROST_BASE_URL` environment values. No real accounts, credentials, or CLI
configuration files were read or edited. Both runs exited successfully.

The gateway supplied two budgets: a weekly fixed `168h` budget with 2 of 10 USD
used and a fixed `720h` budget with either 20 or 12 of 20 USD used. Last reset
was three days earlier for the weekly budget and twenty days earlier for the
monthly budget. The official executable emitted these semantic fields:

```json
{
  "provider": "bifrost",
  "source": "api",
  "usage": {
    "primary": {"usedPercent": 20, "windowMinutes": 10080},
    "secondary": {"usedPercent": 100, "windowMinutes": 43200},
    "providerCost": {"used": 2, "limit": 10, "currencyCode": "USD", "period": "Budget"}
  }
}
```

Both windows also carried explicit ISO reset timestamps, four and ten days
after the observation respectively. In the second run, secondary usage was
60%. `providerCost` described the first, weekly budget in both runs and carried
its own reset. No pace was emitted in these probes. These are synthetic upstream
responses processed by the official executable, not authenticated account
observations or a proposed CLI schema. Structured pace remains supported by the
separate [0.76.0 Linux evidence](research/2026-10-15-claude-details-0.76.0.md).

## Accepted display contracts

- **Panel spend budget:** opt-in horizontal text for the selected provider,
  using the existing provider-cost allowance classification. Show used and
  limit in the same reported three-letter uppercase currency. Normalization
  preserves currency absence; the popup's legacy USD fallback cannot qualify a
  panel budget. Hide it without
  a positive allowance, with negative used amounts, for non-monetary units,
  during retained-data fallback, and in privacy mode. Preserve known balance
  exceptions. Do not aggregate providers or currencies. This extends the
  existing text element, so its visibility rule and ordering still apply.
  Crowded panels surrender name, credits, then spend before usage; a generic
  icon's identifying name outlives spend. Full text remains accessible and the
  budget remains in the tooltip while enabled.
- **Automatic quota text and tab gauge:** prefer an authoritative exhausted
  window, then an authoritative window with a known CLI run-out forecast,
  shortest CLI ETA first. Retained measurements keep ordinary preference order,
  including in privacy mode. Preserve the prior order for ties and ordinary
  windows. Preserve Factory, exhausted Perplexity and exhausted Cursor
  alternate-pool preferences. Manual lanes and the primary/secondary capsule
  pair keep their existing behavior. Percentage-only readings do not gain
  automation privileges. Automatic *provider* selection still ranks by highest
  measured percentage with incident tie-breaking; changing that policy remains
  a separate TODO candidate.
- **Monthly daily allowance:** opt-in popup metadata for an explicitly emitted
  window of 28–31 days with a measured percentage and future reset. Divide its
  remaining percentage by local calendar days until reset, with a minimum of
  one day. Count calendar dates across DST instead of dividing elapsed hours
  by 24. A reset beyond the window length plus one day is rejected. Accept
  only a valid ISO-8601 timestamp with an explicit timezone. Validate
  calendar and time components before parsing so impossible dates cannot roll
  into the next month, including during privacy projection. Show zero
  for an exhausted window, omit missing/estimated/unknown-confidence data and
  retained measurements, and preserve numeric-only privacy presentation.
  This is an even allocation of the remainder, not a CLI consumption forecast.
  It does not affect warnings, selection, fetching, or notifications.

Monetary and token/request daily targets, inferred monthly descriptor durations,
and spend-only monthly resets are not accepted here. They require separate
verified contracts; the frontend does not infer them from provider prose or
subscription renewal dates. Existing screenshots keep the unchanged default
appearance because both new options default to off.

## Verification boundaries

Direct QtTests cover budget classification, fitting and tooltip recovery,
privacy and stale-data suppression, automatic/manual lane selection, confidence,
monthly input validation, local calendar boundaries and DST. The panel matrix
adds both styles, spend-only and unavailable-budget cases, and the six
compositions needed when spend, credits, automatic quota labels and compact
pace text are all enabled. The
`monthly-allowance` smoke scenario renders the production popup with a synthetic
60%-used monthly window resetting in ten days and checks its 4% daily reading.
These checks establish the frontend contract, not provider authentication.
