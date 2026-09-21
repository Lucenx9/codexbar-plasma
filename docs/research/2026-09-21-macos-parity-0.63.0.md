# Linux parity review at CodexBar 0.63.0

Checked 2026-09-21 against Plasma commit
[`1dc7f2c`](https://github.com/Lucenx9/codexbar-plasma/commit/1dc7f2c5fbc834bb74c205ad4b9d5607aba597bf).
The macOS reference is official
[`v0.63.0`](https://github.com/steipete/CodexBar/releases/tag/v0.63.0),
commit [`f3e718c897d5ed76af4e07182df899c722118546`](https://github.com/steipete/CodexBar/commit/f3e718c897d5ed76af4e07182df899c722118546),
published 2026-09-20 at 21:17:10 UTC.

This is a release-delta review for useful Linux behavior. It covers the single
stable release published after the
[0.62.0 review](2026-09-20-macos-parity-0.62.0.md) and does not repeat the full
[0.56.2 contract audit](2026-09-01-macos-parity-0.56.2.md). Current open parity
work belongs in [TODO.md](../../TODO.md).

## Release coverage

| Release | Published | Commit | Linux-relevant observations |
| --- | --- | --- | --- |
| [0.63.0](https://github.com/steipete/CodexBar/releases/tag/v0.63.0) | 2026-09-20 | `f3e718c897d5ed76af4e07182df899c722118546` | Registry grows from 74 to 75 with the local-only `pi` provider; `cost --provider pi` reports local Pi/OMP token history with estimated costs through the unchanged generic cost envelope; Cursor cost is still rejected with Pi now named among the supported providers; usage, sessions, and config JSON envelopes are otherwise unchanged. |

## Linux CLI contract changes since 0.62.0

- **Pi provider registry and local cost history (verified in emitted
  output).** `config providers --format json --json-only` returns 75 records
  with the unchanged keys `provider`, `displayName`, `enabled`, and
  `defaultEnabled`. The single addition is `pi` (Pi, `defaultEnabled: false`).
  `cost --provider pi --format json --json-only` emits the generic cost
  envelope (`totals`, `daily[]` with `modelBreakdowns[]`, `coverage`,
  `provenance`, `currencyCode`) with token counts and list-price-estimated
  costs. Plasma needs no normalization change: the generic daily/model path
  already renders token and estimated-cost rows, the same path that already
  renders Antigravity and Muse Code local history. The bundled fallback
  metadata for `pi` (name, icon, documentation link) ships in the companion
  provider change; brand color and dashboard/login/status links are omitted
  because no verifiable upstream source names them (see below).
- **Pi usage is estimated local data with no quotas (verified in emitted
  output).** `usage --provider pi` returns `source: local` with
  `dataConfidence: estimated` and null primary/secondary/tertiary quotas.
  Upstream [`docs/pi.md`](https://github.com/steipete/CodexBar/blob/main/docs/pi.md)
  states Pi has no subscription quota or account balance, costs are API-rate
  estimates rather than a billing statement, and no provider login or
  credential is required to read the transcripts. The existing unknown-quota
  presentation already covers this shape.
- **Pi/OMP session dialect is CLI surface (source-observed).** Upstream
  [`docs/sessions.md`](https://github.com/steipete/CodexBar/blob/main/docs/sessions.md)
  says `sessions --json-v2` can carry provider `pi` with a `pi`/`omp` dialect
  tag. No local Pi session was exercised here, and Plasma's session view
  already normalizes display fields only, so no frontend work is tracked.
- **Cursor cost is still rejected; Pi joins the supported list (verified in
  help output).** `cost --provider cursor` still fails, with the message now
  naming Antigravity, Claude, Codex, Muse Code, and Pi. The Cursor-cost
  blocker in TODO stays open.
- **No new provider settings descriptor or generic config action (verified in
  help output).** `config providers --descriptors` is still rejected with
  `Unknown option --descriptors`, and `config --help` still lists
  `set-api-key` as the sole writer. Both TODO blockers stay open.
- **Provider-reported 30-day spend and small-widget balances
  (release-notes-observed, unverified in Linux JSON).** The 0.63.0 notes
  describe dashboard 30-day USD spend when no local cost row exists,
  preserved OpenRouter completed UTC history, and DeepSeek/OpenRouter
  balances with live-update ages in small widgets. The scoped probes below
  observed no new emitted keys behind these displays, so they stay
  unverified candidates documented here rather than TODO entries.
- **Fetcher and refresh reliability fixes (release-notes-observed).**
  Paginated Codex cost counting, oversized LongCat/Kilo/Kimi/Chutes/MiniMax/
  Perplexity value guards, Kilo obsolete-refresh discard, Kimi nonzero weekly
  retention, StepFun Credit labelling, Devin organization pairing, Claude
  account-email matching for Web enrichment, config-file replacement
  detection, Augment keepalive cancellation, plugin/Codex obsolete-refresh
  rejection, and Keychain/credential-diagnostic hardening are provider,
  fetcher, or app-surface changes arriving through existing generic fields.
  Plasma needs no QML port and tracks none of them.
- **macOS-only.** Small-widget balances and live-update ages, simplified
  Homebrew update instructions, menu-bar status-item identity, and Debug
  Workspaces memory reduction are app-surface or fetcher-side changes with
  no emitted-shape change.

## Scoped official Linux probes

Probes ran against the installed `/usr/bin/codexbar` (`CodexBar 0.63.0`),
not a checksum-verified isolated release asset, and the usage probe observed
the local account, whose values are redacted below. This review therefore
records a release delta only and does not advance the full-audit baseline.

| Probe | Result |
| --- | --- |
| `--version` | `CodexBar 0.63.0`. |
| `config providers --format json --json-only` | Exit 0; 75 records with keys `provider`, `displayName`, `enabled`, `defaultEnabled`; the only addition since 0.62.0 is `pi` (Pi, `defaultEnabled: false`). |
| `config providers --descriptors --format json --json-only` | Rejected, `Unknown option --descriptors`. |
| `config --help` | Same commands; `set-api-key` remains the sole writer. |
| `cost --provider pi --format json --json-only` | Exit 0; generic envelope with token counts and estimated costs (`provenance: listPriceEstimate`), daily entries and model breakdowns present. |
| `cost --provider cursor --format json --json-only` | Rejected; cost is supported only for Antigravity, Claude, Codex, Muse Code, and Pi. |
| `cost --help` | Names `pi` support, `--provider-native-only`, and the unchanged `--remote` / `--summary-only` Codex modes. |
| `usage --provider pi --format json --json-only` | Exit 0; `source: local`, `dataConfidence: estimated`, null quotas. |
| `usage --provider codex --status --format json --json-only` | Envelope keys unchanged from 0.62.0. |
| `sessions --json-v2` | Exit 0; array shape unchanged. |

No authenticated quota comparison was exercised. The Grok reset-credit
detail row, Mistral and Venice allowances, Hugging Face ZeroGPU quota,
workspace balances, Copilot seat rows, Antigravity progress rows, service
tiers, and display-currency behavior remain unverified in emitted output.
Those limitations stay explicit in TODO.

## Carried-forward blockers

Every blocker in TODO remains open. 0.63.0 adds no provider settings
descriptor, generic config action, Cursor cost support, service-tier field,
structured localization identifier, or display-currency contract. Pi token
history arrives through the existing generic cost envelope, so it resolves
no blocker and adds none.

## Pi brand sources and omissions

Upstream `docs/pi.md` was fetched (HTTP 200) and confirms the local-only
model: no subscription quota, no account balance, no login or credential.
It names no dashboard, login, or status URL and no brand color. The `cost`
and `usage` help texts name no CLI alias beyond `pi`. Color, dashboard,
login, and status URLs are therefore omitted rather than invented; the
widget falls back to the theme highlight and hides missing links by design.
The `pi.md` documentation path is the one verified upstream fact bundled
beyond the CLI-observed name. The `pi.svg` icon is an original pi-glyph drawn for this widget, not a
vendor mark, since no official monochrome brand asset was verified.
