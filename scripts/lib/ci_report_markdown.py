"""Render a CI report from validated measurements and authoritative job data."""

from dataclasses import dataclass

from lib.ci_report_data import JOBS, MARKER, comparable, require

STATUSES = {"success", "failure", "cancelled", "skipped", "timed_out", "action_required", "neutral"}


def code_names(names):
    return ", ".join(f"`{name}`" for name in names)


def popup_summary(popup):
    if popup is None:
        return ["Popup scenario measurements are unavailable."]
    failures = sorted(case["scenario"] for case in popup if not case["passed"])
    lines = [f"Popup scenarios: **{len(popup) - len(failures)}/{len(popup)} passed**."]
    if failures:
        lines.append("Failed scenarios: " + code_names(failures) + ".")
    return lines


def timing_row(case, old):
    seconds, previous = case["seconds"], old[case["scenario"]]["seconds"]
    return f"| `{case['scenario']}` | {previous:.3f}s | {seconds:.3f}s | {seconds - previous:+.3f}s |"


def new_failures(popup, old):
    return sorted(case["scenario"] for case in popup if not case["passed"] and old[case["scenario"]]["passed"])


def timing_table(current, baseline):
    if not comparable(current, baseline):
        return ["", "No comparable baseline: measurements or scenario/environment fingerprints differ or are unavailable."]
    popup = current["popup"]
    old = {case["scenario"]: case for case in baseline["popup"]}
    failures = new_failures(popup, old)
    lines = ["", "New popup failures versus baseline: " + (code_names(failures) if failures else "none") + ".",
             "", "<details><summary>Scenario timings</summary>", "",
             "| Scenario | Baseline | This PR | Change |", "| --- | ---: | ---: | ---: |"]
    lines += [timing_row(case, old) for case in sorted(popup, key=lambda item: item["scenario"])]
    return lines + ["", "</details>"]


def editorial_only(statuses):
    gates_passed = all(statuses.get(key) == "success" for key in ("scope", "lint", "check", "smoke"))
    runtimes_skipped = all(statuses.get(key) == "skipped" for key in ("check-runtime", "smoke-runtime"))
    return gates_passed and runtimes_skipped


@dataclass
class Report:
    repo: str
    run: dict
    jobs: list
    result: dict | None
    baseline: dict | None = None
    baseline_run: dict | None = None
    rejected: bool = False

    def run_url(self):
        return f"https://github.com/{self.repo}/actions/runs/{self.run['id']}/attempts/{self.run['run_attempt']}"

    def header(self):
        return [MARKER, f"<!-- ci-report-run:{self.run['id']}:{self.run['run_attempt']} -->", "## CI report", "",
                f"Commit `{self.run['head_sha'][:12]}` · [CI run]({self.run_url()}) · {self.run['conclusion']}", ""]

    def check_table(self):
        statuses = {job["name"]: job["conclusion"] for job in self.jobs if job["name"] in JOBS}
        lines = ["| Check | Result |", "| --- | --- |"]
        for name in JOBS:
            status = statuses.get(name)
            lines.append(f"| `{name}` | {status if status in STATUSES else 'missing'} |")
        if editorial_only(statuses):
            lines += ["", "Runtime checks were intentionally omitted by the editorial-only scope gates."]
        return lines

    def measurement_lines(self):
        if self.result is None:
            return ["", "Measurement artifact unavailable or rejected by validation." if self.rejected else
                    "No measurement artifact was produced; check the job results above."]
        lines = ["", "### Runtime measurements", ""]
        if self.result["runAttempt"] != self.run["run_attempt"]:
            lines += [f"Measurements retained from CI attempt {self.result['runAttempt']}; the smoke job was not rerun.", ""]
        lines += popup_summary(self.result["popup"])
        count = self.result["panelCases"]
        lines.append("Panel cases recorded: " + (str(count) if count is not None else "unavailable") + ".")
        lines += timing_table(self.result, self.baseline)
        return lines + ["", f"Reported tested tree: `{self.result['testedSha'][:12]}`.",
                        "Scenario durations include harness setup and process startup; they are not Plasmoid update latency."]

    def baseline_lines(self):
        if not self.baseline_run:
            return []
        run = self.baseline_run
        return ["", f"Baseline: [`{run['head_sha'][:12]}`](https://github.com/{self.repo}/actions/runs/{run['id']})",
                "Exact PR base commit." if run.get("exact_base") else
                "Latest successful base-branch run with measurements; the exact PR base has no available measurements."]

    def render(self):
        lines = self.header() + self.check_table() + self.measurement_lines() + self.baseline_lines()
        lines += ["", "[Popup and panel artifacts](" + self.run_url() + "#artifacts)", "",
                  "Results are reported by trusted code; PR artifacts are data, never executed. "
                  "Existing required CI checks remain the merge gates. Screenshots require human visual review."]
        body = "\n".join(lines)
        require(len(body.encode()) <= 60000, "Rendered report exceeds the comment size limit")
        return body
