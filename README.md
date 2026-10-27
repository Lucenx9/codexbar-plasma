# CodexBar Plasma

A standalone KDE Plasma 6 widget for the official
[CodexBar CLI](https://github.com/steipete/CodexBar). Track Codex, Claude, Gemini,
and other CLI providers from your panel, with quotas, reset windows, costs,
local agent sessions, notifications, and multiple accounts.

Available data and setup actions depend on the provider and the Linux CLI.

[Install](#install) · [Requirements](#requirements) · [Features](#features) · [Update](#update) · [Troubleshooting](#troubleshooting) · [Development](#development)

![Overview, Usage and Spend, Sessions, and a provider detail tab in the CodexBar popup](docs/codexbar-plasma-tour.gif)

Breeze Dark with synthetic data. The widget follows your Plasma theme.

## Requirements

- KDE Plasma 6, `kpackagetool6`, and the `org.kde.plasma.plasma5support` QML module.
- A working `codexbar` CLI on Plasma's `PATH` or an absolute path selected in
  the widget. You can install a private official copy during setup. Managed
  downloads support Linux x86_64 and aarch64 with glibc or musl.
- For the terminal installer and widget updater: Bash,
  `curl`, `jq`, `python3`, `sha256sum`, GNU `timeout`, and util-linux `flock`.

Distribution package names vary. Source builds also need `make`, Python 3,
and GNU gettext; see [Development](#development).

<details>
<summary>Dependencies for individual features</summary>

| Feature | Dependencies |
| --- | --- |
| Plasma notifications | `notify-send` |
| Usage sharing, file picker, and image clipboard | `QtQuick.Dialogs` and KDE Declarative's `org.kde.kquickcontrolsaddons` QML modules |
| Terminate hung background CLI reads and bound writes after a secret prompt | GNU `timeout` |
| Offline support reports and service status components | `python3` and GNU `timeout` |
| CLI release checks and managed installs | `python3` and GNU `timeout` |
| AI Insights | `python3`, GNU `timeout`, and the `QtCore` QML module |
| AI Insights keys for OpenRouter or OpenAI | Also `kdialog`, `secret-tool`, and a Secret Service provider such as KWallet |
| Identified Codex token subtotals | CLI 0.75.0 or later and GNU `timeout` |
| Refresh as soon as the network connection returns | Qt 6.7 or later with the `QtNetwork` QML module |
| SSH source for identified Codex tokens | Also the CLI on the remote computer and noninteractive SSH authentication with trusted host keys |

Without GNU `timeout`, background CLI reads still work, but canceling a request
cannot terminate a hung process. Without the support-report or status helpers,
other Diagnostics controls and links to status pages remain available.
AI Insights is off by default and needs no helper dependencies while disabled.

</details>

## Install

### Quick install from a terminal

In your Plasma 6 desktop session, run this as your regular user, without `sudo`.
Bash must be installed; your terminal can use another shell.

```sh
bash -o pipefail -c 'curl -fsSL --connect-timeout 10 -m 30 --max-filesize 65536 --max-redirs 5 --proto "=https" --proto-redir "=https" https://raw.githubusercontent.com/Lucenx9/codexbar-plasma/main/setup.sh | bash'
```

This downloads the installer from this repository's `main` branch and installs
its latest stable release package, without a Git checkout or build. It reports
missing commands before downloading the package. If `codexbar` is absent from
your terminal's `PATH`, answer `y` to prepare a private official CLI.
Existing CLI installations and provider credentials are preserved.

Continue with [Set up the widget](#set-up-the-widget).

Rerunning the command upgrades an older widget and offers to restart Plasma.
Prompts default to No and are skipped without a terminal. Download failures
return a nonzero exit status.

<details>
<summary>Inspect the installer or run unattended setup</summary>

To inspect the bootstrap first, download
[`setup.sh`](https://github.com/Lucenx9/codexbar-plasma/blob/main/setup.sh)
to a file you choose, inspect it, and run it with `bash FILE`.
It downloads the complete
[`scripts/update-widget.sh`](https://github.com/Lucenx9/codexbar-plasma/blob/main/scripts/update-widget.sh)
into shell memory before running it. You can also download and inspect the full
installer and run it with `bash FILE --setup`.
The installer verifies the package's GitHub SHA-256 digests, published checksum,
applet ID, and version.

For unattended or scripted setup, use this form to suppress optional prompts:

```sh
bash -o pipefail -c 'curl -fsSL --connect-timeout 10 --max-time 30 --max-filesize 65536 --max-redirs 5 --proto "=https" --proto-redir "=https" https://raw.githubusercontent.com/Lucenx9/codexbar-plasma/main/setup.sh | bash -s -- --no-input'
```

Add `--with-cli` after `--no-input`, inside the quotes, to install or reuse the
private CLI too. To select the prepared copy, use **General → Managed CLI →
Use managed CLI** in widget settings, then **Apply**.
A CLI preparation failure leaves the widget installed and returns a nonzero status.

</details>

### KDE Store or manual installation

Choose either installation method, then [set up the widget](#set-up-the-widget).

#### KDE Store

From your panel, open **Add Widgets → Get New Widgets → Download New Plasma
Widgets**, search for **CodexBar**, and install it from the
[KDE Store](https://store.kde.org/p/2370789/).

#### Manual package

Download `codexbar-plasma.plasmoid` from the
[latest widget release](https://github.com/Lucenx9/codexbar-plasma/releases/latest).
In the directory containing that file, run:

```sh
kpackagetool6 -t Plasma/Applet -i codexbar-plasma.plasmoid
```

A store listing can trail the GitHub release. The widget's updater follows GitHub.

### Set up the widget

After installing through any method:

1. Open your panel's **Add Widgets** chooser and add **CodexBar**.
2. If the popup reports **CodexBar CLI not found**, click **Install and use CLI**.
   This installs or reuses a private official Linux binary and selects it immediately.
   To use an existing CLI that Plasma cannot find, set its absolute path in
   **Diagnostics → Command path** in widget settings and apply.
3. In widget settings, open **Providers** to enable providers and use their
   supported setup actions. For authentication that needs another tool, follow
   the linked upstream provider instructions.

The popup shows quotas when the CLI returns usage. Use **Panel** settings to
change the compact display and **General** for refresh and privacy settings.
Provider setup and enable/disable actions save immediately to the CLI configuration.
**Apply** and **Cancel** cover widget settings only.

Widget updates install automatically by default. To opt out, clear
**General → Updates → Install widget updates automatically** and apply.
Installed updates take effect after a Plasma restart or logout and login;
the automatic updater never restarts Plasma itself.

For another CLI installation method, see the
[official Linux releases](https://github.com/steipete/CodexBar/releases/latest)
and [upstream instructions](https://github.com/steipete/CodexBar).
Third-party packages such as AUR can lag behind upstream.
For private CLI selection, updates, and rollback, see
[managed CLI settings](https://github.com/Lucenx9/codexbar-plasma/blob/main/docs/usage.md#managed-cli).

## Features

- Quota meters, reset windows, account selection, and provider status, with
  configurable warnings and Plasma notifications.
- Standard and Minimal panel styles, up to two quota capsules per provider,
  horizontal and vertical meters, optional text, and a live settings preview.
- **Usage & Spend** with cost and token charts, history ranges, an activity
  heatmap, and provider, model, and project breakdowns when the CLI supplies them.
- Local agent **Sessions**. Transcript paths and working directories are never
  displayed or opened.
- A local usage summary to save as a PNG or copy as text, and a redacted offline
  support report in **Diagnostics**.
- Optional privacy mode, manual identified Codex token subtotals, and beta
  [AI Insights](https://github.com/Lucenx9/codexbar-plasma/blob/main/docs/usage.md#ai-insights)
  from Ollama, OpenRouter, or OpenAI. AI Insights is off by default and uses
  aggregated statistics only.
- English, Italian, French, German, Spanish, and Brazilian Portuguese, selected
  through your Plasma language preferences.

Bundled names and icons cover all 106 providers in the official CLI 0.77.0
registry. Newer CLI providers use generic presentation where needed.

| Standard panel | Minimal panel |
| --- | --- |
| [![Colored provider icons and dual quota capsules in the Standard panel](docs/codexbar-plasma-panel-standard.png)](docs/codexbar-plasma-panel-standard.png) | [![Monochrome provider icons and dual quota capsules in the Minimal panel](docs/codexbar-plasma-panel-minimal.png)](docs/codexbar-plasma-panel-minimal.png) |

The same usage in both styles, with panel text hidden.

| Provider overview | Local sessions |
| --- | --- |
| [![Overview with Codex, Claude, and Gemini usage](docs/codexbar-plasma-overview.png)](docs/codexbar-plasma-overview.png) | [![Active and idle local agent sessions](docs/codexbar-plasma-sessions.png)](docs/codexbar-plasma-sessions.png) |
| **Usage & Spend** | **Provider details** |
| [![Thirty days of spending and activity across providers](docs/codexbar-plasma-usage-spend.png)](docs/codexbar-plasma-usage-spend.png) | [![Codex quotas, reset windows, and daily cost history](docs/codexbar-plasma-codex.png)](docs/codexbar-plasma-codex.png) |

Click an image to open it. All captures use synthetic data.

New widgets refresh quotas every five minutes and when you open the popup on
stale data. Percentages show quota **used**, with warning and critical thresholds
at 80% and 95%. After a failed refresh, recent quotas remain visible as last known
for up to 24 hours. See
[data freshness](https://github.com/Lucenx9/codexbar-plasma/blob/main/docs/usage.md#data-freshness)
for cache limits.

<!-- Web links to guides also work in the installed package, which omits those files. -->
The [usage and settings guide](https://github.com/Lucenx9/codexbar-plasma/blob/main/docs/usage.md)
covers options, defaults, provider setup, and data limits. The
[documentation index](https://github.com/Lucenx9/codexbar-plasma/blob/main/docs/README.md)
links verified CLI evidence; [Linux parity TODO](https://github.com/Lucenx9/codexbar-plasma/blob/main/TODO.md)
tracks remaining work and upstream blockers.

## Update

Widget update checks, notifications, and automatic installation are enabled by
default, with checks every 24 hours. Manage them in **General → Updates**.
Existing saved choices are preserved. Instances without a saved value use the
current defaults, including automatic installation. Plasma may have omitted a
previous off value because it matched the old default.
Read the [changelog](CHANGELOG.md) for changes and upgrade notes.

To update manually, download the new `.plasmoid` from the
[latest widget release](https://github.com/Lucenx9/codexbar-plasma/releases/latest)
and run in its directory:

```sh
kpackagetool6 -t Plasma/Applet -u codexbar-plasma.plasmoid
```

After either kind of update, log out and back in, or reload your Plasma panels
and desktop:

```sh
systemctl --user restart plasma-plasmashell.service
```

The updater verifies the release and backs up the installed widget before an
upgrade. A failed installation restores the previous package. For scheduling
and recovery details, see
[update settings](https://github.com/Lucenx9/codexbar-plasma/blob/main/docs/usage.md#settings).

CLI updates are separate. Update a system or package-manager CLI through its
original installation method. **General → CLI updates** can check for official
releases; daily checks are off by default. **General → Managed CLI** can update
or restore the private copy. Its automatic daily updates are also off by default.
See [CLI release checks](https://github.com/Lucenx9/codexbar-plasma/blob/main/docs/usage.md#cli-release-checks-and-installed-versions)
and [managed CLI settings](https://github.com/Lucenx9/codexbar-plasma/blob/main/docs/usage.md#managed-cli).

## Troubleshooting

### The widget stays on Loading or cannot find the CLI

Use **Retry** in the popup or open **Diagnostics** in widget settings.
**Check versions** reports the widget and CLI versions and the resolved CLI path.
If the CLI is missing, **Install and use CLI** prepares a private copy.
A damaged existing private copy reports an error instead of being selected.

To check an existing CLI, run this in a terminal:

```sh
codexbar usage --format json --json-only
```

If it fails, resolve the provider or CLI setup first. If it works, locate it:

```sh
command -v codexbar
```

Paste the returned absolute path into **Diagnostics → Command path** and apply.
Plasma may have a different `PATH` from your terminal. **Use PATH** restores the
`codexbar` default. For a managed copy, use the resolved path from
**Diagnostics → Check versions** in terminal commands.

### Providers, accounts, or costs are missing

If the popup has no provider data, choose **Configure providers** and enable or
set up a provider. Check the relevant CLI response, for example:

```sh
codexbar usage --provider codex --all-accounts --format json --json-only
codexbar cost --format json --json-only
```

The widget displays only data the CLI returns. Missing dollar amounts do not
mean zero spend. See the
[provider setup and compatibility notes](https://github.com/Lucenx9/codexbar-plasma/blob/main/docs/usage.md#providers-and-accounts)
for version-specific issues, including Gemini's Automatic source on CLI 0.77.0
through 0.80.0.

### Notifications do not appear

Check **Notifications** in widget settings and test desktop notifications:

```sh
notify-send "CodexBar" "Notification test"
```

### Report a problem

[Open a widget issue](https://github.com/Lucenx9/codexbar-plasma/issues/new/choose)
and complete the form. Include reproduction steps, expected and actual behavior,
your distribution, and the Plasma, widget, and CLI versions. You can collect a
redacted offline support report in **Diagnostics** and review its preview first.
Report suspected vulnerabilities privately through the
[security policy](https://github.com/Lucenx9/codexbar-plasma/blob/main/SECURITY.md).

For QML errors, inspect recent logs:

```sh
journalctl --user -u plasma-plasmashell.service --since '10 minutes ago' --no-pager
```

Include only relevant CodexBar errors. Redact account details, paths, credentials,
and other personal information before sharing logs or screenshots.
If the CLI command itself fails, consult
[upstream CodexBar](https://github.com/steipete/CodexBar) for CLI support.

## Development

Install the build dependencies listed under [Requirements](#requirements), then:

```sh
git clone https://github.com/Lucenx9/codexbar-plasma.git
cd codexbar-plasma
make install
```

Reload Plasma as described under [Update](#update). Before submitting changes,
read [CONTRIBUTING.md](https://github.com/Lucenx9/codexbar-plasma/blob/main/CONTRIBUTING.md)
and run `make check`. The
[development guide](https://github.com/Lucenx9/codexbar-plasma/blob/main/docs/development.md)
lists test dependencies, checks, packaging, runtime verification, and QML conventions.
Provider logic and CLI contracts belong upstream.
To add or improve a language, follow the
[translation guide](https://github.com/Lucenx9/codexbar-plasma/blob/main/docs/translations.md).
CLI-supplied free-form text retains its original language.

## Support

If CodexBar Plasma saves you time, you can
[support development on Ko-fi](https://ko-fi.com/lucenx9). The same link is in
the repository's **Sponsor** button.

## License and attribution

CodexBar Plasma is a standalone frontend for the official
[CodexBar CLI](https://github.com/steipete/CodexBar). The widget code is
distributed under the [MIT License](LICENSE). Bundled provider artwork includes
upstream CodexBar assets and a Poe icon under CC BY 4.0. See
[NOTICE.md](NOTICE.md) for sources, licenses, and attribution.
