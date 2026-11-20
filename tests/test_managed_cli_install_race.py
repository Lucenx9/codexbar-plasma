"""Exercise managed CLI install reuse across competing invocations."""
import fcntl
import unittest
from unittest.mock import patch

from managed_cli_test_support import ManagedCliFixture, cli


class ManagedCliInstallRaceTests(ManagedCliFixture, unittest.TestCase):
    def test_install_reuses_copy_activated_before_lock_acquisition(self):
        real_flock = fcntl.flock

        def finish_peer_install_then_lock(lock, flags):
            with patch.object(fcntl, "flock", real_flock):
                self.assertEqual(self.operation("install")["status"], "installed")
            real_flock(lock, flags)

        with patch.object(fcntl, "flock", side_effect=finish_peer_install_then_lock), \
                patch.object(cli.cli_release, "latest_release", side_effect=ConnectionError("offline")) as remote:
            result = cli.run("install", self.command)

        self.assertEqual(result["status"], "ready")
        self.assertEqual(result["path"], self.command)
        remote.assert_not_called()
