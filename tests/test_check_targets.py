"""`make check` must schedule every check the repository defines."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
MAKEFILE = (ROOT / "Makefile").read_text(encoding="utf-8")


def check_targets():
    """Return the target names listed in the CHECK_TARGETS assignment."""
    match = re.search(r"^CHECK_TARGETS :=((?:[^\n]*\\\n)*[^\n]*)$", MAKEFILE, re.M)
    assert match, "Makefile must assign CHECK_TARGETS"
    return match.group(1).replace("\\\n", " ").split()


def defined_targets():
    """Return explicitly defined check-* targets, excluding the pattern rule."""
    return re.findall(r"^(check-[a-z0-9-]+):", MAKEFILE, re.M)


class CheckTargetTests(unittest.TestCase):
    def test_every_defined_check_target_is_scheduled(self):
        listed = set(check_targets())
        missing = sorted(target for target in defined_targets() if target not in listed)
        self.assertEqual(missing, [], "defined but never run by `make check`")

    def test_every_listed_target_exists(self):
        defined = set(defined_targets())
        listed = [target for target in check_targets() if not target.startswith("$(")]
        missing = sorted(target for target in listed if target not in defined)
        self.assertEqual(missing, [], "listed in CHECK_TARGETS without a rule")

    def test_python_modules_are_scheduled_individually(self):
        self.assertIn("$(PYTHON_CHECK_TARGETS)", check_targets())
        self.assertRegex(MAKEFILE, r"(?m)^PYTHON_TEST_MODULES := .*wildcard tests/test_\*\.py")
        self.assertRegex(MAKEFILE, r"(?m)^check-python-%:")

    def test_every_check_script_runs_in_some_target(self):
        scripts = sorted(path.name for path in (ROOT / "scripts").glob("test_*.sh"))
        self.assertTrue(scripts, "expected shell check scripts")
        missing = [name for name in scripts if f"scripts/{name}" not in MAKEFILE]
        self.assertEqual(missing, [], "check script not wired into the Makefile")

    def test_check_suite_opts_into_parallel_targets(self):
        # A serial recipe would leave the machine idle: most Python modules
        # start their own qmltestrunner.
        self.assertRegex(MAKEFILE, r"(?m)^MAKEFLAGS \+= -j\$\(JOBS\) --output-sync=target$")
        self.assertRegex(MAKEFILE, r"(?m)^JOBS \?= ")


if __name__ == "__main__":
    unittest.main()
