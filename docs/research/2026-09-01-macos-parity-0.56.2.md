# CodexBar macOS parity at 0.56.2

Checked 2026-09-01. This is a read-only comparison of the official
`steipete/CodexBar` product against the Plasma baseline. It supersedes
[`2026-08-24-macos-parity-0.55.0.md`](./2026-08-24-macos-parity-0.55.0.md).

## Pinned scope

| Reference | Exact revision | Date |
| --- | --- | --- |
| Plasma baseline | [`06d488fc99fa3b735bd97ccf6447c47fd9c5c491`](https://github.com/Lucenx9/codexbar-plasma/commit/06d488fc99fa3b735bd97ccf6447c47fd9c5c491), plus this report | 2026-09-01 |
| Official baseline | [`v0.56.2`](https://github.com/steipete/CodexBar/releases/tag/v0.56.2), commit [`5351013a211f90df83b91d7ec2b788ff1c35c1f3`](https://github.com/steipete/CodexBar/commit/5351013a211f90df83b91d7ec2b788ff1c35c1f3) | published 2026-08-31 11:53 UTC |
| Intermediate releases | [`v0.55.1`](https://github.com/steipete/CodexBar/releases/tag/v0.55.1), [`v0.56.0`](https://github.com/steipete/CodexBar/releases/tag/v0.56.0), [`v0.56.1`](https://github.com/steipete/CodexBar/releases/tag/v0.56.1) | 2026-08-26 through 2026-08-30 |
| Previous baseline | `v0.55.0`, commit `061593ca15d904ab29858d23ed5e38298d6cad95` | 2026-08-24 |
| Linux CLI under test | official `CodexBarCLI-v0.56.2-linux-x86_64.tar.gz`, SHA-256 `34d7cf58f5ebad73b34b65b5da7677e11fb667ab9512cce010ec452098205316` | probed in isolation 2026-09-01 |

The GitHub Releases API reported v0.56.2 as the latest release at the end of
the check. The archive matched both its official `.sha256` file and the digest
published by GitHub. It was extracted into a temporary directory and was not
installed. Source claims come from the pinned tag and the official
[`v0.55.0...v0.56.2` comparison](https://github.com/steipete/CodexBar/compare/v0.55.0...v0.56.2).

## Verdict

The one material Linux frontend change is Antigravity local token history.
Starting with 0.56.1, `codexbar cost --provider antigravity` succeeds and emits
the existing `cost` envelope. Token totals and daily rows are available, dollar
costs are intentionally unknown, and incomplete history remains distinct from a
complete empty window. Cursor cost remains unavailable through the released
Linux CLI.

Plasma already requests and parses the generic cost envelope, so no new process
lifecycle or raw JSON parser is needed. One bounded presentation correction is
still required before Antigravity history is truthful. The current
[`normalizeCostDaily`](../../contents/ui/ProviderNormalizer.js) and
[`normalizeCostTotals`](../../contents/ui/ProviderNormalizer.js) paths convert a
missing cost to `0`. That makes token-only Antigravity rows look like zero-dollar
history in totals and cost-mode charts. The normalizer must preserve
"unavailable" separately from numeric zero, while the existing tokens metric
continues to render the token values. This is the recommended first frontend PR
from 0.56.2.

The provider catalog, `config providers`, `usage`, and `sessions --json-v2`
contracts remain compatible. No settings descriptor or generic action contract
was added. One fallback link drifted: OpenRouter now points its dashboard action
at Activity rather than credit settings. The other release changes either
improve values inside fields Plasma already consumes or are macOS UI,
persistence, credential, and performance work.

## Verified Linux CLI contracts

### Version, provider catalog, and configuration

```text
$ CodexBarCLI --version
CodexBar 0.56.2

$ CodexBarCLI config providers --format json --json-only
records: 69
record keys: defaultEnabled, displayName, enabled, provider

$ CodexBarCLI config providers --descriptors --format json --json-only
[{"provider":"cli","error":{"code":1,"message":"Unknown option --descriptors","kind":"args"},"source":"cli"}]
```

The canonical provider ID, display name, and default-enabled map was
byte-for-byte equal to the verified v0.55.0 output. The tagged
[`ProviderManifest.swift`](https://github.com/steipete/CodexBar/blob/v0.56.2/Sources/CodexBarCore/Providers/ProviderManifest.swift)
and
[`Providers.swift`](https://github.com/steipete/CodexBar/blob/v0.56.2/Sources/CodexBarCore/Providers/Providers.swift)
also have no changes from v0.55.0.

`config --help` still exposes only `validate`, `dump`, `providers`, `enable`,
`disable`, and `set-api-key`. There is no descriptor, `config set`, or
`config action`; the tagged
[`CLIConfigCommand.swift`](https://github.com/steipete/CodexBar/blob/v0.56.2/Sources/CodexBarCLI/CLIConfigCommand.swift)
confirms that command set.

### Usage and sessions

The `ProviderPayload` source is unchanged from v0.55.0. It still encodes the
same optional `usage`, `credits`, `pace`, account, and error records through
[`CLIPayloads.swift`](https://github.com/steipete/CodexBar/blob/v0.56.2/Sources/CodexBarCLI/CLIPayloads.swift).
Provider improvements such as Bailian quotas, Fireworks spend, Grok recovery,
Antigravity quota selection, and OpenCode Go pace suppression therefore flow
through existing fields.

An isolated `sessions --json-v2` probe returned `[]`. The tagged
[`CLISessionsCommand.swift`](https://github.com/steipete/CodexBar/blob/v0.56.2/Sources/CodexBarCLI/CLISessionsCommand.swift)
and its JSON model are unchanged. Optional session fields remain `id`,
`provider`, `dialect`, `source`, `state`, `pid`, `cwd`, `projectName`,
`sessionName`, `startedAt`, `lastActivityAt`, `transcriptPath`, and `host`.
Plasma must continue discarding paths, IDs, and PIDs.

### Cost

The verified v0.55.0 CLI rejected Antigravity cost and listed only Claude and
Codex. The v0.56.2 CLI accepts Antigravity:

```text
$ CodexBarCLI cost --provider antigravity --days 7 --format json --json-only
record keys when local history is unavailable:
coverage, currencyCode, daily, historyCoverageIsEstablished, historyDays,
projects, provenance, provider, source, updatedAt

provider: antigravity
source: local
historyCoverageIsEstablished: false
daily: []
projects: []
provenance: unknown
```

An explicit Cursor request still fails with `cost is only supported for
Antigravity, Claude, Codex`. `--provider all` includes those three supported
providers. The exact source enables Antigravity through
[`AntigravityProviderDescriptor.swift`](https://github.com/steipete/CodexBar/blob/v0.56.2/Sources/CodexBarCore/Providers/Antigravity/AntigravityProviderDescriptor.swift)
and routes it through the existing payload in
[`CLICostCommand.swift`](https://github.com/steipete/CodexBar/blob/v0.56.2/Sources/CodexBarCLI/CLICostCommand.swift).

The JSON schema itself did not change. A valid Antigravity snapshot carries
tokens with nil dollar costs; corrupt, partial, or absent stores keep
`historyCoverageIsEstablished` false. An established but empty snapshot is the
exception: CLI 0.56.2 emits zero for both token and dollar totals, while its text
renderer still says dollar costs are unavailable. No generic JSON field
distinguishes that sentinel from an observed zero, so Plasma masks cost totals
for Antigravity at the provider normalization boundary. An explicit CLI cost
availability field remains the upstream contract requirement. The official
[`AntigravityCLICostTests.swift`](https://github.com/steipete/CodexBar/blob/v0.56.2/Tests/CodexBarTests/AntigravityCLICostTests.swift)
pins those semantics. Project records remain Codex-only and keep the same
`name`, local `path`, totals, daily rows, model breakdowns, and sources. Plasma
must not retain or expose `path`.

## Changes since 0.55.0

| Release item | Official source | Classification | Plasma consequence |
| --- | --- | --- | --- |
| Antigravity bounded local SQLite/JSONL token history and 0.56.1 CLI routing | [v0.56.0](https://github.com/steipete/CodexBar/releases/tag/v0.56.0), [v0.56.1](https://github.com/steipete/CodexBar/releases/tag/v0.56.1) | **Plasma-native and implementable now** | The existing cost envelope and token charts are reusable. Preserve missing dollar costs instead of coercing them to zero, and describe the record as token-only history. |
| Cursor estimates when usage events omit prices | [v0.56.0](https://github.com/steipete/CodexBar/releases/tag/v0.56.0) | **Blocked on an official Linux CLI contract** | The app has a reader, but released `cost --provider cursor` still fails. Do not read Cursor databases, cookies, or caches in QML. |
| Codex, Claude, OpenCodex, and local-cost cache correctness/performance fixes | [v0.56.2](https://github.com/steipete/CodexBar/releases/tag/v0.56.2) | **Already covered by generic paths** | Totals, token classes, model totals, coverage, provenance, and daily rows improve inside the existing cost payload. No new QML branch is required. |
| Fireworks billing restoration | [v0.55.1](https://github.com/steipete/CodexBar/releases/tag/v0.55.1) | **Already covered by generic paths** | Spend remains `usage.providerCost`, which Plasma already normalizes. The CLI owns API access and account discovery. |
| Bailian CLI Token Plan quotas, Grok recovery, Antigravity cadence selection, and OpenCode Go scale/pace fixes | [v0.55.1](https://github.com/steipete/CodexBar/releases/tag/v0.55.1), [v0.56.0](https://github.com/steipete/CodexBar/releases/tag/v0.56.0), [v0.56.2](https://github.com/steipete/CodexBar/releases/tag/v0.56.2) | **Already covered by generic paths** | These alter existing usage windows, confidence, identity, and pace values. Plasma should consume the corrected payloads unchanged. |
| OpenCode Go monthly menu-bar metric | [v0.55.1](https://github.com/steipete/CodexBar/releases/tag/v0.55.1) | **Already covered for data; optional Plasma-native layout work** | The monthly value uses the existing tertiary window. Direct lane placement and conditional rules still need a Plasma-native settings model, not Swift layout persistence. |
| AED display currency | [v0.55.1](https://github.com/steipete/CodexBar/releases/tag/v0.55.1) | **Already covered by generic paths** | Plasma accepts bounded currency codes and displays the emitted code. Currency selection and exchange remain CLI-owned. |
| Agent-session scan deadline fixes | [v0.56.2](https://github.com/steipete/CodexBar/releases/tag/v0.56.2) | **Already covered by generic paths** | The `sessions --json-v2` contract is unchanged; scans should simply complete with less filesystem work. |
| OpenRouter dashboard action | [`OpenRouterProviderDescriptor.swift`](https://github.com/steipete/CodexBar/blob/v0.56.2/Sources/CodexBarCore/Providers/OpenRouter/OpenRouterProviderDescriptor.swift) | **Plasma-native and implementable now** | Sync the fallback URL from `/settings/credits` to `/activity`; provider identity, icon, and CLI aliases are otherwise unchanged. |
| Credits-history and plan-history chart fixes | [v0.56.2](https://github.com/steipete/CodexBar/releases/tag/v0.56.2) | **macOS-only/non-goal at this layer** | They change native chart presentation, not Linux JSON. There is still no generic history payload to consume. |
| Codex Workspaces navigation, menu-card height caching, privacy masking, Keychain behavior, and localization changes | [v0.56.1](https://github.com/steipete/CodexBar/releases/tag/v0.56.1) | **macOS-only/non-goal** | Do not reproduce AppKit navigation, persistence, credential, or privacy-mode machinery in the widget. |

## Plasma-native and implementable now

### Preserve token-only cost semantics

The cost boundary validates records, bounds history, and retains whether each
cost amount was present. Antigravity token totals, daily points, model totals,
and coverage use the existing token metric while cost-mode summaries and charts
remain unavailable. Missing amounts stay generic at the numeric boundary. The
0.56.2 established-empty sentinel requires one provider compatibility rule and
an Antigravity-specific hint until the CLI exposes explicit cost availability.

### Fireworks single-key setup

This is not a new 0.56.2 contract, but it remains a small independent frontend
follow-up. `config set-api-key --provider fireworks --stdin` is supported
because the tagged
[`FireworksProviderDescriptor.swift`](https://github.com/steipete/CodexBar/blob/v0.56.2/Sources/CodexBarCore/Providers/Fireworks/FireworksProviderDescriptor.swift)
uses the generic API-key credential adapter. If no account slug is stored, the
official
[`FireworksUsageFetcher.swift`](https://github.com/steipete/CodexBar/blob/v0.56.2/Sources/CodexBarCore/Providers/Fireworks/FireworksUsageFetcher.swift)
discovers the single visible account and the strategy persists it. Plasma can
therefore add Fireworks to its existing allowlisted single-key setup path; it
does not need a slug editor for the common single-account case. Multiple visible
accounts still require an explicit slug and remain blocked on a generic field
or action descriptor.

### OpenRouter dashboard fallback

The v0.56.2
[`OpenRouterProviderDescriptor.swift`](https://github.com/steipete/CodexBar/blob/v0.56.2/Sources/CodexBarCore/Providers/OpenRouter/OpenRouterProviderDescriptor.swift)
uses `https://openrouter.ai/activity` for its dashboard action. Plasma's
fallback map still uses `https://openrouter.ai/settings/credits`. Updating that
single bounded fallback and its drift assertion is implementable now.

Project-spend presentation and direct or conditional panel rules also remain
implementable from existing bounded data, but 0.56.2 does not increase their
priority. A project view must discard local paths. Panel rules must use a
Plasma-native configuration model. The weekly reserve token remains optional
and unchanged.

## Blocked on an official Linux CLI contract

| Gap | Why it remains blocked at 0.56.2 |
| --- | --- |
| Generic provider settings and actions | No settings descriptor, `config set`, or `config action`. |
| Cursor local or dashboard cost | The released Linux CLI still rejects Cursor cost. Private app readers are not a frontend contract. |
| Explicit Grok unknown-usage row with reset | A genuinely unavailable percentage still has no generic unknown-window representation in Linux JSON. Do not infer it from diagnostics. |
| Browser-cookie, OAuth, local-file, CLI-auth, and general token-account onboarding | No JSON-described action contract. The z.ai-specific `set-api-key` options do not make a generic editor. |
| Credits history, plan-utilization history, hourly activity, and forecasts | No stable generic Linux history payload. Chart work in 0.56.2 is native UI only. |
| Rich request and pricing-detail presentation | The cost envelope carries bounded totals and coverage, but there is no generic CLI-described UI contract for provider-specific breakdown sections. |
| Currency selection and conversion | AED joins the app converter, but Linux `config` still has no setter or descriptor for display currency. |

## macOS-only or non-goals

Codex Workspaces navigation, native menu layout persistence, menu-card sizing,
privacy-mode project masking, Keychain migration preferences, app-managed cost
catch-up, chart submenu layout, WidgetKit, Sparkle, remote session focus, and
iCloud sync remain macOS-only or non-goals. Plasma should keep its own bounded
sessions, configuration, translation, update, and panel-composition paths.

## Provider catalog

The verified 0.56.2 Linux CLI reports the same 69 provider IDs, display names,
and default-enabled values as the verified 0.55.0 CLI. The tagged provider enum
and manifest are also unchanged. No provider key, alias, title, color, status
URL, or icon sync is required. The OpenRouter dashboard fallback is the only
metadata update: it now targets `https://openrouter.ai/activity`.

## Recommended parity decision

1. Recommend the checksum-verified CodexBar CLI 0.56.2 so existing generic
   usage, cost, and session paths receive the upstream fixes.
2. Make missing-versus-zero cost preservation, including truthful Antigravity
   token-only history, the first frontend PR from this audit.
3. Sync the OpenRouter dashboard fallback in that PR or as an independent
   one-line metadata correction.
4. Enable Fireworks in the existing generic API-key setup path as a separate
   small follow-up, while leaving multi-account slug editing blocked.
5. Keep Cursor cost, provider editors, onboarding actions, and history surfaces
   at the official CLI boundary.

No broad QML refactor or provider catalog expansion is justified by 0.56.2.
