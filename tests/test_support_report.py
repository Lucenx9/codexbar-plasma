"""Offline support facts exclude raw CLI output and personal system information."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
SPEC = importlib.util.spec_from_file_location("support", Path(__file__).resolve().parents[1] / "scripts/collect-support-report.py")
support = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(support)


class SupportReportTests(unittest.TestCase):
    def test_provider_roster_accepts_large_metadata_but_stays_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            command = Path(directory) / "codexbar"
            for hint_length, expected in ((240, {"status": "checked", "enabled": ["codex"]}),
                                          (2500, {"status": "unavailable", "enabled": []})):
                with self.subTest(hint_length=hint_length):
                    providers = [{"provider": "codex", "enabled": True}]
                    providers.extend({"provider": f"provider-{index}", "enabled": False,
                                      "authentication": {"tokenAccounts": {"setupHint": "x" * hint_length}}}
                                     for index in range(110))
                    command.write_text(f"#!{sys.executable}\nprint({json.dumps(providers)!r})\n")
                    command.chmod(0o700)
                    self.assertEqual(support.provider_record(str(command)), expected)

    def test_provider_ids_only_and_no_truthy_enablement(self):
        payload = [{"provider": "future-provider", "enabled": True, "displayName": "secret-label",
                    "apiKey": "secret-key"}, {"provider": "codex", "enabled": False}]
        with patch.object(support, "output", return_value=json.dumps(payload)) as probe:
            self.assertEqual(support.provider_record("/some cli"), {"status": "checked", "enabled": ["future-provider"]})
            self.assertEqual(probe.call_args.args[0], ["/some cli", "config", "providers", "--format", "json", "--json-only"])
        for payload in ([{"provider": "codex", "enabled": "true"}], {}, [None],
                        [{"provider": "codex\npassword=secret", "enabled": True}],
                        [{"provider": "prototype", "enabled": True}],
                        [{"provider": "constructor", "enabled": True}],
                        [{"provider": "a" * 129, "enabled": True}],
                        [{"provider": "codex", "enabled": True}] * 257):
            with patch.object(support, "output", return_value=json.dumps(payload)):
                self.assertEqual(support.provider_record("codexbar"), {"status": "unavailable", "enabled": []})

    def test_valid_empty_roster_differs_from_failure(self):
        for text in ("", "not json", "password=secret"):
            with patch.object(support, "output", return_value=text):
                self.assertEqual(support.provider_record("codexbar")["status"], "unavailable")
        with patch.object(support, "output", return_value="[]"):
            self.assertEqual(support.provider_record("codexbar"), {"status": "checked", "enabled": []})

    def test_roster_decode_failure_preserves_rest_of_report(self):
        local = {"status": "local", "path": "/usr/bin/codexbar", "version": "0.83.0"}
        with patch.object(support, "local_record", return_value=local), \
                patch.object(support, "environment_record", return_value={}), \
                patch.object(support, "output", return_value="[]"), \
                patch.object(support.json, "loads", side_effect=RecursionError):
            result = support.collect("codexbar")
        self.assertEqual(result["selected"], local)
        self.assertEqual(result["providers"], {"status": "unavailable", "enabled": []})

    def test_report_leaves_room_for_other_facts_when_enabled_ids_are_long(self):
        providers = [{"provider": "a" * 125 + str(index).zfill(3), "enabled": True} for index in range(256)]
        local = {"status": "local", "path": "/usr/bin/codexbar", "version": "0.83.0"}
        with patch.object(support, "local_record", return_value=local), \
                patch.object(support, "environment_record", return_value={}), \
                patch.object(support, "output", return_value=json.dumps(providers)):
            result = support.collect("codexbar")
        self.assertEqual(result["selected"], local)
        self.assertEqual(result["providers"], {"status": "unavailable", "enabled": []})

    def test_report_omits_long_paths_to_preserve_versions_and_providers(self):
        for depth, extra_providers in ((15, 124), (30, 0)):
            with self.subTest(depth=depth, extra_providers=extra_providers):
                enabled = ["codex"] + ["a" * 125 + str(index).zfill(3) for index in range(extra_providers)]
                providers = [{"provider": provider, "enabled": True} for provider in enabled]
                selected = {"status": "local", "path": ("/" + "é" * 100) * depth + "/codexbar", "version": "0.84.0"}
                system = {"status": "local", "path": ("/" + "ñ" * 100) * depth + "/codexbar", "version": "0.83.0"}
                with patch.object(support, "local_record", side_effect=[selected, system]), \
                        patch.object(support, "environment_record", return_value={}), \
                        patch.object(support, "output", return_value=json.dumps(providers)):
                    result = support.collect("selected-cli")
                self.assertLessEqual(len(json.dumps(result)) + 1, 32768)
                self.assertEqual(result["selected"], {**selected, "path": ""})
                self.assertEqual(result["system"], {**system, "path": ""})
                self.assertEqual(result["providers"], {"status": "checked", "enabled": enabled})

    def test_kinfo_keeps_only_versions(self):
        banner = "KDE Plasma Version: 6.5.0\nKDE Frameworks Version: 6.19.0\nQt Version: 6.9.2\nHostname: private-machine\n"
        with patch.object(support, "bounded_command", return_value=(0, banner)):
            self.assertEqual(support.environment_record(), {"plasma": "6.5.0", "frameworks": "6.19.0", "qt": "6.9.2"})

    def test_missing_kinfo_uses_fixed_offline_probes_without_starting_plasma(self):
        answers = {"plasma-workspace": "4:6.3.6-2", "libkf6coreaddons6": "6.13.0-1"}
        def output(argv, **_kwargs):
            return answers.get(argv[-1], "6.8.2" if argv == ["qtpaths6", "--qt-version"] else "")
        with patch.object(support, "bounded_command", side_effect=FileNotFoundError), \
                patch.object(support, "output", side_effect=output) as probe:
            self.assertEqual(support.environment_record(), {"plasma": "6.3.6", "frameworks": "6.13.0", "qt": "6.8.2"})
            self.assertFalse(any(call.args[0][0] == "plasmashell" for call in probe.call_args_list))

    def test_command_failure_has_no_stderr_or_exception_details(self):
        for error in (OSError("private-path"), ValueError("secret"), subprocess.TimeoutExpired("secret-command", 3)):
            with patch.object(support, "bounded_command", side_effect=error):
                self.assertEqual(support.output(["codexbar"]), "")

    def test_missing_cli_does_not_run_provider_command(self):
        missing = {"status": "missing", "path": "", "version": "", "manager": "external"}
        with patch.object(support, "local_record", return_value=missing), \
                patch.object(support, "environment_record", return_value={}), \
                patch.object(support, "provider_record") as probe:
            self.assertEqual(support.collect("missing")["providers"]["status"], "unavailable")
            probe.assert_not_called()


if __name__ == "__main__":
    unittest.main()
