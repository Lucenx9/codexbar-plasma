"""Validate the repository changelog and extract one release's notes."""

import argparse
from datetime import date
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
VERSION = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
RELEASE = re.compile(rf"({VERSION}) - ([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})")
CATEGORIES = {"Added", "Changed", "Deprecated", "Removed", "Fixed", "Security"}


def validate(text, version, tag=None):
    """Return the tagged release body, or validate without preparing a release."""
    if not isinstance(version, str) or not re.fullmatch(VERSION, version):
        raise ValueError("metadata must contain a version in X.Y.Z format")
    headings = list(re.finditer(r"^## (.+)$", text, re.MULTILINE))
    if not headings or headings[0].group(1) != "Unreleased":
        raise ValueError("the first section must be '## Unreleased'")
    sections = {}
    previous_version = None
    previous_date = None
    for index, heading in enumerate(headings):
        title = heading.group(1)
        if index == 0:
            key = "Unreleased"
        else:
            match = RELEASE.fullmatch(title)
            if not match:
                raise ValueError(f"invalid release heading: {title}")
            key, released_on = match.groups()
            released_on = date.fromisoformat(released_on)
            number = tuple(map(int, key.split(".")))
            if previous_version is not None and number >= previous_version:
                raise ValueError("release versions must be unique and newest first")
            if previous_date is not None and released_on > previous_date:
                raise ValueError("release dates must be newest first")
            previous_version, previous_date = number, released_on
        end = headings[index + 1].start() if index + 1 < len(headings) else len(text)
        body = text[heading.end():end].strip()
        categories = list(re.finditer(r"^### (.+)$", body, re.MULTILINE))
        seen = set()
        for category_index, category in enumerate(categories):
            name = category.group(1)
            if name not in CATEGORIES or name in seen:
                raise ValueError(f"unknown or duplicate category in {key}: {name}")
            seen.add(name)
            category_end = (categories[category_index + 1].start()
                            if category_index + 1 < len(categories) else len(body))
            if not re.search(r"^- \S", body[category.end():category_end], re.MULTILINE):
                raise ValueError(f"empty category in {key}: {name}")
        if (key != "Unreleased" or body) and not categories:
            raise ValueError(f"{key} needs categorized change entries")
        sections[key] = body
    if len(sections) < 2 or list(sections)[1] != version:
        raise ValueError("the newest changelog release must match metadata version")
    if tag is not None:
        if tag != f"v{version}":
            raise ValueError("release tag must match metadata and changelog version")
        if sections["Unreleased"]:
            raise ValueError("move Unreleased entries into the release before tagging")
        return sections[version] + "\n"
    return ""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--changelog", type=Path, default=ROOT / "CHANGELOG.md")
    parser.add_argument("--metadata", type=Path, default=ROOT / "metadata.json")
    parser.add_argument("--tag", help="validate release readiness and print its notes")
    args = parser.parse_args()
    try:
        metadata = json.loads(args.metadata.read_text(encoding="utf-8"))
        notes = validate(args.changelog.read_text(encoding="utf-8"),
                         metadata["KPlugin"]["Version"], args.tag)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"changelog: {error}\n")
    if args.tag is not None:
        print(notes, end="")
    else:
        print("Changelog checks passed.")


if __name__ == "__main__":
    main()
