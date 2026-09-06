"""Check shipped catalogs, placeholder integrity, and generated package contents."""

import gettext
import json
import io
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from compile_translations import ROOT, compile_catalogs

HEADER = '''msgid ""
msgstr ""
"Project-Id-Version: translation-test\\n"
"Report-Msgid-Bugs-To: https://example.com/issues\\n"
"PO-Revision-Date: 2026-09-06 00:00+0000\\n"
"Last-Translator: Test team\\n"
"Language-Team: Italian\\n"
"Language: it\\n"
"MIME-Version: 1.0\\n"
"Content-Type: text/plain; charset=UTF-8\\n"
"Content-Transfer-Encoding: 8bit\\n"
"Plural-Forms: nplurals=2; plural=(n != 1);\\n"

'''

PLURAL_CASES = (
    ("it", "nplurals=2; plural=(n != 1);", ("Un elemento", "%1 elementi"), ((1, 0), (2, 1)), (1,)),
    ("fr", "nplurals=2; plural=(n > 1);", ("%1 élément", "%1 éléments"), ((0, 0), (1, 0), (2, 1)), (1,)),
    ("ru", "nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);",
     ("%1 элемент", "%1 элемента", "%1 элементов"), ((1, 0), (21, 0), (2, 1), (5, 2)), (0, 1, 2)),
    ("ja", "nplurals=1; plural=0;", ("%1 個",), ((1, 0), (2, 0)), (0,)),
    ("it", "nplurals=2; plural=(n == 1);", ("%1 elementi", "Un elemento"), ((1, 1), (2, 0)), (0,)),
)


