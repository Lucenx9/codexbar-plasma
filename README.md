# CodexBar Plasma

KDE Plasma 6 widget for [CodexBar](https://github.com/steipete/CodexBar).
It shows AI provider usage, reset windows, costs, status, and account data in
the Plasma panel.

This repository contains only the Plasma applet. Provider logic,
authentication, configuration, quota parsing, and JSON output come from the
`codexbar` CLI.

![CodexBar Plasma overview](docs/codexbar-plasma-overview.png)

![Usage and spend dashboard](docs/codexbar-plasma-usage-spend.png)

![Local agent sessions](docs/codexbar-plasma-sessions.png)

![Codex provider detail](docs/codexbar-plasma-codex.png)

Screenshots use synthetic demo accounts, usage, spend, and session data; no
personal account data is included. They use one Plasma theme and accent color.
The widget follows the user's Plasma theme for text, surfaces, selection, and
status colors; provider accent colors stay stable for recognition.

## Install

1. Install the `codexbar` CLI from the
   [official CodexBar release tarballs](https://github.com/steipete/CodexBar/releases/latest)
   or another installation method documented by the upstream project. Third-party
   packages such as AUR can lag behind upstream releases.

2. Download `codexbar-plasma.plasmoid` from the
   [latest release](https://github.com/Lucenx9/codexbar-plasma/releases/latest).

3. Install the widget:

   ```sh
   kpackagetool6 -t Plasma/Applet -i codexbar-plasma.plasmoid
   ```

4. Add **CodexBar** to a Plasma panel.

To upgrade an existing install:

```sh
kpackagetool6 -t Plasma/Applet -u codexbar-plasma.plasmoid
systemctl --user restart plasma-plasmashell.service
```

To update using the bundled release helper:

```sh
make update
```

The helper accepts only immutable GitHub releases. It binds both release assets
to the advertised tag, checks their GitHub SHA-256 digests and published
checksum, then validates the applet id and version inside the archive before
invoking `kpackagetool6`. Any mismatch aborts the installation.

The widget can also check GitHub Releases for newer `.plasmoid` packages.
**Check for widget updates** and update-available notifications are enabled by
default; **Install widget updates automatically** is opt-in. If the widget is
published through KDE Store in the future, prefer Plasma Discover/KNewStuff for
that install channel.

## Requirements

- KDE Plasma 6
- `kpackagetool6`
- `org.kde.plasma.plasma5support`
- `codexbar` CLI on `PATH`, or an absolute CLI path configured in the widget
- `notify-send` for optional Plasma notifications
- `curl`, `jq`, `python3`, `sha256sum`, and GNU `timeout` for the bundled release
  updater; GNU `timeout` also bounds CLI writes after a secret prompt

Leave **Command path** set to `codexbar` to resolve the CLI through Plasma's
`PATH`. If the CLI works in a terminal but the widget cannot find it, locate the
binary with:

```sh
command -v codexbar
```

Then paste the returned absolute path into the widget setting.

## CLI check

Before debugging the widget, verify the data source directly. If these commands
do not work, the Plasma widget cannot show the corresponding data.

```sh
codexbar usage --format json --json-only
codexbar usage --format json --json-only --provider codex --source oauth
codexbar usage --provider codex --all-accounts --format json --json-only
codexbar cost --format json --json-only
codexbar sessions --json-v2
```

The widget keeps compatibility fallbacks for older CLI payloads. With CodexBar
0.48.1 and later it also consumes the generic `usage.details` contract for
provider-defined detail rows and bounded bar/line charts.

## Features

Panel and popup:

- Compact panel indicator for one provider or multiple providers.
- Provider tabs with usage bars, reset windows, account identity, status, and
  credits.
- Panel text modes for percent used or left, pace, usage plus pace, reset time,
  and a run-out forecast that shows the predicted duration only while the CLI
  expects the quota to run out before its reset.
- Auto-select highest-usage provider for the compact panel and provider detail
  focus.
- Overview tab with per-provider usage summary and quick switching.
- Global **Usage & Spend** tab with a Cost/Tokens selector, a 7/30/90-day range
  selector, interactive daily chart, activity heatmap, and provider totals that
  keep different currencies separate.
- Local **Sessions** tab backed by `sessions --json-v2`; transcript paths and
  working directories are never rendered or opened. The tab refreshes stale
  session data while it remains visible.
- Overview providers can be limited to a chosen set of up to 3 providers, or
  left automatic (the first 3 eligible providers).
- Usage dashboard summaries for provider payloads that expose API spend,
  request, token, model, or dashboard fields through the CLI.
- Declarative provider detail sections from the CLI `usage.details` contract,
  including labeled rows, secondary values, and keyboard/pointer-inspectable
  bar/line charts.

Providers and accounts:

- Provider enable/disable and setup actions write CodexBar configuration
  immediately; Apply and Cancel cover widget settings only.
- Account discovery and selection through `codexbar usage --all-accounts`.
- Provider docs, dashboards, login/account links, and redacted diagnostics.
- Descriptor-backed provider settings for CLI-advertised fields such as source,
  API key, cookie source/manual cookie, base URL, workspace/project ID, region,
  and optional usage extras.
- Provider-specific CLI command hints as a fallback when a descriptor is not
  available.
- Generic API key setup for Fireworks, whose current CLI contract discovers the
  account slug from the key.
- Fallback names, colors, links, aliases, and icons for all 69 providers in the
  official CodexBar 0.49.1 registry; fork-only provider assets remain available
  for compatibility.

Costs and history:

- Local cost drill-down when the CLI exposes cost data.
- Local-history scans run independently from quota refreshes, automatically at
  most once per hour; the **Usage & Spend** refresh button starts one immediately.
- Token breakdowns, model summaries, recent daily spend, cost history bars, and
  average cost per 1M tokens, with a configurable cost history window.
- Cost totals qualified as estimated, partial, or approximate from the CLI's
  bounded pricing coverage and provenance metadata.
- Cost-trust notices explain why a range is incomplete or estimated. Closing a
  notice suppresses the same meaning for that provider or the aggregate Spend
  view across refreshes and popup reopenings; a materially different warning is
  shown again.

Status and notifications:

- Provider status incident badge in the panel and provider detail view.
- Optional quota warning markers on usage bars.
- Optional Plasma notifications for provider status incidents, configurable
  quota crossings, predicted quota exhaustion from CLI pace data, and when a
  heavily used limit resets back to empty.

Settings:

- Split settings pages for general refresh/notification controls, display,
  advanced provider overrides, and redacted CLI diagnostics.
- A global, cancelable **Restore all defaults** action for user-facing widget
  settings; provider accounts and CodexBar CLI configuration are left intact.
- Usage refresh choices: no periodic refresh, 1 min, 2 min, 5 min, 15 min, or a
  custom interval. Provider service status remains opt-in.
- Configurable order for the provider identity, service status, usage text, and
  provider meters shown in the panel.
- Check for widget updates, notify when an update is available, and opt in to
  silent automatic widget installation.

## Troubleshooting

If the widget stays on **Loading**:

```sh
codexbar usage --format json --json-only
```

If that works in a terminal but not in Plasma, run `command -v codexbar` and
paste the returned absolute path into the widget setting. Use **Use PATH** to
return to the portable `codexbar` default after changing installation method.

If providers or accounts are missing:

```sh
codexbar usage --provider codex --all-accounts --format json --json-only
```

Then check the **Providers** settings page and make sure the provider is
enabled.

If costs are missing:

```sh
codexbar cost --format json --json-only
```

Cost sections are shown only when the CLI returns cost data for the selected
provider.

If notifications do not appear:

```sh
notify-send "CodexBar" "Notification test"
```

Then confirm notifications are enabled in the widget settings.

For Plasma/QML errors:

```sh
journalctl --user -u plasma-plasmashell.service --since "10 minutes ago" --no-pager | grep -iE "codexbar|app.codexbar|qml|error"
```

## Development

Install from a local checkout:

```sh
git clone https://github.com/Lucenx9/codexbar-plasma.git
cd codexbar-plasma
make install
systemctl --user restart plasma-plasmashell.service
```

Upgrade a local checkout:

```sh
./install.sh
```

Both paths build and install the curated `.plasmoid` archive; repository-only
files such as tests and agent instructions are not copied into the installed
applet.

Run checks:

```sh
make check
```

Update the translation template after changing user-facing `i18n` strings:

```sh
make translations
```

Package locally:

```sh
make package
```

`make check` runs ShellCheck, the static regression checks, the Qt tests,
XML/JSON validation, and `qmllint`. When `kpackagetool6` is available, it also
validates the AppStream metadata; otherwise, it reports that the check was
skipped. The command passes `--unqualified disable` to `qmllint` because Plasma
injects helpers such as `i18n()` as context properties that otherwise create
noisy false-positive warnings.

Project structure:

```text
metadata.json
contents/config/
contents/icons/
contents/ui/
docs/
scripts/
```

Provider support stays upstream in CodexBar. When the Plasma frontend needs new
data, add it to the CLI JSON contract first instead of scraping or editing
CodexBar config files directly from QML.

## Attribution

CodexBar Plasma is derived from the CodexBar project and uses the same MIT
license. See [NOTICE.md](NOTICE.md).
