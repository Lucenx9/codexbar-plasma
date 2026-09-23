"""Offline private CLI installs, integrity, activation, concurrency and rollback."""
import fcntl
import hashlib
import http.client
import io
import json
import os
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
import urllib.error
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from lib import managed_cli as cli


def archive(path, version="0.62.0", extra=None, banner=None):
    with tarfile.open(path, "w:gz") as bundle:
        for name, raw in [("CodexBarCLI", ('#!/bin/sh\nprintf "CodexBar ' + (banner or version) + '\\n"\n').encode()),
                          ("VERSION", version.encode())]:
            item = tarfile.TarInfo(name)
            item.size = len(raw)
            bundle.addfile(item, io.BytesIO(raw))
        item = tarfile.TarInfo("codexbar")
        item.type = tarfile.SYMTYPE
        item.linkname = "CodexBarCLI"
        bundle.addfile(item)
        if extra:
            bundle.addfile(extra, io.BytesIO(b"x" * extra.size))


def release(path, version="0.62.0"):
    tag = "v" + version
    name = "CodexBarCLI-" + tag + "-linux-x86_64.tar.gz"
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    checksum = (digest + "  " + name + "\n").encode()
    path.with_suffix(".sha256").write_bytes(checksum)
    assets = []
    for filename, content in [(name, path.read_bytes()), (name + ".sha256", checksum)]:
        assets.append(dict(name=filename, size=len(content), digest="sha256:" + hashlib.sha256(content).hexdigest(),
                           browser_download_url=cli.DOWNLOAD_PREFIX + tag + "/" + filename))
    return dict(tag_name=tag, draft=False, prerelease=False, html_url=cli.cli_release.RELEASE_PREFIX + tag, assets=assets)


class ManagedCliTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        env = patch.dict(os.environ, {"XDG_DATA_HOME": str(self.base / "data")})
        env.start()
        self.addCleanup(env.stop)
        self.root = cli.root_path()
        self.command = str(self.root / "current/codexbar")
        self.payload = self.base / "test.tar.gz"
        self.publish()

    def publish(self, version="0.62.0", **kwargs):
        archive(self.payload, version, **kwargs)
        self.release = release(self.payload, version)

    def operation(self, action, command=None):
        def download(asset, target):
            path = self.payload.with_suffix(".sha256") if asset["name"].endswith(".sha256") else self.payload
            target.write_bytes(path.read_bytes())
        with patch.object(cli.cli_release, "latest_release", return_value=self.release), \
                patch.object(cli, "platform_suffix", return_value="linux-x86_64"), \
                patch.object(cli, "download", side_effect=download):
            return cli.run(action, self.command if command is None else command)

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

    def test_owns_command_resolves_canonical_probe_paths(self):
        self.operation("install")
        current = cli.installed(self.root)
        # Probes canonicalize directory prefixes (resolving `current`) while
        # keeping the `codexbar` entry name.
        probed = os.path.join(os.path.realpath(self.root / "current"), "codexbar")
        self.assertTrue(cli.owns_command(self.command))
        self.assertTrue(cli.owns_command(probed))
        self.assertTrue(cli.owns_command(str(self.root / current["target"] / "codexbar")))
        self.assertFalse(cli.owns_command(str(self.root / "current/CodexBarCLI")))
        self.assertFalse(cli.owns_command(""))
        self.assertFalse(cli.owns_command("/usr/bin/codexbar"))

    def test_select_existing_copy_is_offline_even_during_an_update(self):
        self.operation("install")
        with (self.root / ".lock").open("w") as lock, \
                patch.object(cli.cli_release, "latest_release", side_effect=OSError("offline")) as remote:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = cli.run("install", "/usr/bin/codexbar")
        self.assertEqual(result["status"], "ready")
        self.assertEqual(result["path"], self.command)
        self.assertEqual(result["version"], "0.62.0")
        remote.assert_not_called()

    def test_external_actions_do_not_create_storage_or_fetch(self):
        for action in ("automatic", "update", "rollback"):
            with self.subTest(action=action), patch.object(cli.cli_release, "latest_release") as remote:
                self.assertEqual(cli.run(action, "/usr/bin/codexbar")["status"], "external")
                self.assertFalse(self.root.exists())
                remote.assert_not_called()

    def test_automatic_throttle_shared_and_no_downgrade(self):
        self.operation("install")
        self.publish("0.63.0")
        self.assertEqual(self.operation("automatic")["version"], "0.62.0")
        with patch.object(cli.time, "time", return_value=cli.time.time() + 86401):
            self.assertEqual(self.operation("automatic")["version"], "0.63.0")
        self.publish("0.61.0")
        self.assertEqual(self.operation("update")["version"], "0.63.0")

    def test_failed_probe_preserves_selected_release(self):
        self.operation("install")
        previous = os.readlink(self.root / "current")
        self.publish("0.63.0", banner="0.62.0")
        with self.assertRaisesRegex(ValueError, "version_probe"):
            self.operation("update")
        self.assertEqual(os.readlink(self.root / "current"), previous)
        self.assertFalse(list(self.root.glob(".install-*")))

    def test_interrupted_activation_preserves_current_and_previous(self):
        self.operation("install")
        self.publish("0.63.0")
        self.operation("update")
        self.publish("0.64.0")
        with patch.object(cli, "switch", side_effect=OSError("disk")), self.assertRaises(OSError):
            self.operation("update")
        result = cli.status(self.root)
        self.assertEqual(result["version"], "0.63.0")
        self.assertEqual(result["previous"], "0.62.0")
        self.assertEqual(self.operation("rollback")["version"], "0.62.0")

    def test_corrupt_checksum_preserves_current(self):
        self.operation("install")
        self.publish("0.63.0")
        self.payload.with_suffix(".sha256").write_text("0" * 64)
        with self.assertRaisesRegex(ValueError, "checksum_file"):
            self.operation("update")
        self.assertEqual(cli.status(self.root)["version"], "0.62.0")

    def test_abandoned_download_is_pruned_before_a_failed_retry(self):
        cli.private_directory(self.root)
        abandoned = self.root / ".install-abandoned"
        abandoned.mkdir()
        (abandoned / "archive.tar.gz").write_bytes(b"partial")
        old = cli.time.time() - 86401
        os.utime(abandoned, (old, old))
        with patch.object(cli.cli_release, "latest_release", side_effect=OSError("offline")), self.assertRaises(OSError):
            cli.run("install")
        self.assertFalse(abandoned.exists())

    def test_lock_is_shared_between_instances(self):
        cli.private_directory(self.root)
        with (self.root / ".lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertEqual(self.operation("install")["status"], "busy")
        self.assertEqual(self.operation("install")["status"], "installed")

    def test_platform_selection_fails_closed(self):
        with patch.object(cli.platform, "system", return_value="Linux"), \
                patch.object(cli.platform, "machine", return_value="aarch64"), \
                patch.object(cli.os, "confstr", return_value="glibc 2.39"):
            self.assertEqual(cli.platform_suffix(), "linux-aarch64")
        with patch.object(cli.platform, "system", return_value="Linux"), \
                patch.object(cli.platform, "machine", return_value="x86_64"), \
                patch.object(cli.os, "confstr", return_value=None), \
                patch("builtins.open", return_value=io.StringIO("1-2 r-x /lib/ld-musl-x86_64.so.1")):
            self.assertEqual(cli.platform_suffix(), "linux-musl-x86_64")
        with patch.object(cli.platform, "machine", return_value="riscv64"), self.assertRaises(ValueError):
            cli.platform_suffix()

    def test_asset_validation(self):
        for field, value in [("browser_download_url", "https://evil.test/file"), ("digest", ""),
                             ("size", True), ("size", cli.MAX_ARCHIVE + 1)]:
            data = json.loads(json.dumps(self.release))
            data["assets"][0][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                cli.release_assets(data, "linux-x86_64")
        self.release["assets"].append(self.release["assets"][0])
        with self.assertRaises(ValueError):
            cli.release_assets(self.release, "linux-x86_64")

    def test_archive_rejects_traversal_links_devices_duplicates_and_oversize(self):
        for name, kind, link, size in [("../escape", tarfile.REGTYPE, "", 0),
                                       ("CodexBarCLI", tarfile.REGTYPE, "", 0),
                                       ("CodexBar_CodexBarCore.bundle/bad", tarfile.SYMTYPE, "/etc", 0),
                                       ("device", tarfile.CHRTYPE, "", 0),
                                       ("CodexBar_CodexBarCore.bundle/big", tarfile.REGTYPE, "", 100)]:
            item = tarfile.TarInfo(name)
            item.type, item.linkname, item.size = kind, link, size
            self.publish(extra=item)
            with tempfile.TemporaryDirectory(dir=self.base) as directory, \
                    patch.object(cli, "MAX_EXPANDED", 99 if size else cli.MAX_EXPANDED), \
                    self.subTest(name=name), self.assertRaises(ValueError):
                cli.unpack(self.payload, Path(directory))
        self.assertFalse((self.base / "escape").exists())

    def test_state_shapes_are_bounded_before_mutation(self):
        cli.private_directory(self.root)
        for state in ({"previous": []}, {"blockedVersion": {}}, {"lastAttempt": "today"},
                      {"activation": {"target": []}}, {"activation": []}):
            (self.root / "state.json").write_text(json.dumps(state))
            with self.subTest(state=state), self.assertRaises(ValueError):
                cli.status(self.root)
        (self.root / "state.json").write_text("x" * 20000)
        with self.assertRaises(ValueError):
            cli.status(self.root)

    def test_prune_keeps_previous_and_recent_versions(self):
        self.operation("install")
        first = cli.installed(self.root)["target"]
        self.publish("0.63.0")
        self.operation("update")
        second = cli.installed(self.root)["target"]
        self.publish("0.64.0")
        self.operation("update")
        self.assertTrue((self.root / first).exists())
        old = cli.time.time() - 8 * 86400
        for target in (first, second):
            os.utime(self.root / target, (old, old))
        cli.prune(self.root)
        self.assertFalse((self.root / first).exists())
        self.assertTrue((self.root / second).exists())

    def test_prune_removes_incomplete_orphans_but_protects_selected_paths_and_symlinks(self):
        self.operation("install")
        orphan = self.root / cli.installed(self.root)["target"]
        self.publish("0.63.0")
        self.operation("update")
        previous = self.root / cli.installed(self.root)["target"]
        self.publish("0.64.0")
        self.operation("update")
        current = self.root / cli.installed(self.root)["target"]
        old = cli.time.time() - 8 * 86400
        for directory in (orphan, previous, current):
            (directory / "receipt.json").unlink()
            os.utime(directory, (old, old))
        outside = self.base / "outside"
        outside.mkdir()
        (outside / "keep").write_text("untouched")
        link = self.root / "releases" / ("v0.65.0-" + "a" * 16)
        link.symlink_to(outside, target_is_directory=True)
        os.utime(outside, (old, old))
        unrelated = self.root / "releases/notes"
        unrelated.mkdir()
        os.utime(unrelated, (old, old))
        cli.prune(self.root)
        self.assertFalse(orphan.exists())
        self.assertTrue(previous.exists())
        self.assertTrue(current.exists())
        self.assertTrue(link.is_symlink())
        self.assertTrue((outside / "keep").exists())
        self.assertTrue(unrelated.exists())

    def test_rollback_then_update_retains_recently_active_old_release(self):
        self.operation("install")
        self.publish("0.63.0")
        self.operation("update")
        outgoing = cli.installed(self.root)["target"]
        old = cli.time.time() - 8 * 86400
        for directory in (self.root / "releases").iterdir():
            os.utime(directory, (old, old))
        self.operation("rollback")
        self.publish("0.64.0")
        self.operation("update")
        self.assertTrue((self.root / outgoing).exists())
        self.assertGreater((self.root / outgoing).stat().st_mtime, old)

    def test_unsafe_storage_and_forged_pointer(self):
        self.root.parent.mkdir(parents=True)
        self.root.symlink_to(self.base, target_is_directory=True)
        with self.assertRaises(ValueError):
            self.operation("install")
        self.root.unlink()
        cli.private_directory(self.root)
        (self.root / "current").symlink_to("/usr/bin")
        self.assertFalse(cli.owns_command(self.command))

    def test_failures_are_named_without_leaking_detail(self):
        self.operation("install")
        self.publish("0.63.0")
        self.payload.with_suffix(".sha256").write_text("0" * 64)
        with self.assertRaises(ValueError) as refused:
            self.operation("update")
        self.assertEqual(cli.failure_status(refused.exception), "unverified")
        self.publish("0.64.0", banner="0.62.0")
        with self.assertRaises(ValueError) as probed:
            self.operation("update")
        self.assertEqual(cli.failure_status(probed.exception), "unverified")
        # An unsupported system is rejected before the release API is contacted.
        with patch.object(cli, "platform_suffix", side_effect=ValueError("unsupported_platform")), \
                patch.object(cli.cli_release, "latest_release", side_effect=AssertionError("requested")), \
                self.assertRaises(ValueError) as unsupported:
            cli.run("update", self.command)
        self.assertEqual(cli.failure_status(unsupported.exception), "unsupported")
        for error, expected in [(urllib.error.URLError("offline"), "network"),
                                (TimeoutError("read"), "network"),
                                (ConnectionResetError("reset"), "network"),
                                (http.client.RemoteDisconnected("closed"), "network"),
                                (http.client.IncompleteRead(b""), "network"),
                                (tarfile.TarError("truncated"), "unverified"),
                                (ValueError("asset_missing"), "unsupported"),
                                (ValueError("state_field"), "error"),
                                (OSError("disk"), "error"), (RuntimeError("checksum"), "error")]:
            with self.subTest(error=error):
                self.assertEqual(cli.failure_status(error), expected)
        self.assertEqual(cli.status(self.root)["version"], "0.62.0")

    def test_download_size_digest_and_redirect_bounds(self):
        from unittest.mock import MagicMock
        opener = MagicMock()
        payload = b"verified"
        asset = dict(browser_download_url="https://github.com/steipete/CodexBar/releases/download/v0.62.0/x",
                     size=len(payload), digest="sha256:" + hashlib.sha256(payload).hexdigest())
        # A short body is a dropped connection; a longer or different one is refused.
        for body, refusal in ((b"verifie", ConnectionError), (b"tampered", ValueError),
                              (payload + b"extra", ValueError), (payload, None)):
            opener.open.return_value.__enter__.return_value.read.side_effect = [body, b""]
            target = self.base / "download"
            with patch.object(cli.urllib.request, "build_opener", return_value=opener):
                if refusal is None:
                    cli.download(asset, target)
                else:
                    with self.assertRaises(refusal) as failed:
                        cli.download(asset, target)
                    self.assertEqual(cli.failure_status(failed.exception),
                                     "network" if refusal is ConnectionError else "unverified")
            target.unlink()
        for url in ("http://objects.githubusercontent.com/x", "https://evil.test/x",
                    "https://user@objects.githubusercontent.com/x", "https://objects.githubusercontent.com:44/x"):
            with self.assertRaises(ValueError):
                cli.AssetRedirect().redirect_request(None, None, 302, "", {}, url)


if __name__ == "__main__":
    unittest.main()
