"""Offline release checks, provenance and bounded executable probes."""
import importlib.util
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
SPEC = importlib.util.spec_from_file_location("cli_update", Path(__file__).resolve().parents[1] / "scripts/lib/cli_release.py")
cli = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cli)


def release(tag="v0.62.0"):
    return dict(tag_name=tag, draft=False, prerelease=False, html_url=cli.RELEASE_PREFIX + tag)


class CliUpdateTests(unittest.TestCase):
    def test_version_comparison(self):
        for version, expected in [("0.9.0", "available"), ("0.62.0", "current"),
                                  ("0.100.0", "current"), ("0.62.0-beta.1", "uncomparable"),
                                  ("", "uncomparable")]:
            with self.subTest(version=version):
                result = cli.compare_release({"version": version}, release())
                self.assertEqual(result["status"], expected)

    def test_invalid_release(self):
        for value in [[], None, {}, release("v01.2.3"), release("v1.2.3-beta"),
                      {**release(), "draft": True}, {**release(), "prerelease": True},
                      {**release(), "html_url": "https://example.test"}]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                cli.compare_release({"version": "0.60.4"}, value)

    def test_local_probe_and_argument_quoting(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cli ' $(touch nope)"
            path.write_text('#!/bin/sh\n[ "$1" = --version ] || exit 1\nprintf "CodexBar 0.60.4\\r\\n"\n')
            path.chmod(0o700)
            with patch.object(cli, "installation_manager", return_value="external"), \
                    patch.object(cli, "latest_release") as remote:
                result = cli.check(str(path), local_only=True)
            remote.assert_not_called()
            self.assertEqual(result["version"], "0.60.4")
            self.assertEqual(result["path"], str(path))

    def test_missing_does_not_fetch(self):
        with patch.object(cli.shutil, "which", return_value=None), patch.object(cli, "latest_release") as remote:
            self.assertEqual(cli.check("missing")["status"], "missing")
            remote.assert_not_called()

    def test_network_failure_preserves_local_facts(self):
        record = dict(status="local", version="0.60.4", path="/usr/bin/codexbar", manager="pacman")
        with patch.object(cli, "local_record", return_value=record), \
                patch.object(cli, "latest_release", side_effect=OSError):
            result = cli.check("codexbar")
        self.assertEqual(result["status"], "network_error")
        self.assertEqual(result["manager"], "pacman")
        self.assertEqual(result["version"], "0.60.4")

    def test_package_owner_is_not_called_aur(self):
        with patch.object(cli.shutil, "which", side_effect=lambda name: "/usr/bin/" + name), \
                patch.object(cli, "bounded_command", return_value=(0, "codexbar-cli")) as command:
            self.assertEqual(cli.installation_manager("/usr/bin/codexbar"), "pacman")
            command.assert_called_once_with(["/usr/bin/pacman", "-Qqo", "/usr/bin/codexbar"])

    def test_unknown_origin_is_external(self):
        with patch.object(cli.shutil, "which", return_value=None):
            self.assertEqual(cli.installation_manager("/opt/custom-cli"), "external")

    def test_output_and_time_limits(self):
        with self.assertRaises(ValueError):
            cli.bounded_command(["python3", "-c", "print('x' * 20000)"])
        with self.assertRaises(ValueError):
            cli.bounded_command(["sleep", "5"], seconds=0.05)

    def test_dpkg_ownership_and_symlink_target(self):
        with patch.object(cli.shutil, "which", side_effect=lambda name: "/bin/dpkg-query" if name == "dpkg-query" else None), \
                patch.object(cli.os.path, "realpath", return_value="/opt/cli"), \
                patch.object(cli, "bounded_command", side_effect=[(1, ""), (0, "package: /opt/cli")]):
            self.assertEqual(cli.installation_manager("/usr/local/bin/codexbar"), "dpkg")

    def test_unrecognized_banner_is_not_displayed(self):
        with patch.object(cli.shutil, "which", return_value="/usr/bin/codexbar"), \
                patch.object(cli, "installation_manager", return_value="external"), \
                patch.object(cli, "bounded_command", return_value=(0, "private wrapper diagnostics")):
            result = cli.local_record("codexbar")
        self.assertEqual(result["status"], "unknown")
        self.assertEqual(result["version"], "")
        self.assertNotIn("private", str(result))

    def test_homebrew_requires_formula_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            formula = Path(directory) / "Cellar/codexbar/0.62.0"
            formula.mkdir(parents=True)
            with patch.object(cli.shutil, "which", side_effect=lambda name: "/bin/brew" if name == "brew" else None), \
                    patch.object(cli, "bounded_command", return_value=(0, str(formula))):
                self.assertEqual(cli.installation_manager(str(formula / "bin/codexbar")), "external")
                (formula / "INSTALL_RECEIPT.json").write_text('{}')
                self.assertEqual(cli.installation_manager(str(formula / "bin/codexbar")), "homebrew")
                self.assertEqual(cli.installation_manager("/opt/other/codexbar"), "external")

    def test_release_reads_are_bounded_and_do_not_redirect(self):
        from unittest.mock import MagicMock
        opener = MagicMock()
        opener.open.return_value.__enter__.return_value.read.return_value = b'x' * (1024 * 1024 + 1)
        with patch.object(cli.urllib.request, "build_opener", return_value=opener), self.assertRaises(ValueError):
            cli.latest_release()
        opener.open.return_value.__enter__.return_value.read.assert_called_once_with(1024 * 1024 + 1)
        request = opener.open.call_args.args[0]
        self.assertEqual(request.full_url, cli.RELEASE_API)
        self.assertIsNone(cli.NoRedirect().redirect_request(None, None, 302, "", {}, "https://example.test"))

    def test_notification_and_settings_ownership(self):
        root = Path(__file__).resolve().parents[1]
        main = (root / "contents/ui/main.qml").read_text()
        controller = main.split("Controllers.CliUpdateController {", 1)[1].split("Controllers.WidgetUpdateController {", 1)[0]
        for guard in ("!root.enableNotifications", "cliUpdateNotificationsEnabled === false",
                      "cliUpdateLastNotifiedVersion === version", "sourceName.length > 0"):
            self.assertIn(guard, controller)
        for page in ("configGeneral.qml", "configDiagnostics.qml"):
            text = (root / "contents/ui" / page).read_text()
            self.assertNotIn("cfg_cliUpdateLastCheck", text)
            self.assertNotIn("cfg_cliUpdateLastNotifiedVersion", text)
