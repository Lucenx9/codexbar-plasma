"""The TODO gate must send TODO.md, flag truncation, and reject malformed answers."""

import http.server
import json
from pathlib import Path
import subprocess
import sys
import threading
import unittest
import urllib.error
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import todo_gate
from todo_gate import (DIFF_LIMIT, TODO_LIMIT, ask, build_request, main,
                       probability, read_change, threshold_argument,
                       usage_line, verdict)


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


class GateHandler(http.server.BaseHTTPRequestHandler):
    mode = "ok"
    evil_hits = 0
    evil_authorization = None

    def log_message(self, *args):
        pass

    def _send_json(self, code, payload, location=None):
        raw = json.dumps(payload).encode()
        self.send_response(code)
        if location is not None:
            self.send_header("Location", location)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            self.rfile.read(length)
        if GateHandler.mode == "redirect":
            self._send_json(302, {}, location="/evil")
        elif GateHandler.mode == "big":
            self._send_json(200, {"answers": {"todo": {"noul": 0.1}},
                                  "pad": "x" * 70000})
        else:
            self._send_json(200, {"answers": {"todo": {"noul": 0.1}},
                                  "usage": {}})

    def do_GET(self):
        if self.path == "/evil":
            GateHandler.evil_hits += 1
            GateHandler.evil_authorization = self.headers.get("Authorization")
        self._send_json(200, {"answers": {"todo": {"noul": 0.99}},
                              "usage": {}})


class AskTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0),
                                                     GateHandler)
        cls.thread = threading.Thread(target=cls.server.serve_forever,
                                      daemon=True)
        cls.thread.start()
        cls.url = f"http://127.0.0.1:{cls.server.server_address[1]}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        GateHandler.mode = "ok"
        GateHandler.evil_hits = 0
        GateHandler.evil_authorization = None
        endpoint = patch.object(todo_gate, "ENDPOINT", self.url)
        endpoint.start()
        self.addCleanup(endpoint.stop)

    def test_small_valid_response_is_accepted(self):
        answers, usage = ask({"model": "m"}, "key")
        self.assertEqual(answers, {"todo": {"noul": 0.1}})
        self.assertEqual(usage, {})

    def test_redirect_is_refused_without_sending_the_key(self):
        GateHandler.mode = "redirect"
        with self.assertRaises(urllib.error.HTTPError):
            ask({"model": "m"}, "key")
        self.assertEqual(GateHandler.evil_hits, 0)
        self.assertIsNone(GateHandler.evil_authorization)

    def test_oversized_response_is_rejected(self):
        GateHandler.mode = "big"
        with self.assertRaises(ValueError):
            ask({"model": "m"}, "key")


class ReadChangeTests(unittest.TestCase):
    def test_git_calls_carry_a_timeout(self):
        with patch("subprocess.check_output", return_value="") as git:
            read_change("main")
        self.assertTrue(git.called)
        for call in git.call_args_list:
            self.assertEqual(call.kwargs.get("timeout"), 120)

    def test_git_timeout_skips_the_gate(self):
        with patch.object(todo_gate, "read_change",
                          side_effect=subprocess.TimeoutExpired("git", 120)), \
                patch.dict("os.environ", {"OPENROUTER_API_KEY": "key"}):
            self.assertEqual(main(["--base", "main"]), 0)


if __name__ == "__main__":
    unittest.main()
