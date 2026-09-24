"""AI Insights helper: request contract, language, privacy routing, failures, secrets.

Every network test talks to a local HTTP server; no real provider is contacted
and no real credential or wallet is used.
"""
import gettext
import http.server
import importlib.util
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "scripts/lib"))
from compile_translations import compile_catalogs  # noqa: E402
from qml_surfaces import Surface  # noqa: E402

SPEC = importlib.util.spec_from_file_location("ai_insights", ROOT / "scripts/lib/ai_insights.py")
ai = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ai)

KEY = "sk-test-0123456789abcdef"
SNAPSHOT = json.dumps({"version": 1, "providers": [{"id": "codex", "state": "current", "quotas": [
    {"window": "primary", "usedPercent": 72, "resetsInHours": 2, "forecast": "runsOutBeforeReset",
     "runsOutInHours": 1}]}], "signals": [{"kind": "quotaRunsOutBeforeReset", "provider": "codex"}]})
INSIGHT = {"summary": "Codex esaurira la finestra prima del reset.", "highlights": ["Codex: 72%"]}


class Handler(http.server.BaseHTTPRequestHandler):
    routes = {}
    requests = []
    # OpenRouter model metadata lookups, kept apart from the billed requests.
    metadata = []

    def log_message(self, *args):
        pass

    def respond(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        record = {"method": self.command, "path": self.path, "headers": dict(self.headers),
                  "body": json.loads(body) if body else None}
        (Handler.metadata if self.path.endswith("/endpoints") else Handler.requests).append(record)
        route = Handler.routes.get(self.path, (404, {"error": "missing"}, {}, 0))
        # A callable route answers according to the request body.
        status, payload, headers, delay = route(record["body"]) if callable(route) else route
        if delay:
            time.sleep(delay)
        raw = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        self.send_response(status)
        for name, value in headers.items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        try:
            self.wfile.write(raw)
        except BrokenPipeError:
            pass

    do_GET = respond
    do_POST = respond


def chat(content, finish="stop", refusal=None):
    return {"choices": [{"finish_reason": finish, "message": {"content": content, "refusal": refusal}}]}


class HelperTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f"http://127.0.0.1:{cls.server.server_address[1]}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        Handler.routes = {}
        Handler.requests = []
        Handler.metadata = []
        bases = {"openrouter": self.base + "/api/v1", "openai": self.base + "/v1"}
        for patcher in (patch.dict(ai.CLOUD_BASES, bases), patch.object(ai, "read_key", return_value=KEY)):
            patcher.start()
            self.addCleanup(patcher.stop)

    def generate(self, provider="openrouter", model="vendor/model", language="it", zdr=True, snapshot=SNAPSHOT):
        endpoint = self.base if provider == "ollama" else ""
        result = ai.run("generate", provider, model, endpoint, language, snapshot, "", zdr)
        self.assertNotIn(KEY, json.dumps(result))
        return result


class RequestContractTests(HelperTestCase):
    def test_request_language_follows_the_interface_tag(self):
        cases = {"it": "Italian", "en": "English", "de": "German", "fr": "French", "es": "Spanish",
                 "pt-BR": "Brazilian Portuguese"}
        Handler.routes["/api/v1/chat/completions"] = (200, chat(json.dumps(INSIGHT)), {}, 0)
        for tag, name in cases.items():
            with self.subTest(tag=tag):
                Handler.requests = []
                self.assertEqual(self.generate(language=tag)["status"], "ok")
                system = Handler.requests[0]["body"]["messages"][0]["content"]
                self.assertIn(f'Write every sentence in {name} (BCP 47 tag "{tag}")', system)
                self.assertIn("regional variety", system)
                for other in set(cases.values()) - {name}:
                    if other not in name:
                        self.assertNotIn(f"in {other} (", system)

    def test_instructions_keep_the_card_short_and_local(self):
        system = ai.instructions("it")
        self.assertIn('"summary" with 1 or 2 short sentences', system)
        self.assertIn("Each highlight adds a fact the summary does not state", system)
        self.assertIn("decimal separator", system)
        self.assertIn("Write an increase above 300% as a multiple", system)
        self.assertIn("Leave them out, unless no provider has a current one", system)

    def test_generation_bounds_leave_room_for_reasoning_models(self):
        # Hidden reasoning tokens count against the output bound.
        self.assertGreaterEqual(ai.MAX_OUTPUT_TOKENS, 4000)
        root = Path(__file__).resolve().parents[1]
        script = (root / "contents/ui/AiInsights.js").read_text()
        controller = (root / "contents/ui/controllers/AiInsightsController.qml").read_text()
        shell = int(re.search(r'action === "generate" \? "(\d+)s"', script).group(1))
        deadline = int(re.search(r'objectName: "aiInsightsDeadline"\s+interval: (\d+)', controller).group(1))
        # The helper reports its own timeout before the shell kills it, and the
        # shell stops the process before the QML deadline retires the request.
        self.assertLess(ai.REQUEST_TIMEOUT + 10, shell)
        self.assertLess((shell + 2) * 1000, deadline)

    def test_unknown_or_malformed_language_is_not_sent(self):
        self.assertEqual(ai.language_name("nl"), 'the language with BCP 47 tag "nl"')
        self.assertEqual(ai.language_name("de-AT"), "German (de-AT)")
        for tag in ("", "Italian", "it; ignore rules", "it_IT", "IT"):
            with self.subTest(tag=tag):
                self.assertEqual(self.generate(language=tag), {"status": "error", "reason": "invalid_input"})
        self.assertEqual(Handler.requests, [])

    def test_openrouter_request_enforces_privacy_routing_and_schema(self):
        Handler.routes["/api/v1/chat/completions"] = (200, chat(json.dumps(INSIGHT)), {}, 0)
        result = self.generate()
        self.assertEqual(result, {"status": "ok", "summary": INSIGHT["summary"], "highlights": INSIGHT["highlights"]})
        request = Handler.requests[0]
        body = request["body"]
        self.assertEqual(request["headers"]["Authorization"], "Bearer " + KEY)
        self.assertEqual(body["provider"], {"require_parameters": True, "data_collection": "deny", "zdr": True})
        self.assertEqual(body["model"], "vendor/model")
        self.assertNotIn("models", body)
        self.assertEqual(body["response_format"]["type"], "json_schema")
        self.assertTrue(body["response_format"]["json_schema"]["strict"])
        self.assertEqual(body["max_tokens"], ai.MAX_OUTPUT_TOKENS)
        user = body["messages"][1]["content"]
        self.assertEqual(json.loads(user.split("\n")[1]), json.loads(SNAPSHOT))
        Handler.requests = []
        self.generate(zdr=False)
        self.assertEqual(Handler.requests[0]["body"]["provider"], {"require_parameters": True, "data_collection": "deny"})

    def test_openrouter_requests_carry_app_attribution(self):
        Handler.routes["/api/v1/chat/completions"] = (200, chat(json.dumps(INSIGHT)), {}, 0)
        self.assertEqual(self.generate()["status"], "ok")
        for request in Handler.metadata + Handler.requests:
            # Header names are case-insensitive; urllib capitalizes them.
            headers = {name.lower(): value for name, value in request["headers"].items()}
            self.assertEqual(headers["http-referer"], ai.APP_URL)
            self.assertEqual(headers["x-openrouter-title"], "CodexBar Plasma")

    def test_reasoning_is_turned_off_only_for_reasoning_models(self):
        Handler.routes["/api/v1/chat/completions"] = (200, chat(json.dumps(INSIGHT)), {}, 0)
        endpoints = "/api/v1/models/vendor/model/endpoints"
        cases = (("reasoning model", {"data": {"endpoints": [
                     {"supported_parameters": ["reasoning", "structured_outputs", "max_tokens"]}]}}, True),
                 # require_parameters needs both on one endpoint.
                 ("split endpoints", {"data": {"endpoints": [{"supported_parameters": ["reasoning"]},
                                                             {"supported_parameters": ["structured_outputs"]}]}}, False),
                 ("plain model", {"data": {"endpoints": [{"supported_parameters": ["max_tokens"]}]}}, False),
                 ("malformed metadata", {"data": {"endpoints": "reasoning"}}, False),
                 ("metadata unavailable", None, False))
        for name, metadata, expected in cases:
            with self.subTest(name):
                Handler.requests, Handler.metadata = [], []
                if metadata is None:
                    Handler.routes.pop(endpoints, None)
                else:
                    Handler.routes[endpoints] = (200, metadata, {}, 0)
                self.assertEqual(self.generate()["status"], "ok")
                self.assertEqual(len(Handler.metadata), 1)
                # The public lookup never carries the key.
                self.assertNotIn("Authorization", Handler.metadata[0]["headers"])
                body = Handler.requests[0]["body"]
                if expected:
                    self.assertEqual(body["reasoning"], {"effort": "none"})
                else:
                    self.assertNotIn("reasoning", body)

    def test_reasoning_without_a_route_is_retried_once_without_it(self):
        Handler.routes["/api/v1/models/vendor/model/endpoints"] = (200, {"data": {"endpoints": [
            {"supported_parameters": ["reasoning", "structured_outputs"]}]}}, {}, 0)
        no_route = (404, {"error": {"message": "No endpoints found"}}, {}, 0)
        Handler.routes["/api/v1/chat/completions"] = lambda body: (
            no_route if "reasoning" in body else (200, chat(json.dumps(INSIGHT)), {}, 0))
        self.assertEqual(self.generate()["status"], "ok")
        self.assertEqual(["reasoning" in request["body"] for request in Handler.requests], [True, False])
        # Any other failure, or a failure without the parameter, is not retried.
        Handler.requests = []
        Handler.routes["/api/v1/chat/completions"] = (401, {"error": "auth"}, {}, 0)
        self.assertEqual(self.generate(), {"status": "error", "reason": "auth"})
        self.assertEqual(len(Handler.requests), 1)
        Handler.requests = []
        Handler.routes["/api/v1/models/vendor/model/endpoints"] = (404, {"error": "missing"}, {}, 0)
        Handler.routes["/api/v1/chat/completions"] = no_route
        self.assertEqual(self.generate()["status"], "error")
        self.assertEqual(len(Handler.requests), 1)

    def test_router_aliases_are_refused(self):
        self.assertEqual(self.generate(model="openrouter/auto"), {"status": "error", "reason": "model"})
        self.assertEqual(Handler.requests, [])

    def test_openai_request_disables_storage(self):
        Handler.routes["/v1/chat/completions"] = (200, chat(json.dumps(INSIGHT)), {}, 0)
        self.assertEqual(self.generate(provider="openai", model="gpt-test")["status"], "ok")
        body = Handler.requests[0]["body"]
        self.assertFalse(body["store"])
        self.assertEqual(body["max_completion_tokens"], ai.MAX_OUTPUT_TOKENS)
        self.assertNotIn("provider", body)

    def test_ollama_uses_the_native_schema_request_without_credentials(self):
        Handler.routes["/api/chat"] = (200, {"message": {"content": json.dumps(INSIGHT)}, "done_reason": "stop"}, {}, 0)
        with patch.object(ai, "read_key", side_effect=AssertionError("Ollama must not read a key")):
            self.assertEqual(self.generate(provider="ollama", model="llama3.2:3b", language="de")["status"], "ok")
        request = Handler.requests[0]
        self.assertNotIn("Authorization", request["headers"])
        self.assertEqual(request["body"]["format"], ai.SCHEMA)
        self.assertFalse(request["body"]["stream"])
        self.assertIn('German (BCP 47 tag "de")', request["body"]["messages"][0]["content"])
        # Thinking models would otherwise exhaust the output bound, and the
        # model is unloaded as soon as the insight is written.
        self.assertIs(request["body"]["think"], False)
        self.assertEqual(request["body"]["keep_alive"], 0)
        self.assertTrue(request["body"]["messages"][1]["content"].endswith(
            "Write the summary and highlights in German."))

    def test_cloud_destinations_are_pinned_https(self):
        spec = importlib.util.spec_from_file_location("fresh_ai", ROOT / "scripts/lib/ai_insights.py")
        fresh = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(fresh)
        self.assertEqual(fresh.CLOUD_BASES, {"openrouter": "https://openrouter.ai/api/v1",
                                             "openai": "https://api.openai.com/v1"})

    def test_ollama_endpoint_validation(self):
        valid = {"": "http://localhost:11434", "http://localhost:11434/": "http://localhost:11434",
                 "http://127.0.0.1:8080": "http://127.0.0.1:8080", "http://[::1]:11434": "http://[::1]:11434",
                 "https://gpu.example:11434": "https://gpu.example:11434"}
        for value, expected in valid.items():
            with self.subTest(value=value):
                self.assertEqual(ai.ollama_base(value), expected)
        for value in ("http://192.168.1.4:11434", "http://gpu.example", "ftp://localhost", "https://u:p@gpu.example",
                      "https://gpu.example/api", "https://gpu.example?x=1", "http://localhost:99999",
                      "https://gpu example", "file:///etc/passwd"):
            with self.subTest(value=value), self.assertRaises(ai.Failure):
                ai.ollama_base(value)


class ResponseValidationTests(HelperTestCase):
    def reply(self, payload, status=200, headers=None, provider="openrouter"):
        path = "/v1/chat/completions" if provider == "openai" else "/api/v1/chat/completions"
        Handler.routes[path] = (status, payload, headers or {}, 0)
        return self.generate(provider=provider, model="gpt-test" if provider == "openai" else "vendor/model")

    def test_structured_content_is_validated_and_bounded(self):
        long = {"summary": "word " * 400, "highlights": ["- **bold** item", 4, "", "x" * 400, "three", "four"]}
        result = self.reply(chat(json.dumps(long)))
        self.assertEqual(result["status"], "ok")
        self.assertLessEqual(len(result["summary"]), ai.MAX_SUMMARY_CHARS)
        self.assertTrue(result["summary"].endswith("…"))
        self.assertEqual(result["highlights"][0], "bold item")
        self.assertEqual(len(result["highlights"]), ai.MAX_HIGHLIGHTS)
        self.assertEqual(result["highlights"][2], "three")
        self.assertLessEqual(len(result["highlights"][1]), ai.MAX_HIGHLIGHT_CHARS)
        fenced = self.reply(chat("```json\n" + json.dumps(INSIGHT) + "\n```"))
        self.assertEqual(fenced["summary"], INSIGHT["summary"])
        control = self.reply(chat(json.dumps({"summary": "a\u0000‮\nb", "highlights": []})))
        self.assertEqual(control["summary"], "a b")

    def test_malformed_outputs_fail_without_retrying(self):
        cases = [
            chat("not json"), chat(""), chat(None), chat(json.dumps([INSIGHT])),
            chat(json.dumps({"summary": 3})), chat(json.dumps({"highlights": []})),
            chat(json.dumps({"summary": "x", "highlights": "y"})), chat("x" * (ai.MAX_CONTENT_CHARS + 1)),
            {"choices": []}, {"unexpected": True}, b"<html>", b"",
        ]
        for payload in cases:
            with self.subTest(payload=str(payload)[:60]):
                Handler.requests = []
                self.assertEqual(self.reply(payload), {"status": "error", "reason": "format"})
                self.assertEqual(len(Handler.requests), 1)

    def test_refusal_and_truncation(self):
        self.assertEqual(self.reply(chat(None, refusal="I can't")), {"status": "error", "reason": "refused"})
        self.assertEqual(self.reply(chat("{}", finish="content_filter")), {"status": "error", "reason": "refused"})
        self.assertEqual(self.reply(chat('{"summary": "x', finish="length")), {"status": "error", "reason": "truncated"})
        Handler.routes["/api/chat"] = (200, {"message": {"content": "{"}, "done_reason": "length"}, {}, 0)
        self.assertEqual(self.generate(provider="ollama", model="llama3"), {"status": "error", "reason": "truncated"})

    def test_http_failures_map_to_bounded_reasons(self):
        cases = [
            (401, {}, "openrouter", {"reason": "auth"}),
            (402, {}, "openrouter", {"reason": "credits"}),
            (403, {}, "openrouter", {"reason": "forbidden"}),
            (404, {}, "openrouter", {"reason": "model"}),
            (400, {}, "openai", {"reason": "request"}),
            (408, {}, "openrouter", {"reason": "timeout"}),
            (429, {"Retry-After": "120"}, "openrouter", {"reason": "rate_limited", "retryAfter": 120}),
            (429, {"Retry-After": "999999999"}, "openrouter", {"reason": "rate_limited", "retryAfter": ai.MAX_RETRY_AFTER}),
            (429, {"Retry-After": "Wed, 21 Oct 2015"}, "openrouter", {"reason": "rate_limited"}),
            (503, {}, "openrouter", {"reason": "routing"}),
            (500, {}, "openai", {"reason": "unavailable"}),
        ]
        for status, headers, provider, expected in cases:
            with self.subTest(status=status, headers=headers):
                payload = {"error": {"message": "secret detail " + KEY, "code": status}}
                self.assertEqual(self.reply(payload, status, headers, provider), {"status": "error", **expected})
        quota = {"error": {"message": "You exceeded your current quota", "code": "insufficient_quota"}}
        self.assertEqual(self.reply(quota, 429, {}, "openai"), {"status": "error", "reason": "credits"})

    def test_redirects_are_never_followed(self):
        Handler.routes["/api/v1/chat/completions"] = (302, b"", {"Location": self.base + "/stolen"}, 0)
        self.assertEqual(self.generate(), {"status": "error", "reason": "network"})
        self.assertEqual([request["path"] for request in Handler.requests], ["/api/v1/chat/completions"])

    def test_timeout_and_connection_failures(self):
        Handler.routes["/api/v1/chat/completions"] = (200, chat(json.dumps(INSIGHT)), {}, 1.5)
        with patch.object(ai, "REQUEST_TIMEOUT", 0.3):
            self.assertEqual(self.generate(), {"status": "error", "reason": "timeout"})
        with patch.dict(ai.CLOUD_BASES, {"openrouter": "http://127.0.0.1:9/api/v1"}):
            self.assertEqual(self.generate(), {"status": "error", "reason": "network"})

    def test_invalid_snapshots_are_rejected_before_any_request(self):
        for snapshot in ("", "{", "[]", json.dumps({"providers": {}}), json.dumps({"providers": ["x" * 20000]})):
            with self.subTest(snapshot=snapshot[:20]):
                self.assertEqual(self.generate(snapshot=snapshot), {"status": "error", "reason": "invalid_input"})
        self.assertEqual(Handler.requests, [])

    def test_missing_key_never_contacts_the_provider(self):
        with patch.object(ai, "read_key", return_value=""):
            self.assertEqual(self.generate(), {"status": "error", "reason": "missing_key"})
            self.assertEqual(ai.run("models", "openai"), {"status": "error", "reason": "missing_key"})
        self.assertEqual(Handler.requests, [])


class ModelDiscoveryTests(HelperTestCase):
    def test_ollama_models(self):
        Handler.routes["/api/tags"] = (200, {"models": [{"name": "llama3.2:3b"}, {"name": "bad name"}, {"name": 3},
                                                        {"name": "qwen3:8b"}]}, {}, 0)
        result = ai.run("models", "ollama", endpoint=self.base)
        self.assertEqual(result, {"status": "ok", "key": "none", "models": [
            {"id": "llama3.2:3b", "label": "llama3.2:3b"}, {"id": "qwen3:8b", "label": "qwen3:8b"}]})

    def test_local_ollama_never_uses_an_environment_proxy(self):
        # A proxy would receive data the settings promise stays on this device.
        Handler.routes["/api/tags"] = (200, {"models": [{"name": "llama3"}]}, {}, 0)
        proxy = {"http_proxy": "http://127.0.0.1:9", "HTTP_PROXY": "http://127.0.0.1:9",
                 "https_proxy": "http://127.0.0.1:9", "HTTPS_PROXY": "http://127.0.0.1:9"}
        with patch.dict(os.environ, proxy):
            for name in ("no_proxy", "NO_PROXY"):
                os.environ.pop(name, None)
            for endpoint in (self.base, self.base.replace("127.0.0.1", "localhost")):
                with self.subTest(endpoint=endpoint):
                    self.assertEqual(ai.run("models", "ollama", endpoint=endpoint)["status"], "ok")

    def test_ollama_not_running(self):
        self.assertEqual(ai.run("models", "ollama", endpoint="http://127.0.0.1:9"), {"status": "error", "reason": "network"})

    def test_openrouter_checks_the_key_and_keeps_structured_output_models(self):
        Handler.routes["/api/v1/key"] = (200, {"data": {"label": "x"}}, {}, 0)
        Handler.routes["/api/v1/models"] = (200, {"data": [
            {"id": "b/model", "name": "B", "supported_parameters": ["structured_outputs", "max_tokens"]},
            {"id": "a/plain", "name": "A", "supported_parameters": ["max_tokens"]},
            {"id": "openrouter/auto", "name": "Auto", "supported_parameters": ["structured_outputs"]},
            {"id": "c/model", "name": "C\u0007 model", "supported_parameters": ["structured_outputs"]},
            # Batch variants serve only the asynchronous Batch API.
            {"id": "b/model:batch", "name": "B (batch)", "supported_parameters": ["structured_outputs"]},
        ]}, {}, 0)
        result = ai.run("models", "openrouter")
        self.assertEqual(result["key"], "valid")
        self.assertEqual([model["id"] for model in result["models"]], ["b/model", "c/model"])
        self.assertEqual(result["models"][1]["label"], "C model")
        key_request = Handler.requests[0]
        self.assertEqual((key_request["path"], key_request["headers"]["Authorization"]), ("/api/v1/key", "Bearer " + KEY))
        self.assertNotIn("Authorization", Handler.requests[1]["headers"])

    def test_openrouter_invalid_key(self):
        Handler.routes["/api/v1/key"] = (401, {"error": {"code": 401}}, {}, 0)
        self.assertEqual(ai.run("models", "openrouter"), {"status": "error", "reason": "auth"})

    def test_openai_keeps_chat_models(self):
        Handler.routes["/v1/models"] = (200, {"data": [{"id": name} for name in (
            "gpt-4.1-mini", "gpt-4o-audio-preview", "text-embedding-3-small", "o4-mini", "dall-e-3",
            "gpt-4o-realtime-preview", "whisper-1", "gpt-image-1")]}, {}, 0)
        self.assertEqual([model["id"] for model in ai.run("models", "openai")["models"]], ["gpt-4.1-mini", "o4-mini"])


class SecretStorageTests(unittest.TestCase):
    """The key reaches secret-tool only through stdin and never leaves the helper."""

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)
        self.log = self.path / "log.jsonl"
        self.store = self.path / "store.json"
        tool = self.path / "secret-tool"
        tool.write_text(f"""#!{sys.executable}
import json, os, sys
log, store = {str(self.log)!r}, {str(self.store)!r}
if os.environ.get("FAKE_SECRET_BROKEN"):
    sys.stderr.write("Cannot autolaunch D-Bus without X11\\n"); sys.exit(1)
data = json.load(open(store)) if os.path.exists(store) else {{}}
stdin = sys.stdin.read() if sys.argv[1] == "store" else ""
open(log, "a").write(json.dumps({{"argv": sys.argv[1:], "stdin": stdin}}) + "\\n")
key = sys.argv[-1]
if sys.argv[1] == "store":
    data[key] = stdin
elif sys.argv[1] == "lookup":
    if key not in data: sys.exit(1)
    sys.stdout.write(data[key])
elif sys.argv[1] == "clear":
    data.pop(key, None)
json.dump(data, open(store, "w"))
""")
        dialog = self.path / "kdialog"
        dialog.write_text(f"""#!{sys.executable}
import json, os, sys
open({str(self.log)!r}, "a").write(json.dumps({{"dialog": sys.argv[1:]}}) + "\\n")
if os.environ.get("FAKE_DIALOG_CANCEL"): sys.exit(1)
print(os.environ.get("FAKE_DIALOG_VALUE", {KEY!r}))
""")
        tool.chmod(0o700)
        dialog.chmod(0o700)
        for patcher in (patch.object(ai, "SECRET_TOOL", str(tool)), patch.object(ai, "KDIALOG", str(dialog))):
            patcher.start()
            self.addCleanup(patcher.stop)

    def entries(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_set_lookup_clear_round_trip(self):
        self.assertEqual(ai.run("key-status", "openrouter"), {"status": "absent"})
        self.assertEqual(ai.run("set-key", "openrouter", prompt="OpenRouter API key"), {"status": "saved"})
        self.assertEqual(ai.read_key("openrouter"), KEY)
        self.assertEqual(ai.run("key-status", "openrouter"), {"status": "present"})
        self.assertEqual(ai.run("key-status", "openai"), {"status": "absent"})
        self.assertEqual(ai.run("clear-key", "openrouter"), {"status": "cleared"})
        self.assertEqual(ai.run("key-status", "openrouter"), {"status": "absent"})
        for entry in self.entries():
            self.assertNotIn(KEY, json.dumps(entry.get("argv", entry.get("dialog"))))
        stores = [entry for entry in self.entries() if entry.get("argv", [""])[0] == "store"]
        self.assertEqual(stores[0]["stdin"], KEY)
        self.assertIn("app.codexbar.plasma", stores[0]["argv"])
        self.assertEqual(stores[0]["argv"][-2:], ["provider", "openrouter"])

    def test_cancel_invalid_and_missing_dialog(self):
        with patch.dict(os.environ, {"FAKE_DIALOG_CANCEL": "1"}):
            self.assertEqual(ai.run("set-key", "openai"), {"status": "cancelled"})
        with patch.dict(os.environ, {"FAKE_DIALOG_VALUE": "short"}):
            self.assertEqual(ai.run("set-key", "openai"), {"status": "invalid"})
        with patch.dict(os.environ, {"FAKE_DIALOG_VALUE": "sk key with spaces"}):
            self.assertEqual(ai.run("set-key", "openai"), {"status": "invalid"})
        self.assertFalse(self.store.exists())
        with patch.object(ai, "KDIALOG", str(self.path / "missing-kdialog")):
            self.assertEqual(ai.run("set-key", "openai"), {"status": "dialog_missing"})
        self.assertEqual(ai.run("set-key", "ollama"), {"status": "invalid"})

    def test_unavailable_wallet_fails_safely(self):
        with patch.dict(os.environ, {"FAKE_SECRET_BROKEN": "1"}):
            self.assertEqual(ai.run("key-status", "openai"), {"status": "unavailable"})
            self.assertEqual(ai.run("generate", "openai", "gpt-test", "", "en", SNAPSHOT),
                             {"status": "error", "reason": "secret_unavailable"})
            self.assertEqual(ai.run("set-key", "openai"), {"status": "unavailable"})
        with patch.object(ai, "SECRET_TOOL", str(self.path / "missing-secret-tool")):
            self.assertEqual(ai.run("key-status", "openai"), {"status": "unavailable"})

    def test_entry_point_prints_only_bounded_json(self):
        environment = {**os.environ, "PATH": f"{self.path}:{os.environ.get('PATH', '')}"}
        output = subprocess.run([sys.executable, str(ROOT / "scripts/ai-insights.py"), "--action", "key-status",
                                 "--provider", "openai"], capture_output=True, text=True, env=environment,
                                timeout=30, check=True)
        self.assertEqual(json.loads(output.stdout), {"status": "absent"})
        rejected = subprocess.run([sys.executable, str(ROOT / "scripts/ai-insights.py"), "--action", "run",
                                   "--provider", "openai"], capture_output=True, text=True, timeout=30)
        self.assertNotEqual(rejected.returncode, 0)


LANGUAGE_QML = '''import QtQuick
import QtTest
import "SOURCE_URL/AiInsights.js" as AiInsights
TestCase {
    name: "AiInsightsCatalogLanguage"
    property var messages: ({})
    function i18nc(context, source) {
        var key = context + "\\u0004" + source;
        return Object.prototype.hasOwnProperty.call(messages, key) ? messages[key] : source;
    }
    function aiInsightsLanguageTag() { BODY }
    function test_languages_data() { return CASES; }
    function test_languages(data) {
        messages = data.messages;
        var command = AiInsights.command("file:///pkg/scripts/ai-insights.py", "generate", {
            provider: "openrouter", model: "vendor/model", language: aiInsightsLanguageTag(), snapshot: "{}"});
        var match = /--language (\\S+)/.exec(command);
        verify(match !== null, command);
        console.log("REQUEST_LANGUAGE " + data.tag + " " + match[1] + " " + Qt.locale().name);
        compare(match[1], data.expected);
    }
}
'''


class CatalogLanguageTests(HelperTestCase):
    """The shipped catalog i18n() resolves decides the request language end to end."""

    CONTEXT = ("BCP 47 language tag of this translation, such as it or pt-BR. "
               "AI Insights are written in this language.")
    EXPECTED = {"en": "en", "it": "it", "de": "de", "fr": "fr", "es": "es", "pt_BR": "pt-BR"}

    def resolved_tags(self, environment):
        applet = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        applet.texts = {main: main.read_text()}
        applet.files = [main]
        with tempfile.TemporaryDirectory(prefix="codexbar-ai-language-") as temporary:
            directory = Path(temporary)
            compile_catalogs(directory / "locale")
            cases = []
            for language, expected in self.EXPECTED.items():
                catalog = gettext.translation("plasma_applet_app.codexbar.plasma", directory / "locale",
                                              languages=[language], fallback=language == "en")
                messages = {key: value for key, value in getattr(catalog, "_catalog", {}).items()
                            if isinstance(key, str) and key.startswith(self.CONTEXT)}
                self.assertEqual(catalog.pgettext(self.CONTEXT, "en"), expected)
                cases.append({"tag": language, "messages": messages, "expected": expected})
            fixture = directory / "tst_ai_language.qml"
            fixture.write_text(LANGUAGE_QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
                               .replace("BODY", applet.function_body("aiInsightsLanguageTag"))
                               .replace("CASES", json.dumps(cases)))
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software", **environment},
                capture_output=True, text=True, timeout=60)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("QWARN", output)
            records = [line[line.index("REQUEST_LANGUAGE"):].split() for line in output.splitlines()
                       if "REQUEST_LANGUAGE" in line]
            self.assertEqual(len(records), len(self.EXPECTED), output)
            return {record[1]: record[2] for record in records}, {record[3] for record in records}

    def test_catalog_language_reaches_the_generation_request(self):
        # A C/English numeric and regional locale must not change the language.
        tags, locales = self.resolved_tags({"LC_ALL": "C.UTF-8", "LANG": "C.UTF-8"})
        self.assertEqual(tags, {language: tag for language, tag in self.EXPECTED.items()})
        self.assertEqual(len(locales), 1)
        self.assertFalse(next(iter(locales)).startswith(("it", "de", "fr", "es", "pt")))
        Handler.routes["/api/v1/chat/completions"] = (200, chat(json.dumps(INSIGHT)), {}, 0)
        names = {"it": "Italian", "en": "English", "de": "German", "pt-BR": "Brazilian Portuguese"}
        for tag, name in names.items():
            with self.subTest(tag=tag):
                Handler.requests = []
                self.assertEqual(self.generate(language=tag)["status"], "ok")
                self.assertIn(f"in {name} (", Handler.requests[0]["body"]["messages"][0]["content"])

    def test_every_catalog_names_its_own_language(self):
        with tempfile.TemporaryDirectory(prefix="codexbar-ai-catalogs-") as temporary:
            compile_catalogs(Path(temporary) / "locale")
            catalogs = sorted(path.stem for path in (ROOT / "po").glob("*.po"))
            self.assertTrue(catalogs)
            for language in catalogs:
                with self.subTest(language=language):
                    catalog = gettext.translation("plasma_applet_app.codexbar.plasma", Path(temporary) / "locale",
                                                  languages=[language])
                    self.assertEqual(catalog.pgettext(self.CONTEXT, "en"), language.replace("_", "-"))

    def test_region_does_not_select_the_language(self):
        # An Italian region with the English catalog still writes English, and
        # the reverse mismatch is covered by the C locale run above.
        tags, _ = self.resolved_tags({"LC_ALL": "it_IT.UTF-8", "LANG": "it_IT.UTF-8", "LC_NUMERIC": "it_IT.UTF-8"})
        self.assertEqual(tags["en"], "en")
        self.assertEqual(tags["it"], "it")


if __name__ == "__main__":
    unittest.main()
