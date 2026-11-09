#!/usr/bin/env python3
"""Collect bounded CI measurements and publish a trusted sticky PR report."""

import argparse
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import stat
import urllib.error
import urllib.parse
import urllib.request
import zipfile
import zlib

MARKER = "<!-- codexbar-ci-report -->"
ARTIFACT = "ci-results"
RESULT_FILE = "ci-results.json"
MAX_RESULT = 128 * 1024
JOBS = ("scope", "lint", "check-runtime", "smoke-runtime", "check", "smoke")
SHA = re.compile(r"[0-9a-f]{40}")
DIGEST = re.compile(r"[0-9a-f]{64}")
CASE = re.compile(r"[a-zA-Z0-9][a-zA-Z0-9_-]{0,100}")
ARTIFACT_ERRORS = (ValueError, KeyError, zipfile.BadZipFile, RecursionError, zlib.error, OSError)


def exact(value, keys):
    if not isinstance(value, dict) or set(value) != set(keys):
        raise ValueError("Unexpected report fields")


def positive(value):
    if type(value) is not int or not 1 <= value <= 10**12:
        raise ValueError("Invalid positive identifier")
    return value


def json_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("Duplicate JSON field")
        value[key] = item
    return value


def validate(result):
    exact(result, ("schemaVersion", "runId", "runAttempt", "headSha", "testedSha",
                   "image", "fixture", "popup", "panelCases"))
    if type(result["schemaVersion"]) is not int or result["schemaVersion"] != 1:
        raise ValueError("Unsupported report schema")
    positive(result["runId"])
    positive(result["runAttempt"])
    for key in ("headSha", "testedSha"):
        if not isinstance(result[key], str) or not SHA.fullmatch(result[key]):
            raise ValueError("Invalid commit SHA")
    for key in ("image", "fixture"):
        if not isinstance(result[key], str) or not DIGEST.fullmatch(result[key]):
            raise ValueError("Invalid environment digest")
    cases = result["popup"]
    if cases is not None:
        if not isinstance(cases, list) or not 1 <= len(cases) <= 512:
            raise ValueError("Invalid popup results")
        seen = set()
        for case in cases:
            exact(case, ("scenario", "passed", "seconds"))
            name = case["scenario"]
            if not isinstance(name, str) or not CASE.fullmatch(name) or name in seen:
                raise ValueError("Invalid or duplicate scenario")
            seen.add(name)
            if type(case["passed"]) is not bool:
                raise ValueError("Invalid scenario outcome")
            seconds = case["seconds"]
            if type(seconds) not in (int, float) or not 0 <= seconds <= 3600 or not math.isfinite(seconds):
                raise ValueError("Invalid scenario duration")
    count = result["panelCases"]
    if count is not None and (type(count) is not int or not 0 <= count <= 10000):
        raise ValueError("Invalid panel count")
    return result


def load_json(path, limit=MAX_RESULT):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > limit:
        raise ValueError("Result must be a bounded regular file")
    return json.loads(path.read_text(encoding="utf-8"))


def collect(root, env):
    popup_path = root / "dist/smoke/ci/results.json"
    panel_path = root / "dist/smoke/panel-matrix/results.json"
    popup = load_json(popup_path) if popup_path.exists() else None
    if popup is not None:
        if not isinstance(popup, list) or len(popup) > 512:
            raise ValueError("Invalid popup result list")
        popup = [{key: case[key] for key in ("scenario", "passed", "seconds")} for case in popup]
    panels = load_json(panel_path, 16 * 1024 * 1024) if panel_path.exists() else None
    if panels is not None and (not isinstance(panels, list) or len(panels) > 10000):
        raise ValueError("Invalid panel result list")
    digest = hashlib.sha256()
    inputs = [root / "scripts/smoke_popup.py", root / "scripts/panel_matrix.py"]
    inputs += sorted(path for path in (root / "scripts/smoke").rglob("*")
                     if path.is_file() and "__pycache__" not in path.parts)
    for path in inputs:
        digest.update(path.relative_to(root).as_posix().encode() + b"\0" + path.read_bytes())
    return validate({"schemaVersion": 1, "runId": int(env["GITHUB_RUN_ID"]),
                     "runAttempt": int(env["GITHUB_RUN_ATTEMPT"]), "headSha": env["CI_REPORT_HEAD_SHA"],
                     "testedSha": env["GITHUB_SHA"], "image": env["CI_REPORT_IMAGE"],
                     "fixture": digest.hexdigest(), "popup": popup,
                     "panelCases": None if panels is None else len(panels)})


