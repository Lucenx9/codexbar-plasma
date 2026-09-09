"""Select graphical smoke coverage and validate its required CI result."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[1]
EDITORIAL_FILES = {
    "AGENTS.md", "CLAUDE.md", "README.md", "TODO.md", "CHANGELOG.md", "NOTICE.md",
    ".github/copilot-instructions.md", ".github/pull_request_template.md",
}


def docs_only(paths):
    return bool(paths) and all(
        path in EDITORIAL_FILES
        or (path.startswith("docs/") and path.endswith(".md")
            and "\n" not in path and "\r" not in path)
        for path in paths
    )


def select_smoke(event_name, ref, event, root=ROOT):
    """Unknown events, missing history, and empty diffs keep full coverage."""
    if ref.startswith("refs/tags/"):
        return True, "Release tags always run graphical smoke tests."
    try:
        if event_name == "pull_request":
            # Compare the tested merge tree with its base parent, not just the
            # last contributor commit. Renames must retain both changed paths.
            parents = subprocess.check_output(
                ["git", "rev-list", "--parents", "-n", "1", "HEAD"], cwd=root,
                text=True, stderr=subprocess.DEVNULL,
            ).split()
            if len(parents) != 3:
                return True, "PR merge history unavailable; running smoke tests."
            base = parents[1]
        elif event_name == "push" and ref == "refs/heads/main":
            base = event.get("before", "")
        else:
            return True, "Event requires full smoke coverage."
        if not isinstance(base, str) or not re.fullmatch(r"[0-9a-f]{40}", base) or base == "0" * 40:
            return True, "Comparison base unavailable; running smoke tests."
        changed = subprocess.check_output(
            ["git", "diff", "--name-only", "--no-renames", "-z", base, "HEAD", "--"],
            cwd=root, stderr=subprocess.DEVNULL,
        )
        paths = [os.fsdecode(path) for path in changed.split(b"\0") if path]
    except (OSError, subprocess.CalledProcessError):
        return True, "Change detection failed; running smoke tests."
    if docs_only(paths):
        return False, "Only editorial Markdown changed; graphical smoke tests are not needed."
    return True, "Changes require graphical smoke tests."


def smoke_result(scope_result, required, runtime_result):
    if scope_result == "success" and required == "false" and runtime_result == "skipped":
        return "Graphical smoke tests intentionally omitted for editorial Markdown only."
    if scope_result == "success" and required == "true" and runtime_result == "success":
        return "Graphical smoke tests passed."
    raise ValueError("Smoke coverage is unresolved or failed; inspect scope and smoke-runtime jobs.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gate", action="store_true")
    args = parser.parse_args()
    if args.gate:
        try:
            message = smoke_result(os.environ.get("SCOPE_RESULT"), os.environ.get("RUN_SMOKE"),
                                   os.environ.get("RUNTIME_RESULT"))
        except ValueError as error:
            parser.exit(1, f"{error}\n")
    else:
        try:
            event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
            if not isinstance(event, dict):
                raise ValueError("event must be an object")
            required, message = select_smoke(os.environ["GITHUB_EVENT_NAME"],
                                             os.environ["GITHUB_REF"], event)
        except (OSError, ValueError, KeyError):
            required, message = True, "Event data unavailable; running smoke tests."
        with open(os.environ["GITHUB_OUTPUT"], "a") as output:
            output.write(f"run_smoke={str(required).lower()}\n")
    print(message)
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
        summary.write(message + "\n")


if __name__ == "__main__":
    main()
