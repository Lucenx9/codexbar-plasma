# Auto Update and Theme Handling Design

## Scope

Add an opt-in quiet update path for the Plasma widget and verify that generic UI
colors follow the user's Plasma theme. Provider identity colors stay hardcoded.

This repository remains a small Plasma applet. The updater may install a
released `.plasmoid` package for this applet, but it must not pull in the full
macOS app, Swift sources, or upstream CodexBar tree.

## Goals

- Let users enable automatic widget updates from settings.
- Let users get a quiet notification when a widget update is available, even
  when automatic installation is disabled.
- Keep updates quiet after explicit opt-in.
- Avoid executing remote scripts or arbitrary release content.
- Preserve provider brand colors exactly as provider identity data.
- Make generic text, borders, surfaces, hover, selection, and status colors use
  Plasma/Kirigami theme colors.
- Add cheap static checks for the updater and theme boundaries.

## Non-Goals

- Automatic updates for the `codexbar` CLI.
- A custom release channel UI or changelog browser.
- Runtime editing of provider color identity.
- Replacing Plasma's package manager or distribution package updates.

## Updater Approach

Use a small local helper script plus separate settings for update checks and
automatic installation.

- Add `scripts/update-widget.sh`.
- Add `make update` as a local/manual entry point.
- Add persistent settings in `contents/config/main.xml`:
  - `updateChecksEnabled`, default `true`.
  - `updateNotificationsEnabled`, default `true`.
  - `autoUpdateEnabled`, default `false`.
  - `autoUpdateIntervalHours`, default `24`, bounded to a conservative range.
  - `autoUpdateLastCheck`, stored as a timestamp string or epoch value.
- Add General settings controls:
  - checkbox: `Check for widget updates`.
  - checkbox: `Notify when a widget update is available`, enabled only when
    update checks are enabled.
  - checkbox: `Install widget updates automatically`, enabled only when update
    checks are enabled.
  - interval control enabled only when update checks are enabled.
- Runtime QML schedules checks when `updateChecksEnabled` is true.

The helper script owns all update mechanics:

1. Read the installed/local version from `metadata.json`.
2. Fetch GitHub release metadata for `Lucenx9/codexbar-plasma`.
3. Pick the latest stable semver tag newer than the local version.
4. Download only the `codexbar-plasma.plasmoid` release asset.
5. In check-only mode, report the available version and asset URL without
   installing anything.
6. In install mode, install with `kpackagetool6 -t Plasma/Applet -u`.
7. Restart `plasma-plasmashell.service` only after a successful install.

The widget calls the helper via the existing executable DataSource pattern. A
successful no-op, successful install, and failed check all return structured
JSON that QML can reduce to a quiet status string for settings/debug surfaces.
When check-only mode finds a newer release and notifications are enabled, QML
sends one Plasma notification per version. If automatic installation is enabled,
the widget installs silently instead of only notifying.

## Updater Security Rules

- Do not execute content downloaded from GitHub.
- Do not pipe network data into a shell.
- Use `curl --fail --location --show-error --silent` or an equivalent explicit
  download command.
- Use `mktemp -d` and clean temporary files on exit.
- Install only an asset named `codexbar-plasma.plasmoid`.
- Ignore prereleases and drafts.
- Compare semver tags before installing.
- Quote every shell variable used in paths or commands.
- Keep the update URL and release asset expectations visible in the script.

The first implementation may rely on HTTPS and GitHub Releases. Signature
verification can be added later if releases start publishing checksums or
signatures.

## Theme Handling Approach

Provider colors are identity data and remain hardcoded inside `providerColor()`
and provider icon assets. The theme audit only covers generic UI colors.

Allowed hardcoded color usage:

- `providerColor()` in `main.qml` and `configProviders.qml`.
- Provider icon assets under `contents/icons/providers/`.
- The contrast helper that chooses readable text on arbitrary color fills.
- The root app icon asset.
- Transparent values.

Generic UI colors should use Plasma/Kirigami theme values:

- normal text: `Kirigami.Theme.textColor`.
- selected text: `Kirigami.Theme.highlightedTextColor`.
- selection/accent UI: `Kirigami.Theme.highlightColor`.
- semantic status text: `positiveTextColor`, `negativeTextColor`,
  `neutralTextColor` where appropriate.
- secondary UI marks, borders, hover, and dividers: alpha-adjusted theme colors
  through existing helpers such as `withAlpha()`.

The implementation should audit current QML for hardcoded black, white, gray,
or RGB values outside the allowed identity/contrast areas. Fix only generic UI
theme violations; do not normalize or alter provider identity colors.

## Error Handling

- If the updater cannot reach GitHub, cannot find a valid asset, or install
  fails, it exits non-zero with a concise error.
- QML records the failure as update status for Debug or General settings, but
  does not spam notifications.
- QML memoizes the last notified version so an available update does not notify
  repeatedly on every refresh cycle.
- Existing usage refresh behavior must keep working even if update checks fail.
- If required tools are missing (`curl`, `jq`, `kpackagetool6`,
  `systemctl`), the helper reports the missing tool clearly.

## Tests and Verification

Add a focused static regression script, or extend `scripts/test_feature_parity.sh`,
to assert:

- `scripts/update-widget.sh` exists and is referenced by `Makefile`.
- The update script uses `kpackagetool6 -t Plasma/Applet -u`.
- The update script downloads only `codexbar-plasma.plasmoid`.
- The update script does not execute downloaded files.
- New config keys exist in `contents/config/main.xml`.
- General settings expose update-check, notification, auto-install, and interval
  controls.
- Runtime QML checks `updateChecksEnabled` before invoking the updater.
- Runtime QML can notify for an available update even when `autoUpdateEnabled`
  is false.
- Runtime QML only installs when `autoUpdateEnabled` is true.
- Generic UI hardcoded colors are not introduced outside documented allowed
  areas.

Manual/final verification:

```sh
make check
make package
./install.sh
journalctl --user -u plasma-plasmashell.service --since '2 minutes ago' --no-pager \
  | rg -n 'app\.codexbar|CodexBar|ReferenceError|TypeError|SyntaxError|file://.*/app.codexbar'
```

For updater behavior, use a dry-run or check-only mode in the helper so tests
can exercise version parsing and release selection without installing a release.

## Open Decisions Resolved

- Automatic updates are opt-in, not enabled by default.
- Update checks and available-update notifications are enabled by default.
- After opt-in, updates are quiet unless there is an error visible in settings.
- Provider identity colors remain hardcoded.
- Theme work is limited to generic UI colors that should follow Plasma.
