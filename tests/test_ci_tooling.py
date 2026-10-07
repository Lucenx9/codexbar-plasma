"""Unverified CI downloads must fail before archive extraction."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ActionlintInstallerTests(unittest.TestCase):
    def test_corrupt_or_failed_download_never_reaches_extraction(self):
        for failed_download in (False, True):
            with self.subTest(failed_download=failed_download), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                tools, downloads = root / "tools", root / "downloads"
                tools.mkdir()
                downloads.mkdir()
                curl = tools / "curl"
                curl.write_text("""#!/bin/sh
while [ "$#" -gt 0 ]; do
    if [ "$1" = -o ]; then
        shift
        printf 'corrupt archive' > "$1"
        break
    fi
    shift
done
if [ "$TEST_DOWNLOAD_FAIL" = 1 ]; then exit 22; fi
""")
                tar = tools / "tar"
                tar.write_text('#!/bin/sh\ntouch "$TEST_EXTRACTION_MARKER"\n')
                curl.chmod(0o755)
                tar.chmod(0o755)
                marker = root / "extracted"
                result = subprocess.run(
                    ["bash", str(ROOT / "scripts/install-actionlint.sh")],
                    env={**os.environ, "PATH": f"{tools}:{os.environ['PATH']}",
                         "TMPDIR": str(downloads), "TEST_EXTRACTION_MARKER": str(marker),
                         "TEST_DOWNLOAD_FAIL": str(int(failed_download))},
                    capture_output=True, text=True, timeout=10,
                )
                self.assertNotEqual(result.returncode, 0)
                if failed_download:
                    self.assertEqual(result.returncode, 22)
                else:
                    self.assertIn("checksum did NOT match", result.stderr)
                self.assertFalse(marker.exists(), "Unverified archive reached tar")
                self.assertEqual(list(downloads.iterdir()), [], "Download temporary files leaked")


class DependencyInstallerTests(unittest.TestCase):
    def test_archive_failures_stop_before_installation_or_locale_generation(self):
        for failure_stage in ("update", "install"):
            with self.subTest(stage=failure_stage), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                apt = root / "apt-get"
                apt.write_text("""#!/bin/sh
printf '%s\\n' "$*" >> "$APT_TEST_CALLS"
case " $* " in
  *" $APT_TEST_FAILURE_STAGE "*) exit 42 ;;
esac
""")
                locale = root / "locale-gen"
                locale.write_text('#!/bin/sh\nexit 99\n')
                apt.chmod(0o755)
                locale.chmod(0o755)
                calls = root / "calls"
                result = subprocess.run(
                    ["bash", str(ROOT / "scripts/install-ci-dependencies.sh")],
                    env={**os.environ, "PATH": f"{root}:{os.environ['PATH']}",
                         "APT_TEST_CALLS": str(calls), "APT_TEST_FAILURE_STAGE": failure_stage},
                    capture_output=True, text=True, timeout=10,
                )
                self.assertEqual(result.returncode, 42)
                commands = calls.read_text().splitlines()
                self.assertEqual(len(commands), 1 if failure_stage == "update" else 2)
                self.assertIn("APT::Update::Error-Mode=any", commands[0])
                for command in commands:
                    self.assertIn("Acquire::Retries=3", command)
                    self.assertIn("Acquire::http::Timeout=30", command)
                    self.assertIn("Acquire::https::Timeout=30", command)


if __name__ == "__main__":
    unittest.main()
