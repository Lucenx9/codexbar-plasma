# Linux parity review at CodexBar 0.76.0

Checked 2026-10-15 against Plasma commit
[`8554f93`](https://github.com/Lucenx9/codexbar-plasma/commit/8554f9369b813ff31a4be88b80ea11e1cd7656ca).
The official reference is [v0.76.0](https://github.com/steipete/CodexBar/releases/tag/v0.76.0),
commit `2d8b1409a1649dce60f3610ebe4eab52b92545de`, published
2026-10-15 at 16:47:06 UTC. This covers the stable release since the
[0.75.0 review](2026-10-15-macos-parity-0.75.0.md), including unresolved findings.
It does not replace the full [0.56.2 audit](2026-09-01-macos-parity-0.56.2.md).
[TODO.md](../../TODO.md) owns follow-up work. No feature is implemented here.
The installed `/usr/local/bin/codexbar` reports 0.74.1 and was not replaced.

## Release coverage

| Release | Published | Commit | Linux-relevant changes |
| --- | --- | --- | --- |
| [0.76.0](https://github.com/steipete/CodexBar/releases/tag/v0.76.0) | 2026-10-15 | `2d8b1409a1649dce60f3610ebe4eab52b92545de` | Claude Platform API credits, grants, and spend; concurrent CLI usage fetches; buffered output from fast-exiting CLI probes; Claude OAuth email; provider runtime-memory fixes; config-load preservation; Helmcode Cloud import, Muse Keychain grant, and Droid browser variants. Linux archives also add `THIRD_PARTY_NOTICES`. Large text, monospaced usage digits, and native About acknowledgements are macOS presentation. |

## Linux CLI contract changes

- `config providers --format json --json-only` returns 104 records with the
  same four keys: `provider`, `displayName`, `enabled`, `defaultEnabled`.
  `claudeplatform` is the only addition, named `Claude Platform`, disabled by
  default. Plasma's generic discovery and unknown-provider fallback can list it
  without static metadata.
- Claude Platform does not have a supported Linux setup path. It rejects
  `config set-api-key --stdin`; both Auto and Web usage report that the selected
  web source is macOS-only. The tagged descriptor defines browser-cookie setup
  and a manual `Cookie` header containing `sessionKey`, but 0.76.0 still has no
  descriptor, generic field writer, or config action that can set those fields.
  That source inspection establishes a possible runtime strategy, not a
  released writable Linux contract. QML must not edit the config file.
- The tagged provider source maps primary API credits, purchased credits, grant
  expirations, billing details, organization identity, and a typed
  `providerCost` prepaid balance. Plasma already consumes generic quota labels,
  reset descriptions, detail rows, identity fields, and most provider-cost
  fields. Authenticated Linux output was not observed, and the frontend does
  not retain an explicit balance field, so exact balance semantics remain a
  verification candidate rather than an implementation claim.
- `usage --provider all --format json --json-only` returned all 104 providers
  in registry order on three consecutive isolated probes, with the same order
  hash each time. Tagged source caps concurrent fetches at three and restores
  the input index before encoding. This changes CLI scheduling, not the JSON
  contract or frontend refresh ownership.
- One hundred isolated fast-exit `--version` probes each returned exactly
  `CodexBar 0.76.0`. Preserving buffered output is a CLI reliability fix; it
  requires no Plasma parser change.
- The official Linux archive now includes the exact root regular file
  `THIRD_PARTY_NOTICES` (104,104 bytes, archive mode `0640`). Its release
  checksum and GitHub digest agree, but the managed installer at the reviewed
  Plasma commit rejects the new member. The bounded, non-executable exact-file
  compatibility fix is tracked separately in
  [PR #524](https://github.com/Lucenx9/codexbar-plasma/pull/524), so it is not a
  remaining TODO item in this documentation-only review.
- The release says Claude OAuth accounts now include email. Plasma already
  consumes `usage.identity.accountEmail`, but no authenticated 0.76.0 Claude
  record was available to verify the emitted shape or multi-account behavior.

## Carried-forward blockers rechecked

- `config providers --descriptors` still fails with `Unknown option
  --descriptors`; `config action` remains unknown. Registry/help expose no
  display-currency descriptor or writer. Generic settings, onboarding, and
  currency remain blocked.
- ClinePass labeled stdin writes and FLORA `--workspace-id` still reject their
  options as z.ai-only. Parallel still rejects API-key setup.
- Cursor cost still fails and lists Antigravity, Claude, Codex, Muse Code, and
  Pi. Empty Codex cost keeps the 17-key shape and has no service-tier fields.
- Empty Pi usage retains `estimated` confidence and null quota windows; idle
  `sessions --json-v2` returns `[]`.
- Throughput, imported incomplete costs, reset-credit rows, funded-credit
  flags, stable detail IDs, and other authenticated candidates retain their
  earlier evidence. Source inspection does not promote them to emitted Linux
  contracts.

## Excluded from the Linux backlog

- Large text, monospaced usage digits, native About acknowledgements, and
  provider-specific macOS layouts are native presentation choices. Plasma
  retains its own panel, popup, typography, and About experience.
- Provider runtime-memory fixes, config-load preservation, Helmcode Cloud
  import, Muse Keychain grant, Droid browser variants, and other browser/import
  corrections belong to CLI authentication and provider ownership. They do not
  supply the missing Linux setup actions.
- Concurrent fetch scheduling, buffered process output, and provider parsing
  fixes remain CLI-owned as long as their released JSON contracts stay stable.
  The frontend must not reproduce their scheduling or authentication logic.

## Unverified in this review

No authenticated provider output or external network call was performed.
Claude Platform credits, purchased grants, balance/cost semantics, grant expiry,
organization identity, and Claude OAuth email remain unverified. The earlier
OpenAI throughput, imported incomplete cost, reset-credit, funded-credit,
detail-ID, and other credential-dependent candidates remain open. These limits
are reflected in [TODO.md](../../TODO.md).

## Probe method

The official Linux x86_64 archive matched both its release SHA-256 file and the
GitHub asset digest:
`44be9901769d6d4d111cacae8b679aa5c585b26f77afa4f6436b0928206091fd`.
Every CLI probe used `bwrap --unshare-all`, tmpfs over `/home`, `/root`, `/run`,
and `/tmp`, a cleared environment, and temporary home/config/cache paths. Host
credentials, history, network, and IPC were inaccessible. Each process had a
25-second external deadline; none timed out. Synthetic keys entered through
stdin, never argv; config writes used official commands. Sources were inspected
only at the exact release tag. Temporary archives and probe results remain in
ignored `dist/review/076/`; they are not product files.
