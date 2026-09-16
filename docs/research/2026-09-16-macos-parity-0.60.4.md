# Linux parity review at CodexBar 0.60.4

Checked 2026-09-16 against Plasma commit
[`8d49266`](https://github.com/Lucenx9/codexbar-plasma/commit/8d49266166c3e892a1c52f191b57cf44374bc498).
The macOS reference is official
[`v0.60.4`](https://github.com/steipete/CodexBar/releases/tag/v0.60.4),
commit [`937b20813cf47340093b6c312331c63a52768097`](https://github.com/steipete/CodexBar/commit/937b20813cf47340093b6c312331c63a52768097),
published 2026-09-16 at 12:22:58 UTC.

This is a release-delta review for useful Linux behavior. It covers published
stable releases after the [0.58.0 review](2026-09-11-macos-parity-0.58.0.md)
through 0.60.4, with targeted source inspection and scoped CLI probes. It does
not repeat the full 0.56.2 contract audit. Current open parity work belongs in
[TODO.md](../../TODO.md).

## Release coverage

| Release | Published | Commit | Linux-relevant observations |
| --- | --- | --- | --- |
| [0.59.0](https://github.com/steipete/CodexBar/releases/tag/v0.59.0) | 2026-09-11 | `dca9c5f4b7a2721ec7d40d3211369d7a724dcacb` | Devin manual Bearer settings with manual quota requests on Linux; optional macOS pace colors; Codex spend/account-card fixes; Kimi exhausted-monthly in automatic menus. |
| [0.60.0](https://github.com/steipete/CodexBar/releases/tag/v0.60.0) | 2026-09-12 | `c22b9f08db71225a79a5d29f6074e93a5475e41c` | Separate Qt desktop app and Omarchy bar widget; Codex workspace credit balances; DeepSeek daily spend; Copilot credit allowances with legacy-default clearing; Linux Cursor authentication from the signed-in app; Antigravity local-history recovery; Manus empty-credits rejection. |
| [0.60.1](https://github.com/steipete/CodexBar/releases/tag/v0.60.1) | 2026-09-13 | `0b79c8edec8bbba2e15f566595578748409fb95b` | Account-card identity fixes with provider account-ID preservation under fallback labels; z.ai missing limits stay unavailable; Antigravity duplicate-row suppression; OAuth reserved-character preservation. |
| [0.60.2](https://github.com/steipete/CodexBar/releases/tag/v0.60.2) | 2026-09-14 | `3335e8a0d4d7a901889cbca506dd6290c17bbb1f` | Codex cost-estimate restoration; Antigravity quota recovery through the structured usage report; explicit credit-pool percentages (Warp, Perplexity, Abacus); Manus/MiMo/Neuralwatt quota counts, LiteLLM budgets, LongCat balances in CLI text/cards; Linux distro runtime documentation. |
| [0.60.3](https://github.com/steipete/CodexBar/releases/tag/v0.60.3) | 2026-09-15 | `9db44805dc1e0180993492bffd14ac98dd6a866f` | Cursor monthly/Grok-Bot weekly pace windows; known spend retained beside unpriced sources with a text-only partial-estimate marker; Claude session-warning and Remote-Control probe fixes. |
| [0.60.4](https://github.com/steipete/CodexBar/releases/tag/v0.60.4) | 2026-09-16 | `937b20813cf47340093b6c312331c63a52768097` | Last-known usage retention through transient failures; OpenCodex provider-attributed pricing with unpriced-instead-of-zero; dashboard bars default to remaining quota; Amp/Grok allowance fixes. |

## Linux CLI contract changes since 0.58.0

Compared `88fa2f4...937b208` under `Sources/CodexBarCLI/` (18 files) and the
consumed Core payload models. JSON keys below are source-observed on shared
`Codable` structs; fetcher-side behavior is CLI-owned. Nothing here replaces
authenticated output evidence.

- **Credit availability flags.** `CreditsSnapshot` gains `creditsAvailable:
  Bool?` and `balanceIsWorkspace: Bool` (always encoded); `balanceReadSucceeded`
  is now false whenever the provider omits the balance, including cap-only
  responses. `OpenAIDashboardSnapshot` gains `accountID`, `creditsAvailable`,
  and `balanceIsWorkspace`, plus a computed `requiresWorkspaceBalanceScope`.
  The dashboard builder now hides credits unless `balanceReadSucceeded`.
  Plasma still reads `remaining` without these flags, so the TODO verification
  candidate grows but stays unverified for Linux output.
- **Structured detail rows.** `ProviderDetailSection.Row` gains optional `id`,
  `progress: {used, total}`, and `usageValue`, all `Codable`. Copilot seat-credit
  rows use stable IDs (`copilot-seat-credits`) and Antigravity local SQLite rows
  carry progress. Labels stay opaque display strings. Plasma
  (`UsageDetails.js`) keeps only label/value/secondaryValue, so the numbers are
  currently dropped. This is a new generic contract awaiting Linux output
  verification, not an implemented feature.
- **Usage snapshot additions.** `copilotMeteredZeroCredits` (encoded only when
  true) distinguishes a metered seat with no visible credit row from an unread
  balance. `deepseekPlatformBalanceOwner` is live-only. `detailRow(id:)`
  supports lookup by the new stable row IDs.
- **Account identity.** `usage.identity` gains no new fields; the token-account
  label helper now preserves `accountID` instead of dropping it. The Claude
  account-email gap is unchanged.
- **Cost JSON unchanged.** `CostPayload`, daily entries, and coverage keys are
  identical; OpenCodex pricing refresh and the partial-estimate marker affect
  values and text rendering within the existing schema.
- **Status indicator unchanged.** The enum moved to Core and `label` became
  `cliLabel`; raw values and English strings are identical.
- **Cursor cost still gated.** The cost provider set remains descriptor-driven
  (`cli.supportsCostCommand`); Cursor still lacks it, so `cost --provider
  cursor` is rejected before the dashboard-API path. The new cookie-source
  availability errors are unreachable on Linux until the gate changes.
- **No config contracts.** `config` gains no descriptors, generic `set`, or
  `action` commands; the diff is a secret-cleaning refactor. New CLI output
  formats (`--format toon`) and flags (`--source`, `--all-accounts`,
  `--account-index`, cost `--provider-native-only`/`--group-by`) add no JSON
  envelope changes. The removed `CLIErrorReporting.printError` had no callers.
- **`serve` only.** `usageBarsShowUsed` (bars default to remaining quota) flows
  through the dashboard snapshot and web UI operation key. Plasma does not
  consume `serve`.

## 0.59.0–0.60.4 features against existing Plasma behavior

- **Cursor cost tracking (0.59.0–0.60.4).** Still rejected on Linux (see probes).
  Plasma's cost path is fully generic per selected provider, so no frontend
  change is needed once the CLI emits data. The TODO blocker stands with a new
  verified version.
- **Workspace balances and allowances (0.60.0).** Codex owner-visible balances,
  DeepSeek daily spend, and Copilot seat entitlements arrive through the generic
  `credits`/`openaiDashboard`/`details` fields above. Displaying a typed
  balance without parsing provider text still needs the verified availability
  contract, so the balance-text and rich-usage blockers stand with new source
  evidence.
- **Credit-pool percentages and quota counts (0.60.2).** Warp/Perplexity/Abacus
  percentages, LongCat balances, LiteLLM budgets, and Manus/MiMo/Neuralwatt
  counts are CLI text/cards rendering over existing quota fields. No new Plasma
  contract; the rich-usage blocker already covers generic allowances.
- **Last-known retention (0.60.4).** Codex, Claude OAuth, Cursor, and DeepSeek
  keep prior measurements through transient failures with original timestamps.
  Plasma already retains last-known quotas with age limits and stale marking;
  the new `usesLastKnownUsage` marker is cards-text-only. Existing native
  behavior, no gap.
- **Pace windows (0.59.0, 0.60.3–0.60.4).** Optional macOS pace colors and the
  Cursor/Grok-Bot window fixes are menu presentation and fetcher corrections.
  Plasma pace indicators keep signed values and existing presentation; a color
  preference was evaluated and not added (macOS chrome, low value).
- **Kimi exhausted monthly (0.59.0).** Automatic-menu selection semantics owned
  by each frontend; the existing exhausted-selection verification candidate
  already covers useful differences.
- **Antigravity recovery and dedup (0.60.0–0.60.2).** Local-history recovery,
  structured-report fallback, and duplicate-row suppression are fetcher-side;
  Linux output flows through the generic path with no Plasma change.
- **Devin on Linux (0.59.0).** Manual Bearer settings with manual quota requests
  are CLI-owned; browser import stays macOS-only. The isolated probe without
  manual configuration still reports macOS-only web support, so the manual path
  is source-observed and unverified. No Plasma change (generic path).
- **z.ai unavailable limits (0.60.1).** Missing limits stay unavailable instead
  of rendering 100%; Plasma must already treat absent bounds as unknown. No new
  contract.
- **Perplexity automatic window (0.60.x).** Upstream simplified its automatic
  selection to the first display window; automatic selection stays
  frontend-owned on Plasma. No port.
- **Account identity fixes (0.60.1).** Fresh subscription dates, no cross-account
  inheritance on empty cards, token-account ID preservation, and Claude alias
  labels are reconciler-side. Linux identity fields are unchanged; the
  account-identity verification candidate stands.
- **Linux desktop app and Omarchy widget (0.60.0).** Separate Linux surfaces
  outside this Plasma widget. Excluded as non-goal; no behavior ported.
- **Plugin switcher tabs (0.59.0).** macOS menu chrome. Excluded.
- **Documentation (0.60.2).** The upstream Linux distro-dependency and install
  flow note (#3615) concerns the CLI/desktop archives, not this widget's
  requirements. No README change.

## Scoped official Linux probes

The official `CodexBarCLI-v0.60.4-linux-x86_64.tar.gz` asset passed the
release's SHA-256 check:
`12b51e3016500a7068b73f45c50a034d0e436d6599430c83c1ee3112592005e3`.
Assets and checksum are on the [official release](https://github.com/steipete/CodexBar/releases/tag/v0.60.4).

Probes ran inside a network-isolated Bubblewrap process with temporary home,
configuration, cache, and data roots, a cleared environment, and no host
credentials reachable. No installed CLI was replaced. Executed from the
extracted asset it reports `CodexBar 0.60.4`, which the probes used.

| Probe | Result |
| --- | --- |
| `config providers --format json --json-only` | Exit 0; still 69 records, keys `provider`, `displayName`, `enabled`, `defaultEnabled`. No descriptor, `hiddenUsageItemIDs`, or `accentColor` emitted. |
| `config providers --descriptors --format json --json-only` | Exit 1, JSON envelope `provider: cli`, `error.kind: args`, `Unknown option --descriptors`. The descriptor remains unavailable. |
| `config --help` | Existing config commands only, `set-api-key` sole writer. No generic `set` or `action`. |
| `cost --provider cursor --format json --json-only` | Exit 1, `cost is only supported for Antigravity, Claude, Codex.` Cursor cost remains unavailable on Linux. |
| `cost --provider claude --format json --json-only` | Exit 0; empty history with `historyCoverageIsEstablished: true`, measured zeros, unchanged keys including `coverage` and `totals`. |
| `cost --provider antigravity --format json --json-only` | Exit 0; empty daily/projects, no cost totals, `historyCoverageIsEstablished: false`. Unchanged shape. |
| `cost --provider codex --format json --json-only` | Exit 0; empty history with `historyCoverageIsEstablished: true`. Unchanged shape. |
| `sessions --json-v2` | Exit 0, empty array in the isolated account. |
| `usage --provider cursor --format json --json-only` | Exit 1, `provider`-kind error with cookie-setup guidance. Envelope keys unchanged. |
| `usage --provider claude --format json --json-only` | Exit 1, `No available fetch strategy for claude.` Envelope keys unchanged. |
| `usage --provider devin --format json --json-only` | Exit 1, `selected source requires web support and is only supported on macOS.` The manual-quota path needs configured Bearer settings and stays unverified. |

No authenticated usage, credit validity, workspace balances, Copilot seat rows,
Antigravity progress rows, DeepSeek balances, z.ai limits, account switching,
provider balance units, or nonempty cost history was exercised. Those
limitations remain explicit in TODO; this is not a replacement for the full
0.56.2 audit.

## Carried-forward blockers

Every blocker in TODO remains open. No 0.60.4 change adds a provider settings
descriptor, generic config action, Cursor cost support, service-tier fields,
cost availability metadata beyond `historyCoverageIsEstablished`, structured
localization identifiers, or a display-currency contract. The new
credit-availability and detail-row fields are source-observed only; the scoped
0.60.4 probes re-verify the descriptor rejection, the absent generic config
commands, the Cursor cost rejection, and the unchanged cost/usage envelope
shapes at this version. The [0.56.2 audit](2026-09-01-macos-parity-0.56.2.md)
remains the contract baseline for unprobed authenticated cases.
