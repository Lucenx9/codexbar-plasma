# Agent Instructions

This repository is the standalone KDE Plasma widget for CodexBar.

## Project Boundaries

- Keep this repo small. It should contain only the Plasma applet, packaging helpers, tests, and docs.
- Do not copy the macOS app, Swift sources, Xcode projects, or full upstream CodexBar tree into this repo.
- Provider logic, authentication, config parsing, quota fetching, and JSON contracts belong in the upstream `codexbar` CLI.
- The local upstream/fork workspace is usually `/home/simone/CodexBar`; use it only for comparison, syncing provider maps, or proposing CLI contract changes.
- If the Plasma frontend needs new provider data, prefer extending the CLI JSON contract upstream. Do not hand-edit CodexBar config JSON from QML except through supported CLI commands.

## Layout

- `metadata.json`: Plasma applet metadata.
- `contents/ui/main.qml`: panel, popup, provider details, status badges, bars, account selection.
- `contents/ui/configGeneral.qml`: general widget settings.
- `contents/ui/configProviders.qml`: provider enablement and provider actions.
- `contents/config/main.xml`: persisted Plasma configuration schema.
- `contents/icons/`: applet and provider icons.
- `scripts/`: static regression checks.

## Verification

Run this before committing QML, config, packaging, or README changes:

```sh
make check
```

For packaging changes, also run:

```sh
make package
```

For runtime verification on the local KDE session:

```sh
./install.sh
journalctl --user -u plasma-plasmashell.service --since '2 minutes ago' --no-pager \
  | rg -n 'app\.codexbar|CodexBar|ReferenceError|TypeError|SyntaxError|file://.*/app.codexbar'
```

Ignore unrelated Plasma logs from other widgets unless they mention `app.codexbar`.

## CLI Assumptions

The widget expects a working `codexbar` binary. Useful probes:

```sh
codexbar usage --format json --json-only
codexbar usage --provider codex --status --format json --json-only
codexbar usage --provider codex --all-accounts --format json --json-only
codexbar cost --format json --json-only
codexbar config providers --format json --json-only
```

On the owner machine, the AUR package normally installs the CLI at `/usr/bin/codexbar`.

## Release Flow

1. Keep `main` green with `make check`.
2. Generate the distributable with `make package`.
3. Publish `dist/codexbar-plasma.plasmoid` in a GitHub Release.
4. Use the full fork workspace only for upstream sync work; this standalone repo is the public user-facing project.
