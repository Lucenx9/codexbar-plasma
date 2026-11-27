"""Exercise reinstalling over a damaged managed CLI copy."""
import os
import shutil
import unittest

from managed_cli_test_support import ManagedCliFixture, cli


class ManagedCliRepairTests(ManagedCliFixture, unittest.TestCase):
    def test_install_replaces_damaged_active_copy(self):
        for damage in ("deleted release", "missing receipt"):
            for latest in ("0.62.0", "0.63.0"):
                with self.subTest(damage=damage, latest=latest):
                    shutil.rmtree(self.root, ignore_errors=True)
                    self.publish("0.62.0")
                    self.operation("install")
                    damaged = os.readlink(self.root / "current")
                    if damage == "deleted release":
                        shutil.rmtree(self.root / damaged)
                    else:
                        (self.root / damaged / "receipt.json").unlink()
                    self.assertEqual(cli.status(self.root)["status"], "absent")
                    self.publish(latest)
                    result = self.operation("install")
                    self.assertEqual((result["status"], result["version"]), ("installed", latest))
                    self.assertEqual(cli.status(self.root)["status"], "ready")

    def test_install_refuses_forged_active_pointer(self):
        cli.private_directory(self.root)
        (self.root / "current").symlink_to("/usr/bin")
        with self.assertRaisesRegex(ValueError, "activation_origin"):
            self.operation("install")
        self.assertEqual(os.readlink(self.root / "current"), "/usr/bin")


if __name__ == "__main__":
    unittest.main()
