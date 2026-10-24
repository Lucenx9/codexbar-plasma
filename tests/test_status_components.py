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