def read_archive(raw, run, expected_attempt=None):
    if len(raw) > MAX_RESULT:
        raise ValueError("Artifact archive exceeds its size limit")
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        entries = archive.infolist()
        if len(entries) != 1 or entries[0].filename != RESULT_FILE:
            raise ValueError("Unexpected artifact entries")
        entry = entries[0]
        mode = entry.external_attr >> 16
        if (entry.file_size > MAX_RESULT or stat.S_ISLNK(mode) or entry.is_dir()
                or entry.flag_bits & 1 or entry.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)):
            raise ValueError("Invalid result entry")
        result = validate(json.loads(archive.read(entry), object_pairs_hook=json_object))
    if ((result["runId"], result["headSha"]) != (run["id"], run["head_sha"])
            or not 1 <= result["runAttempt"] <= run["run_attempt"]
            or expected_attempt is not None and result["runAttempt"] != expected_attempt):
        raise ValueError("Artifact does not belong to this run attempt and head")
    return result


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class GitHub:
    def __init__(self, repo, read_token, write_token):
        if not re.fullmatch(r"[\w.-]+/[\w.-]+", repo, re.ASCII):
            raise ValueError("Invalid repository")
        self.repo = repo
        self.read_token, self.write_token = read_token, write_token

    def api(self, path, body=None, method=None):
        token = self.write_token if body is not None else self.read_token
        headers = {"Authorization": "Bearer " + token, "Accept": "application/vnd.github+json",
                   "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "codexbar-ci-report"}
        if body is not None:
            headers["Content-Type"] = "application/json"
        raw = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request("https://api.github.com/repos/" + self.repo + "/" + path,
                                     data=raw, headers=headers, method=method)
        with urllib.request.build_opener(NoRedirect).open(req, timeout=30) as response:
            data = response.read(4 * 1024 * 1024 + 1)
        if len(data) > 4 * 1024 * 1024:
            raise ValueError("GitHub response exceeds its size limit")
        return json.loads(data)

    def pages(self, path, key=None):
        for page in range(1, 101):
            data = self.api(path + ("&" if "?" in path else "?") + f"per_page=100&page={page}")
            entries = data if key is None else data[key]
            yield from entries
            if len(entries) < 100:
                return
        raise ValueError("GitHub pagination limit reached")

    def artifact(self, run, expected_attempt=None):
        artifacts = sorted(self.pages(f"actions/runs/{run['id']}/artifacts", "artifacts"),
                           key=lambda item: item["id"], reverse=True)
        artifact = next((item for item in artifacts if item["name"] == ARTIFACT and not item["expired"]), None)
        if artifact is None:
            return None
        if artifact["size_in_bytes"] > MAX_RESULT:
            raise ValueError("Artifact exceeds its size limit")
        req = urllib.request.Request(
            f"https://api.github.com/repos/{self.repo}/actions/artifacts/{positive(artifact['id'])}/zip",
            headers={"Authorization": "Bearer " + self.read_token, "User-Agent": "codexbar-ci-report"})
        try:
            urllib.request.build_opener(NoRedirect).open(req, timeout=30)
        except urllib.error.HTTPError as error:
            if error.code != 302:
                raise
            url = error.headers["Location"]
        else:
            raise ValueError("Expected signed artifact download redirect")
        target = urllib.parse.urlsplit(url)
        if target.scheme != "https" or not target.hostname or not target.hostname.endswith(
                (".blob.core.windows.net", ".githubusercontent.com")):
            raise ValueError("Unexpected artifact download host")
        # The signed storage request must never receive the GitHub token.
        with urllib.request.build_opener(NoRedirect).open(url, timeout=30) as response:
            raw = response.read(MAX_RESULT + 1)
        return read_archive(raw, run, expected_attempt)


def comparable(current, baseline):
    return bool(current and baseline and current["popup"] is not None and baseline["popup"] is not None
                and all(current[key] == baseline[key] for key in ("schemaVersion", "image", "fixture"))
                and {case["scenario"] for case in current["popup"]}
                == {case["scenario"] for case in baseline["popup"]})


def render(repo, run, jobs, result, baseline=None, baseline_run=None, rejected=False):
    url = f"https://github.com/{repo}/actions/runs/{run['id']}/attempts/{run['run_attempt']}"
    statuses = {job["name"]: job["conclusion"] for job in jobs if job["name"] in JOBS}
    allowed = {"success", "failure", "cancelled", "skipped", "timed_out", "action_required", "neutral"}
    lines = [MARKER, f"<!-- ci-report-run:{run['id']}:{run['run_attempt']} -->", "## CI report", "",
             f"Commit `{run['head_sha'][:12]}` · [CI run]({url}) · {run['conclusion']}", "",
             "| Check | Result |", "| --- | --- |"]
    for name in JOBS:
        status = statuses.get(name)
        lines.append(f"| `{name}` | {status if status in allowed else 'missing'} |")
    if all(statuses.get(key) == "success" for key in ("scope", "lint", "check", "smoke")) and all(
            statuses.get(key) == "skipped" for key in ("check-runtime", "smoke-runtime")):
        lines += ["", "Runtime checks were intentionally omitted by the editorial-only scope gates."]
    if result is None:
        lines += ["", "Measurement artifact unavailable or rejected by validation." if rejected else
                  "No measurement artifact was produced; check the job results above."]
    else:
        popup = result["popup"]
        lines += ["", "### Runtime measurements", ""]
        if result["runAttempt"] != run["run_attempt"]:
            lines += [f"Measurements retained from CI attempt {result['runAttempt']}; the smoke job was not rerun.", ""]
        if popup is None:
            lines.append("Popup scenario measurements are unavailable.")
        else:
            failures = sorted(case["scenario"] for case in popup if not case["passed"])
            lines.append(f"Popup scenarios: **{len(popup) - len(failures)}/{len(popup)} passed**.")
            if failures:
                lines.append("Failed scenarios: " + ", ".join(f"`{name}`" for name in failures) + ".")
        count = result["panelCases"]
        lines.append("Panel cases recorded: " + (str(count) if count is not None else "unavailable") + ".")
        if comparable(result, baseline):
            old = {case["scenario"]: case for case in baseline["popup"]}
            regressions = sorted(case["scenario"] for case in popup if not case["passed"] and old[case["scenario"]]["passed"])
            lines += ["", "New popup failures versus baseline: " +
                      (", ".join(f"`{name}`" for name in regressions) if regressions else "none") + ".",
                      "", "<details><summary>Scenario timings</summary>", "",
                      "| Scenario | Baseline | This PR | Change |", "| --- | ---: | ---: | ---: |"]
            for case in sorted(popup, key=lambda item: item["scenario"]):
                seconds, previous = case["seconds"], old[case["scenario"]]["seconds"]
                lines.append(f"| `{case['scenario']}` | {previous:.3f}s | {seconds:.3f}s | {seconds - previous:+.3f}s |")
            lines += ["", "</details>"]
        else:
            lines += ["", "No comparable baseline: measurements or scenario/environment fingerprints differ or are unavailable."]
        lines += ["", f"Reported tested tree: `{result['testedSha'][:12]}`.",
                  "Scenario durations include harness setup and process startup; they are not Plasmoid update latency."]
    if baseline_run:
        lines += ["", f"Baseline: [`{baseline_run['head_sha'][:12]}`](https://github.com/{repo}/actions/runs/{baseline_run['id']})",
                  "Exact PR base commit." if baseline_run.get("exact_base") else
                  "Latest successful base-branch run with measurements; the exact PR base has no available measurements."]
    lines += ["", "[Popup and panel artifacts](" + url + "#artifacts)", "",
              "Results are reported by trusted code; PR artifacts are data, never executed. "
              "Existing required CI checks remain the merge gates. Screenshots require human visual review."]
    body = "\n".join(lines)
    if len(body.encode()) > 60000:
        raise ValueError("Rendered report exceeds the comment size limit")
    return body


def current_run(api, run, pr):
    fresh = api.api(f"pulls/{pr['number']}")
    if fresh["state"] != "open" or fresh["head"]["sha"] != run["head_sha"]:
        return False
    current = api.api(f"actions/runs/{run['id']}")
    if current["run_attempt"] != run["run_attempt"] or current["status"] != "completed":
        return False
    recent = api.api(f"actions/workflows/{run['workflow_id']}/runs?event=pull_request&head_sha={run['head_sha']}&per_page=100")
    return not any(item["run_number"] > run["run_number"] for item in recent["workflow_runs"])


def latest_jobs(jobs, attempt):
    latest = {}
    for job in sorted(jobs, key=lambda item: (item["run_attempt"], item["id"])):
        if job["name"] in JOBS and 1 <= job["run_attempt"] <= attempt:
            latest[job["name"]] = job
    return list(latest.values())


def source_run(api, run_id):
    run = api.api(f"actions/runs/{positive(run_id)}")
    workflow = api.api("actions/workflows/ci.yml")
    if run["workflow_id"] != workflow["id"] or run["event"] != "pull_request":
        raise ValueError("Source must be a pull-request CI run")
    if not SHA.fullmatch(run["head_sha"]):
        raise ValueError("Invalid source head SHA")
    return run


def source_key(run):
    source = f"{positive(run['head_repository']['id'])}:{run['head_branch']}"
    return hashlib.sha256(source.encode()).hexdigest()


def publish(api, run_id, expected_login, expected_attempt=None):
    if not re.fullmatch(r"[a-zA-Z0-9-]+\[bot\]", expected_login):
        raise ValueError("Invalid bot login")
    run = source_run(api, run_id)
    if (run["status"] != "completed"
            or expected_attempt is not None and run["run_attempt"] != positive(expected_attempt)):
        print("Skipping incomplete or superseded CI attempt.")
        return None
    pulls = list(api.pages(f"commits/{run['head_sha']}/pulls"))
    candidates = [pr for pr in pulls if pr["state"] == "open" and pr["head"]["sha"] == run["head_sha"]
                  and pr["base"]["repo"]["full_name"] == api.repo
                  and pr["head"]["repo"] and run["head_repository"]
                  and pr["head"]["repo"]["id"] == run["head_repository"]["id"]
                  and pr["head"]["ref"] == run["head_branch"]]
    if len(candidates) != 1 or not current_run(api, run, candidates[0]):
        print("Skipping stale, closed, or ambiguous PR result.")
        return None
    pr = candidates[0]
    jobs = latest_jobs(api.pages(f"actions/runs/{run_id}/jobs?filter=all", "jobs"), run["run_attempt"])
    smoke_attempt = next((job["run_attempt"] for job in jobs if job["name"] == "smoke-runtime"), None)
    rejected = False
    try:
        result = api.artifact(run, expected_attempt=smoke_attempt)
    except ARTIFACT_ERRORS:
        result, rejected = None, True
    baseline, baseline_run = None, None
    branch = urllib.parse.quote(pr["base"]["ref"], safe="")
    recent = api.api(f"actions/workflows/{run['workflow_id']}/runs?event=push&branch={branch}&status=success&per_page=20")["workflow_runs"]
    exact_runs = api.api(f"actions/workflows/{run['workflow_id']}/runs?event=push&branch={branch}&status=success&head_sha={pr['base']['sha']}&per_page=20")["workflow_runs"]
    for candidate in (exact_runs + [item for item in recent if item["head_sha"] != pr["base"]["sha"]])[:20]:
        try:
            baseline = api.artifact(candidate)
        except ARTIFACT_ERRORS:
            continue
        if baseline:
            baseline_run = dict(candidate, exact_base=candidate["head_sha"] == pr["base"]["sha"])
            break
    body = render(api.repo, run, jobs, result, baseline, baseline_run, rejected)
    comments = list(api.pages(f"issues/{pr['number']}/comments"))
    existing = next((comment for comment in comments if comment["user"]["login"] == expected_login
                     and comment["user"]["type"] == "Bot" and MARKER in (comment.get("body") or "")), None)
    if not current_run(api, run, pr):
        print("Skipping result superseded while preparing the report.")
        return None
    if existing and existing["body"] == body:
        return existing["html_url"]
    response = api.api(f"issues/comments/{existing['id']}" if existing else f"issues/{pr['number']}/comments",
                       {"body": body}, method="PATCH" if existing else "POST")
    if response["user"]["login"] != expected_login or response["user"]["type"] != "Bot":
        raise ValueError("Unexpected published comment author")
    return response["html_url"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("collect", "source", "publish"))
    args = parser.parse_args()
    if args.command == "collect":
        root = Path(__file__).resolve().parents[1]
        result = collect(root, os.environ)
        path = root / "dist" / RESULT_FILE
        path.parent.mkdir(exist_ok=True)
        path.write_text(json.dumps(result, allow_nan=False) + "\n")
        if path.stat().st_size > MAX_RESULT:
            raise ValueError("Report exceeds its size limit")
    else:
        event = load_json(Path(os.environ["GITHUB_EVENT_PATH"]), 1024 * 1024)
        if os.environ["GITHUB_EVENT_NAME"] == "workflow_run":
            run_id = event["workflow_run"]["id"]
            expected_attempt = event["workflow_run"]["run_attempt"]
        else:
            run_id = int(event["inputs"]["run_id"])
            expected_attempt = None
        api = GitHub(os.environ["GITHUB_REPOSITORY"], os.environ["GH_TOKEN"], os.environ.get("CI_REPORT_TOKEN", ""))
        if args.command == "source":
            with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
                output.write("group=" + source_key(source_run(api, run_id)) + "\n")
        else:
            url = publish(api, run_id, os.environ["CI_REPORT_BOT_LOGIN"], expected_attempt)
            print(url or "No comment needed.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, urllib.error.URLError) as error:
        # Never log request headers, signed download URLs, or artifact contents.
        raise SystemExit(f"CI report failed: {type(error).__name__}") from None
