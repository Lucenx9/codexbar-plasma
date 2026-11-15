"""Keep maintained docs indexed and temporary work artifacts out of docs/."""

from pathlib import Path
import re
from tempfile import TemporaryDirectory
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


def documentation_inventory(directory):
    root = directory.resolve()
    pending = {root / "README.md"}
    visited = set()
    indexed = set(pending)
    while pending:
        index = pending.pop()
        visited.add(index)
        links = {path for path in local_links(index) if path.is_relative_to(root)}
        indexed.update(links)
        pending.update(path for path in links if path.name == "README.md" and path not in visited)
    return indexed


class DocumentationTests(unittest.TestCase):
    def test_root_agent_instructions_fit_repository_budget(self):
        self.assertLessEqual(
            (ROOT / "AGENTS.md").stat().st_size, 16 * 1024,
            "Keep AGENTS.md within 16 KiB; move task-specific detail behind conditional document links.",
        )

    def test_every_documentation_file_is_indexed(self):
        actual = {path.resolve() for path in DOCS.rglob("*") if path.is_file()}
        self.assertEqual(
            actual, documentation_inventory(DOCS),
            "List maintained docs and images in the linked README indexes; put temporary artifacts in dist/review/.",
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


class DocumentationInventoryTests(unittest.TestCase):
    def test_linked_nested_index_covers_documents_and_images(self):
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "research").mkdir()
            (root / "README.md").write_text("[Evidence](research/README.md)")
            (root / "research/README.md").write_text("[Contract](contract.md)\n![Fixture](fixture.png)")
            (root / "research/contract.md").touch()
            (root / "research/fixture.png").touch()
            self.assertEqual(documentation_inventory(root), {
                root / "README.md", root / "research/README.md",
                root / "research/contract.md", root / "research/fixture.png",
            })

    def test_cycles_terminate_and_outside_links_are_excluded(self):
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "research").mkdir()
            (root / "README.md").write_text("[Evidence](research/README.md)\n[Policy](../AGENTS.md)")
            (root / "research/README.md").write_text("[Index](../README.md)\n[Web](https://example.com)")
            self.assertEqual(documentation_inventory(root), {
                root / "README.md", root / "research/README.md",
            })

    def test_unlinked_indexes_and_leaf_links_do_not_cover_files(self):
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "orphan").mkdir()
            (root / "README.md").write_text("[Guide](guide.md)")
            (root / "guide.md").write_text("![Capture](capture.png)")
            (root / "capture.png").touch()
            (root / "orphan/README.md").write_text("[Report](report.md)")
            (root / "orphan/report.md").touch()
            self.assertEqual(documentation_inventory(root), {root / "README.md", root / "guide.md"})


if __name__ == "__main__":
    unittest.main()
