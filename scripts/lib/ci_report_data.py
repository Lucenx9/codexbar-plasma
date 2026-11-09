"""Bounded CI measurements, provenance checks, and baseline compatibility."""

import hashlib
import io
import json
import math
import re
import stat
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


def require(condition, message):
    if not condition:
        raise ValueError(message)


def exact(value, keys):
    require(isinstance(value, dict), "Expected a JSON object")
    require(set(value) == set(keys), "Unexpected report fields")


def integer(value, minimum, maximum=10**12):
    require(type(value) is int, "Expected an integer")
    require(minimum <= value <= maximum, "Integer outside its bounds")
    return value


def positive(value):
    return integer(value, 1)


def patterned_text(value, pattern):
    require(isinstance(value, str), "Expected text")
    require(pattern.fullmatch(value), "Invalid report identifier")
    return value


def bounded_list(value, maximum, minimum=0):
    require(isinstance(value, list), "Expected a result list")
    require(minimum <= len(value) <= maximum, "Result list outside its bounds")
    return value


def json_object(pairs):
    value = {}
    for key, item in pairs:
        require(key not in value, "Duplicate JSON field")
        value[key] = item
    return value


def validate_case(case):
    exact(case, ("scenario", "passed", "seconds"))
    name = patterned_text(case["scenario"], CASE)
    require(type(case["passed"]) is bool, "Invalid scenario outcome")
    seconds = case["seconds"]
    require(type(seconds) in (int, float), "Expected numeric duration")
    require(0 <= seconds <= 3600, "Duration outside its bounds")
    require(math.isfinite(seconds), "Invalid scenario duration")
    return name


def validate_popup(cases):
    if cases is None:
        return
    names = [validate_case(case) for case in bounded_list(cases, 512, minimum=1)]
    require(len(set(names)) == len(names), "Duplicate scenario")


def validate(result):
    exact(result, ("schemaVersion", "runId", "runAttempt", "headSha", "testedSha",
                   "image", "fixture", "popup", "panelCases"))
    integer(result["schemaVersion"], 1, 1)
    for key in ("runId", "runAttempt"):
        positive(result[key])
    for key in ("headSha", "testedSha"):
        patterned_text(result[key], SHA)
    for key in ("image", "fixture"):
        patterned_text(result[key], DIGEST)
    validate_popup(result["popup"])
    if result["panelCases"] is not None:
        integer(result["panelCases"], 0, 10000)
    return result


def load_json(path, limit=MAX_RESULT):
    require(not path.is_symlink(), "Result must not be a symlink")
    require(path.is_file(), "Result must be a regular file")
    require(path.stat().st_size <= limit, "Result exceeds its size limit")
    return json.loads(path.read_text(encoding="utf-8"))


def optional_results(path, maximum, byte_limit=MAX_RESULT):
    if not path.exists():
        return None
    return bounded_list(load_json(path, byte_limit), maximum)


def popup_results(root):
    cases = optional_results(root / "dist/smoke/ci/results.json", 512)
    if cases is None:
        return None
    return [{key: case[key] for key in ("scenario", "passed", "seconds")} for case in cases]


def panel_count(root):
    panels = optional_results(root / "dist/smoke/panel-matrix/results.json", 10000, 16 * 1024 * 1024)
    return None if panels is None else len(panels)


def fixture_digest(root):
    digest = hashlib.sha256()
    inputs = [root / "scripts/smoke_popup.py", root / "scripts/panel_matrix.py"]
    inputs += sorted(path for path in (root / "scripts/smoke").rglob("*")
                     if path.is_file() and "__pycache__" not in path.parts)
    for path in inputs:
        digest.update(path.relative_to(root).as_posix().encode() + b"\0" + path.read_bytes())
    return digest.hexdigest()


def collect(root, env):
    return validate({"schemaVersion": 1, "runId": int(env["GITHUB_RUN_ID"]),
                     "runAttempt": int(env["GITHUB_RUN_ATTEMPT"]), "headSha": env["CI_REPORT_HEAD_SHA"],
                     "testedSha": env["GITHUB_SHA"], "image": env["CI_REPORT_IMAGE"],
                     "fixture": fixture_digest(root), "popup": popup_results(root),
                     "panelCases": panel_count(root)})


def result_entry(archive):
    entries = archive.infolist()
    require(len(entries) == 1, "Unexpected artifact entries")
    entry = entries[0]
    require(entry.filename == RESULT_FILE, "Unexpected artifact path")
    require(entry.file_size <= MAX_RESULT, "Result exceeds its size limit")
    require(not stat.S_ISLNK(entry.external_attr >> 16), "Result must not be a symlink")
    require(not entry.is_dir(), "Result must not be a directory")
    require(not entry.flag_bits & 1, "Result must not be encrypted")
    require(entry.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED), "Unexpected compression")
    return entry


def bind_result(result, run, expected_attempt):
    require((result["runId"], result["headSha"]) == (run["id"], run["head_sha"]),
            "Artifact does not belong to this run and head")
    require(result["runAttempt"] <= run["run_attempt"], "Artifact belongs to a future attempt")
    if expected_attempt is not None:
        require(result["runAttempt"] == expected_attempt, "Artifact does not match the smoke job attempt")
    return result


def read_archive(raw, run, expected_attempt=None):
    require(len(raw) <= MAX_RESULT, "Artifact archive exceeds its size limit")
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        result = validate(json.loads(archive.read(result_entry(archive)), object_pairs_hook=json_object))
    return bind_result(result, run, expected_attempt)


def has_popup(result):
    return bool(result and result["popup"] is not None)


def scenario_names(result):
    return {case["scenario"] for case in result["popup"]}


def environment_fingerprint(result):
    return tuple(result[key] for key in ("schemaVersion", "image", "fixture"))


def comparable(current, baseline):
    if not all((has_popup(current), has_popup(baseline))):
        return False
    return (environment_fingerprint(current) == environment_fingerprint(baseline)
            and scenario_names(current) == scenario_names(baseline))
