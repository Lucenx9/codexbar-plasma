"""Shell fragment assertions must fail when their source cannot be inspected."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


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


if __name__ == "__main__":
    unittest.main()
