# Translate the widget

The applet ships Italian (`it`), French (`fr`), German (`de`), and Spanish (`es`).
It follows Plasma's language preferences and uses English when no matching
catalog exists. CLI-provided labels and provider names are outside the applet's
translation catalog.

Install GNU gettext and Python 3 before running the commands below. Run them
from the repository root.

## Update a catalog

Regenerate the template after changing user-facing QML strings:

```sh
make translations
```

Merge the template into the language you are updating:

```sh
msgmerge --update --backup=none --no-fuzzy-matching po/it.po po/codexbar-plasma.pot
```

Edit the `msgstr` entries in `po/it.po` with a PO editor or text editor. Keep
`msgid` and `msgid_plural` unchanged. Source references above each entry point
to the QML that gives the message its context.

- Keep every `%1`, `%2`, and other numbered argument. You may reorder them.
- Translate every plural form, including short duration labels. Keep the
  language's `Plural-Forms` header accurate.
- Keep CodexBar, provider brands, command names, paths, and URLs unchanged.
- Use short labels for the panel and tabs. Check longer text in the popup.
- Resolve fuzzy entries and translate empty entries before submitting.

Run the catalog checks and build the distributable:

```sh
make check
make package
```

The build uses the plugin ID in `metadata.json` to name the catalog. For this
applet the path inside the archive is
`contents/locale/it/LC_MESSAGES/plasma_applet_app.codexbar.plasma.mo`.
Only the PO sources are committed. The generated catalogs are bundled with the
widget and need no separate system-wide installation. This follows the
[Plasma translation domain convention](https://develop.kde.org/docs/plasma/widget/translations-i18n/).

## Preview a translation

From a Plasma 6 graphical session, run a preview with synthetic data:

```sh
make smoke SMOKE_ARGS='--scenario localization-it'
```

Use `localization-fr`, `localization-de`, or `localization-es` for the other
catalogs. Install or generate the corresponding UTF-8 locale first:
`it_IT.UTF-8`, `fr_FR.UTF-8`, `de_DE.UTF-8`, or `es_ES.UTF-8`.
The CI container generates all four locales.

The preview uses isolated settings and a private D-Bus session. It checks
translated popup and settings text, checks singular and plural forms, and saves
a screenshot. It does not change your desktop language or installed widget.
Review the screenshots for clipped labels and awkward wrapping.

## Add a language

Create a catalog from the current template. For example, for Dutch:

```sh
msginit --no-translator --locale=nl --input=po/codexbar-plasma.pot --output-file=po/nl.po
```

Set the `Language`, `Language-Team`, `Last-Translator`, `PO-Revision-Date`, and
`Plural-Forms` headers. Complete all translations and follow the checks above.
Packaging discovers `po/*.po` automatically.

Add a translated `Description[language]` to `metadata.json` for the widget
picker. Add the language to the catalog assertions in
`tests/test_translations.py`, the preview locale map in `scripts/smoke_popup.py`,
and the scenarios in `scripts/smoke/fixture_cli.py`. Supply expected popup and
plural labels in `scripts/smoke/Capture.qml` and generate the locale in
`scripts/install-ci-dependencies.sh`.

Include the PO file, metadata, checks, and updated language lists in one pull
request. Do not commit `.mo` files or change the CLI to translate its output.
