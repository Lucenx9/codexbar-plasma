# Linux parity review at CodexBar 0.57.0

Checked 2026-09-09 against Plasma commit
[`3e818ae71dda1ccada2e8f8d662bb883c21d4da9`](https://github.com/Lucenx9/codexbar-plasma/commit/3e818ae71dda1ccada2e8f8d662bb883c21d4da9).
The macOS reference is official
[`v0.57.0`](https://github.com/steipete/CodexBar/releases/tag/v0.57.0),
commit [`45cda6084d6415795053624b80ca3f8c05026580`](https://github.com/steipete/CodexBar/commit/45cda6084d6415795053624b80ca3f8c05026580),
published 2026-09-08 at 14:42:23 UTC.

This is a release-delta review for useful Linux behavior. It covers published
releases after the [0.56.2 contract audit](2026-09-01-macos-parity-0.56.2.md)
through 0.57.0, with targeted source inspection. It does not claim a new
exhaustive review of every macOS surface or live authenticated provider output.
The [settings comparison](2026-09-08-settings-experience.md) and
[daily cost evidence](../cost-history.md#pinned-cli-evidence) remain scoped
0.56.8 references. Current open parity work belongs in [TODO.md](../../TODO.md).

## Release coverage

All published stable releases in the interval were read. The official release
list contained no 0.56.9 release on the review date.

| Release | Linux-relevant observations |
| --- | --- |
| [0.56.3](https://github.com/steipete/CodexBar/releases/tag/v0.56.3) | Ollama monthly quota moves into the existing primary window. Provider parsing and cost scan fixes stay CLI-owned. Same-email workspace labels require account-contract checks before claiming parity. |
| [0.56.4](https://github.com/steipete/CodexBar/releases/tag/v0.56.4) | Codex scan completion and Antigravity Linux discovery improve upstream. Bedrock monitoring-charge guidance is relevant to Linux users. AppKit layout and app menus do not transfer. |
| [0.56.5](https://github.com/steipete/CodexBar/releases/tag/v0.56.5) | Codex purchased balances and monthly caps gain separate freshness semantics. Plasma already bounds charts and retains explicit day selection. Tailscale remote-host discovery and iCloud settings remain outside this widget. |
| [0.56.6](https://github.com/steipete/CodexBar/releases/tag/v0.56.6) | Exhausted automatic quota selection is a behavior to compare against Plasma's own lane policy. Cost repricing, Kimi enrichment, and Kiro parsing belong upstream. Native text-image caching and executable hook settings do not establish a frontend contract. |
| [0.56.7](https://github.com/steipete/CodexBar/releases/tag/v0.56.7) | Linux cache fixes benefit CLI consumers. Currency and unavailable-plan corrections arrive through provider output. WidgetKit age-label changes do not require copying WidgetKit. |
| [0.56.8](https://github.com/steipete/CodexBar/releases/tag/v0.56.8) | Account matching and malformed-history handling stay upstream. Plasma must continue isolating notification state by account and accepting corrected generic provider values. |
| [0.57.0](https://github.com/steipete/CodexBar/releases/tag/v0.57.0) | Spend freshness, automatic balance text, and Codex credit semantics deserve frontend follow-up. Claude breakdown output adds no JSON field. Provider recovery and scan fixes stay upstream. |

The table identifies affected areas; it is not evidence that every provider was
exercised with credentials. Source checks below determine the actionable gaps.

## Implementable with existing Linux data

### Refresh stale spend views when revisited

The macOS
[`PreferencesSpendDashboardPane`](https://github.com/steipete/CodexBar/blob/45cda6084d6415795053624b80ca3f8c05026580/Sources/CodexBar/PreferencesSpendDashboardPane.swift)
checks freshness on appearance and app activation, and responds to day and
timezone changes. Its
[`SpendDashboardController.refreshIfStale`](https://github.com/steipete/CodexBar/blob/45cda6084d6415795053624b80ca3f8c05026580/Sources/CodexBar/SpendDashboardController.swift)
guards concurrent work and snapshot age.

Plasma's [CostRefreshPolicy.js](../../contents/ui/CostRefreshPolicy.js) has an
hourly automatic interval. In [main.qml](../../contents/ui/main.qml), popup
expansion refreshes usage and sessions, while costs refresh at startup, on the
hourly timer, or through explicit actions. There is no spend-tab revisit or
calendar-day freshness trigger. A stale view can therefore await the next timer.

A Plasma implementation can use the existing cost command, retained snapshots,
and lifecycle guard. Add a bounded freshness decision for entering Usage &
Spend and crossing the bucket day. Preserve cached charts during refresh and
failed-attempt cooldowns. Selecting a metric or inspecting a day must still make
no request. These are local lifecycle decisions and need no new provider API.
The current [SpendView.qml](../../contents/ui/components/SpendView.qml) already
keeps loaded records visible while the refresh button indicates loading.

### Review automatic exhausted-quota selection

The 0.56.6 release changed macOS automatic quota choice when a supported quota
is exhausted. Plasma's `switcherCandidateRows` in
[main.qml](../../contents/ui/main.qml) has its own provider preference order;
[PanelDisplay.js](../../contents/ui/PanelDisplay.js) selects the first row that
supports the chosen mode. The relevant percentages are already available.

This is a Linux-implementable comparison, not a proven defect across all
providers. Evaluate exact provider cases before changing the automatic lane.
Keep direct primary/secondary/tertiary selections and intentional independent
quota pools. A blanket choice of the highest percentage is not established by
this review.

## Source-observed contract change requiring output verification

The pinned
[`CreditsModels.swift`](https://github.com/steipete/CodexBar/blob/45cda6084d6415795053624b80ca3f8c05026580/Sources/CodexBarCore/CreditsModels.swift)
encodes `credits.balanceReadSucceeded`. A false value distinguishes a retained
monthly-cap record after a failed balance read from a confirmed zero balance.
[`CodexExtraUsageCost.swift`](https://github.com/steipete/CodexBar/blob/45cda6084d6415795053624b80ca3f8c05026580/Sources/CodexBarCore/Providers/Codex/CodexExtraUsageCost.swift)
also separates purchased balance freshness from monthly-cap freshness.
[`CLIPayloads.swift`](https://github.com/steipete/CodexBar/blob/45cda6084d6415795053624b80ca3f8c05026580/Sources/CodexBarCLI/CLIPayloads.swift)
encodes that credits model, and the
[`Codex provider descriptor`](https://github.com/steipete/CodexBar/blob/45cda6084d6415795053624b80ca3f8c05026580/Sources/CodexBarCore/Providers/Codex/CodexProviderDescriptor.swift)
constructs it in CLI-capable strategies.

Plasma currently reads `credits.remaining` without that validity flag in
`normalizeProvider` in [main.qml](../../contents/ui/main.qml). Verify emitted
0.57.0 Linux records for failed reads, measured zero, and separate purchased
balances before implementing or closing this gap. This review has source
evidence only for those cases. Preserve legacy payload behavior and do not
reinterpret a cap remainder as purchased credit.

## Automatic balance text needs a generic contract

MacOS 0.57.0 can substitute a monetary or points balance for a missing automatic
percentage. The pinned
[`menuBarBalanceDisplayText`](https://github.com/steipete/CodexBar/blob/45cda6084d6415795053624b80ca3f8c05026580/Sources/CodexBar/StatusItemController+Animation.swift)
uses provider-specific branches, including parsing login-method strings,
reset descriptions, and a detail row named `Remaining`.
[`MenuBarLayoutRenderer.swift`](https://github.com/steipete/CodexBar/blob/45cda6084d6415795053624b80ca3f8c05026580/Sources/CodexBar/MenuBarLayoutRenderer.swift)
then consumes the prepared text.

Plasma's `compactText` supports an optional credit count, while automatic text
comes from a quota row. Reproducing every macOS fallback would require forbidden
provider-specific prose parsing. Track a generic typed balance or automatic
metric with unit/currency and availability semantics as an official CLI
requirement. Existing numeric credit display does not prove a money/points
contract. A future implementation must preserve genuine quota percentages and
avoid presenting a balance as an allowance meter.

## Existing paths and upstream ownership

The pinned
[`CLICostCommand.swift`](https://github.com/steipete/CodexBar/blob/45cda6084d6415795053624b80ca3f8c05026580/Sources/CodexBarCLI/CLICostCommand.swift)
passes `--breakdown` only to the text renderer. JSON still uses `makeCostPayload`
without that option. Plasma already displays daily model rows and period model
totals from the generic envelope, with missing values and truncation covered by
[the cost guide](../cost-history.md). Do not add the flag to widget commands or
call text output a new JSON contract.

Ollama's monthly quota in
[`OllamaUsageSnapshot.swift`](https://github.com/steipete/CodexBar/blob/45cda6084d6415795053624b80ca3f8c05026580/Sources/CodexBarCore/Providers/Ollama/OllamaUsageSnapshot.swift)
uses the existing primary rate window. The widget's generic normalization can
consume it. CLI parsing, pricing, account identity resolution, authentication
recovery, and cache correctness fixes remain upstream responsibilities. None
authorizes copying those implementations into QML.

Bedrock's monitoring-charge explanation is useful Linux documentation. The
macOS
[Bedrock provider implementation](https://github.com/steipete/CodexBar/blob/45cda6084d6415795053624b80ca3f8c05026580/Sources/CodexBar/Providers/Bedrock/BedrockProviderImplementation.swift)
is presentation evidence, not a generic settings descriptor. Any provider
setup notice should remain linked to official CLI/provider guidance until a
stable descriptor supports it.

## Scoped official Linux probes

The official `CodexBarCLI-v0.57.0-linux-x86_64.tar.gz` asset passed the
release's SHA-256 check:
`bde7f64464d608f6ff7c1544f83171ed49420a64652f20a2341576d689818b52`.
Assets and checksum are on the [official release](https://github.com/steipete/CodexBar/releases/tag/v0.57.0).
The binary reported `CodexBar 0.57.0`.

Final probes ran inside a network-isolated Bubblewrap process with temporary
home, configuration, cache, Claude, and Codex roots. Host home and runtime
credentials were inaccessible. No installed CLI was replaced. An initial run
with HOME/XDG environment overrides alone returned pre-existing synthetic cost
rows, so its cost observations were discarded. The isolated repeat returned
empty history. Environment overrides alone are insufficient evidence of cache
isolation for future audits.

| Probe | Result |
| --- | --- |
| `config providers --format json --json-only` | Exit 0; 69 records, none with a descriptor. This checks count and descriptor absence, not every metadata field. |
| `config providers --descriptors --format json --json-only` | Exit 1, unknown option. The descriptor remains unavailable. |
| `config --help` | Lists existing config commands, with no generic `set` or `action`. |
| `cost --provider cursor --format json --json-only` | Exit 1; supported list remains Antigravity, Claude, Codex. The broad provider list in help does not prove support. |
| `cost --provider claude --format json --json-only`, with and without `--breakdown` | Both exit 0. Parsed empty-history JSON is identical after excluding `updatedAt`. Together with the source check above, this confirms the option is not needed for JSON. |
| `cost --provider antigravity --format json --json-only` | Exit 0; empty daily/projects, no cost totals, history coverage not yet established. This does not retest the old established-empty sentinel. |
| `sessions --json-v2` | Exit 0, empty array in the isolated account. |

No authenticated usage, credit validity, account switching, provider balance
units, or nonempty history was exercised in these probes. Those limitations
remain explicit in TODO; this is not a replacement for the full 0.56.2 audit.

## Excluded from the Linux backlog

WidgetKit margins, Sparkle updates, AppKit menu positions/highlighting, Keychain
prompts, iCloud preferences, and native macOS window behavior are outside the
Plasma target. The official release links above retain that exclusion evidence.
MacOS session-host focus and app-managed low-power scan coordination do not
become widget requirements merely because they appear in release notes.
