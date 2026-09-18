"""The TODO gate must send TODO.md, flag truncation, and reject malformed answers."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from todo_gate import (DIFF_LIMIT, TODO_LIMIT, build_request, probability,
                       threshold_argument, usage_line, verdict)


def answered(probability):
    return {"todo": {"type": "noul", "noul": probability}}


class RequestTests(unittest.TestCase):
    def test_todo_reaches_the_model_with_the_diff(self):
        request = build_request(["contents/ui/main.qml"], "diff body", "- [ ] entry")
        self.assertEqual(set(request["questions"]), {"todo"})
        self.assertEqual(request["questions"]["todo"]["type"], "noul")
        self.assertEqual(request["state"]["todo"], "- [ ] entry")
        self.assertEqual(request["state"]["diff"], "diff body")
        self.assertEqual(request["state"]["changed_files"], ["contents/ui/main.qml"])

    def test_oversized_inputs_are_capped_and_flagged(self):
        request = build_request(["a"], "x" * (DIFF_LIMIT + 1), "y" * (TODO_LIMIT + 1))
        self.assertEqual(len(request["state"]["diff"]), DIFF_LIMIT)
        self.assertEqual(len(request["state"]["todo"]), TODO_LIMIT)
        self.assertTrue(request["state"]["diff_truncated"])
        self.assertTrue(request["state"]["todo_truncated"])

    def test_inputs_within_bounds_are_not_flagged(self):
        request = build_request(["a"], "x", "y")
        self.assertFalse(request["state"]["diff_truncated"])
        self.assertFalse(request["state"]["todo_truncated"])


class VerdictTests(unittest.TestCase):
    def test_owed_reconciliation_is_reported(self):
        self.assertEqual(verdict(answered(0.86), ["contents/ui/main.qml"]), 0.86)

    def test_touching_todo_clears_the_verdict(self):
        self.assertIsNone(verdict(answered(0.99), ["contents/ui/main.qml", "TODO.md"]))

    def test_threshold_is_inclusive(self):
        self.assertEqual(verdict(answered(0.6), ["a"], 0.6), 0.6)
        self.assertIsNone(verdict(answered(0.59), ["a"], 0.6))

    def test_malformed_answers_are_rejected(self):
        for broken in ({}, {"todo": {"type": "noul"}}, {"todo": {"noul": "high"}},
                       {"todo": {"noul": True}}, {"todo": 0.9}, {"other": answered(0.9)},
                       [], None):
            with self.subTest(broken=broken):
                with self.assertRaises(ValueError):
                    verdict(broken, ["a"])

    def test_out_of_range_scores_are_rejected_not_silently_passed(self):
        for score in (float("nan"), float("inf"), float("-inf"), 1.5, -0.1):
            with self.subTest(score=score):
                with self.assertRaises(ValueError):
                    verdict(answered(score), ["a"])


class ProbabilityTests(unittest.TestCase):
    def test_bounds_are_inclusive_and_finite(self):
        self.assertEqual(probability(0.0, "p"), 0.0)
        self.assertEqual(probability(1, "p"), 1.0)
        for bad in (float("nan"), float("inf"), 1.01, -0.01, True, "0.5", None):
            with self.subTest(bad=bad):
                with self.assertRaises(ValueError):
                    probability(bad, "p")

    def test_threshold_argument_rejects_junk_and_out_of_range(self):
        import argparse
        self.assertEqual(threshold_argument("0.6"), 0.6)
        for bad in ("nan", "inf", "2", "-1", "abc", ""):
            with self.subTest(bad=bad):
                with self.assertRaises(argparse.ArgumentTypeError):
                    threshold_argument(bad)


class UsageLineTests(unittest.TestCase):
    def test_untrusted_usage_never_raises(self):
        self.assertEqual(usage_line({"input_tokens": 12, "cost": 0.5}),
                         "(12 input tokens, $0.500000)")
        for usage in ({}, {"cost": "free"}, {"input_tokens": True, "cost": None},
                      {"input_tokens": "many", "cost": [1]}):
            with self.subTest(usage=usage):
                self.assertIn("input tokens", usage_line(usage))


if __name__ == "__main__":
    unittest.main()
