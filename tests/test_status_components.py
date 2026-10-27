"""Offline parsing and failure handling for the status-component helper."""
import importlib.util
import io
import json
from contextlib import redirect_stdout
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/status-components.py"
SPEC = importlib.util.spec_from_file_location("status_components", SCRIPT)
status = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(status)


def incidentio(items, affected=()):
    return json.dumps({"summary": {"structure": {"items": items}, "affected_components": list(affected)}})


class StatusComponentsTests(unittest.TestCase):
    def test_feeds_are_fixed_https_urls(self):
        self.assertEqual(sorted(status.FEEDS), ["claude", "openai"])
        for _, url in status.FEEDS.values():
            self.assertTrue(url.startswith("https://status."))

    def test_incidentio_groups_take_the_worst_child(self):
        rows = status.parse("incidentio", incidentio([
            {"group": {"id": "g", "name": "APIs", "components": [
                {"component_id": "a", "name": "Chat Completions"},
                {"component_id": "b", "name": "Batch"},
                {"component_id": "h", "name": "Hidden", "hidden": True}]}},
            {"group": {"id": "x", "name": "Secret", "hidden": True, "components": []}},
            {"component": {"component_id": "c", "name": " Login\n"}},
        ], [{"component_id": "a", "status": "degraded_performance"},
            {"component_id": "b", "status": "full_outage"},
            {"component_id": "c", "status": "something_new"}]))
        self.assertEqual(rows, [
            {"name": "APIs", "indicator": "critical", "children": [
                {"name": "Chat Completions", "indicator": "minor", "children": []},
                {"name": "Batch", "indicator": "critical", "children": []}]},
            {"name": "Login", "indicator": "unknown", "children": []}])

    def test_incidentio_matches_upstream_rank_and_missing_status(self):
        rows = status.parse("incidentio", incidentio([
            {"group": {"id": "g", "name": "Codex", "components": [
                {"component_id": "m", "name": "CLI"}, {"component_id": "u", "name": "Web"}]}},
            {"component": {"component_id": "n", "name": "Login"}},
        ], [{"component_id": "m", "status": "under_maintenance"}, {"component_id": "u", "status": "new_state"},
            {"component_id": "n", "status": None}]))
        self.assertEqual(rows[0]["indicator"], "maintenance")
        self.assertEqual(rows[1]["indicator"], "none")

    def test_statuspage_malformed_status_keeps_healthy_components(self):
        for malformed in ([], {}, ["operational"]):
            with self.subTest(status=malformed):
                rows = status.parse("statuspage", json.dumps({"components": [
                    {"id": "bad", "name": "Unknown service", "status": malformed},
                    {"id": "good", "name": "Claude Code", "status": "major_outage"},
                ]}))
                self.assertEqual([r["indicator"] for r in rows], ["unknown", "critical"])

    def test_incidentio_malformed_items_keep_healthy_components(self):
        for malformed in (None, [], "invalid", 1):
            with self.subTest(item=malformed):
                rows = status.parse("incidentio", incidentio([
                    malformed, {"component": {"component_id": "good", "name": "Codex"}},
                ], [{"component_id": "good", "status": "full_outage"}]))
                self.assertEqual(rows, [{"name": "Codex", "indicator": "critical", "children": []}])

    def test_incidentio_malformed_component_id_cannot_claim_operational(self):
        for component_id in (None, [], {}, ""):
            with self.subTest(component_id=component_id):
                rows = status.parse("incidentio", incidentio([
                    {"component": {"component_id": component_id, "name": "Unknown service"}},
                    {"component": {"component_id": "good", "name": "Codex"}},
                ], [{"component_id": "good", "status": "full_outage"}]))
                self.assertEqual([r["indicator"] for r in rows], ["unknown", "critical"])

    def test_incidentio_group_severity_includes_children_beyond_display_limit(self):
        components = [{"component_id": str(i), "name": "Component " + str(i)}
                      for i in range(status.MAXIMUM_COMPONENTS + 1)]
        rows = status.parse("incidentio", incidentio([
            {"group": {"name": "APIs", "components": components}},
        ], [{"component_id": str(status.MAXIMUM_COMPONENTS), "status": "full_outage"}]))
        self.assertEqual(len(rows[0]["children"]), status.MAXIMUM_COMPONENTS)
        self.assertEqual(rows[0]["indicator"], "critical")

    def test_statuspage_nests_children_in_position_order(self):
        rows = status.parse("statuspage", json.dumps({"components": [
            {"id": "c2", "name": "Child 2", "status": "operational", "group_id": "g", "position": 3},
            {"id": "g", "name": "Group", "status": "partial_outage", "group": True, "position": 1},
            {"id": "c1", "name": "Child 1", "status": "under_maintenance", "group_id": "g", "position": 2},
            {"id": "l", "name": "Claude Code", "status": "major_outage", "group_id": None, "position": 4},
            {"id": "n", "name": "", "status": "operational"},
        ]}))
        self.assertEqual(rows, [
            {"name": "Group", "indicator": "major", "children": [
                {"name": "Child 1", "indicator": "maintenance", "children": []},
                {"name": "Child 2", "indicator": "none", "children": []}]},
            {"name": "Claude Code", "indicator": "critical", "children": []}])

    def test_record_fits_the_widget_reader_limit(self):
        # 64 groups of 64 children with maximal escaped names exceeded the
        # 256 KiB stdout limit in StatusComponents.js, so a valid page read as unavailable.
        reader = (SCRIPT.parents[1] / "contents/ui/StatusComponents.js").read_text()
        self.assertIn("text.length > " + str(status.MAXIMUM_OUTPUT), reader)
        components = []
        for g in range(status.MAXIMUM_COMPONENTS):
            components.append({"id": "g" + str(g), "name": "\u00e9" * 500, "status": "major_outage",
                               "group": True, "position": g})
            components.extend({"id": f"c{g}.{c}", "name": "\U0001f600" * 500, "status": "operational",
                               "group_id": "g" + str(g), "position": g}
                              for c in range(status.MAXIMUM_COMPONENTS))
        output = io.StringIO()
        with patch.object(status, "fetch", return_value=json.dumps({"components": components}).encode()), \
                patch.object(sys, "argv", ["status-components.py", "--provider", "claude"]), redirect_stdout(output):
            status.main()
        self.assertLessEqual(len(output.getvalue()), status.MAXIMUM_OUTPUT)
        record = json.loads(output.getvalue())
        self.assertEqual(record["status"], "ok")
        self.assertEqual(record["components"][0]["indicator"], "critical")
        self.assertGreater(len(record["components"][0]["children"]), 0)

    def test_small_records_are_not_trimmed(self):
        rows = [{"name": "Group", "indicator": "minor", "children": [
            {"name": "Child", "indicator": "minor", "children": []}]}]
        self.assertEqual(status.within_output(rows), rows)

    def test_bounds_names_and_counts(self):
        rows = status.parse("statuspage", json.dumps({"components": [
            {"id": str(i), "name": "x" * 500, "status": "operational"} for i in range(100)]}))
        self.assertEqual(len(rows), status.MAXIMUM_COMPONENTS)
        self.assertEqual(len(rows[0]["name"]), status.MAXIMUM_NAME)

    def test_invalid_or_empty_payloads_raise(self):
        for kind, raw in [("statuspage", "{}"), ("statuspage", '{"components": []}'),
                          ("incidentio", '{"summary": {}}'), ("incidentio", incidentio([])), ("statuspage", "nope")]:
            with self.assertRaises(Exception):
                status.parse(kind, raw)

    def test_every_failure_prints_only_the_error_record(self):
        def run(error):
            output = io.StringIO()
            with patch.object(sys, "argv", ["status-components.py", "--provider", "openai"]), \
                    patch.object(status, "fetch", side_effect=error), redirect_stdout(output):
                status.main()
            return json.loads(output.getvalue())
        for error in [OSError("offline https://status.openai.com"), ValueError("size"), TimeoutError()]:
            self.assertEqual(run(error), {"status": "error"})


if __name__ == "__main__":
    unittest.main()
