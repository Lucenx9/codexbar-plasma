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

import re
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
    "general": (
        "contents/ui/configGeneral.qml",
        "contents/ui/general/*.js",
    ),
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
        "contents/ui/general/*.js",
        # Preview-only capture code is linted, but never packaged with the applet.
        "scripts/smoke/*.qml",
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

    def require_definition_where_used(
        self, name: str, body_fragment: str | None = None
    ) -> None:
        """Every file that calls helper `name` must also declare it.

        QML and JS files share no function scope, so `function hasOwnKey(...)` is
        a per-file contract, not a surface-wide one: a plain `require` is
        satisfied by any sibling that happens to declare the same helper, so
        deleting the copy that live callers depend on would go unnoticed.

        A file needs the declaration when it calls the helper unqualified.
        Components reach the applet root through their `applet` property
        (`applet.contrastTextColor(...)`), so such a call obliges the surface
        root instead. Calls qualified by a JS import namespace resolve to that
        module and oblige nobody here.

        `body_fragment` is required inside every declaration found, which is how
        a guard such as `Object.prototype.hasOwnProperty.call` stays enforced on
        each copy rather than on whichever one a search happens to reach first.
        """
        declaration = re.compile(rf"function\s+{re.escape(name)}\s*\(")
        unqualified_call = re.compile(rf"(?<![\w.$]){re.escape(name)}\s*\(")
        applet_call = re.compile(rf"\bapplet\.{re.escape(name)}\s*\(")

        owed: dict[str, str] = {}
        declared: list[Path] = []
        for path, text in self.texts.items():
            if declaration.search(text) is not None:
                declared.append(path)
                continue
            # Declarations are stripped first so `function foo(` never reads as a call.
            if unqualified_call.search(declaration.sub("", text)):
                owed[self.rel(path)] = "calls it unqualified"

        surface_root = self.files[0]
        reached_through_applet = [
            self.rel(path) for path, text in self.texts.items() if applet_call.search(text)
        ]
        if reached_through_applet and declaration.search(self.texts[surface_root]) is None:
            owed[self.rel(surface_root)] = (
                f"is the surface root reached by applet.{name}(...) in "
                f"{', '.join(sorted(reached_through_applet))}"
            )

        if owed:
            declares_in = ", ".join(self.rel(path) for path in declared) or "(nowhere)"
            detail = "; ".join(f"{path} {why}" for path, why in sorted(owed.items()))
            raise AssertionError(
                f"{name} must be declared where it is used: {detail}. "
                f"Surface {self.name} declares it in {declares_in}"
            )
        if not declared:
            raise AssertionError(
                f"surface {self.name} declares no {name}, so nothing enforces it"
            )
        if body_fragment is None:
            return
        for path in declared:
            text = self.texts[path]
            start = declaration.search(text).start()
            if body_fragment not in self._match_braces(text, text.index("{", start)):
                raise AssertionError(
                    f"{self.rel(path)}: {name} must keep its guard: {body_fragment}"
                )

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

    def handler_body(self, name: str) -> str:
        """Body of the unique braced QML signal handler named `name`."""
        marker = f"{name}: {{"
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


USAGE = (
    "usage: qml_surfaces.py files <surface>\n"
    "       qml_surfaces.py surfaces\n"
    "       qml_surfaces.py definition <surface> <function> [body-fragment]"
)


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] not in {"files", "surfaces", "definition"}:
        print(USAGE, file=sys.stderr)
        return 2
    if argv[1] == "surfaces":
        print("\n".join(sorted(SURFACES)))
        return 0
    if argv[1] == "definition":
        if len(argv) not in {4, 5}:
            print(USAGE, file=sys.stderr)
            return 2
        try:
            Surface(argv[2]).require_definition_where_used(
                argv[3], argv[4] if len(argv) == 5 else None
            )
        except AssertionError as error:
            print(error, file=sys.stderr)
            return 1
        return 0
    if len(argv) != 3:
        print(USAGE, file=sys.stderr)
        return 2
    for path in surface_files(argv[2]):
        print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