class TranslationTests(unittest.TestCase):
    def fixture(self, root, translated, *, flags="", plural=False, source=None,
                language="it", plural_forms="nplurals=2; plural=(n != 1);"):
        (root / "po").mkdir(exist_ok=True)
        (root / "metadata.json").write_text(json.dumps({"KPlugin": {"Id": "test.widget"}}))
        if plural:
            source = source or 'msgid "%1 minute"\nmsgid_plural "%1 minutes"\n'
            empty = 'msgstr[0] ""\nmsgstr[1] ""\n'
        else:
            source = source or 'msgid "Updated %1"\n'
            empty = 'msgstr ""\n'
        header = HEADER.replace("Language: it", "Language: " + language).replace(
            "nplurals=2; plural=(n != 1);", plural_forms)
        (root / "po/codexbar-plasma.pot").write_text(header + source + empty, encoding="utf-8")
        (root / f"po/{language}.po").write_text(header + flags + source + translated, encoding="utf-8")

    def plural_fixture(self, root, language, plural_forms, translations, source=None):
        translated = "".join(f"msgstr[{index}] {json.dumps(text, ensure_ascii=False)}\n"
                             for index, text in enumerate(translations))
        self.fixture(root, translated, plural=True, language=language, plural_forms=plural_forms,
                     source=source or 'msgid "One item"\nmsgid_plural "%1 items"\n')

    def test_shipped_catalogs_compile_with_plurals_and_english_fallback(self):
        expected = {"it": "Panoramica", "fr": "Vue d'ensemble", "de": "Übersicht", "es": "Resumen",
                    "pt_BR": "Visão geral"}
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "locale"
            self.assertEqual(compile_catalogs(output), sorted(expected))
            domain = "plasma_applet_" + json.loads((ROOT / "metadata.json").read_text())["KPlugin"]["Id"]
            for language, overview in expected.items():
                with self.subTest(language=language):
                    catalog = gettext.translation(domain, output, languages=[language])
                    self.assertEqual(catalog.gettext("Overview"), overview)
                    self.assertNotEqual(catalog.ngettext("%1 hour", "%1 hours", 1), "%1 hour")
                    self.assertNotEqual(catalog.ngettext("%1 hour", "%1 hours", 2), "%1 hours")
            fallback = gettext.translation(domain, output, languages=["zz"], fallback=True)
            self.assertEqual(fallback.gettext("Overview"), "Overview")

    def test_missing_translation_and_fuzzy_entry_are_rejected(self):
        for flags, translation in [("", 'msgstr ""\n'), ('#, fuzzy\n', 'msgstr "Aggiornato %1"\n')]:
            with self.subTest(flags=flags), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                self.fixture(root, translation, flags=flags)
                with self.assertRaises(subprocess.CalledProcessError):
                    compile_catalogs(root / "locale", root)

    def test_placeholder_loss_is_rejected_even_without_format_flags(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fixture(root, 'msgstr "Aggiornato %2"\n')
            output = root / "locale"
            output.mkdir()
            (output / "previous.mo").write_bytes(b"previous catalog")
            with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                compile_catalogs(output, root)
            self.assertEqual((output / "previous.mo").read_bytes(), b"previous catalog")

    def test_all_plural_forms_preserve_placeholders(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fixture(root, 'msgstr[0] "%1 minuto"\nmsgstr[1] "minuti"\n', plural=True)
            with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                compile_catalogs(root / "locale", root)

    def test_differing_source_placeholders_follow_the_language_plural_rules(self):
        for language, formula, translations, probes, _ in PLURAL_CASES:
            with self.subTest(language=language, formula=formula), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                self.plural_fixture(root, language, formula, translations)
                compile_catalogs(root / "locale", root)
                catalog = gettext.translation("plasma_applet_test.widget", root / "locale", languages=[language])
                for count, index in probes:
                    self.assertEqual(catalog.ngettext("One item", "%1 items", count), translations[index])

    def test_plural_only_arguments_cannot_disappear_from_forms_used_for_many(self):
        for language, formula, translations, _, required_forms in PLURAL_CASES:
            for index in required_forms:
                with self.subTest(language=language, formula=formula, form=index), tempfile.TemporaryDirectory() as temporary:
                    root = Path(temporary)
                    changed = list(translations)
                    changed[index] = changed[index].replace("%1", "")
                    self.plural_fixture(root, language, formula, changed)
                    with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                        compile_catalogs(root / "locale", root)

    def test_every_plural_form_preserves_shared_arguments_and_rejects_added_arguments(self):
        source = 'msgid "%1 item for %2"\nmsgid_plural "%1 items for %2"\n'
        for language, formula, translations, _, _ in PLURAL_CASES:
            for index in range(len(translations)):
                for changed_text in ("Item %1", "Item %2", "Item %1 %2 %3", "Item %1 %1 %2"):
                    with self.subTest(language=language, formula=formula, form=index,
                                      text=changed_text), tempfile.TemporaryDirectory() as temporary:
                        root = Path(temporary)
                        changed = ["Item %1 %2"] * len(translations)
                        changed[index] = changed_text
                        self.plural_fixture(root, language, formula, changed, source)
                        with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                            compile_catalogs(root / "locale", root)

    def test_context_and_multiline_plural_sources_keep_their_own_arguments(self):
        source = ('msgctxt ""\n"Count\\n"\n"context %9"\n'
                  'msgid ""\n"One item\\n"\n"for %2"\n'
                  'msgid_plural ""\n"%1 items\\n"\n"for %2"\n')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.plural_fixture(root, "it", "nplurals=2; plural=(n != 1);",
                                ("Un elemento\nper %2", "%1 elementi\nper %2"), source)
            compile_catalogs(root / "locale", root)
            catalog = gettext.translation("plasma_applet_test.widget", root / "locale", languages=["it"])
            self.assertEqual(catalog.npgettext("Count\ncontext %9", "One item\nfor %2", "%1 items\nfor %2", 2),
                             "%1 elementi\nper %2")

    def test_no_format_flag_cannot_disable_argument_validation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fixture(root, 'msgstr "Aggiornato %2"\n', flags="#, no-kde-format\n")
            with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                compile_catalogs(root / "locale", root)

    def test_rebuild_removes_stale_catalogs_and_uses_requested_domain(self):
        with tempfile.TemporaryDirectory(prefix="translations with spaces '") as temporary:
            root = Path(temporary)
            self.fixture(root, 'msgstr "Aggiornato %1"\n')
            output = root / "locale"
            output.mkdir()
            (output / "stale.mo").touch()
            compile_catalogs(output, root, applet_id="test.smoke")
            files = [str(path.relative_to(output)) for path in output.rglob("*") if path.is_file()]
            self.assertEqual(files, ["it/LC_MESSAGES/plasma_applet_test.smoke.mo"])
            catalog = gettext.translation("plasma_applet_test.smoke", output, languages=["it"])
            self.assertEqual(catalog.gettext("Updated %1"), "Aggiornato %1")

    def test_language_header_must_match_the_catalog_name(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fixture(root, 'msgstr "Aggiornato %1"\n')
            (root / "po/it.po").rename(root / "po/fr.po")
            with self.assertRaisesRegex(ValueError, "Language header"):
                compile_catalogs(root / "locale", root)

    def package_fixture(self, root):
        shutil.copyfile(ROOT / "Makefile", root / "Makefile")
        shutil.copyfile(ROOT / "metadata.json", root / "metadata.json")
        shutil.copytree(ROOT / "po", root / "po")
        (root / "scripts").mkdir()
        shutil.copyfile(ROOT / "scripts/compile_translations.py", root / "scripts/compile_translations.py")

    def test_package_bundles_compiled_catalogs_without_po_sources(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.package_fixture(root)
            (root / "contents").mkdir()
            subprocess.run(["make", "-C", str(root), "package", "PACKAGE_FILES=metadata.json contents"],
                           check=True, capture_output=True, text=True)
            with zipfile.ZipFile(root / "dist/codexbar-plasma.plasmoid") as archive:
                paths = [name for name in archive.namelist() if name.endswith(".mo")]
                self.assertEqual(len(paths), 5)
                self.assertFalse(any(name.endswith(".po") for name in archive.namelist()))
                italian = "contents/locale/it/LC_MESSAGES/plasma_applet_app.codexbar.plasma.mo"
                catalog = gettext.GNUTranslations(io.BytesIO(archive.read(italian)))
                self.assertEqual(catalog.gettext("Overview"), "Panoramica")
                portuguese = "contents/locale/pt_BR/LC_MESSAGES/plasma_applet_app.codexbar.plasma.mo"
                catalog = gettext.GNUTranslations(io.BytesIO(archive.read(portuguese)))
                self.assertEqual(catalog.gettext("Overview"), "Visão geral")
                self.assertEqual(catalog.ngettext("%1 hour", "%1 hours", 0), "%1 hora")
                self.assertEqual(catalog.ngettext("%1 hour", "%1 hours", 1), "%1 hora")
                self.assertEqual(catalog.ngettext("%1 hour", "%1 hours", 2), "%1 horas")

    def test_package_rejects_source_symlinks_before_compiling(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.package_fixture(root)
            external = root / "external"
            external.mkdir()
            (root / "contents").symlink_to(external, target_is_directory=True)
            result = subprocess.run(["make", "-C", str(root), "package", "PACKAGE_FILES=metadata.json contents"],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("refusing to package symlinks", result.stderr)
            self.assertEqual(list(external.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
