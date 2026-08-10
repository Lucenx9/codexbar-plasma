# CodexBar macOS progress after 0.48.1

Checked 2026-08-10 at 11:28 UTC. This is a read-only comparison of the
official `steipete/CodexBar` repository against the Plasma baseline; it does
not propose or apply changes to `TODO.md` or the applet.

## Pinned scope

| Reference | Exact revision | Date |
| --- | --- | --- |
| Plasma baseline | local `72b55f733e1ad8f0ba244c8a4ebcefced51979ed`; the fallback catalog is explicitly pinned to CodexBar 0.48.1 in `scripts/test_provider_icons.sh` | 2026-08-09 |
| Official baseline | [`v0.48.1`](https://github.com/steipete/CodexBar/releases/tag/v0.48.1), commit [`226085b80f2414346624fce7a3b794bda6c54087`](https://github.com/steipete/CodexBar/commit/226085b80f2414346624fce7a3b794bda6c54087) | published 2026-08-08 00:14 UTC |
| Intermediate release | [`v0.49.0`](https://github.com/steipete/CodexBar/releases/tag/v0.49.0), commit [`0e46d1940c35b8d1e09d93b0391ded4377812cab`](https://github.com/steipete/CodexBar/commit/0e46d1940c35b8d1e09d93b0391ded4377812cab) | published 2026-08-09 15:55 UTC |
| Latest stable | [`v0.49.1`](https://github.com/steipete/CodexBar/releases/tag/v0.49.1), commit [`ae1111e39912642da33c6f1bf6647ce1ab3f2883`](https://github.com/steipete/CodexBar/commit/ae1111e39912642da33c6f1bf6647ce1ab3f2883) | published 2026-08-10 05:57 UTC |
| Upstream `main` | [`b093129a4f94b54dfc94a993f5686246e4145226`](https://github.com/steipete/CodexBar/commit/b093129a4f94b54dfc94a993f5686246e4145226), four commits ahead of 0.49.1 | 2026-08-10 10:59 UTC |

Primary release summary: [`CHANGELOG.md` at v0.49.1](https://github.com/steipete/CodexBar/blob/v0.49.1/CHANGELOG.md).

## Verdict

Yes, the official product moved forward, but the stable parity delta is
compact rather than architectural:

- the first-party catalog grew from 67 to 69 providers, adding Fireworks and
  IBM Bob;
- the Linux CLI now runs the same bundled JavaScript providers through
  QuickJS, so several macOS data fixes also reach Plasma without QML-specific
  provider logic;
- macOS gained useful metric/presentation refinements, but no general
  machine-readable provider-settings/action descriptor was added;
- upstream now lists this exact repository under Linux desktop integrations in
  [`README.md`](https://github.com/steipete/CodexBar/blob/v0.49.1/README.md#linux-desktop-integration), added by
  [`ce5d769fb5336a2b5f544afd5e30c6420730df69`](https://github.com/steipete/CodexBar/commit/ce5d769fb5336a2b5f544afd5e30c6420730df69).

## Stable 0.49.0/0.49.1 candidates

### Plasma-native and implementable now

| Candidate | Official evidence and contract | Plasma consequence |
| --- | --- | --- |
| Fireworks 30-day spend | Provider ID and metadata are in [`Sources/CodexBarCore/Providers/Providers.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCore/Providers/Providers.swift) and [`FireworksProviderDescriptor.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCore/Providers/Fireworks/FireworksProviderDescriptor.swift). The fetcher emits the existing generic `usage.providerCost` shape in [`FireworksUsageFetcher.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCore/Providers/Fireworks/FireworksUsageFetcher.swift). | Add fallback metadata/icon and let the current generic cost UI render it. No Fireworks-specific QML data parser is needed. Full onboarding is separately blocked below. |
| IBM Bob monthly Bobcoins | `ibmbob` and aliases are declared in [`IBMBobProviderDescriptor.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCore/Providers/IBMBob/IBMBobProviderDescriptor.swift). [`IBMBobUsageFetcher.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCore/Providers/IBMBob/IBMBobUsageFetcher.swift) exports a generic monthly `primary` window plus bounded `usage.details` team rows. | Add catalog metadata/icon; existing rate-window, pace and detail-row rendering can consume it. The generic `config set-api-key` path is sufficient for setup. |
| z.ai credit quotas, rate schedule and pace | The bundled provider adds a generic `Quota rate` detail row for credit plans in [`Sources/CodexBarCore/Resources/Plugins/zai.js`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCore/Resources/Plugins/zai.js). Pace selection is defined in [`ZaiProviderDescriptor.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCore/Providers/Zai/ZaiProviderDescriptor.swift). 0.49.1 also fixes `CREDIT_LIMIT` parsing and 5-hour/weekly/MCP pace. | The applet already consumes generic `usage.details` and `pace`; upgrading the official CLI should surface the corrected data without a provider branch. |
| Notion monthly compact metric | [`NotionProviderDescriptor.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCore/Providers/Notion/NotionProviderDescriptor.swift) maps the secondary semantic window to `Monthly`; [`NotionUsageSnapshot.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCore/Providers/Notion/NotionUsageSnapshot.swift) already serializes it as a generic secondary window. | A Plasma compact monthly metric is implementable from `usage.secondary`/`pace.secondary` for an already configured account. Browser-cookie onboarding remains blocked below. |
| DeepInfra automatic compact metric | 0.49.1 makes the macOS automatic icon use spend/limit, implemented in [`MenuBarMetricWindowResolver.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBar/MenuBarMetricWindowResolver.swift). The underlying cross-platform data is already the generic `ProviderCostSnapshot` emitted by [`DeepInfraUsageFetcher.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCore/Providers/DeepInfra/DeepInfraUsageFetcher.swift). | A Plasma-native panel equivalent can be derived from `providerCost.used / providerCost.limit`; the popup already has the required data. |
| CLI data-quality fixes | Stable fixes include Codex monthly credit-limit decoding, Cursor plan-label normalization, Kimi duplicate-lane removal, z.ai pace correction, and Claude CLI fallback. The generic payload remains `ProviderPayload { usage, pace, ... }` in [`Sources/CodexBarCLI/CLIPayloads.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCLI/CLIPayloads.swift), populated by [`CLIUsageCommand.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCLI/CLIUsageCommand.swift). | These are CLI-upgrade benefits, not new QML surfaces. Preserve generic rendering and avoid duplicating the fixes in Plasma. |

The generic JSON types used above are still the bounded Codable contracts in
[`UsageFetcher.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCore/UsageFetcher.swift),
[`ProviderCostSnapshot.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCore/ProviderCostSnapshot.swift), and
[`ProviderDetailSection.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCore/ProviderDetailSection.swift).

### Blocked on an official Linux CLI contract

| Gap | Why it remains blocked |
| --- | --- |
| Complete Fireworks onboarding | Fireworks needs both an API key and `accountSlug`. The slug is a provider extension in [`FireworksProviderConfig.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCore/Providers/Fireworks/FireworksProviderConfig.swift), but [`CLIConfigCommand.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCLI/CLIConfigCommand.swift) exposes only validate/dump/providers/enable/disable/set-api-key. There is no stable field/action descriptor or slug setter. |
| Notion browser onboarding | [`NotionProviderDescriptor.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCore/Providers/Notion/NotionProviderDescriptor.swift) permits a manual cookie on Linux but automatic browser-cookie discovery is compiled for macOS. Plasma should not import or parse browser sessions itself. |
| Arbitrary local-provider plugin management | QuickJS is now portable and [`CLIPluginsCommand.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCLI/CLIPluginsCommand.swift) can fetch a known plugin as generic JSON, but `plugins list` is text-only, approvals are interactive, browser-cookie plugins fail closed in the CLI, and settings/secrets have no JSON action descriptor. Bundled first-party providers benefit now; a safe Plasma plugin manager does not yet have a complete contract. |
| IBM Bob multi-account editing | The provider advertises token-account support, but `config set-api-key` only accepts account options for z.ai in [`CLIConfigCommand.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCLI/CLIConfigCommand.swift). A single IBM Bob key works; generic add/edit/remove account actions still do not exist. |
| Full remote Agent Sessions parity | Local discovery has an official `codexbar sessions --json-v2` contract in [`CLISessionsCommand.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCLI/CLISessionsCommand.swift), so a local list is possible. The new 0.49.1 change only repairs the macOS “Additional SSH hosts” editor; remote focus is explicitly macOS-only and there is no Linux CLI action that owns the configured-host aggregation/focus workflow. |

### macOS-only or non-goals

- showing the app in the Dock while Settings/Sparkle dialogs are open;
- direct Claude Keychain-read consent and macOS credential-prompt recovery UI;
- AppKit status-item layout details such as the compact DeepSeek balance editor,
  open-menu reconciliation, and active claude-swap icon selection;
- WidgetKit packaging, Sparkle behavior, Finder actions, and remote window focus.

The corresponding release notes are in
[`CHANGELOG.md` 0.49.1/0.49.0](https://github.com/steipete/CodexBar/blob/v0.49.1/CHANGELOG.md#0491--2026-08-09).

## Stable cross-platform engine change

0.49.0 replaces the Linux-only native twins for cut-over providers with the
same sandboxed QuickJS plugin engine used elsewhere. Relevant paths are
[`QuickJSProviderPluginEngine.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCore/Plugins/QuickJSProviderPluginEngine.swift),
[`ProviderPluginSnapshotMapper.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCore/Plugins/ProviderPluginSnapshotMapper.swift), and
[`docs/plugins.md`](https://github.com/steipete/CodexBar/blob/v0.49.1/docs/plugins.md).
This is meaningful for Plasma because official Linux CLI output should now be
byte-equivalent for the bundled JavaScript providers. It is not permission to
move provider fetch/auth logic into QML.

## CLI privacy change

The dashboard/serve snapshot now defaults to full account emails; callers must
pass `--identity redacted` when a snapshot can cross an untrusted boundary.
This is documented in
[`CLIHelp.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCLI/CLIHelp.swift)
and implemented by
[`DashboardSnapshotBuilder.swift`](https://github.com/steipete/CodexBar/blob/v0.49.1/Sources/CodexBarCLI/DashboardSnapshotBuilder.swift).
The current Plasma widget does not consume the dashboard-v1 snapshot, so no UI
port is needed; any future use must select identity mode explicitly and avoid
logging or persisting full addresses unintentionally.

## Unreleased `main` after 0.49.1

At the pinned HEAD, `main` is four commits ahead and identifies itself as
**0.49.2 Unreleased**. The comparison is
[`v0.49.1...b093129`](https://github.com/steipete/CodexBar/compare/v0.49.1...b093129a4f94b54dfc94a993f5686246e4145226).

- Sub2API gets localized, grouped menu-card summaries in
  [`MenuCardView+ModelHelpers.swift`](https://github.com/steipete/CodexBar/blob/b093129a4f94b54dfc94a993f5686246e4145226/Sources/CodexBar/MenuCardView%2BModelHelpers.swift).
- User-installed macOS plugin cards honor the used/remaining bar preference in
  [`StatusItemController+UserPlugins.swift`](https://github.com/steipete/CodexBar/blob/b093129a4f94b54dfc94a993f5686246e4145226/Sources/CodexBar/StatusItemController%2BUserPlugins.swift).
- Codex cost-cache refresh avoids reprocessing stable snapshots in
  [`CostUsageStore+CodexCache.swift`](https://github.com/steipete/CodexBar/blob/b093129a4f94b54dfc94a993f5686246e4145226/Sources/CodexBarCore/Vendored/CostUsage/CostUsageStore%2BCodexCache.swift).

These are presentation/performance fixes, not a new released provider or CLI
JSON/settings contract. They should not be reported as available in 0.49.1.

## Local contract probe

The official `CodexBarCLI-v0.49.1-linux-x86_64.tar.gz` asset advertises and
matched SHA-256
`67fa6aa8790ab11cc6334e15e51c8aba375de5f167bc62aea7057096a2f851fd`
([release asset](https://github.com/steipete/CodexBar/releases/tag/v0.49.1)).
Against a clean temporary config:

- `codexbar config providers --format json --json-only` returned 69 IDs,
  including `fireworks` and `ibmbob`;
- `config set-api-key` worked for both; IBM Bob validated, while Fireworks
  correctly reported `missing_account_slug`;
- `config providers --descriptors` exited with `Unknown option --descriptors`;
- the local fallback-icon regression failed only for the two new IDs,
  `fireworks` and `ibmbob`.

The machine's installed `/usr/bin/codexbar` is still 0.42.1, so none of the
0.49.x behavior is active there until the CLI package is upgraded.

## Recommended parity decision

The next small, evidence-backed Plasma sync is the two-provider catalog/icon
update plus regression coverage, relying on generic `providerCost`, rate
windows, pace and detail rows. Fireworks should be display-only for accounts
already configured until the official CLI exposes a safe account-slug field
action. The broader plugin/settings/onboarding gaps should remain blocked, and
the macOS-only presentation fixes should not be ported literally.
