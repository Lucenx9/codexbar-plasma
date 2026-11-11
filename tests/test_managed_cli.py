"""Offline private CLI installs, integrity, activation, concurrency and rollback."""
import fcntl
import hashlib
import http.client
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
import urllib.error
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from lib import managed_cli as cli


def archive(path, version="0.62.0", extra=None, banner=None, version_bytes=None):
    with tarfile.open(path, "w:gz") as bundle:
        for name, raw in [("CodexBarCLI", ('#!/bin/sh\nprintf "CodexBar ' + (banner or version) + '\\n"\n').encode()),
                          ("VERSION", version_bytes if version_bytes is not None else version.encode())]:
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

    def operation(self, action, command=None, expected_previous=None):
        if action == "rollback" and expected_previous is None:
            expected_previous = cli.status(self.root)["previous"]
        def download(asset, target):
            path = self.payload.with_suffix(".sha256") if asset["name"].endswith(".sha256") else self.payload
            target.write_bytes(path.read_bytes())
        with patch.object(cli.cli_release, "latest_release", return_value=self.release), \
                patch.object(cli, "platform_suffix", return_value="linux-x86_64"), \
                patch.object(cli, "download", side_effect=download):
            return cli.run(action, self.command if command is None else command, expected_previous or "")

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

    def test_install_normalizes_data_home_before_returning_the_selected_path(self):
        data = self.base / "data"
        data.mkdir()
        expected = str(data / "codexbar-plasma/cli/current/codexbar")
        for location in (str(data / ".." / "data"), "/" + str(data)):
            with self.subTest(location=location), patch.dict(os.environ, {"XDG_DATA_HOME": location}):
                result = self.operation("install")
                self.assertIn(result["status"], ("installed", "ready"))
                self.assertEqual(result["path"], expected)
                self.assertTrue(cli.owns_command(result["path"]))
                self.assertTrue(cli.owns_command(str(Path(location) / "codexbar-plasma/cli/current/codexbar")))
                self.assertTrue(os.access(result["path"], os.X_OK))

    def test_data_home_parent_segments_preserve_symlink_resolution(self):
        nested = self.base / "nested"
        (nested / "child").mkdir(parents=True)
        alias = self.base / "alias"
        alias.symlink_to(nested / "child", target_is_directory=True)
        with patch.dict(os.environ, {"XDG_DATA_HOME": str(alias / ".." / "data")}):
            result = self.operation("install")
            self.assertEqual(result["status"], "installed")
            self.assertEqual(result["path"], str(nested / "data/codexbar-plasma/cli/current/codexbar"))
            self.assertTrue(cli.owns_command(result["path"]))
        self.assertFalse((self.base / "data/codexbar-plasma").exists())

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

    def test_install_rejects_unusable_existing_copy_without_fetching(self):
        self.operation("install")
        binary = self.root / "current/CodexBarCLI"
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
                    binary.write_text('#!/bin/sh\nprintf "synthetic-private-diagnostic\\n"\nexit 1\n')
                with patch.object(cli.cli_release, "latest_release") as remote:
                    self.assertEqual(cli.run("install", self.command), {"status": "unusable"})
                remote.assert_not_called()
                self.assertTrue(binary.exists())

    def test_existing_copy_probe_is_bounded_and_does_not_expose_its_output(self):
        self.operation("install")
        with patch.object(cli.cli_release, "bounded_command", side_effect=ValueError("command_timeout")), \
                patch.object(cli.cli_release, "latest_release") as remote:
            self.assertEqual(cli.run("install", self.command), {"status": "unusable"})
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

    def test_activation_recovery_distinguishes_both_sides_of_the_switch(self):
        cli.private_directory(self.root)
        before = "releases/v0.63.0-" + "a" * 16
        target = "releases/v0.64.0-" + "b" * 16
        previous = "releases/v0.62.0-" + "c" * 16
        state = dict(previous=before, blockedVersion="0.63.0", lastAttempt=123,
                     activation=dict(target=target, before=before, previous=previous, blockedVersion="0.61.0"))
        state_file = self.root / "state.json"
        raw = json.dumps(state)
        state_file.write_text(raw)
        for selected, expected_previous, expected_blocked in ((before, previous, "0.61.0"),
                                                              (target, before, "0.63.0")):
            with self.subTest(selected=selected):
                (self.root / "current").symlink_to(selected)
                self.assertEqual(cli.state_record(self.root),
                                 dict(previous=expected_previous, blockedVersion=expected_blocked, lastAttempt=123))
                self.assertEqual(os.readlink(self.root / "current"), selected)
                self.assertEqual(state_file.read_text(), raw)
                (self.root / "current").unlink()

    def test_activation_recovery_rejects_unrelated_current_without_writing(self):
        self.operation("install")
        selected = os.readlink(self.root / "current")
        state = dict(activation=dict(target="releases/v0.64.0-" + "a" * 16,
                                     before="releases/v0.63.0-" + "b" * 16))
        state_file = self.root / "state.json"
        raw = json.dumps(state)
        state_file.write_text(raw)
        with self.assertRaisesRegex(ValueError, "^activation_state$"):
            cli.state_record(self.root)
        self.assertEqual(state_file.read_text(), raw)
        self.assertEqual(os.readlink(self.root / "current"), selected)

    def test_corrupt_checksum_preserves_current(self):
        self.operation("install")
        self.publish("0.63.0")
        self.payload.with_suffix(".sha256").write_text("0" * 64)
        with self.assertRaisesRegex(ValueError, "checksum_file"):
            self.operation("update")
        self.assertEqual(cli.status(self.root)["version"], "0.62.0")

    def test_failed_reinstallation_preserves_rollback_copy(self):
        self.operation("install")
        self.publish("0.63.0")
        self.operation("update")
        self.operation("rollback")
        before = cli.status(self.root)
        rename = os.rename

        def fail_staged_move(source, target):
            if source.name == "release":
                raise OSError("synthetic install interruption")
            return rename(source, target)

        with patch.object(cli.os, "rename", side_effect=fail_staged_move), self.assertRaises(OSError):
            self.operation("update")

        self.assertEqual(cli.status(self.root), before)
        self.assertEqual(self.operation("rollback")["version"], "0.63.0")

    def test_failed_reinstallation_and_recovery_keep_backup_on_disk(self):
        self.operation("install")
        self.publish("0.63.0")
        self.operation("update")
        previous = self.root / cli.installed(self.root)["target"]
        receipt = (previous / "receipt.json").read_bytes()
        binary = (previous / "CodexBarCLI").read_bytes()
        self.operation("rollback")
        rename = os.rename

        def fail_replacement_and_recovery(source, target):
            if target == previous:
                raise OSError("synthetic filesystem failure")
            return rename(source, target)

        with patch.object(cli.os, "rename", side_effect=fail_replacement_and_recovery), self.assertRaises(OSError):
            self.operation("update")

        self.assertEqual(cli.status(self.root)["version"], "0.62.0")
        backups = list(self.root.glob(".retained-*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / "receipt.json").read_bytes(), receipt)
        self.assertEqual((backups[0] / "CodexBarCLI").read_bytes(), binary)
        os.rename(backups[0], previous)
        self.assertEqual(self.operation("rollback")["version"], "0.63.0")

    def test_install_accepts_bounded_third_party_notices(self):
        notice = tarfile.TarInfo("THIRD_PARTY_NOTICES")
        notice.size = 128
        self.publish(extra=notice)

        result = self.operation("install")

        self.assertEqual(result["status"], "installed")
        installed = self.root / os.readlink(self.root / "current") / notice.name
        self.assertEqual(installed.read_bytes(), b"x" * notice.size)
        self.assertEqual(installed.stat().st_mode & 0o777, 0o600)

        self.publish(extra=notice)
        with tempfile.TemporaryDirectory(dir=self.base) as directory, \
                patch.object(cli, "MAX_NOTICE", notice.size - 1), \
                self.assertRaisesRegex(ValueError, "archive_size"):
            cli.unpack(self.payload, Path(directory))

    def test_binary_staged_files_report_unverified(self):
        self.operation("install")
        self.publish("0.63.0")
        self.payload.with_suffix(".sha256").write_bytes(b"\xff\xfe\x00binary")
        with self.assertRaisesRegex(ValueError, "checksum_file") as refused:
            self.operation("update")
        self.assertEqual(cli.failure_status(refused.exception), "unverified")
        self.publish("0.63.0", version_bytes=b"\xff\xfe")
        with self.assertRaisesRegex(ValueError, "version_file") as refused:
            self.operation("update")
        self.assertEqual(cli.failure_status(refused.exception), "unverified")
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
        with self.assertRaises(ValueError) as refused:
            cli.release_assets(self.release, "linux-x86_64")
        self.assertEqual(str(refused.exception), "asset_missing")

    def test_archive_rejects_traversal_links_devices_duplicates_and_oversize(self):
        for name, kind, link, size in [("../escape", tarfile.REGTYPE, "", 0),
                                       ("CodexBar_CodexBarCore.bundle/..", tarfile.REGTYPE, "", 0),
                                       ("CodexBarCLI", tarfile.REGTYPE, "", 0),
                                       ("CodexBar_CodexBarCore.bundle/bad", tarfile.SYMTYPE, "/etc", 0),
                                       ("THIRD_PARTY_NOTICES", tarfile.SYMTYPE, "VERSION", 0),
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

    def test_archive_accepts_flat_resources_and_bundle_directory_with_private_modes(self):
        for directory in (False, True):
            name = "CodexBar_CodexBarCore.bundle" + ("" if directory else "/resource.json")
            item = tarfile.TarInfo(name)
            item.type = tarfile.DIRTYPE if directory else tarfile.REGTYPE
            item.size = 0 if directory else 7
            self.publish(extra=item)
            with self.subTest(directory=directory), tempfile.TemporaryDirectory(dir=self.base) as temporary:
                destination = Path(temporary)
                cli.unpack(self.payload, destination)
                self.assertTrue((destination / "CodexBar_CodexBarCore.bundle").is_dir())
                self.assertEqual(os.readlink(destination / "codexbar"), "CodexBarCLI")
                self.assertEqual((destination / "CodexBarCLI").stat().st_mode & 0o777, 0o700)
                self.assertEqual((destination / "VERSION").stat().st_mode & 0o777, 0o600)
                if not directory:
                    self.assertEqual((destination / name).read_bytes(), b"x" * 7)
                    self.assertEqual((destination / name).stat().st_mode & 0o777, 0o600)

    def test_archive_member_count_boundary(self):
        for additional, error in ((253, None), (254, "archive_name")):
            payload = self.base / "many.tar.gz"
            with tarfile.open(self.payload, "r:gz") as source, tarfile.open(payload, "w:gz") as bundle:
                for member in source:
                    bundle.addfile(member, source.extractfile(member) if member.isfile() else None)
                for index in range(additional):
                    bundle.addfile(tarfile.TarInfo("CodexBar_CodexBarCore.bundle/file" + str(index)))
            with self.subTest(additional=additional), tempfile.TemporaryDirectory(dir=self.base) as temporary:
                if error:
                    with self.assertRaisesRegex(ValueError, "^" + error + "$"):
                        cli.unpack(payload, Path(temporary))
                else:
                    cli.unpack(payload, Path(temporary))
                    self.assertEqual(len(list((Path(temporary) / "CodexBar_CodexBarCore.bundle").iterdir())), 253)

    def test_rejected_archive_keeps_active_release_and_cleans_staging(self):
        self.operation("install")
        selected = os.readlink(self.root / "current")
        for name, error in (("./unexpected", "archive_name"), ("x" * 201, "archive_name"),
                            ("unexpected", "archive_type"),
                            ("CodexBar_CodexBarCore.bundle/nested/file", "archive_type")):
            self.publish("0.63.0", extra=tarfile.TarInfo(name))
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "^" + error + "$"):
                self.operation("update")
            self.assertEqual(os.readlink(self.root / "current"), selected)
            self.assertFalse(list(self.root.glob(".install-*")))
        self.publish("0.63.0", version_bytes=b"x" * 129)
        with self.assertRaisesRegex(ValueError, "^archive_size$"):
            self.operation("update")
        self.assertEqual(os.readlink(self.root / "current"), selected)
        self.assertFalse(list(self.root.glob(".install-*")))

    def test_state_shapes_are_bounded_before_mutation(self):
        cli.private_directory(self.root)
        for state in ({"previous": []}, {"blockedVersion": {}}, {"lastAttempt": "today"},
                      {"lastAttempt": True}, {"lastAttempt": False},
                      {"lastAttempt": float("nan")}, {"lastAttempt": float("inf")},
                      {"lastAttempt": float("-inf")}, {"activation": {"target": []}},
                      {"activation": []}):
            (self.root / "state.json").write_text(json.dumps(state))
            with self.subTest(state=state), self.assertRaises(ValueError):
                cli.status(self.root)
        for timestamp in (10 ** 400, -(10 ** 400)):
            (self.root / "state.json").write_text(json.dumps({"lastAttempt": timestamp}))
            with self.subTest(timestamp=timestamp), self.assertRaisesRegex(ValueError, "^state_time$"):
                cli.status(self.root)
        (self.root / "state.json").write_text("x" * 20000)
        with self.assertRaises(ValueError):
            cli.status(self.root)

    def test_invalid_state_timestamp_returns_json_without_changing_installation(self):
        self.operation("install")
        selected = os.readlink(self.root / "current")
        helper = Path(__file__).resolve().parents[1] / "scripts/manage-cli.py"
        cases = [("positive-overflow", json.dumps({"lastAttempt": 10 ** 400})),
                 ("negative-overflow", json.dumps({"lastAttempt": -(10 ** 400)})),
                 ("parser-limit", '{"lastAttempt":' + "9" * 4301 + '}')]
        for label, raw in cases:
            (self.root / "state.json").write_text(raw)
            for action in ("status", "install", "update", "automatic", "rollback"):
                with self.subTest(case=label, action=action):
                    result = subprocess.run(
                        [sys.executable, str(helper), "--action", action, "--command", self.command],
                        env={**os.environ, "PYTHONINTMAXSTRDIGITS": "4300"},
                        capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(json.loads(result.stdout), {"status": "error"})
                    self.assertEqual(result.stderr, "")
                    self.assertEqual(os.readlink(self.root / "current"), selected)
                    self.assertEqual((self.root / "state.json").read_text(), raw)

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

    def test_cleanup_failure_does_not_block_install_update_or_rollback(self):
        with patch.object(cli, "prune", side_effect=OSError("synthetic cleanup failure")):
            self.assertEqual(self.operation("install")["status"], "installed")
            self.publish("0.63.0")
            self.assertEqual(self.operation("update")["version"], "0.63.0")
            restored = self.operation("rollback")
        self.assertEqual(restored["status"], "restored")
        self.assertEqual(restored["version"], "0.62.0")
        self.assertEqual(restored["previous"], "0.63.0")

    def test_prune_keeps_only_current_and_previous_after_daily_updates(self):
        # Upstream ships near-daily, so a replaced release must not linger for days.
        self.operation("install")
        first = cli.installed(self.root)["target"]
        self.publish("0.63.0")
        self.operation("update")
        self.publish("0.64.0")
        self.operation("update")
        recent = cli.time.time() - 2 * 3600
        os.utime(self.root / first, (recent, recent))
        cli.prune(self.root)
        self.assertEqual(len(list((self.root / "releases").iterdir())), 2)

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
