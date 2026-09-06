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


class TranslationTests(unittest.TestCase):
    def fixture(self, root, translated, *, flags="", plural=False):
        (root / "po").mkdir(exist_ok=True)
        (root / "metadata.json").write_text(json.dumps({"KPlugin": {"Id": "test.widget"}}))
        if plural:
            source = 'msgid "%1 minute"\nmsgid_plural "%1 minutes"\n'
            empty = 'msgstr[0] ""\nmsgstr[1] ""\n'
        else:
            source = 'msgid "Updated %1"\n'
            empty = 'msgstr ""\n'
        (root / "po/codexbar-plasma.pot").write_text(HEADER + source + empty)
        (root / "po/it.po").write_text(HEADER + flags + source + translated)

    def test_shipped_catalogs_compile_with_plurals_and_english_fallback(self):
        expected = {"it": "Panoramica", "fr": "Vue d'ensemble", "de": "Übersicht", "es": "Resumen"}
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
            with self.assertRaisesRegex(ValueError, "changed placeholders"):
                compile_catalogs(output, root)
            self.assertEqual((output / "previous.mo").read_bytes(), b"previous catalog")

    def test_all_plural_forms_preserve_placeholders(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fixture(root, 'msgstr[0] "%1 minuto"\nmsgstr[1] "minuti"\n', plural=True)
            with self.assertRaisesRegex(ValueError, "changed placeholders"):
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
                self.assertEqual(len(paths), 4)
                self.assertFalse(any(name.endswith(".po") for name in archive.namelist()))
                italian = "contents/locale/it/LC_MESSAGES/plasma_applet_app.codexbar.plasma.mo"
                catalog = gettext.GNUTranslations(io.BytesIO(archive.read(italian)))
                self.assertEqual(catalog.gettext("Overview"), "Panoramica")

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
