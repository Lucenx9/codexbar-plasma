"""Isolated managed CLI installations and synthetic official-release archives."""
import hashlib
import io
import os
from pathlib import Path
import sys
import tarfile
import tempfile
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from lib import managed_cli as cli


def archive(path, version, options):
    banner = options.get("banner")
    version_bytes = options.get("version_bytes")
    extra = options.get("extra")
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


class ManagedCliFixture:
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
        archive(self.payload, version, kwargs)
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
