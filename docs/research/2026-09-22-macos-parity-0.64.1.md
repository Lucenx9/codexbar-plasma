# Linux parity review at CodexBar 0.64.1

Checked 2026-09-22 against Plasma commit
[`4de929a`](https://github.com/Lucenx9/codexbar-plasma/commit/4de929a514386748e1b6870088573a196cd3196a).
The macOS reference is official
[`v0.64.1`](https://github.com/steipete/CodexBar/releases/tag/v0.64.1),
commit [`89e84ab3f243946dd914898f304410692ad5fbf7`](https://github.com/steipete/CodexBar/commit/89e84ab3f243946dd914898f304410692ad5fbf7),
published 2026-09-22 at 08:29:31 UTC.

This is a release-delta review for useful Linux behavior. It covers the two
stable releases published after the
[0.63.0 review](2026-09-21-macos-parity-0.63.0.md) and does not repeat the full
[0.56.2 contract audit](2026-09-01-macos-parity-0.56.2.md). Current open parity
work belongs in [TODO.md](../../TODO.md).

## Release coverage

| Release | Published | Commit | Linux-relevant observations |
| --- | --- | --- | --- |
| [0.64.0](https://github.com/steipete/CodexBar/releases/tag/v0.64.0) | 2026-09-21 | `c545178fda03620a6c2d4cb83250eff64bb92c69` | Registry adds `helmcode`, `v0`, and `typesafe` (a 78-record count inferred from the 0.63.0 baseline, not observed: only 0.64.1 was installed); ElevenLabs, LiteLLM, and LLM Proxy move to bundled JavaScript plugins without a reported envelope change; Linux quota reporting is said to drop synthetic windows (#3785). |
| [0.64.1](https://github.com/steipete/CodexBar/releases/tag/v0.64.1) | 2026-09-22 | `89e84ab3f243946dd914898f304410692ad5fbf7` | `crof` is retired after the service shut down, leaving 77 records; Antigravity quota pools are listed once per family on Linux (#3799); Kimi gains a China/International region selector; Neuralwatt moves to the bundled plugin. |

## Linux CLI contract changes since 0.63.0

- **Registry membership (verified in emitted output).** `config providers
  --format json --json-only` returns 77 records with the unchanged keys
  `provider`, `displayName`, `enabled`, and `defaultEnabled`. Against 0.63.0
  the set gains `helmcode` (Helmcode), `v0` (v0), and `typesafe` (TypeSafe),
  all `defaultEnabled: false`, and loses `crof`. `config enable --provider crof`
  now fails with `Unknown or missing provider`, so the retirement is enforced
  and not only documented. The `usage --provider` allowlist names all three
  additions under their bare keys, so no CLI-argument alias is required.

- **v0 is the only Linux-usable addition (verified in emitted output).**
  `config set-api-key --provider v0 --api-key <synthetic>` succeeds and returns
  `{"provider":"v0","configPath":…,"enabled":true}`, and a subsequent
  `usage --provider v0` classifies the synthetic key as a `provider` error
  (`v0 API key was rejected.`) rather than a runtime failure. The same
  `set-api-key` call is refused for the other two with
  `helmcode does not support config API keys.` and the matching TypeSafe text.

- **Helmcode and TypeSafe are cookie-only and unreachable on Linux through
  supported writes (verified in emitted output).** Both return
  `Error: selected source requires web support and is only supported on macOS.`
  on the default source, and `Source 'api' is not supported for <provider>.`
  when forced to `api`. Upstream documents a `cookieSource: "manual"` plus
  `cookieHeader` config path, but no CLI writer exposes it: `set-api-key`
  remains the sole writer. Reaching these providers would require hand-editing
  the CLI config, which the frontend must not do. They are therefore metadata
  fallback only until the generic settings contract lands.

- **v0 `--workspace-id` is not a Linux writer (verified in emitted output).**
  `set-api-key --provider v0 --workspace-id <synthetic>` fails with
  `Token-account options are only supported for --provider zai.`, so the
  optional v0 Scope field documented upstream has no supported CLI write path.
  Plasma exposes the key-only setup that the CLI does support.

## Carried-forward blockers, rechecked at 0.64.1

- **Generic provider-settings descriptors are still absent.** `config providers
  --descriptors` fails with `Unknown option --descriptors`, and the 77 provider
  records still carry only the four keys above. The TODO entry stands unchanged.
- **There is still no generic `config action` command.** `set-api-key` remains
  the only supported writer, so CLI-described cookie import, local-file setup,
  OAuth/device flow, and token-account actions stay blocked.

## Unverified in this review

These 0.64.x changes touch contracts the Plasma frontend consumes, but proving
the emitted Linux output needs a signed-in account this review deliberately did
not use. They stay out of the actionable inventory until measured.

- **Linux quota windows (#3785, #3799).** 0.64.0 claims Linux now omits
  synthetic or unmeasured quota, and 0.64.1 claims each Antigravity quota pool
  is listed once with its family label. Both would change the window array the
  popup renders. No enabled provider in the probe account returns quota, so
  neither claim was observed in emitted output.
- **Cursor Grok Bot allowance (0.64.1).** The release adds a `Grok Bot %`
  menu-bar layout token. Whether the Linux `usage` payload gains a
  corresponding rate window, and under what key, is unmeasured.
- **Kimi region selection (0.64.1).** The region is described as a config
  value; no supported CLI writer for it was found, which would place it with
  the other descriptor-blocked settings, but the config shape was not probed.

## Probe method

Every command above ran as the installed `codexbar` 0.64.1 under `env -i` with
`HOME`, `XDG_CONFIG_HOME`, and `XDG_CACHE_HOME` pointed at an empty temporary
directory and no credential environment passed, so the host config and provider
files stayed inaccessible and the writes landed in the throwaway config. Inputs
were synthetic. The installed CLI was not replaced, so this is a scoped probe of
the installed release rather than a checksum-verified asset audit; the full
contract baseline stays at the [0.56.2 audit](2026-09-01-macos-parity-0.56.2.md).

## Bundled metadata added for the three new providers

Upstream publishes a setup guide and one dashboard entry point per provider, and
declares no brand color or status page for any of them. The bundled fallback
therefore carries the name, an original non-vendor icon glyph, the docs link,
and the dashboard URL, and lets brand color and status degrade by design, the
same shape the [0.63.0 review](2026-09-21-macos-parity-0.63.0.md#pi-brand-sources-and-omissions)
used for Pi.

| Provider | Display name | Dashboard | Docs | Login |
| --- | --- | --- | --- | --- |
| `helmcode` | Helmcode | `https://cloud.helmcode.com/dashboard` (Cloud tenant; NaN Builders is the second tenant and has no static entry point) | `helmcode.md` | none |
| `v0` | v0 | `https://v0.app/settings/billing` | `v0.md` | `https://v0.app/settings/keys` |
| `typesafe` | TypeSafe | `https://console.typesafe.ai/settings/billing` | `typesafe.md` | none |

Crof keeps its bundled name, icon, brand color, and docs link. An installed
0.63.0 still emits the provider, and dropping the metadata would downgrade a
named provider to the unknown-provider fallback for anyone who has not upgraded.
