# CodexBar macOS parity at 0.55.0

Checked 2026-08-24. This is a read-only comparison of the official
`steipete/CodexBar` product against the Plasma baseline. It supersedes
[`2026-08-20-macos-parity-0.54.0.md`](./2026-08-20-macos-parity-0.54.0.md).

## Pinned scope

| Reference | Exact revision | Date |
| --- | --- | --- |
| Plasma baseline | [`849457bbeafd185e48591b5b8a1cbb9932864f68`](https://github.com/Lucenx9/codexbar-plasma/commit/849457bbeafd185e48591b5b8a1cbb9932864f68), plus this report | 2026-08-24 |
| Official baseline | [`v0.55.0`](https://github.com/steipete/CodexBar/releases/tag/v0.55.0), commit [`061593ca15d904ab29858d23ed5e38298d6cad95`](https://github.com/steipete/CodexBar/commit/061593ca15d904ab29858d23ed5e38298d6cad95) | published 2026-08-24 08:14 UTC |
| Intermediate release | [`v0.54.1`](https://github.com/steipete/CodexBar/releases/tag/v0.54.1), commit [`d6d281e898a0691685d04640bb40d1ff2c3390ea`](https://github.com/steipete/CodexBar/commit/d6d281e898a0691685d04640bb40d1ff2c3390ea) | published 2026-08-23 10:45 UTC |
| Previous baseline | `v0.54.0`, commit `22a2168842a9ed4fdd15dd6761cd109c56bcd3b5` | 2026-08-20 |
| Linux CLI under test | official `CodexBarCLI-v0.55.0-linux-x86_64.tar.gz`, SHA-256 `132ce0b2ec5de1f3540c33dccdbfe278d5cb9d29d259ec3653b7a88f4a4c356b` | probed in isolation 2026-08-24 |
| Host-installed Linux CLI | `codexbar` 0.55.0 | upgraded after the isolated probes on 2026-08-24 |

The GitHub Releases API reported v0.55.0 as the latest release at the end of the
check. The official 0.55.0 checksum file matched the downloaded Linux archive.
All 0.55.0 CLI claims below come from that verified binary. The same verified
archive was installed after the comparison, with the previous 0.54.0 directory
kept as a local rollback. Source claims come from the pinned tag and the official
[`v0.54.0...v0.55.0` comparison](https://github.com/steipete/CodexBar/compare/v0.54.0...v0.55.0).

## Verdict

There is no broad Plasma rework to do for 0.55.0. The provider catalog, config
commands, and the main `usage`, `cost`, and `sessions` JSON shapes remain
compatible. The missing machine-readable provider settings and action
descriptor is still the main configuration boundary.

Most useful provider changes already fit contracts the widget consumes:

- Kiro overage usage uses `usage.extraRateWindows`, `usage.providerCost`, and
  `usage.details`.
- z.ai BigModel CN balance is a `usage.details` row.
- Cursor Grok Bot usage is an extra rate window.
- parser, token-count, and cost fixes change the values inside existing fields.

Those changes need the 0.55.0 CLI, not new QML.

One frontend gap is now worth recording. `credits.codexCreditLimit` is an
optional official field with `used`, `limit`, `remaining`, `remainingPercent`,
and reset metadata. v0.54.1 made the Business and Enterprise monthly limit more
reliable. Plasma currently drops the nested field and renders only
`credits.remaining`. A bounded Codex monthly-limit projection is implementable
now. It must stay separate from generic credit balances, which still have no
allowance and must not regain an invented meter.

There is also one contract limitation hidden by the macOS release notes. The new
Cursor and Antigravity local spend readers are not exposed by the released Linux
`cost` command. The 0.55.0 binary rejects both providers and says cost is only
supported for Claude and Codex. Plasma must not read tokscale or provider cache
files to copy the macOS dashboard.

## Live Linux CLI probes

### Version and provider configuration

```text
$ CodexBarCLI --version
CodexBar 0.55.0

$ CodexBarCLI config providers --format json --json-only | jq 'length'
69

$ CodexBarCLI config providers --format json --json-only \
    | jq -r '[.[] | keys] | add | unique | join(", ")'
defaultEnabled, displayName, enabled, provider

$ CodexBarCLI config providers --descriptors --format json --json-only
[{"error":{"code":1,"kind":"args","message":"Unknown option --descriptors"},"source":"cli","provider":"cli"}]
```

The sorted provider ID and display-name map has the same SHA-256 on 0.54.0 and
0.55.0: `46fc8f51b763f61e58a9c8f72e5fae8e20a5100124b590e20d7e60b581e2fd9c`.
No fallback catalog sync is needed.

`config --help` still lists only `validate`, `dump`, `providers`, `enable`,
`disable`, and `set-api-key`. There is no `config set`, `config action`, or
settings descriptor. The tagged
[`CLIConfigCommand.swift`](https://github.com/steipete/CodexBar/blob/v0.55.0/Sources/CodexBarCLI/CLIConfigCommand.swift)
confirms the same command set.

### Usage contract

A live refresh of the enabled providers returned four healthy records. Only
field names and provider IDs were retained for this report:

```text
record keys:
credits, pace, provider, source, usage, version

providers:
antigravity, codex, openrouter, zai

usage keys:
accountEmail, codexResetCredits, dataConfidence, details, extraRateWindows,
identity, loginMethod, primary, secondary, tertiary, updatedAt

detail row keys:
label, secondaryValue, value

credits keys observed on this account:
events, remaining, updatedAt
```

`usage --provider codex --all-accounts` also matched 0.54.0. The current account
returned one record with `account`, `credits`, `pace`, `provider`, `source`,
`usage`, and `version`.

The output shape matched the pre-upgrade host 0.54.0 binary. Optional fields only
appear when a provider has data, so the live Codex account did not exercise
`credits.codexCreditLimit`. The contract is still confirmed by
[`ProviderPayload`](https://github.com/steipete/CodexBar/blob/v0.55.0/Sources/CodexBarCLI/CLIPayloads.swift),
which encodes `CreditsSnapshot` directly, and
[`CreditsModels.swift`](https://github.com/steipete/CodexBar/blob/v0.55.0/Sources/CodexBarCore/CreditsModels.swift),
which defines the optional nested limit and all of its fields. The previous
0.54.0 report's statement that `usage.credits` has no allowance remains correct
for a plain generic balance, but it was too broad for this optional Codex-only
record.

### Cost and sessions contracts

```text
$ CodexBarCLI cost --days 7 --format json --json-only
record keys:
coverage, currencyCode, daily, historyCoverageIsEstablished, historyDays,
last30DaysCostUSD, last30DaysTokens, projects, provenance, provider,
sessionCostUSD, sessionTokens, source, totals, updatedAt

coverage keys:
estimated, priced, unmetered, unpriced

project keys:
daily, modelBreakdowns, name, path, sources, totalCost, totalTokens

$ CodexBarCLI sessions --json-v2
record keys:
cwd, dialect, host, id, lastActivityAt, pid, projectName, provider,
sessionName, source, state, transcriptPath
```

The 0.54.0 and 0.55.0 key sets matched. Plasma must keep discarding project
paths, session paths, IDs, and PIDs.

The new macOS spend readers do not widen the Linux command:

```text
$ CodexBarCLI cost --provider cursor --days 7 --format json --json-only
Error: cost is only supported for Claude, Codex.

$ CodexBarCLI cost --provider antigravity --days 7 --format json --json-only
Error: cost is only supported for Claude, Codex.
```

This agrees with
[`CLICostCommand.swift`](https://github.com/steipete/CodexBar/blob/v0.55.0/Sources/CodexBarCLI/CLICostCommand.swift),
which includes only descriptors that opt into the CLI cost command. The local
readers in
[`CostUsageFetcher.swift`](https://github.com/steipete/CodexBar/blob/v0.55.0/Sources/CodexBarCore/CostUsageFetcher.swift)
feed the full app but do not create a Linux frontend contract by themselves.

## Changes since 0.54.0

| Release item | Official source | Plasma consequence |
| --- | --- | --- |
| Codex CLI 0.149 approval compatibility, Alibaba parsing, Command Code plan recognition | [v0.54.1 release notes](https://github.com/steipete/CodexBar/releases/tag/v0.54.1) | Provider fixes inherited by upgrading the CLI. No QML change. |
| Codex priority-scan cursor and spend loading concurrency | [v0.54.1 release notes](https://github.com/steipete/CodexBar/releases/tag/v0.54.1) | Cache and load performance changes. The cost JSON contract is unchanged. |
| Cursor Grok Bot allowance | [`CursorSandUsage.swift`](https://github.com/steipete/CodexBar/blob/v0.55.0/Sources/CodexBarCore/Providers/Cursor/CursorSandUsage.swift) | Emitted as `extraRateWindows`. Plasma already renders bounded unknown extra windows. |
| Kiro overage credits and charges | [`KiroStatusProbe.swift`](https://github.com/steipete/CodexBar/blob/v0.55.0/Sources/CodexBarCore/Providers/Kiro/KiroStatusProbe.swift) | Existing generic extra-window, cost, and detail-row paths render it. The official CLI owns Kiro credentials and service access. |
| z.ai BigModel CN balance | [`zai.js`](https://github.com/steipete/CodexBar/blob/v0.55.0/Sources/CodexBarCore/Resources/Plugins/zai.js) | Emitted as a generic detail row. Plasma already renders it. |
| Codex Business and Enterprise monthly credit | [v0.54.1 release notes](https://github.com/steipete/CodexBar/releases/tag/v0.54.1), [`CodexProviderDescriptor.swift`](https://github.com/steipete/CodexBar/blob/v0.55.0/Sources/CodexBarCore/Providers/Codex/CodexProviderDescriptor.swift), [`CreditsModels.swift`](https://github.com/steipete/CodexBar/blob/v0.55.0/Sources/CodexBarCore/CreditsModels.swift) | `credits.codexCreditLimit` is implementable now. Plasma currently ignores it. |
| Antigravity warm `agy` reuse and offline fallback | [`AntigravityProviderDescriptor.swift`](https://github.com/steipete/CodexBar/blob/v0.55.0/Sources/CodexBarCore/Providers/Antigravity/AntigravityProviderDescriptor.swift) | Quota and offline identity improvements flow through `usage`. Local spend remains unavailable through Linux `cost`. |
| Codex and OpenCodex token and spend fixes | [v0.55.0 release notes](https://github.com/steipete/CodexBar/releases/tag/v0.55.0) | Correctness and speed improvements inherited through the existing cost payload. |
| OpenRouter completed-day spend fix | [v0.55.0 release notes](https://github.com/steipete/CodexBar/releases/tag/v0.55.0) | Existing usage and spend fields become healthy again. No frontend branch. |
| Gemini shutdown guidance | [v0.55.0 release notes](https://github.com/steipete/CodexBar/releases/tag/v0.55.0) | Provider guidance can flow as an existing error message. The macOS inline enable action has no JSON action contract. |
| Grok period-only responses become unknown instead of 0% | [`GrokCreditsProxyFetcher.swift`](https://github.com/steipete/CodexBar/blob/v0.55.0/Sources/CodexBarCore/Providers/Grok/GrokCreditsProxyFetcher.swift) | The Linux usage snapshot omits the primary window, so Plasma no longer receives a false zero. A distinct "unknown usage" row with reset metadata still needs a generic CLI representation. |
| CHF display currency | [`CurrencyExchange.swift`](https://github.com/steipete/CodexBar/blob/v0.55.0/Sources/CodexBarCore/CurrencyExchange.swift) | Plasma already accepts bounded currency codes and will print CHF payloads. Selecting or converting currency stays CLI-owned. |
| ChatGPT.app Codex activity detection | [`AgentSession.swift`](https://github.com/steipete/CodexBar/blob/v0.55.0/Sources/CodexBarCore/AgentSession.swift) | macOS app refresh behavior. The Linux `sessions --json-v2` shape is unchanged. |
| Single-quota and merged Warp icon fixes | [v0.55.0 release notes](https://github.com/steipete/CodexBar/releases/tag/v0.55.0) | AppKit status-icon layout. Plasma uses its own panel meter composition. |
| Layout editor, plan-history merge, browser-cookie ordering, and spend-dashboard timezone refresh | [v0.54.1](https://github.com/steipete/CodexBar/releases/tag/v0.54.1), [v0.55.0](https://github.com/steipete/CodexBar/releases/tag/v0.55.0) | macOS UI or persistence behavior. No Linux JSON contract was added. |
| Codex profile-switch state, Claude swap and iCloud records, agent-session menu width, and upstream localization | [v0.54.1 release notes](https://github.com/steipete/CodexBar/releases/tag/v0.54.1) | macOS account, menu, persistence, and catalog work. Plasma has separate bounded account labels and its own translation catalog. |
| CLI installer PATH diagnostics | [v0.55.0 release notes](https://github.com/steipete/CodexBar/releases/tag/v0.55.0) | Upstream CLI installation behavior. The Plasma widget does not install or replace the CLI. |

## Plasma-native and implementable now

### Codex monthly credit limit

The widget should eventually normalize a bounded `credits.codexCreditLimit`
record and present the CLI-provided title, used amount, limit, remaining amount,
percentage, and reset time. The normalizer must reject malformed or non-finite
numbers and clamp percentages. The popup may show a meter only when this nested
record supplies the denominator.

This does not reverse the existing generic credit decision. A plain
`credits.remaining` value still has no allowance. It remains a balance line
without a meter.

The current generic paths already cover the other new provider data:

- [`main.qml`](../../contents/ui/main.qml) iterates bounded
  `usage.extraRateWindows` and maps `usage.providerCost`.
- [`UsageDetails.js`](../../contents/ui/UsageDetails.js) bounds and validates
  provider-defined rows and charts.

No provider-specific Kiro, z.ai, or Cursor QML should be added.

## Blocked on an official Linux CLI contract

| Gap | Why it remains blocked at 0.55.0 |
| --- | --- |
| Generic provider settings and actions | No descriptor, `config set`, or `config action`. |
| Cursor and Antigravity local spend | The released Linux CLI rejects both `cost --provider` requests. The app's private local readers are not a frontend contract. |
| Explicit Grok unknown-usage row with reset | A nil Grok percentage becomes an absent primary window in `UsageSnapshot`; the reset has no generic unknown-window representation in Linux JSON. |
| Browser-cookie, OAuth, local-file, CLI-auth, and token-account onboarding | No JSON-described action contract. |
| Hourly activity, credits history, plan-utilization history, and session-equivalent forecasts | No stable generic Linux history payload. |
| Currency selection and conversion | CHF is supported by the app's converter, but Linux `config` has no generic setter or descriptor for it. Plasma should display the CLI currency, not perform exchange-rate work. |

The project-spend projection, conditional panel rules, direct lane elements,
pace visibility, and weekly reserve token from the 0.54.0 report remain optional
Plasma work. v0.55.0 does not change their contracts or priority.

## macOS-only or non-goals

ChatGPT.app activity detection, menu-bar icon lane geometry, menu layout drag and
drop, plan-utilization history persistence, signed-build Keychain behavior,
browser-cookie discovery and ordering, app-managed spend refresh publication,
WidgetKit, Sparkle, remote SSH focus, and iCloud sync remain macOS-only or
non-goals for this repository.

The Gemini shutdown notice can flow through the CLI as provider guidance.
Plasma already lets users enable Antigravity from its Providers page. It should
not parse free-form error text to synthesize the macOS inline action.

## Provider catalog

The verified 0.55.0 Linux CLI reports the same 69 provider IDs and display names
as 0.54.0. No provider, alias, title, color, link, or icon sync is required for
this release.

## Recommended parity decision

1. Recommend CodexBar CLI 0.55.0 so the widget receives the provider and cost
   fixes through existing JSON fields.
2. Make bounded `credits.codexCreditLimit` presentation the only new frontend
   follow-up from this release. Keep plain credit balances meter-free.
3. Keep Cursor and Antigravity local spend, explicit Grok unknown-reset
   presentation, and configuration editors at the CLI boundary.

No urgent QML correction is required for 0.55.0 itself.
