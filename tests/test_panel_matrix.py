"""Verify matrix coverage and reject captures that hide lost content or clipping."""

import copy
from datetime import datetime, timezone
import itertools
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import panel_matrix as matrix
from smoke.fixture_cli import response, usage


class PanelMatrixTests(unittest.TestCase):
    def test_every_content_combination_is_captured_in_both_styles_and_orientations(self):
        expected = set(itertools.product(("standard", "minimal"), (False, True),
                                         (False, True), (False, True), (False, True)))
        for vertical in (False, True):
            cases = matrix.matrix_cases(vertical)
            actual = {(case["config"]["panelStyle"], *(case["config"][key] for key in matrix.CONTENTS))
                      for case in cases}
            self.assertEqual(actual, expected)
            self.assertEqual(len(cases), len({case["id"] for case in cases}))
            self.assertTrue(all(case["vertical"] == vertical for case in cases))
        orders = [case["config"]["panelElementOrder"] for case in matrix.matrix_cases()
                  if case["id"].startswith("order-")]
        self.assertEqual(len(set(orders)), 24)

    def test_fixtures_supply_one_or_three_providers_with_optional_credits(self):
        now = datetime(2026, 9, 9, tzinfo=timezone.utc)
        for scenario, count in (("panel-matrix-one", 1), ("panel-matrix-three", 3)):
            providers = response(["config", "providers", "--format", "json", "--json-only"], scenario, now)
            self.assertEqual(len(providers), count)
            for provider in providers:
                payload = usage(provider["provider"], scenario, now)
                self.assertIn("primary", payload["usage"])
                self.assertIn("secondary", payload["usage"])
                self.assertEqual("credits" in payload, provider["provider"] == "codex")

    def test_validation_rejects_in_bounds_but_missing_or_duplicated_content(self):
        record = {"id": "minimal-1111", "width": 200, "height": 32,
                  "text": "Codex 43% used 125cr", "case": {"vertical": False},
                  "parts": [{"name": name, "x": 0, "y": 0, "width": 20, "height": 6}
                            for name in ("panelMeterTrack", "panelMeterTrack", "panelProviderText")]}
        matrix.validate_record(record, 1)
        mutations = [lambda row: row.update(text="Codex 43% used"),
                     lambda row: row["parts"].pop(0),
                     lambda row: row["parts"].append(copy.deepcopy(row["parts"][-1])),
                     lambda row: row["parts"][0].update(x=-10),
                     lambda row: row["parts"][0].update(width=250),
                     lambda row: row["parts"][0].update(height=0)]
        for mutate in mutations:
            broken = copy.deepcopy(record)
            mutate(broken)
            with self.assertRaises(RuntimeError):
                matrix.validate_record(broken, 1)


if __name__ == "__main__":
    unittest.main()
