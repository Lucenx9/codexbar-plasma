#!/usr/bin/env python3
"""Collect bounded CI measurements and publish a trusted sticky PR report."""

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import urllib.parse

from lib.ci_report_data import (ARTIFACT_ERRORS, JOBS, MARKER, MAX_RESULT, RESULT_FILE,
                                SHA, collect, load_json, positive, require)
from lib.ci_report_github import GitHub
from lib.ci_report_markdown import Report


def current_run(api, run, pr):
    fresh = api.api(f"pulls/{pr['number']}")
    if (fresh["state"], fresh["head"]["sha"]) != ("open", run["head_sha"]):
        return False
    current = api.api(f"actions/runs/{run['id']}")
    if (current["run_attempt"], current["status"]) != (run["run_attempt"], "completed"):
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
    require((run["workflow_id"], run["event"]) == (workflow["id"], "pull_request"),
            "Source must be a pull-request CI run")
    require(SHA.fullmatch(run["head_sha"]), "Invalid source head SHA")
    return run


def source_key(run):
    source = f"{positive(run['head_repository']['id'])}:{run['head_branch']}"
    return hashlib.sha256(source.encode()).hexdigest()


def matching_pr(repo, run, pr):
    if pr["state"] != "open":
        return False
    if not pr["head"]["repo"] or not run["head_repository"]:
        return False
    actual = (pr["head"]["sha"], pr["base"]["repo"]["full_name"],
              pr["head"]["repo"]["id"], pr["head"]["ref"])
    expected = (run["head_sha"], repo, run["head_repository"]["id"], run["head_branch"])
    return actual == expected


def associated_pr(api, run):
    candidates = [pr for pr in api.pages(f"commits/{run['head_sha']}/pulls") if matching_pr(api.repo, run, pr)]
    if len(candidates) != 1:
        return None
    return candidates[0]


def attempt_current(run, expected_attempt):
    if run["status"] != "completed":
        return False
    if expected_attempt is None:
        return True
    return run["run_attempt"] == positive(expected_attempt)


def bot_author(comment, login):
    return (comment["user"]["login"], comment["user"]["type"]) == (login, "Bot")


def report_comment(comment, login):
    return bot_author(comment, login) and MARKER in (comment.get("body") or "")


@dataclass
class Publisher:
    api: GitHub
    run: dict
    pr: dict
    login: str

    def measurements(self, jobs):
        smoke_attempt = next((job["run_attempt"] for job in jobs if job["name"] == "smoke-runtime"), None)
        try:
            return self.api.artifact(self.run, expected_attempt=smoke_attempt), False
        except ARTIFACT_ERRORS:
            return None, True

    def baseline_candidates(self):
        branch = urllib.parse.quote(self.pr["base"]["ref"], safe="")
        query = f"actions/workflows/{self.run['workflow_id']}/runs?event=push&branch={branch}&status=success"
        recent = self.api.api(query + "&per_page=20")["workflow_runs"]
        exact = self.api.api(query + f"&head_sha={self.pr['base']['sha']}&per_page=20")["workflow_runs"]
        return (exact + [run for run in recent if run["head_sha"] != self.pr["base"]["sha"]])[:20]

    def baseline(self):
        for candidate in self.baseline_candidates():
            try:
                result = self.api.artifact(candidate)
            except ARTIFACT_ERRORS:
                continue
            if result:
                return result, dict(candidate, exact_base=candidate["head_sha"] == self.pr["base"]["sha"])
        return None, None

    def existing_comment(self):
        comments = self.api.pages(f"issues/{self.pr['number']}/comments")
        return next((comment for comment in comments if report_comment(comment, self.login)), None)

    def write_comment(self, body):
        existing = self.existing_comment()
        if not current_run(self.api, self.run, self.pr):
            print("Skipping result superseded while preparing the report.")
            return None
        if existing and existing["body"] == body:
            return existing["html_url"]
        path = f"issues/comments/{existing['id']}" if existing else f"issues/{self.pr['number']}/comments"
        response = self.api.api(path, {"body": body}, method="PATCH" if existing else "POST")
        require(bot_author(response, self.login), "Unexpected published comment author")
        return response["html_url"]

    def publish(self):
        jobs = latest_jobs(self.api.pages(f"actions/runs/{self.run['id']}/jobs?filter=all", "jobs"),
                           self.run["run_attempt"])
        result, rejected = self.measurements(jobs)
        baseline, baseline_run = self.baseline()
        body = Report(self.api.repo, self.run, jobs, result, baseline=baseline,
                      baseline_run=baseline_run, rejected=rejected).render()
        return self.write_comment(body)


def publish(api, run_id, expected_login, expected_attempt=None):
    require(re.fullmatch(r"[a-zA-Z0-9-]+\[bot\]", expected_login), "Invalid bot login")
    run = source_run(api, run_id)
    if not attempt_current(run, expected_attempt):
        print("Skipping incomplete or superseded CI attempt.")
        return None
    pr = associated_pr(api, run)
    if pr is None or not current_run(api, run, pr):
        print("Skipping stale, closed, or ambiguous PR result.")
        return None
    return Publisher(api, run, pr, expected_login).publish()


def collect_command():
    root = Path(__file__).resolve().parents[1]
    result = collect(root, os.environ)
    path = root / "dist" / RESULT_FILE
    path.parent.mkdir(exist_ok=True)
    path.write_text(json.dumps(result, allow_nan=False) + "\n")
    require(path.stat().st_size <= MAX_RESULT, "Report exceeds its size limit")


def event_context():
    event = load_json(Path(os.environ["GITHUB_EVENT_PATH"]), 1024 * 1024)
    if os.environ["GITHUB_EVENT_NAME"] == "workflow_run":
        run_id, expected_attempt = event["workflow_run"]["id"], event["workflow_run"]["run_attempt"]
    else:
        run_id, expected_attempt = int(event["inputs"]["run_id"]), None
    api = GitHub(os.environ["GITHUB_REPOSITORY"], os.environ["GH_TOKEN"], os.environ.get("CI_REPORT_TOKEN", ""))
    return api, run_id, expected_attempt


def source_command():
    api, run_id, _ = event_context()
    with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
        output.write("group=" + source_key(source_run(api, run_id)) + "\n")


def publish_command():
    api, run_id, expected_attempt = event_context()
    url = publish(api, run_id, os.environ["CI_REPORT_BOT_LOGIN"], expected_attempt)
    print(url or "No comment needed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = {"collect": collect_command, "source": source_command, "publish": publish_command}
    parser.add_argument("command", choices=commands)
    commands[parser.parse_args().command]()


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError) as error:
        # Never log request headers, signed download URLs, or artifact contents.
        raise SystemExit(f"CI report failed: {type(error).__name__}") from None
