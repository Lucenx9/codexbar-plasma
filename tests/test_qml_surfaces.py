"""Shell fragment assertions must fail when their source cannot be inspected."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/lib"))
from qml_surfaces import surface_files


class QmlSurfaceAssertionsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="qml surfaces ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        library = self.root / "scripts/lib"
        library.mkdir(parents=True)
        shutil.copy(ROOT / "scripts/lib/qml_surfaces.py", library)
        self.main = self.root / "contents/ui/main.qml"
        self.main.parent.mkdir(parents=True)
        self.main.write_text("Item { property string marker: 'needle' }\n", encoding="utf-8")

    def run_helper(self, helper, source, needle="needle"):
        return subprocess.run(
            ["bash", "-c", 'set -euo pipefail; ROOT_DIR="$1"; . "$2"; shift 2; "$@"',
             "assertion-test", str(self.root), str(ROOT / "scripts/lib/qml_surfaces.sh"),
             helper, str(source), needle],
            input="", capture_output=True, text=True, timeout=5,
        )

    def test_valid_sources_distinguish_matches_from_absence(self):
        for helper, source in (("require_in_surface", "applet"),
                               ("reject_in_surface", "applet"),
                               ("require_in_file", self.main),
                               ("reject_in_file", self.main)):
            for needle in ("needle", "absent"):
                with self.subTest(helper=helper, needle=needle):
                    result = self.run_helper(helper, source, needle)
                    expected = (helper.startswith("require") == (needle == "needle"))
                    self.assertEqual(result.returncode == 0, expected, result.stderr)

    def test_unknown_surface_fails(self):
        for helper in ("qml_surface_files", "require_in_surface", "reject_in_surface"):
            with self.subTest(helper=helper):
                result = self.run_helper(helper, "aplet")
                self.assertNotEqual(result.returncode, 0, result.stderr)
                self.assertIn("unknown QML surface", result.stderr)

    def test_empty_surface_fails(self):
        self.main.unlink()
        for helper in ("qml_surface_files", "require_in_surface", "reject_in_surface"):
            with self.subTest(helper=helper):
                result = self.run_helper(helper, "applet")
                self.assertNotEqual(result.returncode, 0, result.stderr)
                self.assertIn("resolved to no files", result.stderr)

    def test_missing_manifest_loader_fails(self):
        (self.root / "scripts/lib/qml_surfaces.py").unlink()
        for helper in ("qml_surface_files", "require_in_surface", "reject_in_surface"):
            with self.subTest(helper=helper):
                result = self.run_helper(helper, "applet")
                self.assertNotEqual(result.returncode, 0, result.stderr)

    def test_missing_file_fails(self):
        for helper in ("require_in_file", "reject_in_file"):
            with self.subTest(helper=helper):
                result = self.run_helper(helper, self.main.with_name("missing.qml"))
                self.assertNotEqual(result.returncode, 0, result.stderr)

    def test_surface_read_error_fails_even_with_another_match(self):
        # A directory is an unreadable grep input even when tests run as root.
        (self.main.parent / "broken.js").mkdir()
        for helper in ("require_in_surface", "reject_in_surface"):
            for needle in ("needle", "absent"):
                with self.subTest(helper=helper, needle=needle):
                    result = self.run_helper(helper, "applet", needle)
                    self.assertNotEqual(result.returncode, 0, result.stderr)

    def test_unreadable_wildcard_directory_fails_instead_of_returning_partial_sources(self):
        directory = self.main.parent / "components"
        directory.mkdir()
        (directory / "Hidden.qml").write_text("forbidden", encoding="utf-8")

        def deny_directory(scan):
            def denied(path):
                if Path(path) == directory:
                    raise PermissionError("unreadable surface directory")
                return scan(path)
            return denied

        # Inject the filesystem error so this also runs in the root CI container.
        # pathlib uses listdir or scandir depending on the Python version.
        with mock.patch("os.scandir", side_effect=deny_directory(os.scandir)), \
                mock.patch("os.listdir", side_effect=deny_directory(os.listdir)):
            with self.assertRaisesRegex(PermissionError, "unreadable surface directory"):
                surface_files("applet", self.root)


class QmlSurfaceHelperShadowingTests(unittest.TestCase):
    def test_sourcing_scripts_do_not_redefine_library_helpers(self):
        # A local copy silently replaces the hardened helper, so a negative
        # assertion on a missing or unreadable file passes again.
        library = (ROOT / "scripts/lib/qml_surfaces.sh").read_text(encoding="utf-8")
        helpers = set(re.findall(r"^([a-z_]+)\(\) \{", library, re.M))
        for script in sorted((ROOT / "scripts").glob("*.sh")):
            text = script.read_text(encoding="utf-8")
            if "scripts/lib/qml_surfaces.sh" not in text:
                continue
            defined = set(re.findall(r"^([a-z_]+)\(\) \{", text, re.M))
            with self.subTest(script=script.name):
                self.assertEqual(defined & helpers, set())


if __name__ == "__main__":
    unittest.main()
