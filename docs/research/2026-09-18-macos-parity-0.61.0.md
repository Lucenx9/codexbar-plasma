# Linux parity review at CodexBar 0.61.0

Checked 2026-09-18 against Plasma commit
[`f589bff`](https://github.com/Lucenx9/codexbar-plasma/commit/f589bffdfc593b0d3338532cbed0349a349faa97).
The macOS reference is official
[`v0.61.0`](https://github.com/steipete/CodexBar/releases/tag/v0.61.0),
commit [`60a677e6b22e160675e1bf2b2be1b57d54598f3b`](https://github.com/steipete/CodexBar/commit/60a677e6b22e160675e1bf2b2be1b57d54598f3b),
published 2026-09-18 at 17:42:32 UTC.

This is a release-delta review for useful Linux behavior. It covers the single
stable release published after the
[0.60.5 review](2026-09-18-macos-parity-0.60.5.md) and does not repeat the full
[0.56.2 contract audit](2026-09-01-macos-parity-0.56.2.md). Current open parity
work belongs in [TODO.md](../../TODO.md).

## Release coverage

| Release | Published | Commit | Linux-relevant observations |
| --- | --- | --- | --- |
| [0.61.0](https://github.com/steipete/CodexBar/releases/tag/v0.61.0) | 2026-09-18 | `60a677e6b22e160675e1bf2b2be1b57d54598f3b` | Provider registry grows from 69 to 74 with Nous Portal, Muse Code, CodeRabbit, Replicate, and Hugging Face; Grok gains a generic reset-credit detail row; Azure OpenAI gains an API-version config extension with no CLI writer; usage, cost, sessions, and config JSON envelopes are otherwise unchanged. |

## Linux CLI contract changes since 0.60.5

Compared `2ac2323...60a677e` (255 changed files) under `Sources/CodexBarCLI/`,
`Sources/CodexBarCore/`, and the consumed payload models.

- **Provider registry grows to 74 (verified in emitted output).** `config
  providers --format json --json-only` returns 74 records with unchanged keys
  `provider`, `displayName`, `enabled`, and `defaultEnabled`. The added IDs are
  `nous` (Nous Portal), `muse` (Muse Code), `coderabbit` (CodeRabbit),
  `replicate` (Replicate), and `huggingface` (Hugging Face). The same five IDs
  appear in the `--provider` enumerations of `usage --help` and `cost --help`.
  Nous, Muse, and Hugging Face ship as bundled provider plugins
  (`Resources/Plugins/{nous,muse,huggingface}.js`); CodeRabbit reads a bounded
  local CLI report and carries the release's only `TestsLinux` addition.
- **New generic Grok detail row (source-observed).** `GrokRemainingResetsFetcher`
  emits a `ProviderDetailSection` with no title holding one row labelled
  `Limit Reset Credits` with a value of the form `N available`. The wiring is in
  the shared Core fetch strategies, not in app-only code, so it reaches CLI JSON
  through the existing `details` array. Plasma's `UsageDetails.js` keeps an
  untitled section that still carries rows, so the row renders through the
  existing generic details path with no code change. Authenticated Grok output
  was not exercised, and the row is gated on the pre-existing
  `requiresOptionalUsageCompleteness` fetch-context flag, which this diff does
  not define; treat the row as source-observed until an authenticated probe
  confirms it.
- **`grokResetCredits` is not a JSON contract.** `UsageSnapshot` gains a
  `grokResetCredits` property, but `GrokRateLimitResetCreditsSnapshot` is
  `Sendable, Equatable` and not `Codable`, `init(from:)` sets the property to
  `nil` with the comment "Live-only inventory; refresh without persisting
  redemption state", and upstream documents that redemption token identifiers
  "never enter a UsageSnapshot or its persisted JSON". Plasma must not expect
  the key.
- **`codexResetCredits` survives the macOS rename.** `UsageMenuCardView.Model`
  renames `codexResetCredits` to `limitResetCredits`, which reads as a breaking
  rename in the diff. It is confined to the macOS menu-card model: the released
  Linux CLI binary contains `codexResetCredits` and no `limitResetCredits`
  symbol, so `ProviderSnapshot.js` keeps consuming `usage.codexResetCredits`
  unchanged.
- **Azure OpenAI API version is config-only.** `ProviderConfig` gains an
  `azureOpenAIAPIVersion` extension value projected to the
  `AZURE_OPENAI_API_VERSION` environment key. `config --help` is unchanged and
  `set-api-key` remains the sole writer, so no supported CLI command sets it.
  The frontend must not hand-edit the config file to reach it.
- **Usage, cost, and sessions envelopes unchanged.** No new keys on usage,
  credits, identity, detail rows, or cost payloads. `UsageSnapshot.init(from:)`
  gains a backward-compatible `identity` decode that reconstructs the object
  from the legacy flat `accountEmail`, `accountOrganization`, and `loginMethod`
  keys; this is decode-side compatibility and changes nothing emitted.
- **New CLI stderr diagnostics.** `antigravityAutoFallbackSummary` adds an
  `Antigravity auto source outcomes: app: … -> cli: …` line on stderr for failed
  `--source auto` Antigravity fetches. This is untrusted display text on the
  error path, alongside the existing Kilo summary.
- **Provider history in CLI text output.** `CLIRenderer.liveHistoryLine` and the
  card renderer now print a `Last N days` line from `snapshot.costUsage`
  (`last30DaysCostUSD`, `last30DaysTokens`, `currencyCode`, `costProvenance`,
  `historyLabel`, `historyDays`). These fields already existed and Plasma
  already consumes `historyLabel` and `historyDays`; the release brings the
  CLI's text rendering up to what the JSON already carried.
- **Plugin snapshot validation relaxed.** `ProviderPluginSnapshotMapper` drops
  the rule rejecting a spend entry whose `reasoningTokens` exceed
  `outputTokens`. Previously rejected OpenRouter history now parses into the
  same shape; no new field.
- **No new config contracts.** `config providers --descriptors` is still
  rejected, and `config --help` lists only `validate`, `dump`, `providers`,
  `enable`, `disable`, and `set-api-key`.

## 0.61.0 features against existing Plasma behavior

- **Five new providers — implementable now.** The widget's bundled fallback
  metadata covers the 0.49.1 registry. The new IDs have no entry in
  `providerBrandChannels`, `providerDashboardUrls`, `providerLoginUrls`,
  `providerStatusUrls`, `providerDocsPaths`, or `providerIconFiles`, and no SVG
  in `contents/icons/providers`. Degradation is graceful by design: display names
  come from the CLI's `displayName`, `ProviderNames.titleForKey` falls back to
  the capitalized key, and a provider with no brand entry falls back to the
  theme highlight. What is missing is the bundled icon, accent color, and
  usage/status/documentation links. Tracked in TODO.
- **Mistral, Venice, and Grok allowances — fetcher-side.** Mistral API and Vibe
  Code allowances, Venice subscription credits, and Grok reset coupons are
  produced by provider fetchers into existing generic fields. Venice's new Web
  source and Replicate's billing plugin depend on cookie import with native
  Chrome session recovery, which is macOS-oriented; no Linux contract is added.
- **OpenRouter pay-as-you-go and Activity — plugin-side.** Uncapped spending
  summaries, prepaid balance, management-key recognition, and 30-day Activity
  totals land in `Resources/Plugins/openrouter.js` and the descriptor. Plasma
  consumes whatever the generic usage and cost payloads carry.
- **Popup usage row visibility — unchanged classification.** The macOS
  `ProviderUsageItemVisibility` change only follows the `limitResetCredits`
  rename. The existing TODO entry stays a Plasma-local display preference with
  no CLI contract.
- **macOS-only.** Menu-bar status-item placement preservation, the Codex card
  refresh while a menu stays open, Claude swap switching phases, switcher label
  alignment, shared-card gateway model families, and the Remote Control startup
  override are app-surface changes. The Claude CLI session and Devin session
  importer changes are fetcher-side with no emitted-shape change.

## Scoped official Linux probes

The official `CodexBarCLI-v0.61.0-linux-x86_64.tar.gz` asset passed the
release's SHA-256 check:
`f1297f36876d3e61a20e6d4836b1e96eba2806e317eb81c7a7935a8736e3ee0a`.
Assets and checksum are on the
[official release](https://github.com/steipete/CodexBar/releases/tag/v0.61.0).

Probes ran inside a network-isolated Bubblewrap process with temporary home,
configuration, cache, and data roots, a cleared environment, and no host
credentials reachable. No installed CLI was replaced. The extracted asset
reports `CodexBar 0.61.0`.

| Probe | Result |
| --- | --- |
| `--version` | `CodexBar 0.61.0`. |
| `config providers --format json --json-only` | Exit 0; 74 records, keys `provider`, `displayName`, `enabled`, `defaultEnabled`. Adds `nous`, `muse`, `coderabbit`, `replicate`, `huggingface`. |
| `config providers --descriptors --format json --json-only` | Exit 1, `error.kind: args`, `Unknown option --descriptors`. |
| `config --help` | Existing commands only; `set-api-key` remains the sole writer. No API-version option. |
| `cost --provider cursor --format json --json-only` | Exit 1, `cost is only supported for Antigravity, Claude, Codex.` |
| `cost --provider codex --format json --json-only` | Exit 0; empty history, `historyCoverageIsEstablished: true`, no `incompleteRequestCount` key. Shape unchanged. |
| `cost --help` | Unchanged flags; no availability or tier options. The `--provider` enumeration lists the five new IDs. |
| `usage --provider claude --format json --json-only` | Exit 1, `No available fetch strategy for claude.` Envelope keys unchanged. |
| `sessions --json-v2` | Exit 0, empty array in the isolated account. |

No authenticated usage was exercised. The Grok reset-credit detail row, Mistral
and Venice allowances, Hugging Face ZeroGPU quota, Nous and Muse subscription
quotas, CodeRabbit review counts, OpenRouter Activity totals, credit validity,
workspace balances, Copilot seat rows, Antigravity progress rows, service tiers,
and display-currency behavior remain unverified in emitted output. Those
limitations stay explicit in TODO.

## Carried-forward blockers

Every blocker in TODO remains open. 0.61.0 adds no provider settings descriptor,
generic config action, Cursor cost support, service-tier field, structured
localization identifier, or display-currency contract. The Azure OpenAI
API-version setting is a new config extension value with no supported CLI
writer, which reinforces rather than resolves the provider-settings blocker.
