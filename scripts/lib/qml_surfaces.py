#!/usr/bin/env python3
"""Single source of truth for which files make up each QML surface.

The static checks in `scripts/` assert that lifecycle, security, and UI rules are
present in the widget sources. Historically each check hardcoded
`contents/ui/main.qml`, so moving a rule into a component or JS helper broke
`make check` for reasons that had nothing to do with behavior, and the only fix
was to edit the assertion in the same commit as the move. That makes the safety
net useless exactly when it matters most.

A *surface* is one scope that owns its own process lifecycle and state: the
plasmoid runtime, or one config page. Assertions run against every file in the
surface, so extracting a helper out of `main.qml` into `contents/ui/` or
`contents/ui/components/` keeps the check green without editing the check.

Some globs point at directories that do not exist yet. That is deliberate: it is
where a planned extraction lands, and an empty glob costs nothing.

Usage from bash (see `qml_surfaces.sh`):

    python3 scripts/lib/qml_surfaces.py files applet

Usage from a python heredoc:

    sys.path.insert(0, str(root / "scripts/lib"))
    from qml_surfaces import Surface
    applet = Surface("applet", root)
    applet.require("function connectUsageCommand(", "usage lifecycle")
"""

from __future__ import annotations

import sys
from pathlib import Path

# Surface -> repo-relative glob patterns, in the order they are concatenated.
SURFACES: dict[str, tuple[str, ...]] = {
    # The plasmoid runtime: panel, popup, and every helper they pull in.
    "applet": (
        "contents/ui/main.qml",
        "contents/ui/*.js",
        "contents/ui/components/*.qml",
        # Planned home for extracted process/command controllers.
        "contents/ui/controllers/*.qml",
        "contents/ui/controllers/*.js",
    ),
    "providers": (
        "contents/ui/configProviders.qml",
        # Planned home for the extracted provider-config backend and descriptor code.
        "contents/ui/config/*.qml",
        "contents/ui/config/*.js",
    ),
    "display": ("contents/ui/configDisplay.qml",),
    "debug": ("contents/ui/configDebug.qml",),
    "general": ("contents/ui/configGeneral.qml",),
    "advanced": ("contents/ui/configAdvanced.qml",),
    # Everything qmllint, the hardening check, and gettext extraction must see.
    "all": (
        "contents/config/config.qml",
        "contents/ui/main.qml",
        "contents/ui/config*.qml",
        "contents/ui/*.js",
        "contents/ui/components/*.qml",
        "contents/ui/controllers/*.qml",
        "contents/ui/controllers/*.js",
        "contents/ui/config/*.qml",
        "contents/ui/config/*.js",
    ),
}


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent.parent


def surface_files(name: str, root: Path | None = None) -> list[Path]:
    """Existing files in `name`, deduplicated, in manifest then sorted order."""
    if name not in SURFACES:
        raise KeyError(f"unknown QML surface: {name} (have: {', '.join(sorted(SURFACES))})")
    root = root or repo_root()
    seen: dict[Path, None] = {}
    for pattern in SURFACES[name]:
        if any(char in pattern for char in "*?["):
            matches = sorted(root.glob(pattern))
        else:
            candidate = root / pattern
            matches = [candidate] if candidate.exists() else []
        for match in matches:
            seen.setdefault(match, None)
    files = list(seen)
    if not files:
        raise AssertionError(f"QML surface {name} resolved to no files")
    return files


class Surface:
    """One lifecycle scope's sources, searchable as a unit."""

    def __init__(self, name: str, root: Path | None = None) -> None:
        self.name = name
        self.root = root or repo_root()
        self.files = surface_files(name, self.root)
        self.texts = {path: path.read_text(encoding="utf-8") for path in self.files}

    def rel(self, path: Path) -> str:
        return str(path.relative_to(self.root))

    @property
    def text(self) -> str:
        """All sources concatenated.

        Fragment checks (`fragment in surface.text`) stay correct across a file
        split. Do not use this for offset arithmetic that assumes a single file;
        use `function_body` or `id_block` instead.
        """
        return "\n".join(self.texts[path] for path in self.files)

    def contains(self, fragment: str) -> bool:
        return any(fragment in text for text in self.texts.values())

    def files_containing(self, fragment: str) -> list[str]:
        return [self.rel(path) for path, text in self.texts.items() if fragment in text]

    def require(self, fragment: str, reason: str) -> None:
        if not self.contains(fragment):
            raise AssertionError(f"{reason}: missing from surface {self.name}: {fragment}")

    def reject(self, fragment: str, reason: str) -> None:
        hits = self.files_containing(fragment)
        if hits:
            raise AssertionError(f"{reason}: unexpected in {', '.join(hits)}: {fragment}")

    def _locate(self, marker: str) -> tuple[Path, str, int]:
        hits = [
            (path, text, text.find(marker))
            for path, text in self.texts.items()
            if marker in text
        ]
        if not hits:
            raise AssertionError(f"missing {marker!r} in surface {self.name}")
        if len(hits) > 1:
            names = ", ".join(self.rel(path) for path, _, _ in hits)
            raise AssertionError(
                f"{marker!r} is ambiguous in surface {self.name} ({names}); "
                "assert against the owning file directly"
            )
        return hits[0]

    @staticmethod
    def _match_braces(text: str, open_brace: int) -> str:
        """Body between `open_brace` and its matching `}`.

        Braces inside strings and comments are not excluded, matching the
        assumption these checks have always made about these sources.
        """
        depth = 1
        index = open_brace + 1
        while index < len(text) and depth > 0:
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
            index += 1
        if depth != 0:
            raise AssertionError("unterminated block")
        return text[open_brace + 1 : index - 1]

    def function_body(self, name: str) -> str:
        marker = f"function {name}("
        _, text, start = self._locate(marker)
        return self._match_braces(text, text.index("{", start))

    def id_block(self, object_id: str) -> str:
        """Body of the QML object declaring `object_id`.

        Walks back to the enclosing `{` instead of scanning forward to the next
        sibling declaration, so the body stays correct when the object moves to
        another file or a different indentation level.
        """
        _, text, marker_at = self._locate(f"id: {object_id}")
        depth = 0
        index = marker_at
        while index > 0:
            index -= 1
            char = text[index]
            if char == "}":
                depth += 1
            elif char == "{":
                if depth == 0:
                    break
                depth -= 1
        else:
            raise AssertionError(f"no enclosing object for id {object_id}")
        return self._match_braces(text, index)


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] not in {"files", "surfaces"}:
        print("usage: qml_surfaces.py files <surface> | qml_surfaces.py surfaces", file=sys.stderr)
        return 2
    if argv[1] == "surfaces":
        print("\n".join(sorted(SURFACES)))
        return 0
    if len(argv) != 3:
        print("usage: qml_surfaces.py files <surface>", file=sys.stderr)
        return 2
    for path in surface_files(argv[2]):
        print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
