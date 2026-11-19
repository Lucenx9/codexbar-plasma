"""Failures while decompressing managed CLI release assets."""
import gzip
import os
import tarfile
import unittest

from managed_cli_test_support import ManagedCliFixture, cli, release


class ManagedCliArchiveTests(ManagedCliFixture, unittest.TestCase):
    def test_invalid_gzip_is_an_unverified_release(self):
        self.operation("install")
        selected = os.readlink(self.root / "current")
        for label, payload in (("wrong format", b"not gzip"), ("truncated", gzip.compress(b"")[:-8])):
            with self.subTest(label=label):
                self.payload.write_bytes(payload)
                self.release = release(self.payload, "0.63.0")
                with self.assertRaises(tarfile.ReadError) as refused:
                    self.operation("update")
                self.assertEqual(cli.failure_status(refused.exception), "unverified")
                self.assertEqual(os.readlink(self.root / "current"), selected)
                self.assertFalse(list(self.root.glob(".install-*")))
