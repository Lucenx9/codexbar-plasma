"""Bounded status transport through a synthetic curl process; never uses the network."""
import importlib.util
import io
import json
import os
from contextlib import redirect_stdout
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/status-components.py"
SPEC = importlib.util.spec_from_file_location("status_transport", SCRIPT)
status = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(status)
URL = "https://data.x.ai/status/summary.json"


class StatusFetchTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.curl = self.directory / "curl"
        environment = patch.dict(os.environ, {"PATH": temporary.name})
        environment.start()
        self.addCleanup(environment.stop)
        network = patch.object(status.urllib.request, "build_opener", side_effect=AssertionError("unexpected network"))
        network.start()
        self.addCleanup(network.stop)

    def fake_curl(self, source):
        self.curl.write_text("#!" + sys.executable + "\nimport os, sys, time\n" + source)
        self.curl.chmod(0o700)

    def helper_record(self):
        output = io.StringIO()
        with patch.object(sys, "argv", ["status-components.py", "--provider", "xai"]), redirect_stdout(output):
            status.main()
        return json.loads(output.getvalue())

    def test_prefers_dual_stack_transport_with_bounded_https_request(self):
        arguments = self.directory / "arguments.json"
        self.fake_curl("import json, pathlib\n"
                       "pathlib.Path(" + repr(str(arguments)) + ").write_text(json.dumps(sys.argv[1:]))\n"
                       "sys.stdout.buffer.write(b'{}\\n200')\n")
        self.assertEqual(status.fetch(URL), b"{}")
        args = json.loads(arguments.read_text())
        self.assertEqual(args[0], "--disable")
        self.assertIn("--fail", args)
        self.assertEqual(args[args.index("--proto") + 1], "=https")
        self.assertEqual(args[args.index("--connect-timeout") + 1], "5")
        self.assertEqual(args[args.index("--max-time") + 1], "10")
        self.assertEqual(args[args.index("--max-filesize") + 1], str(status.MAXIMUM_BYTES))
        self.assertNotIn("--location", args)
        self.assertNotIn("--insecure", args)
        self.assertNotIn("--ipv4", args)
        self.assertEqual(args[-1], URL)

    def test_failed_or_redirected_transfer_cannot_supply_components(self):
        payload = json.dumps({"components": [{"id": "web", "name": "Grok Web", "status": "available"}]}).encode()
        for code, trailer in ((0, b"\n301"), (0, b"\n302"), (0, b"\n404"), (0, b"\n500"),
                              (0, b""), (0, b"\n000"), (28, b"\n200"), (63, b"\n200")):
            with self.subTest(code=code, trailer=trailer):
                self.fake_curl("sys.stdout.buffer.write(" + repr(payload + trailer) + ")\n"
                               "sys.stderr.write('untrusted diagnostic')\nsys.exit(" + str(code) + ")\n")
                self.assertEqual(self.helper_record(), {"status": "error"})

    def test_byte_limit_is_enforced_even_if_curl_ignores_it(self):
        self.fake_curl("while True: os.write(1, b'x' * 65536)\n")
        started = time.monotonic()
        self.assertEqual(self.helper_record(), {"status": "error"})
        self.assertLess(time.monotonic() - started, 2)

    def test_exact_byte_limit_is_accepted(self):
        self.fake_curl("sys.stdout.buffer.write(b'x' * " + str(status.MAXIMUM_BYTES) + " + b'\\n200')\n")
        self.assertEqual(status.fetch(URL), b"x" * status.MAXIMUM_BYTES)

    def test_hung_or_dripping_child_is_retired_within_deadline(self):
        for source in ("time.sleep(30)\n", "while True: os.write(1, b'x'); time.sleep(0.02)\n",
                       "os.close(1); time.sleep(30)\n"):
            with self.subTest(source=source):
                self.fake_curl(source)
                started = time.monotonic()
                with patch.object(status, "FETCH_DEADLINE_SECONDS", 0.15):
                    self.assertEqual(self.helper_record(), {"status": "error"})
                self.assertLess(time.monotonic() - started, 2)

    def test_missing_curl_preserves_bounded_urllib_fallback(self):
        with patch.object(status.urllib.request, "build_opener") as build:
            build.return_value.open.return_value = io.BytesIO(b"{}")
            self.assertEqual(status.fetch(URL), b"{}")
            self.assertIs(build.call_args.args[0], status.NoRedirect)
            self.assertEqual(build.return_value.open.call_args.kwargs, {"timeout": 10})
            build.return_value.open.return_value = io.BytesIO(b"x" * (status.MAXIMUM_BYTES + 1))
            self.assertEqual(self.helper_record(), {"status": "error"})


if __name__ == "__main__":
    unittest.main()
