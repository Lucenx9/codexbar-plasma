# Translate the widget

The applet ships Italian (`it`), French (`fr`), German (`de`), Spanish (`es`),
and Brazilian Portuguese (`pt_BR`).
It follows Plasma's language preferences and uses English when no matching
catalog exists. Known session states and sources, and structured pace forecasts,
use the applet's translation catalog. Provider names remain unchanged.

## CLI text and localization

The CLI 0.56.2 JSON contracts provide the inputs for these translations:

- [`AgentSession`](https://github.com/steipete/CodexBar/blob/v0.56.2/Sources/CodexBarCore/AgentSession.swift)
  defines `active`/`idle` states and `cli`, `desktopApp`, `ide`, and `unknown`
  sources. The widget also translates its existing `running` and `working`
  compatibility values. Unknown future values retain their display text.
- [`CLIRenderer.pacePayload`](https://github.com/steipete/CodexBar/blob/v0.56.2/Sources/CodexBarCLI/CLIRenderer.swift)
  emits `stage`, `deltaPercent`, `expectedUsedPercent`, `willLastToReset`, and
  `etaSeconds`. `PacePresentation.js` validates these fields and returns semantic
  parts; `main.qml` translates them. The widget does not parse the English
  `summary` or recalculate the CLI forecast. A summary-only payload retains its
  bounded, redacted text as a compatibility fallback.

Free-form incident descriptions, provider detail titles/rows/chart labels,
extra-window titles, reset-description fallbacks, and CLI error messages can
still appear in English. Translating them reliably needs official CLI message
identifiers with typed arguments, or a documented locale-aware output contract.
Do not translate arbitrary provider text by matching English phrases. The CLI's
prose-only pace headroom hint also needs a structured presentation field before
the widget can localize it; it is not appended to the structured pace summary.

Track the remaining [structured CLI localization work](../TODO.md#structured-localization)
in TODO.

In Italian, settings use "Diagnostica" and "Finestra a comparsa". Technical
terms such as "provider", "account", and "token" remain unchanged.
Spanish instructions use the formal address consistently. Brazilian Portuguese
uses "Padrão" for the Standard panel style.

Translate labels against their displayed values. "Code review remaining" labels
a remaining quota percentage, and "Included plan" labels usage included in a
plan. Neither describes a count of reviews or a separate included subscription.
The panel's "behind pace" message means the CLI predicts quota exhaustion before
reset (`willLastToReset === false`). Translate it as excessive consumption, not
as consumption below the expected pace.

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
- Integer token, request, and point counts use plural messages. The separate
  `%1 tokens`, `%1 requests`, and `%1 points` entries format compact counts such
  as `1K` and `4.3B`. Keep those abbreviations in the numbered argument; do not
  treat the leading `1` as a singular count.
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

Use `localization-fr`, `localization-de`, `localization-es`, or `localization-pt_BR`
for the other catalogs. Install or generate the corresponding UTF-8 locale first:
`it_IT.UTF-8`, `fr_FR.UTF-8`, `de_DE.UTF-8`, `es_ES.UTF-8`, or `pt_BR.UTF-8`.
The CI container generates all five locales.

The preview uses isolated settings and a private D-Bus session. It checks
translated overview and settings text, singular and plural forms, a provider's
pace summary, and session state/source labels. Count checks cover zero, one,
multiple items, compact values above the integer range, and cost summaries.
It saves a screenshot of the Sessions tab. It does not change your desktop
language or installed widget.
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
