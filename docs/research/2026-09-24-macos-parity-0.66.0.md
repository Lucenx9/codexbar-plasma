# Linux parity review at CodexBar 0.66.0

Checked 2026-09-24 against Plasma commit
[`26a877f`](https://github.com/Lucenx9/codexbar-plasma/commit/26a877f).
The macOS reference is official
[`v0.66.0`](https://github.com/steipete/CodexBar/releases/tag/v0.66.0),
commit [`e665cbf64976839dc947e70a942ba8226388d4c9`](https://github.com/steipete/CodexBar/commit/e665cbf64976839dc947e70a942ba8226388d4c9),
published 2026-09-24 at 18:15:52 UTC.

This is a release-delta review for useful Linux behavior. It covers the one
stable release published after the
[0.65.0 review](2026-09-23-macos-parity-0.65.0.md) and does not repeat the full
[0.56.2 contract audit](2026-09-01-macos-parity-0.56.2.md). Current open parity
work belongs in [TODO.md](../../TODO.md).

## Release coverage

| Release | Published | Commit | Linux-relevant observations |
| --- | --- | --- | --- |
| [0.66.0](https://github.com/steipete/CodexBar/releases/tag/v0.66.0) | 2026-09-24 | `e665cbf64976839dc947e70a942ba8226388d4c9` | Registry adds `devpass`, `atlascloud` (Atlas Cloud), `vercel` (Vercel AI Gateway), and `llmman` for 84 records; the tested `config disable` command keeps user provider plugin entries and secrets (#3944); ten more providers run as bundled plugins; Alibaba/Qwen monthly windows (#3903) and Command Code monthly sizing (#3939). |

## Linux CLI contract changes since 0.65.0

- **CLI help is unchanged apart from the provider list (verified in emitted
  output).** `--help`, `config --help`, `usage --help`, and `cost --help` from
  the 0.65.0 and 0.66.0 Linux assets differ only in the version line and the
  `--provider` allowlist, which gains `devpass`, `atlascloud`, `vercel`, and
  `llmman`. No new flag or subcommand appears.

- **Registry membership (verified in emitted output).** `config providers
  --format json --json-only` returns 84 records with the unchanged keys
  `provider`, `displayName`, `enabled`, and `defaultEnabled`. The four
  additions are all `defaultEnabled: false`, and no existing record changed.
  No CLI alias was found for any of them.

- **All four additions work with the supported key setup (verified in emitted
  output).** `config set-api-key --stdin` accepts a synthetic key for each and
  returns `enabled: true`. The default `usage` source then sends the key:

  | Provider | Default `usage` with a synthetic key |
  | --- | --- |
  | `devpass` | `provider` error: `DevPass API key was rejected or is inactive.` |
  | `atlascloud` | `provider` error: `Atlas Cloud returned HTTP 401.` |
  | `vercel` | `provider` error: `Vercel AI Gateway returned HTTP 401.` |
  | `llmman` | Without a daemon: `llmman is not reachable at http://127.0.0.1:17434. Start it with llmman serve.` |

  The key is optional for llmman. A loopback fixture that answers 401 unless
  the synthetic bearer token is present returns usage with the stored key and
  `llmman requires an API key.` without it, so the widget's key setup reaches
  the plugin. A non-default llmman base URL (`LLMMAN_HOST`, stored as
  `enterpriseHost`) has no CLI writer, like Bifrost's gateway URL.

- **llmman output through a loopback daemon fixture (verified in emitted
  output).** llmman defaults to `http://127.0.0.1:17434`, so a static fixture
  exercised the official plugin without an account. The record carries:
  - `primary` with `usedPercent` and a `resetDescription` of the form
    `6.5 GB of 16.0 GB`, with no `resetsAt` or `windowMinutes`. It measures
    loaded model memory, not a time window.
  - `rateWindowLabels: {"primary": "Memory"}`.
  - `details` with a `Daemon` section (`Loaded`, `Stored`,
    `Version`) and a `Loaded models` section whose rows carry `progress`.
  - `identity.loginMethod` of `Local daemon` or `API key`.

  Plasma already renders these fields generically, but its static lane table
  titled the memory row `Session`. This change adds `Memory` for llmman and the
  upstream `Plan credits`/`Premium weekly` labels for DevPass.

- **`rateWindowLabels` is an existing generic field.** The string is present in
  both the 0.65.0 and 0.66.0 binaries, so it is not new. Plasma ignores it and
  titles lanes from its own localized table, which falls back to `Session`,
  `Weekly`, and `Opus` for providers it does not list. That makes an English
  CLI label a better fallback than a wrong generic one; see TODO.

- **User plugin entries survive `config disable` (verified in emitted
  output).** A synthetic `{"id": "synthplug", "pluginSecrets": {...}}` entry
  added to a temporary config was removed by `config disable --provider grok`
  on 0.65.0 and kept on 0.66.0. Only `config disable` was tested for plugin
  preservation; this check does not establish the behavior of `config enable`
  or `config set-api-key`. The widget needs no change; the usage guide now tells
  users of user plugins to update the CLI before disabling a provider.
  `config providers` still lists built-in providers only.

- **Cost and sessions schemas are unchanged (verified in emitted output).** The
  key set of `cost --provider codex --days 45` is identical between the 0.65.0
  and 0.66.0 assets, and `sessions --json-v2` still returns a list.

## Carried-forward blockers, rechecked at 0.66.0

- **Generic provider-settings descriptors are still absent.** `config providers
  --descriptors` fails with `Unknown option --descriptors`.
- **There is still no generic `config action` command.** `config action` fails
  with `Unknown subcommand 'action' for command 'config'`.
- **Cursor cost is still rejected.** `cost --provider cursor` returns
  `cost is only supported for Antigravity, Claude, Codex, Muse Code, Pi.`

## Excluded from the Linux backlog

These 0.66.0 items are macOS-only or already covered by Plasma:

- iCloud Sync Mac removal, menu-bar balance layouts, Claude widgets and
  claude-swap refresh, Kimi and MiniMax browser-storage import, the Ollama
  manual-cookie action, and Muse Code Keychain checks rely on macOS surfaces.
- The Codex credit bar rescale (#3912) changes a macOS view. Plasma draws a
  Codex credit meter only from the validated `credits.codexCreditLimit` cap and
  never scales a plain balance.
- The ten providers moved to bundled plugins keep their records and output
  shapes, per the release notes; the registry diff shows no changed record.
- History-cache write reductions, Cursor cost back-off, Codex catch-up and plan
  preference, Claude alert de-duplication, Grok fallback, Alibaba/Qwen monthly
  windows, Command Code sizing, and shell-discovery bounds are CLI-owned and
  surface through existing fields.
- The `CodexBarDesktop` Linux asset is upstream's own desktop app, not a CLI
  contract.

## Unverified in this review

- **DevPass, Atlas Cloud, and Vercel AI Gateway payloads** need real keys.
  Their plugins call fixed HTTPS origins. Plugin source shows Atlas Cloud and
  Vercel AI Gateway as balance-only `details` rows, which the
  [automatic balance text](../../TODO.md#automatic-balance-text) blocker already
  covers, and DevPass as a plan-credit primary and a premium weekly secondary
  with `resetsAt`.
- **Alibaba/Qwen monthly windows (#3903)** need an account; Plasma already
  labels the Alibaba tertiary lane `Monthly`.
- Items carried from the [0.64.1 review](2026-09-22-macos-parity-0.64.1.md#unverified-in-this-review)
  remain unmeasured.

## Probe method

The official `CodexBarCLI-v0.66.0-linux-x86_64.tar.gz` and
`CodexBarCLI-v0.65.0-linux-x86_64.tar.gz` assets were downloaded from their
releases. Both matched their published SHA-256 files
(`7a5e4504…e3173390` for 0.66.0). They were extracted into a temporary
directory, and the installed CLI was not replaced. Every command ran under
`env -i` with `HOME`, `XDG_CONFIG_HOME`, and `XDG_CACHE_HOME` pointed at empty
temporary directories and no credential environment passed. All keys and
plugin secrets were synthetic. The llmman fixtures were a static
`python3 -m http.server` and a small bearer-checking handler on
`127.0.0.1:17434`.

This isolation is incomplete. An unrecognized `--provider` value falls back to
Codex, and Codex credential and history discovery still found the host account
despite the temporary `HOME`. Alias probes that hit this fallback were
discarded, and `cost` output was used only for key sets. No account data from
those runs is recorded here. Later reviews should avoid unknown provider names
or run in a separate user account.

## Bundled metadata added for the four new providers

The upstream descriptors at `v0.66.0` declare a brand color, a dashboard, and a
setup guide for each addition, and no status page for any. Icons are original
glyphs with no vendor mark.

| Provider | Display name | Brand color | Dashboard | Docs |
| --- | --- | --- | --- | --- |
| `atlascloud` | Atlas Cloud | `#5975F5` | `https://www.atlascloud.ai/console` | `atlascloud.md` |
| `devpass` | DevPass | `#2563EB` | `https://devpass.llmgateway.io/dashboard` | `devpass.md` |
| `llmman` | llmman | `#6CC5B0` | `http://127.0.0.1:17434` (local daemon) | `llmman.md` |
| `vercel` | Vercel AI Gateway | omitted (upstream `#FFFFFF`) | `https://vercel.com/d?to=%2F%5Bteam%5D%2F%7E%2Fai-gateway` | `vercel.md` |

Vercel's white would make its icon and meters invisible on a light theme, so it
keeps the theme highlight. All four join the widget's API-key setup allowlist.
