# CodexBar Plasma

KDE Plasma 6 widget for [CodexBar](https://github.com/steipete/CodexBar).

This repository is intentionally small: it contains only the Plasma applet. All
provider logic, authentication, configuration, quota parsing, and JSON output
come from the `codexbar` CLI.

## Features

- Multi-provider Plasma panel indicator.
- Provider tabs with usage bars, reset windows, credits, local token cost, and
  provider status links.
- Provider settings page for enable/disable, API key setup, docs, dashboards,
  and login/account links.
- Optional compact multi-provider panel meters.
- Display mode controls: Percent, Pace, Percent and pace, Reset time.
- Account discovery and selection through `codexbar usage --all-accounts`.

## Requirements

- KDE Plasma 6
- `kpackagetool6`
- `org.kde.plasma.plasma5support`
- `codexbar` CLI on `PATH`, or an absolute CLI path configured in the widget

On Arch-compatible systems:

```sh
yay -S codexbar-cli
```

You can also install the CLI from the main CodexBar release tarballs or from a
local Swift build.

## Install

From the repository root:

```sh
kpackagetool6 -t Plasma/Applet -i .
```

Then add **CodexBar** to a Plasma panel.

## Upgrade

```sh
kpackagetool6 -t Plasma/Applet -u .
systemctl --user restart plasma-plasmashell.service
```

## CLI Check

Before debugging the widget, verify the data source directly:

```sh
codexbar usage --format json --json-only
codexbar usage --format json --json-only --provider codex --source oauth
codexbar usage --provider codex --all-accounts --format json --json-only
codexbar cost --format json --json-only
```

If Plasma does not inherit your shell `PATH`, set an absolute command path in
the widget settings. On Arch/CachyOS with the AUR package this is usually:

```text
/usr/bin/codexbar
```

## Test

```sh
scripts/test_feature_parity.sh
scripts/test_refresh_nonce.sh
/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml contents/ui/main.qml contents/ui/configGeneral.qml contents/ui/configProviders.qml
xmllint --noout contents/config/main.xml
jq . metadata.json >/dev/null
kpackagetool6 --appstream-metainfo . | xmllint --noout -
```

## Structure

```text
metadata.json
contents/config/
contents/icons/
contents/ui/
scripts/
```

Provider support stays upstream in CodexBar. When the Plasma frontend needs
new data, add it to the CLI JSON contract first instead of scraping or editing
CodexBar config files directly from QML.

## Attribution

CodexBar Plasma is derived from the CodexBar project and uses the same MIT
license. See [NOTICE.md](NOTICE.md).
