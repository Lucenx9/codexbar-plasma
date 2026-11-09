"""CI reports accept bounded data and update only the current PR's bot comment."""

from copy import deepcopy
import io
import json
from pathlib import Path
import re
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch
import urllib.error
import zipfile
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import ci_report as report
from lib import ci_report_data as schema
from lib.ci_report_github import GitHub
from lib.ci_report_markdown import Report

BOT = "codexbar-review-bot[bot]"
REPO = "example/widget"
HEAD = "a" * 40
BASE = "b" * 40
RUN = {"id": 42, "run_attempt": 2, "head_sha": HEAD, "head_branch": "feature",
       "head_repository": {"id": 7}, "workflow_id": 9, "event": "pull_request",
       "status": "completed", "conclusion": "success", "run_number": 100}
PR = {"number": 12, "state": "open", "head": {"sha": HEAD, "ref": "feature", "repo": {"id": 7}},
      "base": {"sha": BASE, "ref": "main", "repo": {"full_name": REPO}}}


def result():
    return {"schemaVersion": 2, "runId": 42, "runAttempt": 2, "headSha": HEAD,
            "baseRef": "main", "baseSha": BASE,
            "testedSha": "c" * 40, "image": "d" * 64, "fixture": "e" * 64,
            "popup": [{"scenario": "popup-basic", "passed": True, "seconds": 1.5}], "panelCases": 24}


def archive(data, name=schema.RESULT_FILE, extra=False, mode=None):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as bundle:
        entry = zipfile.ZipInfo(name)
        if mode is not None:
            entry.external_attr = mode << 16
        bundle.writestr(entry, json.dumps(data))
        if extra:
            bundle.writestr("unexpected.py", "raise RuntimeError('never execute')")
    return output.getvalue()


class FakeGitHub:
    repo = REPO

    def __init__(self):
        self.run = deepcopy(RUN)
        self.pr = deepcopy(PR)
        self.pulls = [self.pr]
        self.latest = [self.run]
        self.jobs = [{"name": name, "conclusion": "success", "id": index, "run_attempt": 2}
                     for index, name in enumerate(schema.JOBS, 1)]
        self.comments = []
        self.writes = []
        self.measurements = result()
        self.baseline = None
        self.baseline_runs = []
        self.exact_runs = []
        self.before_comments = None
        self.requested_attempts = []

    def api(self, path, body=None, method=None):
        if body is not None:
            self.writes.append((path, method, body))
            return {"user": {"login": BOT, "type": "Bot"}, "html_url": "https://example.test/comment"}
        if path == "actions/workflows/ci.yml":
            return {"id": 9}
        if re.fullmatch(r"actions/runs/\d+", path):
            return next(run for run in [self.run] + self.latest if run["id"] == int(path.split("/")[-1]))
        if path == "pulls/12":
            return self.pr
        if "event=pull_request" in path:
            return {"workflow_runs": self.latest}
        if "event=push" in path:
            return {"workflow_runs": self.exact_runs if "head_sha=" in path else self.baseline_runs}
        raise AssertionError(path)

    def pages(self, path, key=None):
        if path == "pulls?state=open":
            return deepcopy(self.pulls)
        if key == "workflow_runs" and "event=pull_request" in path:
            return self.latest
        if re.fullmatch(r"actions/runs/\d+/jobs\?filter=all", path) and key == "jobs":
            return self.jobs
        if path == "issues/12/comments":
            if self.before_comments:
                self.before_comments()
            return self.comments
        raise AssertionError(path)

    def artifact(self, run, expected_attempt=None):
        self.requested_attempts.append(expected_attempt)
        source_ids = {item["id"] for item in [self.run] + self.latest}
        value = self.measurements if run["id"] in source_ids else self.baseline
        if isinstance(value, Exception):
            raise value
        return value


