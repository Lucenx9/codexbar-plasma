"""Documentation-only changes may omit graphics, never hide missing coverage."""

import itertools
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from ci_scope import ROOT, docs_only, select_smoke, smoke_result


class ScopePolicyTests(unittest.TestCase):
    def test_editorial_allowlist(self):
        self.assertTrue(docs_only(["README.md", "docs/usage.md", "AGENTS.md",
                                   ".github/pull_request_template.md"]))
        for path in ("contents/ui/main.qml", "po/it.po", "docs/overview.png",
                     "metadata.json", "Makefile", "scripts/ci_scope.py", "tests/test_ci_scope.py",
                     ".github/workflows/ci.yml", "NEW.md", "docs/odd\nname.md"):
            with self.subTest(path=path):
                self.assertFalse(docs_only(["README.md", path]))
        self.assertFalse(docs_only([]))

    def test_gate_accepts_only_proven_coverage_or_explicit_doc_omission(self):
        states = ("success", "failure", "cancelled", "skipped", "", None)
        for scope, required, runtime in itertools.product(states, ("true", "false", "", None), states):
            accepted = (scope, required, runtime) in {
                ("success", "true", "success"), ("success", "false", "skipped"),
            }
            with self.subTest(scope=scope, required=required, runtime=runtime):
                if accepted:
                    self.assertTrue(smoke_result(scope, required, runtime))
                else:
                    with self.assertRaises(ValueError):
                        smoke_result(scope, required, runtime)

    def test_gate_cli_returns_failure_for_missing_runtime(self):
        with tempfile.TemporaryDirectory() as temp:
            result = subprocess.run(
                [sys.executable, str(ROOT / "scripts/ci_scope.py"), "--gate"],
                env={**os.environ, "SCOPE_RESULT": "success", "RUN_SMOKE": "true",
                     "RUNTIME_RESULT": "skipped", "GITHUB_STEP_SUMMARY": str(Path(temp) / "summary")},
                capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unresolved or failed", result.stderr)


class ScopeGitTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-b", "main")
        self.git("config", "user.name", "CI Test")
        self.git("config", "user.email", "ci@example.invalid")
        self.write("README.md", "Initial docs\n")
        self.write("contents/ui/main.qml", "initial runtime\n")
        self.commit()
        self.base = self.git("rev-parse", "HEAD").strip()

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True, stderr=subprocess.DEVNULL)

    def write(self, path, text):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    def commit(self):
        self.git("add", ".")
        self.git("-c", "commit.gpgsign=false", "commit", "-m", "test change")

    def required(self, event="push", ref="refs/heads/main", before=None):
        return select_smoke(event, ref, {"before": before or self.base}, self.root)[0]

    def test_markdown_push_omits_graphics_but_tags_always_run(self):
        self.write("README.md", "Updated docs\n")
        self.commit()
        self.assertFalse(self.required())
        self.assertTrue(self.required(ref="refs/tags/v1.0.0"))

    def test_documentation_scope_and_gate_cli(self):
        self.write("scripts/ci_scope.py", (ROOT / "scripts/ci_scope.py").read_text())
        self.commit()
        before = self.git("rev-parse", "HEAD").strip()
        self.write("README.md", "Documentation only\n")
        self.commit()
        event = self.root / "event.json"
        event.write_text(json.dumps({"before": before}))
        output, summary = self.root / "output", self.root / "summary"
        env = {**os.environ, "GITHUB_EVENT_PATH": str(event), "GITHUB_EVENT_NAME": "push",
               "GITHUB_REF": "refs/heads/main", "GITHUB_OUTPUT": str(output),
               "GITHUB_STEP_SUMMARY": str(summary)}
        command = [sys.executable, str(self.root / "scripts/ci_scope.py")]
        subprocess.run(command, env=env, capture_output=True, text=True, check=True)
        self.assertEqual(output.read_text(), "run_smoke=false\n")
        env.update(SCOPE_RESULT="success", RUN_SMOKE="false", RUNTIME_RESULT="skipped")
        subprocess.run(command + ["--gate"], env=env, capture_output=True, text=True, check=True)
        self.assertIn("intentionally omitted", summary.read_text())

    def test_full_push_range_includes_earlier_runtime_commit(self):
        self.write("contents/ui/main.qml", "changed runtime\n")
        self.commit()
        self.write("README.md", "Latest commit only edits docs\n")
        self.commit()
        self.assertTrue(self.required())

    def test_rename_from_runtime_to_docs_keeps_full_coverage(self):
        (self.root / "docs").mkdir()
        self.git("mv", "contents/ui/main.qml", "docs/renamed.md")
        self.commit()
        self.assertTrue(self.required())

    def test_deleted_runtime_keeps_full_coverage(self):
        self.git("rm", "contents/ui/main.qml")
        self.commit()
        self.assertTrue(self.required())

    def test_pr_uses_tested_merge_tree(self):
        self.git("switch", "-c", "topic")
        self.write("README.md", "PR documentation\n")
        self.commit()
        self.git("switch", "main")
        self.write("contents/ui/main.qml", "independent base change\n")
        self.commit()
        self.git("-c", "commit.gpgsign=false", "merge", "--no-ff", "topic", "-m", "PR merge")
        self.assertFalse(self.required(event="pull_request", ref="refs/pull/1/merge"))

    def test_unknown_empty_or_missing_history_runs_graphics(self):
        self.assertTrue(self.required())
        self.assertTrue(self.required(before="0" * 40))
        self.assertTrue(self.required(before="f" * 40))
        self.assertTrue(self.required(before="--invalid-revision"))
        self.assertTrue(self.required(event="workflow_dispatch"))
        self.assertTrue(self.required(event="pull_request", ref="refs/pull/1/merge"))


if __name__ == "__main__":
    unittest.main()
