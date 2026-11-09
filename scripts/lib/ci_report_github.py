"""Separate read/write credentials and bounded GitHub artifact transport."""

import json
import re
import urllib.error
import urllib.parse
import urllib.request

from lib.ci_report_data import ARTIFACT, MAX_RESULT, positive, read_archive, require


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        """Refuse every redirect, regardless of the urllib callback arguments."""
        return None


def storage_url(url):
    target = urllib.parse.urlsplit(url)
    require(target.scheme == "https", "Artifact storage must use HTTPS")
    require(target.hostname, "Missing artifact download host")
    require(target.hostname.endswith((".blob.core.windows.net", ".githubusercontent.com")),
            "Unexpected artifact download host")
    return url


def available_artifact(item):
    return (item["name"], item["expired"]) == (ARTIFACT, False)


class GitHub:
    def __init__(self, repo, read_token, write_token):
        require(re.fullmatch(r"[\w.-]+/[\w.-]+", repo, re.ASCII), "Invalid repository")
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
        require(len(data) <= 4 * 1024 * 1024, "GitHub response exceeds its size limit")
        return json.loads(data)

    def pages(self, path, key=None):
        for page in range(1, 101):
            data = self.api(path + ("&" if "?" in path else "?") + f"per_page=100&page={page}")
            entries = data if key is None else data[key]
            yield from entries
            if len(entries) < 100:
                return
        raise ValueError("GitHub pagination limit reached")

    def artifact_info(self, run):
        artifacts = sorted(self.pages(f"actions/runs/{run['id']}/artifacts", "artifacts"),
                           key=lambda item: item["id"], reverse=True)
        artifact = next((item for item in artifacts if available_artifact(item)), None)
        if artifact is not None:
            require(artifact["size_in_bytes"] <= MAX_RESULT, "Artifact exceeds its size limit")
        return artifact

    def artifact_url(self, artifact):
        req = urllib.request.Request(
            f"https://api.github.com/repos/{self.repo}/actions/artifacts/{positive(artifact['id'])}/zip",
            headers={"Authorization": "Bearer " + self.read_token, "User-Agent": "codexbar-ci-report"})
        try:
            urllib.request.build_opener(NoRedirect).open(req, timeout=30)
        except urllib.error.HTTPError as error:
            if error.code != 302:
                raise
            return storage_url(error.headers["Location"])
        raise ValueError("Expected signed artifact download redirect")

    def artifact(self, run, expected_attempt=None):
        artifact = self.artifact_info(run)
        if artifact is None:
            return None
        # The signed storage request must never receive the GitHub token.
        with urllib.request.build_opener(NoRedirect).open(self.artifact_url(artifact), timeout=30) as response:
            raw = response.read(MAX_RESULT + 1)
        return read_archive(raw, run, expected_attempt)