class ArtifactTests(unittest.TestCase):
    def test_concurrency_is_scoped_to_source_for_automatic_and_manual_reports(self):
        workflow = (Path(__file__).resolve().parents[1] / ".github/workflows/ci-report.yml").read_text()
        self.assertIn("group: ci-report-${{ needs.source.outputs.group }}", workflow)
        self.assertIn("python3 scripts/ci_report.py source", workflow)
        source = report.source_key(RUN)
        self.assertEqual(source, report.source_key(dict(RUN, id=99, head_sha=BASE, run_attempt=3)))
        self.assertNotEqual(source, report.source_key(dict(RUN, head_branch="another-pr")))
        self.assertNotEqual(source, report.source_key(dict(RUN, head_repository={"id": 8})))
        self.assertRegex(source, r"^[0-9a-f]{64}$")

    def test_report_image_matches_both_runtime_containers(self):
        workflow = (Path(__file__).resolve().parents[1] / ".github/workflows/ci.yml").read_text()
        images = re.findall(r"image: ghcr.io/lucenx9/codexbar-plasma-ci-runtime@sha256:([0-9a-f]{64})", workflow)
        fingerprint = re.search(r"CI_REPORT_IMAGE: ([0-9a-f]{64})", workflow)[1]
        self.assertEqual(images, [fingerprint, fingerprint])

    def test_valid_archive_and_exact_run_attempt(self):
        self.assertEqual(schema.read_archive(archive(result()), RUN), result())
        for key, value in (("runId", 43), ("runAttempt", 3), ("headSha", BASE)):
            data = result()
            data[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                schema.read_archive(archive(data), RUN)

    def test_retained_artifact_must_match_the_latest_smoke_job_attempt(self):
        retained = dict(result(), runAttempt=1)
        self.assertEqual(schema.read_archive(archive(retained), RUN, expected_attempt=1), retained)
        with self.assertRaises(ValueError):
            schema.read_archive(archive(retained), RUN, expected_attempt=2)
        self.assertEqual(schema.read_archive(archive(retained), RUN), retained)

    def test_scope_identity_record_does_not_claim_a_smoke_attempt(self):
        record = dict(result(), runAttempt=1, popup=None, panelCases=None)
        self.assertEqual(schema.read_archive(archive(record), RUN, expected_attempt=2), record)

    def test_push_records_have_no_pr_target_and_partial_targets_are_rejected(self):
        self.assertEqual(schema.validate(dict(result(), baseRef=None, baseSha=None))["baseRef"], None)
        for change in ({"baseRef": None}, {"baseSha": None}):
            with self.assertRaises(ValueError):
                schema.validate(dict(result(), **change))

    def test_strict_schema_types_bounds_and_text(self):
        bad = [("schemaVersion", True), ("schemaVersion", 1), ("runId", True), ("runAttempt", 0),
               ("headSha", "x" * 40), ("testedSha", ""), ("image", "unverified"),
               ("baseRef", "bad\nbranch"), ("baseSha", "invalid"),
               ("fixture", 123), ("panelCases", True), ("panelCases", -1),
               ("panelCases", 10001), ("popup", []), ("popup", "success")]
        for key, value in bad:
            data = result()
            data[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                schema.validate(data)
        for change in ({"scenario": "[click](https://evil.test)"}, {"scenario": "a\nb"},
                       {"passed": "true"}, {"seconds": True}, {"seconds": float("nan")},
                       {"seconds": float("inf")}, {"seconds": -1}, {"seconds": 3601},
                       {"seconds": 10**1000}, {"error": "unexpected raw log"}):
            data = result()
            data["popup"][0].update(change)
            with self.subTest(change=change), self.assertRaises(ValueError):
                schema.validate(data)
        for mutate in (lambda data: data.update(extra=True), lambda data: data.pop("fixture"),
                       lambda data: data["popup"].append(data["popup"][0])):
            data = result()
            mutate(data)
            with self.assertRaises(ValueError):
                schema.validate(data)

    def test_missing_measurements_are_valid(self):
        data = result()
        data.update(popup=None, panelCases=None)
        self.assertEqual(schema.validate(data), data)

    def test_rejects_paths_symlinks_extra_entries_and_oversized_json(self):
        for raw in (archive(result(), "../ci-results.json"), archive(result(), extra=True),
                    archive(result(), mode=stat.S_IFLNK | 0o777),
                    archive("x" * schema.MAX_RESULT), b"x" * (schema.MAX_RESULT + 1)):
            with self.subTest(size=len(raw)), self.assertRaises(ValueError):
                schema.read_archive(raw, RUN)

    def test_rejects_duplicate_json_fields_and_unexpected_compression(self):
        for compression, text in ((zipfile.ZIP_STORED, json.dumps(result()).replace(
                '"schemaVersion": 2', '"schemaVersion": 1, "schemaVersion": 2')),
                                  (zipfile.ZIP_LZMA, json.dumps(result()))):
            raw = io.BytesIO()
            with zipfile.ZipFile(raw, "w", compression) as bundle:
                bundle.writestr(schema.RESULT_FILE, text)
            with self.assertRaises(ValueError):
                schema.read_archive(raw.getvalue(), RUN)

    def test_collects_failures_without_error_text_and_partial_panel_count(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts/smoke").mkdir(parents=True)
            (root / ".github/workflows").mkdir(parents=True)
            for path in ("scripts/smoke_popup.py", "scripts/panel_matrix.py", "scripts/smoke/fixture.qml",
                         "Makefile", ".github/workflows/ci.yml"):
                (root / path).write_text("fixture")
            env = {"GITHUB_RUN_ID": "42", "GITHUB_RUN_ATTEMPT": "2", "GITHUB_SHA": "c" * 40,
                   "CI_REPORT_HEAD_SHA": HEAD, "CI_REPORT_IMAGE": "d" * 64,
                   "GITHUB_BASE_REF": "main", "CI_REPORT_BASE_SHA": BASE}
            empty = schema.collect(root, env)
            self.assertIsNone(empty["popup"])
            self.assertIsNone(empty["panelCases"])
            for folder in ("ci", "panel-matrix"):
                (root / "dist/smoke" / folder).mkdir(parents=True)
            (root / "dist/smoke/ci/results.json").write_text(json.dumps([
                {"scenario": "popup-basic", "passed": False, "seconds": 0.5, "error": "raw diagnostic"}]))
            (root / "dist/smoke/panel-matrix/results.json").write_text('[{"partial": true}]')
            data = schema.collect(root, env)
            self.assertEqual(data["panelCases"], 1)
            self.assertFalse(data["popup"][0]["passed"])
            self.assertNotIn("raw diagnostic", json.dumps(data))
            self.assertEqual(data["fixture"], empty["fixture"])
            self.assertEqual((data["baseRef"], data["baseSha"]), ("main", BASE))
            for source in ("Makefile", ".github/workflows/ci.yml"):
                path = root / source
                original = path.read_text()
                path.write_text(original + " --renderer opengl --theme dark")
                self.assertNotEqual(report.collect(root, env)["fixture"], data["fixture"])
                path.write_text(original)
            (root / "scripts/smoke/fixture.qml").write_text("changed fixture")
            self.assertNotEqual(schema.collect(root, env)["fixture"], data["fixture"])


class RenderTests(unittest.TestCase):
    def test_identity_only_record_does_not_claim_retained_runtime_measurements(self):
        record = dict(result(), runAttempt=1, popup=None, panelCases=None)
        body = Report(REPO, RUN, [], record).render()
        self.assertIn("No runtime measurements", body)
        self.assertNotIn("the smoke job was not rerun", body)
        self.assertNotIn("### Runtime measurements", body)
    def test_large_valid_measurements_keep_job_conclusions_and_artifact_link(self):
        current = result()
        current["popup"] = [{"scenario": f"case-{index:03d}-" + "x" * 92, "passed": False, "seconds": 1.5}
                            for index in range(512)]
        baseline = deepcopy(current)
        for case in baseline["popup"]:
            case["passed"] = True
        schema.validate(current)
        self.assertLess(len(json.dumps(current).encode()), schema.MAX_RESULT)
        jobs = [{"name": "smoke", "conclusion": "failure"}]
        body = Report(REPO, RUN, jobs, current, baseline=baseline).render()
        self.assertLessEqual(len(body.encode()), 60000)
        self.assertIn("| `smoke` | failure |", body)
        self.assertIn("Scenario details were omitted", body)
        self.assertIn("#artifacts", body)

    def test_reports_real_statuses_and_measurements_without_inventing_metrics(self):
        api = FakeGitHub()
        api.jobs[0]["conclusion"] = "failure"
        api.measurements["popup"][0]["passed"] = False
        body = Report(REPO, RUN, api.jobs, api.measurements).render()
        self.assertIn("| `scope` | failure |", body)
        self.assertIn("**0/1 passed**", body)
        self.assertIn("Failed scenarios: `popup-basic`.", body)
        self.assertIn("Panel cases recorded: 24.", body)
        self.assertIn("not Plasmoid update latency", body)
        self.assertNotIn("coverage:", body)
        self.assertIn("No comparable baseline", body)

    def test_compares_matching_fixtures_and_records_new_failures(self):
        current, baseline = result(), result()
        current["popup"][0].update(passed=False, seconds=2.0)
        body = Report(REPO, RUN, [], current, baseline, dict(RUN, id=40, head_sha=BASE)).render()
        self.assertIn("New popup failures versus baseline: `popup-basic`", body)
        self.assertIn("| 1.500s | 2.000s | +0.500s |", body)
        self.assertIn("Latest successful base-branch", body)

    def test_does_not_compare_different_images_fixtures_or_scenarios(self):
        current = result()
        for key, value in (("image", "f" * 64), ("fixture", "f" * 64), ("popup", None),
                           ("popup", [{"scenario": "another", "passed": True, "seconds": 1}])):
            baseline = result()
            baseline[key] = value
            with self.subTest(key=key):
                self.assertFalse(schema.comparable(current, baseline))
                self.assertNotIn("<summary>Scenario timings", Report(REPO, RUN, [], current, baseline).render())

    def test_missing_or_rejected_data_is_explicit(self):
        self.assertIn("No measurement artifact", Report(REPO, RUN, [], None).render())
        self.assertIn("artifact unavailable or rejected", Report(REPO, RUN, [], None, rejected=True).render())
        self.assertIn("| `smoke` | missing |", Report(REPO, RUN, [], None).render())

    def test_editorial_omissions_require_successful_gates(self):
        jobs = [{"name": name, "conclusion": "skipped" if name.endswith("-runtime") else "success"}
                for name in schema.JOBS]
        self.assertIn("intentionally omitted", Report(REPO, RUN, jobs, None).render())
        jobs[0]["conclusion"] = "failure"
        self.assertNotIn("intentionally omitted", Report(REPO, RUN, jobs, None).render())


class PublishTests(unittest.TestCase):
    def test_creates_one_bot_comment_and_ignores_spoofed_markers(self):
        api = FakeGitHub()
        api.comments = [{"id": 1, "user": {"login": "contributor", "type": "User"}, "body": schema.MARKER},
                        {"id": 2, "user": {"login": "other[bot]", "type": "Bot"}, "body": schema.MARKER}]
        self.assertEqual(report.publish(api, 42, BOT), "https://example.test/comment")
        self.assertEqual(len(api.writes), 1)
        self.assertEqual(api.writes[0][:2], ("issues/12/comments", "POST"))
        self.assertIn(schema.MARKER, api.writes[0][2]["body"])

    def test_updates_existing_comment_and_skips_unchanged_body(self):
        api = FakeGitHub()
        api.comments = [{"id": 3, "user": {"login": BOT, "type": "Bot"}, "body": schema.MARKER,
                         "html_url": "https://example.test/comment"}]
        report.publish(api, 42, BOT)
        self.assertEqual(api.writes[0][:2], ("issues/comments/3", "PATCH"))
        api.comments[0]["body"] = api.writes[0][2]["body"]
        api.writes.clear()
        report.publish(api, 42, BOT)
        self.assertEqual(api.writes, [])

    def test_rejects_wrong_workflow_event_and_incomplete_runs(self):
        for key, value in (("workflow_id", 10), ("event", "push")):
            api = FakeGitHub()
            api.run[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                report.publish(api, 42, BOT)
            self.assertFalse(api.writes)

    def test_incomplete_attempt_skips_and_old_event_reconciles_to_completed_attempt(self):
        api = FakeGitHub()
        api.run["status"] = "in_progress"
        self.assertIsNone(report.publish(api, 42, BOT, expected_attempt=2))
        self.assertFalse(api.writes)
        api.run["status"] = "completed"
        self.assertIsNotNone(report.publish(api, 42, BOT, expected_attempt=1))
        self.assertIn("ci-report-run:42:2", api.writes[0][2]["body"])

    def test_stale_queued_request_reports_the_latest_head_instead_of_losing_it(self):
        api = FakeGitHub()
        new_head = "f" * 40
        api.pr["head"]["sha"] = new_head
        api.latest.append(dict(RUN, id=43, head_sha=new_head, run_number=101, run_attempt=1))
        api.measurements.update(runId=43, headSha=new_head, runAttempt=1)
        for job in api.jobs:
            job["run_attempt"] = 1
        self.assertIsNotNone(report.publish(api, 42, BOT, expected_attempt=2))
        self.assertIn("ci-report-run:43:1", api.writes[0][2]["body"])
        self.assertIn(f"Commit `{new_head[:12]}`", api.writes[0][2]["body"])

    def test_newer_completed_run_for_same_head_is_reconciled(self):
        api = FakeGitHub()
        api.latest.append(dict(RUN, id=43, run_number=101))
        api.measurements["runId"] = 43
        self.assertIsNotNone(report.publish(api, 42, BOT))
        self.assertIn("ci-report-run:43:2", api.writes[0][2]["body"])

    def test_other_branches_and_forks_with_same_sha_cannot_suppress_this_report(self):
        for change in ({"head_branch": "another"}, {"head_repository": {"id": 8}}):
            api = FakeGitHub()
            api.latest.append(dict(RUN, id=43, run_number=101, **change))
            self.assertIsNotNone(report.publish(api, 42, BOT))
            self.assertIn("ci-report-run:42:2", api.writes[0][2]["body"])

    def test_retargeted_pr_rejects_old_artifact_even_if_run_pr_metadata_updates(self):
        for change in ({"ref": "release"}, {"sha": "f" * 40}):
            api = FakeGitHub()
            api.pr["base"].update(change)
            api.run["pull_requests"] = [deepcopy(api.pr)]
            self.assertIsNone(report.publish(api, 42, BOT))
            self.assertFalse(api.writes)

    def test_retargeting_while_rendering_is_rechecked_before_publication(self):
        api = FakeGitHub()
        api.before_comments = lambda: api.pr["base"].update(ref="release")
        self.assertIsNone(report.publish(api, 42, BOT))
        self.assertFalse(api.writes)

    def test_unavailable_target_provenance_is_labeled_without_hiding_job_status(self):
        api = FakeGitHub()
        api.measurements = None
        report.publish(api, 42, BOT)
        body = api.writes[0][2]["body"]
        self.assertIn("Tested target unverified", body)
        self.assertIn("| `smoke` | success |", body)

    def test_baseline_listing_failures_do_not_hide_job_conclusions(self):
        for exact in (True, False):
            for error in (ValueError("response exceeds limit"),
                          urllib.error.HTTPError("https://api.github.com", 503, "unavailable", {}, None)):
                api = FakeGitHub()
                original_api = api.api
                def fail_listing(path, body=None, method=None):
                    if "event=push" in path and ("head_sha=" in path) == exact:
                        raise error
                    return original_api(path, body, method)
                api.api = fail_listing
                self.assertIsNotNone(report.publish(api, 42, BOT))
                self.assertIn("| `smoke` | success |", api.writes[0][2]["body"])

    def test_identity_only_base_artifacts_do_not_hide_a_measured_baseline(self):
        api = FakeGitHub()
        api.exact_runs = [dict(RUN, id=40, head_sha=BASE)]
        api.baseline_runs = [dict(RUN, id=39, head_sha="f" * 40)]
        identity_only = dict(result(), popup=None, panelCases=None)
        with patch.object(api, "artifact", side_effect=[result(), identity_only, result()]):
            report.publish(api, 42, BOT)
        self.assertIn("/actions/runs/39", api.writes[0][2]["body"])
        self.assertIn("<summary>Scenario timings", api.writes[0][2]["body"])

    def test_partial_rerun_uses_latest_job_per_name_and_retains_earlier_smoke(self):
        api = FakeGitHub()
        smoke = next(job for job in api.jobs if job["name"] == "smoke-runtime")
        smoke["run_attempt"] = 1
        api.jobs += [{"id": 0, "name": "lint", "run_attempt": 1, "conclusion": "failure"}]
        api.measurements["runAttempt"] = 1
        report.publish(api, 42, BOT, expected_attempt=2)
        body = api.writes[0][2]["body"]
        self.assertIn("| `lint` | success |", body)
        self.assertIn("Measurements retained from CI attempt 1", body)
        self.assertIn("**1/1 passed**", body)
        self.assertEqual(api.requested_attempts, [1])

    def test_hostile_json_and_deflate_become_rejected_measurements(self):
        hostile = []
        for text, compression in (("[" * 100000, zipfile.ZIP_DEFLATED),
                                  (json.dumps(result()), zipfile.ZIP_DEFLATED)):
            output = io.BytesIO()
            with zipfile.ZipFile(output, "w", compression) as bundle:
                bundle.writestr(schema.RESULT_FILE, text)
            hostile.append(output.getvalue())
        corrupt = bytearray(hostile[1])
        corrupt[30 + len(schema.RESULT_FILE)] = 0x07  # Reserved deflate block type.
        hostile[1] = bytes(corrupt)
        for raw, error in zip(hostile, (RecursionError, zlib.error)):
            with self.assertRaises(error):
                schema.read_archive(raw, RUN)
            api = FakeGitHub()
            with patch.object(api, "artifact", side_effect=lambda run, expected_attempt=None:
                              schema.read_archive(raw, run, expected_attempt)):
                report.publish(api, 42, BOT)
            self.assertIn("artifact unavailable or rejected", api.writes[0][2]["body"])

    def test_expired_artifacts_do_not_abort_job_status_or_baseline_fallback(self):
        for code in (404, 410):
            api = FakeGitHub()
            error = urllib.error.HTTPError("https://api.github.com", code, "unavailable", {}, None)
            api.baseline_runs = [dict(RUN, id=40, head_sha=BASE), dict(RUN, id=39, head_sha="f" * 40)]
            api.exact_runs = [api.baseline_runs[0]]
            with patch.object(api, "artifact", side_effect=[error, error, result()]):
                report.publish(api, 42, BOT)
            body = api.writes[0][2]["body"]
            self.assertIn("artifact unavailable or rejected", body)
            self.assertIn("| `smoke` | success |", body)
            self.assertIn("/actions/runs/39", body)

    def test_skips_stale_closed_fork_mismatched_or_ambiguous_prs(self):
        for mutate in (lambda api: api.pr["head"].update(sha=BASE),
                       lambda api: api.pr.update(state="closed"),
                       lambda api: api.pr["head"]["repo"].update(id=8),
                       lambda api: api.pr["base"]["repo"].update(full_name="other/repo"),
                       lambda api: api.pr["head"].update(ref="other"),
                       lambda api: api.pulls.append(deepcopy(api.pr))):
            api = FakeGitHub()
            mutate(api)
            self.assertIsNone(report.publish(api, 42, BOT))
            self.assertFalse(api.writes)

    def test_rechecks_head_attempt_and_newer_run_before_writing(self):
        for mutate in (lambda api: api.pr["head"].update(sha=BASE),
                       lambda api: api.run.update(run_attempt=3),
                       lambda api: api.latest.append(dict(RUN, id=43, run_number=101))):
            api = FakeGitHub()
            # API responses are snapshots, as in the real HTTP client.
            original_api = api.api
            api.api = lambda *args, **kwargs: deepcopy(original_api(*args, **kwargs))
            api.before_comments = lambda: mutate(api)
            self.assertIsNone(report.publish(api, 42, BOT))
            self.assertFalse(api.writes)

    def test_failed_runs_and_invalid_artifacts_still_report_authoritative_jobs(self):
        for measurements in (None, ValueError("invalid untrusted data"), zipfile.BadZipFile("invalid")):
            api = FakeGitHub()
            api.measurements = measurements
            api.run["conclusion"] = "failure"
            api.jobs[-1]["conclusion"] = "failure"
            report.publish(api, 42, BOT)
            body = api.writes[0][2]["body"]
            self.assertIn("| `smoke` | failure |", body)
            self.assertNotIn("Runtime measurements", body)

    def test_prefers_exact_base_run_and_falls_back_to_latest_successful_base(self):
        for exact in (True, False):
            api = FakeGitHub()
            baseline_run = dict(RUN, id=40, head_sha=BASE if exact else "f" * 40)
            api.baseline_runs = [dict(RUN, id=41, head_sha="f" * 40)]
            api.exact_runs = [baseline_run] if exact else []
            api.baseline = result()
            report.publish(api, 42, BOT)
            body = api.writes[0][2]["body"]
            self.assertIn("<summary>Scenario timings", body)
            self.assertIn(f"`{baseline_run['head_sha'][:12]}`", body)
            self.assertIn("Exact PR base commit." if exact else "Latest successful base-branch", body)


class TransportTests(unittest.TestCase):
    def test_download_never_sends_the_github_token_to_signed_storage(self):
        api = GitHub(REPO, "read-test-token", "write-test-token")
        requests = []
        storage = "https://production.blob.core.windows.net/artifact?signature=test"

        def open_request(req, timeout):
            requests.append(req)
            if isinstance(req, str):
                return io.BytesIO(archive(result()))
            raise urllib.error.HTTPError(req.full_url, 302, "redirect", {"Location": storage}, None)

        with patch.object(api, "pages", return_value=[{"id": 1, "name": schema.ARTIFACT,
                                                       "expired": False, "size_in_bytes": 1000}]), \
                patch("lib.ci_report_github.urllib.request.build_opener") as opener:
            opener.return_value.open.side_effect = open_request
            self.assertEqual(api.artifact(RUN), result())
        self.assertEqual(requests[0].get_header("Authorization"), "Bearer read-test-token")
        self.assertEqual(requests[1], storage)

    def test_rejects_unexpected_artifact_redirects(self):
        api = GitHub(REPO, "read-test-token", "write-test-token")
        for url in ("http://production.blob.core.windows.net/file", "https://evil.test/file",
                    "https://githubusercontent.com.evil.test/file"):
            with patch.object(api, "pages", return_value=[{"id": 1, "name": schema.ARTIFACT,
                                                           "expired": False, "size_in_bytes": 100}]), \
                    patch("lib.ci_report_github.urllib.request.build_opener") as opener:
                opener.return_value.open.side_effect = urllib.error.HTTPError(
                    "https://api.github.com", 302, "redirect", {"Location": url}, None)
                with self.assertRaises(ValueError):
                    api.artifact(RUN)
                self.assertEqual(opener.return_value.open.call_count, 1)

    def test_api_uses_separate_read_and_write_tokens(self):
        api = GitHub(REPO, "read-test-token", "write-test-token")
        with patch("lib.ci_report_github.urllib.request.build_opener") as opener:
            opener.return_value.open.return_value.__enter__.side_effect = lambda: io.BytesIO(b'{}')
            api.api("pulls/12")
            api.api("issues/12/comments", {"body": "Report"}, method="POST")
            requests = [call.args[0] for call in opener.return_value.open.call_args_list]
        self.assertEqual(requests[0].get_header("Authorization"), "Bearer read-test-token")
        self.assertEqual(requests[1].get_header("Authorization"), "Bearer write-test-token")
        self.assertEqual(requests[1].get_header("Content-type"), "application/json")


if __name__ == "__main__":
    unittest.main()
