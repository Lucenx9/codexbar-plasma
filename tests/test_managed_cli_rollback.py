"""Managed CLI rollback targets, lock ordering and executable verification."""
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

from managed_cli_test_support import ManagedCliFixture, cli


class ManagedCliRollbackTests(ManagedCliFixture, unittest.TestCase):
    def test_install_update_and_rollback_skip_replaced_release(self):
        initial = self.operation("install")
        self.assertEqual(initial["status"], "installed")
        self.assertTrue(cli.owns_command(self.command))
        self.assertFalse(cli.owns_command(str(self.root / "current/CodexBarCLI")))
        self.assertEqual(cli.cli_release.installation_manager(self.command), "managed")
        self.publish("0.63.0")
        updated = self.operation("update")
        self.assertEqual(updated["previous"], "0.62.0")
        restored = self.operation("rollback")
        self.assertEqual(restored["version"], "0.62.0")
        with patch.object(cli.time, "time", return_value=cli.time.time() + 86401):
            self.assertEqual(self.operation("automatic")["version"], "0.62.0")
        # Explicit Update now may reinstall the previously rejected version.
        self.assertEqual(self.operation("update")["version"], "0.63.0")
        self.assertFalse(list(self.root.glob(".retained-*")))

    def test_rollback_rejects_unusable_previous_copy_without_changing_state(self):
        self.operation("install")
        self.publish("0.63.0")
        self.operation("update")
        before = os.readlink(self.root / "current")
        state = (self.root / "state.json").read_bytes()
        previous = cli.state_record(self.root)["previous"]
        binary = self.root / previous / "CodexBarCLI"
        for failure in ("not executable", "corrupt executable", "wrong version", "failed probe"):
            with self.subTest(failure=failure):
                binary.write_text('#!/bin/sh\nprintf "CodexBar 0.62.0\\n"\n')
                binary.chmod(0o700)
                if failure == "not executable":
                    binary.chmod(0o600)
                elif failure == "corrupt executable":
                    binary.write_bytes(b"not an executable")
                elif failure == "wrong version":
                    binary.write_text('#!/bin/sh\nprintf "CodexBar 0.61.0\\n"\n')
                else:
                    binary.write_text('#!/bin/sh\nexit 1\n')
                with patch.object(cli.cli_release, "latest_release") as remote:
                    result = cli.run("rollback", self.command, "0.62.0")
                self.assertEqual(result, {"status": "no_previous"})
                self.assertEqual(os.readlink(self.root / "current"), before)
                self.assertEqual((self.root / "state.json").read_bytes(), state)
                self.assertTrue(os.access(self.command, os.X_OK))
                remote.assert_not_called()

    def test_rollback_probe_timeout_keeps_current_copy(self):
        self.operation("install")
        self.publish("0.63.0")
        self.operation("update")
        before = cli.status(self.root)
        with patch.object(cli.cli_release, "bounded_command", side_effect=ValueError("command_timeout")):
            self.assertEqual(cli.run("rollback", self.command, "0.62.0"), {"status": "no_previous"})
        self.assertEqual(cli.status(self.root), before)

    def test_rollback_requires_a_displayed_target_without_changing_installation(self):
        self.operation("install")
        self.publish("0.63.0")
        self.operation("update")
        before = cli.status(self.root)
        state = (self.root / "state.json").read_bytes()
        result = cli.run("rollback", self.command)
        self.assertEqual(result, {**before, "status": "stale"})
        self.assertEqual(cli.status(self.root), before)
        self.assertEqual((self.root / "state.json").read_bytes(), state)

    def test_rollback_rechecks_the_displayed_target_after_acquiring_the_lock(self):
        self.operation("install")
        self.publish("0.63.0")
        self.operation("update")
        displayed = cli.status(self.root)["previous"]
        self.publish("0.64.0")
        acquire = cli.fcntl.flock
        after_update = {}

        def background_update_then_lock(descriptor, flags):
            with patch.object(cli.fcntl, "flock", side_effect=acquire):
                self.operation("update")
            after_update["status"] = cli.status(self.root)
            after_update["state"] = (self.root / "state.json").read_bytes()
            acquire(descriptor, flags)

        with patch.object(cli.fcntl, "flock", side_effect=background_update_then_lock):
            result = cli.run("rollback", self.command, displayed)
        self.assertEqual(result, {**after_update["status"], "status": "stale"})
        self.assertEqual(cli.status(self.root)["version"], "0.64.0")
        self.assertEqual(cli.status(self.root)["previous"], "0.63.0")
        self.assertEqual((self.root / "state.json").read_bytes(), after_update["state"])
        restored = cli.run("rollback", self.command, result["previous"])
        self.assertEqual(restored["status"], "restored")
        self.assertEqual(restored["version"], "0.63.0")

    def test_rollback_rejects_malformed_target_without_changing_installation(self):
        self.operation("install")
        self.publish("0.63.0")
        self.operation("update")
        before = cli.status(self.root)
        state = (self.root / "state.json").read_bytes()
        for target in (None, False, [], {}, "", "0.62.0-beta", "00.62.0", "0.62.0\n", "x" * 20000):
            with self.subTest(target=repr(target)[:80]):
                self.assertEqual(cli.run("rollback", self.command, target), {**before, "status": "stale"})
                self.assertEqual(cli.status(self.root), before)
                self.assertEqual((self.root / "state.json").read_bytes(), state)

    def test_helper_cli_restores_only_the_requested_version(self):
        self.operation("install")
        self.publish("0.63.0")
        self.operation("update")
        helper = Path(__file__).resolve().parents[1] / "scripts/manage-cli.py"
        command = [sys.executable, str(helper), "--action", "rollback", "--command", self.command]
        for expected, status in (("0.61.0", "stale"), ("0.62.0", "restored")):
            result = subprocess.run(command + ["--expected-previous", expected],
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            reply = json.loads(result.stdout)
            self.assertEqual(reply["status"], status)
            self.assertEqual(reply["version"], "0.63.0" if status == "stale" else "0.62.0")
            self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
