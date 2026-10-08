"""Offline support facts exclude raw CLI output and personal system information."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
SPEC = importlib.util.spec_from_file_location("support", Path(__file__).resolve().parents[1] / "scripts/collect-support-report.py")
support = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(support)


class SupportReportTests(unittest.TestCase):
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
