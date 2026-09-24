"""Ask a System One model whether a change completes a tracked TODO entry."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import urllib.error
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
ENDPOINT = "https://openrouter.ai/api/alpha/decisions"
MODEL = "~typesafe/jev-latest"
API_KEY_ENV = "OPENROUTER_API_KEY"
# The verdict is one float plus usage; anything larger is not an answer.
MAX_RESPONSE_BYTES = 65536
GIT_TIMEOUT = 120
# Jev accepts 32k tokens. Cap both inputs well below that and mark truncation,
# so a dropped hunk or entry is never read as absent.
DIFF_LIMIT = 60000
TODO_LIMIT = 40000
# Replaying 17 recent commits scored every change that left TODO.md alone at or
# below 0.36, and every change that completed a listed entry at or above 0.86.
THRESHOLD = 0.6
QUESTION = {
    "type": "noul",
    "instructions": (
        "`todo` is the current TODO.md of a KDE Plasma widget, tracking remaining "
        "Linux/Plasma parity work and its official CLI blockers. Completed work must be "
        "removed there in the change that implements it. Compare `diff` against the "
        "unchecked entries in `todo` and decide whether this change delivers one of "
        "them. Judge the change itself, even when `diff` already edits TODO.md."
    ),
    "criteria": {
        "true": "The change delivers, supersedes, or narrows the scope of a specific "
                "unchecked entry listed in `todo`.",
        "false": "No unchecked entry in `todo` describes this change. Ordinary fixes, "
                 "refactors, tests, tooling, and documentation that no listed entry "
                 "covers belong here.",
    },
}


def probability(value, label):
    """Return a finite probability in [0, 1]. NaN and infinity compare false."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{label} must be a number")
    if not 0.0 <= value <= 1.0:
        raise ValueError(f"{label} must be between 0 and 1")
    return float(value)


def threshold_argument(text):
    """Parse --threshold, rejecting junk and values outside [0, 1]."""
    try:
        return probability(float(text), "--threshold")
    except ValueError as error:
        raise argparse.ArgumentTypeError(str(error)) from error


def build_request(paths, diff, todo):
    """Build the Decisions payload; truncation is stated, never silent."""
    body = diff[:DIFF_LIMIT]
    entries = todo[:TODO_LIMIT]
    return {
        "model": MODEL,
        "state": {
            "changed_files": sorted(paths),
            "diff": body,
            "diff_truncated": len(body) < len(diff),
            "todo": entries,
            "todo_truncated": len(entries) < len(todo),
        },
        "questions": {"todo": QUESTION},
    }


def verdict(answers, paths, threshold=THRESHOLD):
    """Return the probability when TODO.md is owed but untouched, else None."""
    answer = answers.get("todo") if isinstance(answers, dict) else None
    if not isinstance(answer, dict):
        raise ValueError("missing or malformed answer for todo")
    score = probability(answer.get("noul"), "the todo answer")
    if "TODO.md" in paths or score < threshold:
        return None
    return score


def read_change(base, root=ROOT):
    """Return the committed paths, diff, and TODO.md for this branch."""
    def git(*args):
        return subprocess.check_output(["git", *args], cwd=root, text=True,
                                       stderr=subprocess.DEVNULL,
                                       timeout=GIT_TIMEOUT)

    paths = [path for path in git("diff", "--merge-base", base, "HEAD",
                                  "--name-only").splitlines() if path]
    # Read TODO.md at HEAD, not from the working tree: an uncommitted edit would
    # otherwise change the model input without changing the committed diff.
    try:
        todo = git("show", "HEAD:TODO.md")
    except subprocess.CalledProcessError:
        todo = ""
    return paths, git("diff", "--merge-base", base, "HEAD"), todo


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """A redirect could carry the Authorization header to another host."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def ask(request, key):
    """Post the Decisions request and return its answers and usage."""
    call = urllib.request.Request(
        ENDPOINT, data=json.dumps(request).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    opener = urllib.request.build_opener(NoRedirect)
    with opener.open(call, timeout=120) as response:
        raw = response.read(MAX_RESPONSE_BYTES + 1)
    if len(raw) > MAX_RESPONSE_BYTES:
        raise ValueError("the Decisions response exceeded the supported size")
    payload = json.loads(raw)
    if not isinstance(payload, dict) or not isinstance(payload.get("answers"), dict):
        raise ValueError("the Decisions response carried no answers")
    usage = payload.get("usage")
    return payload["answers"], usage if isinstance(usage, dict) else {}


def usage_line(usage):
    """Describe reported usage without trusting its types."""
    tokens = usage.get("input_tokens")
    cost = usage.get("cost")
    counted = tokens if isinstance(tokens, int) and not isinstance(tokens, bool) else "?"
    priced = (f"${cost:.6f}" if isinstance(cost, (int, float))
              and not isinstance(cost, bool) else "cost unknown")
    return f"({counted} input tokens, {priced})"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="main", help="branch this change merges into")
    parser.add_argument("--threshold", type=threshold_argument, default=THRESHOLD,
                        help="probability at or above which TODO.md is owed")
    options = parser.parse_args(argv)

    key = os.environ.get(API_KEY_ENV, "")
    if not key:
        # Name the variable literally. Interpolating API_KEY_ENV trips CodeQL's
        # clear-text-logging heuristic, which matches the constant's name.
        print("OPENROUTER_API_KEY is not set; skipping the TODO gate")
        return 0
    try:
        paths, diff, todo = read_change(options.base)
    except (OSError, subprocess.SubprocessError):
        print(f"cannot diff against {options.base}; skipping the TODO gate")
        return 0
    if not paths:
        print(f"no committed changes against {options.base}")
        return 0
    if not todo.strip():
        print("TODO.md is empty or missing; skipping the TODO gate")
        return 0
    try:
        answers, usage = ask(build_request(paths, diff, todo), key)
        probability = verdict(answers, paths, options.threshold)
    except (urllib.error.URLError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"TODO gate unavailable: {error}", file=sys.stderr)
        return 2
    print(usage_line(usage), file=sys.stderr)
    if probability is None:
        print("no TODO.md reconciliation appears outstanding")
        return 0
    print(f"todo: {probability:.2f} - this change looks like it completes a TODO.md "
          f"entry it does not remove")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
