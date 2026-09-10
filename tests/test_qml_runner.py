"""Every QML runner invocation must preserve failures and strict skip checks."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class QmlRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="qml runner '")
        self.addCleanup(self.temp.cleanup)
        directory = Path(self.temp.name)
        self.runner = directory / "qmltestrunner"
        self.runner.write_text("""#!/bin/sh
case "$*" in
  *tst_plain_text_controls.qml*) suite=label ;;
  *tst_panel_settings_geometry.qml*) suite=geometry ;;
  *tst_popup_notifications_geometry.qml*) suite=settings-geometry ;;
  *) suite=bulk ;;
esac
if [ "$suite" = "$FAKE_SKIP_SUITE" ]; then
  printf 'SKIP   : optional module unavailable\n'
fi
if [ "$suite" = "$FAKE_FAIL_SUITE" ]; then
  printf 'FAIL!  : runner failure\n'
  exit 7
fi
""")
        self.runner.chmod(0o755)
        self.paths = directory / "qtpaths"
        self.paths.write_text('#!/bin/sh\nprintf \'%s\\n\' "$(dirname "$0")/qml"\n')
        self.paths.chmod(0o755)
        metadata = directory / "qml/org/kde/desktop/qmldir"
        metadata.parent.mkdir(parents=True)
        metadata.touch()

    def run_checks(self, strict=True, skipped="", failed=""):
        return subprocess.run(
            ["bash", str(ROOT / "scripts/test_qml_logic.sh")],
            env={**os.environ, "QMLTESTRUNNER": str(self.runner),
                 "QT_PATHS_TOOL": str(self.paths),
                 "QML_TEST_REQUIRE_NO_SKIPS": "1" if strict else "0",
                 "FAKE_SKIP_SUITE": skipped, "FAKE_FAIL_SUITE": failed},
            capture_output=True, text=True, timeout=10,
        )

    def test_strict_mode_rejects_skips_in_every_invocation(self):
        for suite in ("bulk", "label", "geometry", "settings-geometry"):
            with self.subTest(suite=suite):
                result = self.run_checks(skipped=suite)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("QML tests were skipped", result.stderr)

    def test_optional_mode_allows_skips(self):
        for suite in ("bulk", "label", "geometry", "settings-geometry"):
            with self.subTest(suite=suite):
                result = self.run_checks(strict=False, skipped=suite)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("SKIP", result.stdout)

    def test_runner_failures_propagate(self):
        for suite in ("bulk", "label", "geometry", "settings-geometry"):
            with self.subTest(suite=suite):
                result = self.run_checks(failed=suite)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("FAIL!", result.stdout)

    def test_successful_runs_pass(self):
        result = self.run_checks()
        self.assertEqual(result.returncode, 0, result.stderr)
