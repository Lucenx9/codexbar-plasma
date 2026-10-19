"""Exercise one-use snapshot files without wallets, providers or personal data."""
import os
from pathlib import Path
import stat
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from lib import ai_insights_input as inputs


class InputTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="codexbar input 'test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "private"
        replacement = patch.object(inputs, "input_root", return_value=self.root)
        replacement.start()
        self.addCleanup(replacement.stop)

    def prepare(self, text='{"providers":[{"id":"codex","spend":123.45}]}'):
        prepared = inputs.prepare()
        path = Path(prepared["path"])
        encoded = text.encode().hex()
        path.write_text("[General]\nsnapshot=" + encoded + "\n")
        return prepared, path

    def test_private_one_use_handoff_and_idempotent_discard(self):
        prepared, path = self.prepare()
        for target, mode in ((self.root, 0o700), (path.parent, 0o700), (path, 0o600)):
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), mode)
        self.assertIn('"spend":123.45', inputs.consume(prepared["request"]))
        self.assertFalse(path.parent.exists())
        inputs.discard(prepared["request"])
        with self.assertRaises(FileNotFoundError):
            inputs.consume(prepared["request"])

    def test_empty_malformed_and_oversized_data_fail_closed_and_are_removed(self):
        for raw in (b"", b"[General]\nsnapshot=%%%\n", b"not ini", b"x" * (inputs.MAX_FILE_BYTES + 1),
                    b"[General]\nsnapshot=\xff", b"[General]\nsnapshot=" + b"78" * (inputs.MAX_BYTES + 1)):
            with self.subTest(raw=raw[:40]):
                prepared = inputs.prepare()
                path = Path(prepared["path"])
                path.write_bytes(raw)
                with self.assertRaises((ValueError, UnicodeError)):
                    inputs.consume(prepared["request"])
                self.assertFalse(path.parent.exists())

    def test_request_paths_and_unsafe_permissions_are_rejected(self):
        for request in ("", "../victim", "a" * 33, "/tmp/file"):
            with self.assertRaises(ValueError):
                inputs.consume(request)
        prepared, path = self.prepare()
        path.chmod(0o644)
        with self.assertRaises(ValueError):
            inputs.consume(prepared["request"])
        self.assertFalse(path.parent.exists())
        self.root.chmod(0o777)
        with self.assertRaises(ValueError):
            inputs.prepare()

    def test_symlinks_and_hardlinks_cannot_read_or_remove_other_files(self):
        victim = Path(self.temporary.name) / "victim"
        victim.write_text("private")
        for kind in ("symlink", "hardlink"):
            prepared = inputs.prepare()
            path = Path(prepared["path"])
            path.unlink()
            if kind == "symlink":
                path.symlink_to(victim)
            else:
                os.link(victim, path)
            with self.assertRaises((OSError, ValueError)):
                inputs.consume(prepared["request"])
            self.assertEqual(victim.read_text(), "private")
        request = "a" * 32
        (self.root / request).symlink_to(victim.parent, target_is_directory=True)
        with self.assertRaises(ValueError):
            inputs.discard(request)
        self.assertTrue(victim.exists())

    def test_expired_inputs_are_refused_and_crash_leftovers_are_pruned(self):
        prepared, path = self.prepare()
        expired = time.time() - inputs.MAX_AGE - 1
        os.utime(path.parent, (expired, expired))
        with self.assertRaises(ValueError):
            inputs.consume(prepared["request"])
        abandoned, path = self.prepare()
        os.utime(path.parent, (expired, expired))
        fresh = inputs.prepare()
        self.assertFalse(path.parent.exists())
        self.assertNotEqual(abandoned["request"], fresh["request"])
        inputs.discard(fresh["request"])


if __name__ == "__main__":
    unittest.main()
