"""Release notes must come from the matching, complete changelog section."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from changelog import ROOT, validate


BODY = "### Fixed\n\n- Preserve unknown quota values.\n"
DOCUMENT = "# Changelog\n\n## Unreleased\n\n## 1.2.0 - 2026-09-08\n\n" + BODY


class ChangelogTests(unittest.TestCase):
    def test_extracts_only_matching_release(self):
        older = "\n## 1.1.0 - 2026-09-01\n\n### Added\n\n- Older feature.\n"
        self.assertEqual(validate(DOCUMENT + older, "1.2.0", "v1.2.0"), BODY)

    def test_unreleased_work_is_valid_until_tagging(self):
        text = DOCUMENT.replace("## Unreleased\n", "## Unreleased\n\n### Added\n\n- New feature.\n")
        self.assertEqual(validate(text, "1.2.0"), "")
        with self.assertRaisesRegex(ValueError, "move Unreleased"):
            validate(text, "1.2.0", "v1.2.0")

    def test_rejects_wrong_tags_and_metadata(self):
        for version, tag in (("1.2.1", None), ("1.2.0", "v1.1.0"),
                             ("1.2.0", "1.2.0"), ("1.2.0", "v1.2.0-rc1"),
                             (None, None), ("01.2.0", None)):
            with self.subTest(version=version, tag=tag), self.assertRaises(ValueError):
                validate(DOCUMENT, version, tag)

    def test_rejects_incomplete_or_ambiguous_history(self):
        invalid = [
            DOCUMENT.replace("## Unreleased", "## Upcoming"),
            DOCUMENT.replace("2026-09-08", "2026-02-30"),
            DOCUMENT.replace("### Fixed", "### Misc"),
            DOCUMENT.replace(BODY, ""),
            DOCUMENT.replace("- Preserve unknown quota values.", ""),
            DOCUMENT + "\n" + BODY,
            DOCUMENT + "\n## Unreleased\n",
            DOCUMENT + "\n## 1.2.0 - 2026-09-08\n\n" + BODY,
            DOCUMENT + "\n## 1.3.0 - 2026-09-01\n\n" + BODY,
            DOCUMENT + "\n## 1.1.0 - 2026-09-09\n\n" + BODY,
        ]
        for text in invalid:
            with self.subTest(text=text), self.assertRaises(ValueError):
                validate(text, "1.2.0")

    def test_cli_fails_without_emitting_release_notes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            changelog = root / "CHANGELOG.md"
            metadata = root / "metadata.json"
            changelog.write_text(DOCUMENT)
            metadata.write_text(json.dumps({"KPlugin": {"Version": "1.2.0"}}))
            command = [sys.executable, str(ROOT / "scripts/changelog.py"),
                       "--changelog", str(changelog), "--metadata", str(metadata), "--tag"]
            success = subprocess.run(command + ["v1.2.0"], capture_output=True, text=True)
            self.assertEqual(success.returncode, 0, success.stderr)
            self.assertEqual(success.stdout, BODY)
            failed = subprocess.run(command + ["v1.2.1"], capture_output=True, text=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertEqual(failed.stdout, "")
            self.assertIn("release tag must match", failed.stderr)

    def test_repository_changelog_matches_metadata(self):
        metadata = json.loads((ROOT / "metadata.json").read_text())
        validate((ROOT / "CHANGELOG.md").read_text(), metadata["KPlugin"]["Version"])

    def test_release_workflow_uses_checked_notes(self):
        release = (ROOT / ".github/workflows/ci.yml").read_text().split("\n  release:\n", 1)[1]
        extract = 'python3 scripts/changelog.py --tag "$GITHUB_REF_NAME" > dist/release-notes.md'
        self.assertIn(extract, release)
        self.assertLess(release.index(extract), release.index("- name: Publish release"))
        self.assertIn("body_path: dist/release-notes.md", release)
        self.assertIn("generate_release_notes: false", release)
        self.assertNotIn("generate_release_notes: true", release)


if __name__ == "__main__":
    unittest.main()
