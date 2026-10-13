# Linux parity review at CodexBar 0.74.1

Checked 2026-10-14 against Plasma commit
[`abe8f7d`](https://github.com/Lucenx9/codexbar-plasma/commit/abe8f7dae723c42e42e70042e05c66d3c76dc94b).
The official reference is
[`v0.74.1`](https://github.com/steipete/CodexBar/releases/tag/v0.74.1),
commit [`7c08c0ae783b72040b728757eb85a6cfe4fc2443`](https://github.com/steipete/CodexBar/commit/7c08c0ae783b72040b728757eb85a6cfe4fc2443),
published 2026-10-11 at 21:37:03 UTC.

This review covers the one stable release after the
[0.74.0 review](2026-10-11-macos-parity-0.74.0.md), including its unresolved
findings. It does not replace the full
[0.56.2 contract audit](2026-09-01-macos-parity-0.56.2.md).
[TODO.md](../../TODO.md) owns remaining work; this review implements no features.
The system executable discovered with `command -v codexbar` was
`/usr/local/bin/codexbar`, reporting 0.73.0 before the review. After the isolated
probes, the user separately authorized upgrading it to the checksum-verified
0.74.1 asset; the same path now reports `CodexBar 0.74.1`. The old installation
is retained. Host installation is separate from the comparison evidence.

## Release coverage

| Release | Published | Commit | Linux-relevant observations |
| --- | --- | --- | --- |
| [0.74.1](https://github.com/steipete/CodexBar/releases/tag/v0.74.1) | 2026-10-11 | `7c08c0ae783b72040b728757eb85a6cfe4fc2443` | xAI optional invoice-preview estimate (#4406); Command Code Go v1 allowance and unknown-plan preservation (#4405); OpenCode Go estimated percentage labeling (#4410); Codex status/activity cache memory reductions (#4421, #4424); macOS conversation titles, session cache/performance presentation, hover preference, Claude balance layout, SDK packaging, Settings launch fix, and Replicate artwork (#4429, #4413, #4414, #4422, #4403, #4415, #4411). |

## Linux CLI contract changes since 0.74.0

- **Provider registry and command surfaces are unchanged, verified in output.**
  Both archives emit the same 100 provider records after sorting, each with
  `provider`, `displayName`, `enabled`, and `defaultEnabled`. The `config`,
  `usage`, and `cost` help text is identical after replacing the version line.
  The nine 0.74.0 metadata/setup additions remain unimplemented in Plasma.
  After the authorized system upgrade, `make check` reaches the live registry
  check and `check-provider-icons` fails for exactly those nine missing
  mappings. The same target passes with the retained 0.73.0 executable first
  in `PATH`. This confirms the existing backlog item; it does not make the
  generic runtime icon fallback unavailable.

- **OpenCode Go local estimates are an implementable Plasma gap, verified in
  output and through the current normalizer.** A synthetic SQLite database
  under the isolated passwd home's `.local/share/opencode/opencode.db`, with
  one current assistant message costing $6 and `providerID: "opencode-go"`,
  produces `source: "local"`, `usage.dataConfidence: "estimated"`, and
  primary/secondary/tertiary `usedPercent` values 50/20/10 on both versions.
  The labels are `5-hour`, `Weekly`, and `Monthly`. The contract predates
  0.74.1; this release adds macOS `~` markers and clarifies that the fixed
  $12/$30/$60 denominators are device-local cost estimates, not detected
  subscription allowances. See the pinned
  [OpenCode Go guide](https://github.com/steipete/CodexBar/blob/v0.74.1/docs/opencodego.md).
  A temporary QtTest passed the emitted 0.74.1 record into Plasma's
  `ProviderSnapshot.normalize`: the numeric rows survive, but confidence is
  discarded. `PanelDisplay.js` accepts those rows as ordinary percentages;
  `ProviderAutoSelect.js` and `NotificationPlanner.js` likewise consume the
  numeric rows without a confidence check. Preserve confidence, qualify local
  estimates, and keep them out of claims about authoritative account quota.
  No provider history scanning or estimate arithmetic belongs in QML.

- **xAI adds an optional generic detail row, source-observed.** The bundled
  [xAI plugin](https://github.com/steipete/CodexBar/blob/v0.74.1/Sources/CodexBarCore/Resources/Plugins/xai.js)
  reads `/postpaid/invoice/preview` and subtracts valid signed integer
  `coreInvoice.amountAfterVat` cents from the posted prepaid balance. It adds
  `Live remaining (est.)` beside `Prepaid balance` in `usage.details`.
  Explicit zero and negative remaining values are valid; failed or malformed
  optional enrichment omits only that row. Plasma's existing `UsageDetails.js`
  and `ProviderDetailSection.qml` retain and display bounded row labels/values
  without parsing them or creating a meter. A temporary QtTest confirmed the
  expected two-row shape with a negative value. This is renderer compatibility
  evidence, not authenticated Linux output. No frontend addition is justified
  for this row; typed automatic balance text stays blocked.

- **Command Code fixes remain CLI-owned, source-observed.** The
  [plan catalog](https://github.com/steipete/CodexBar/blob/v0.74.1/Sources/CodexBarCore/Providers/CommandCode/CommandCodePlanCatalog.swift)
  adds `individual-go-v1` with a $10 monthly allowance. The fetcher preserves
  unknown subscription labels instead of throwing, and the
  [snapshot](https://github.com/steipete/CodexBar/blob/v0.74.1/Sources/CodexBarCore/Providers/CommandCode/CommandCodeUsageSnapshot.swift)
  omits an unknown-plan quota instead of borrowing a free-tier 0% reading.
  Plasma's generic rows require an emitted window and do not manufacture a
  missing grant. No QML plan catalog or parser change is needed. Actual
  authenticated records remain unverified.

## Carried-forward blockers, rechecked at 0.74.1

- `config providers --descriptors` still returns `Unknown option --descriptors`;
  `config action` remains an unknown subcommand. Registry records contain no
  settings descriptor or display-currency field; inspected help exposes no
  display-currency writer. The generic settings/action/currency blockers remain.
- `config set-source --provider codex --source api` succeeds on both versions.
  Existing Plasma source controls remain supported. ClinePass
  `set-api-key --label --stdin` still rejects token-account options as z.ai-only.
- `cost --provider cursor` still rejects Cursor. Its supported provider list
  remains Antigravity, Claude, Codex, Muse Code, and Pi.
- Empty Codex, Claude, and Pi cost records keep 17 keys; Antigravity keeps 12.
  Empty Pi usage keeps `provider`, `source`, and `usage`, including estimated
  confidence and null primary/secondary/tertiary windows. `--period all` still
  starts at year 1: Pi reports `historyDays: 739905` during these UTC probes
  on 2026-10-13. Plasma's bounded history behavior remains necessary.
- `config preferences export` and `codex-accounts list` remain macOS-only;
  idle `sessions --json-v2` still returns `[]`.
- The source comparison changes neither `CLIPayloads.swift` nor the shared
  subscription-date encoding. The 0.74.0 subscription-date implementation gap
  and 0.73.0 reset-credit verification candidate remain.
- Exa/Cosmic second-field writers, manual-cookie setup, authenticated credit
  availability, detail-row IDs, localized descriptors, richer histories, and
  the older measured-window/account candidates retain their pinned evidence.
  No new generic writer appears in the unchanged help. They were not all
  exercised with funded accounts in this scoped review.

## Excluded from the Linux backlog

- Saved conversation titles and session-ID tooltips in the macOS Cost menu
  (#4429) consume the app's session history. Plasma's separate live Sessions
  view is not that history menu; idle Linux session output establishes no new
  title contract. Its existing privacy rules remain in effect.
- Cached-input reuse and first-token/cache sample coverage in the macOS session
  performance strip (#4413) are app presentation; no changed Linux cost schema
  was established. Missing data must still remain distinct from zero.
- The default-on hover preference (#4414), Settings placeholder launch fix
  (#4415), and macOS SDK preservation (#4403) are native app behavior.
- Claude prepaid-balance custom menu layouts (#4422) use a macOS presentation
  flag, not a new CLI field. Generic typed balance selection remains blocked
  and authenticated Claude prepaid output remains unverified.
- Replicate glyph changes (#4411) cover upstream app/site/HTTP dashboard
  artwork. Plasma owns its original icons and does not consume `serve` icons.
- Codex read-cache ledger memory changes (#4421, #4424), Claude credential
  routing/refactoring, and browser-profile detection are upstream parsing,
  authentication, or performance work. They need no QML port.

## Unverified in this review

- xAI's actual invoice-preview row, including valid zero, negative remaining,
  and failed enrichment, needs authenticated Linux output. Its HTTPS host is
  fixed; the synthetic QtTest verifies only frontend shape compatibility.
- Command Code Go v1 and unknown-plan responses need a real cookie-backed
  account. No provider scraping, cookie-file editing, or host account access
  was performed.
- Cursor's prior intermittent offline `cursor-agent` stall was not rerun with
  a real login. The earlier reproduction and frontend command bound remain.
- Claude subscription date-only flags; funded credit availability and reset
  inventory; mixed priced/unpriced Codex history; and the older provider quota
  reconciliation/account-identity candidates remain unverified. Empty records
  cannot settle those cases. TODO retains each unresolved scope.

## Probe method

The official Linux x86_64 archives matched their release SHA-256 files:

- 0.74.1: `2d4afdfc4b6404a72f8128e6304f3dcd28a9590fce8f9f6a0790ba4ccb8dbc92`.
- 0.74.0: `fac8b2c474e4e37a2b067224437cb182693411ebf639441cd0facbb57bf086b1`.

Each CLI probe used `bwrap --unshare-all`, tmpfs over `/home`, `/root`, `/run`,
and `/tmp`, a cleared environment, separate temporary home/config/cache
per scenario, and no host network, IPC, credentials, or history. The synthetic
home was also bound onto `/home/simone` inside the tmpfs, because Foundation's
passwd-based home discovery otherwise misses a temporary `HOME`. An initial
HOME-only synthetic OpenCode fixture returned no session; binding the synthetic
passwd home made both official archives read the fixture. The real home stayed
hidden throughout. Every process had an external 25-second bound; none timed out.
The synthetic ClinePass key entered through stdin, never argv. Configuration
writes used supported commands only.

The two temporary QtTest cases ran against the current Plasma pure modules
with Qt 6.8.2, outside the CLI sandbox, and used only synthetic payloads.
They passed, confirming the discarded confidence and generic detail-row
compatibility. Temporary scripts, source comparisons, and outputs remain in
the OS temporary directory. The authorized system CLI installation used the
verified 0.74.1 archive after the probes and was checked with `--version` only.
