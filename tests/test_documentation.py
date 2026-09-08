"""Keep maintained docs indexed and temporary work artifacts out of docs/."""

from pathlib import Path
import re
import unittest
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"


def local_links(document):
    # Check inline Markdown links, including images, but not example code.
    text = re.sub(r"(?ms)^```.*?^```[^\n]*", "", document.read_text())
    for target in re.findall(r"\]\(([^\s)]+)(?:\s+\"[^\"]*\")?\)", text):
        url = urlsplit(target.strip("<>"))
        if not url.scheme and not url.netloc and url.path:
            yield (document.parent / unquote(url.path)).resolve()


class DocumentationTests(unittest.TestCase):
    def test_todo_remains_a_work_tracker_entrypoint(self):
        todo = (ROOT / "TODO.md").read_text()
        self.assertLessEqual(
            len(todo.encode("utf-8")), 2048,
            "Keep TODO.md within 2 KiB; work status belongs in GitHub Issues.",
        )
        self.assertIn("https://github.com/Lucenx9/codexbar-plasma/issues", todo)
        self.assertNotRegex(todo, r"(?m)^\s*[-*]\s+\[[ xX]\]", "Keep task checkboxes in issues.")

    def test_root_agent_instructions_fit_repository_budget(self):
        self.assertLessEqual(
            (ROOT / "AGENTS.md").stat().st_size, 16 * 1024,
            "Keep AGENTS.md within 16 KiB; move task-specific detail behind conditional document links.",
        )

    def test_every_documentation_file_is_indexed(self):
        index = DOCS / "README.md"
        indexed = {path for path in local_links(index) if path.is_relative_to(DOCS)}
        actual = {path.resolve() for path in DOCS.rglob("*") if path.is_file()}
        self.assertEqual(
            actual, indexed | {index},
            "List maintained docs and images in docs/README.md; put temporary artifacts in dist/review/.",
        )

    def test_retired_artifact_directories_stay_out_of_docs(self):
        for name in ("review", "reviews", "settings", "superpowers"):
            with self.subTest(directory=name):
                self.assertFalse(
                    (DOCS / name).exists(),
                    "Use dist/review/ or the OS temp directory for work artifacts.",
                )

    def test_local_markdown_links_resolve(self):
        documents = sorted(ROOT.glob("*.md")) + sorted(DOCS.rglob("*.md"))
        documents += sorted((ROOT / ".github").rglob("*.md"))
        for document in documents:
            for target in local_links(document):
                with self.subTest(document=str(document.relative_to(ROOT)), target=str(target)):
                    self.assertTrue(target.is_relative_to(ROOT), "Local links must stay inside the repository.")
                    self.assertTrue(target.exists(), "Update or remove the broken local Markdown link.")


if __name__ == "__main__":
    unittest.main()
