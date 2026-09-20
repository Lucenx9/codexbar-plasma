"""Private, checksum-verified Linux CLI installations. Never modify external CLIs."""
import fcntl
import hashlib
import gzip
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import stat
import tarfile
import tempfile
import time
import urllib.parse
import urllib.request
import uuid

from . import cli_release

MAX_ARCHIVE = 160 * 1024 * 1024
MAX_EXPANDED = 600 * 1024 * 1024
RELEASE_DIRECTORY = re.compile(r"releases/v" + cli_release.VERSION + r"-[a-f0-9]{16}")
DOWNLOAD_PREFIX = "https://github.com/steipete/CodexBar/releases/download/"


def root_path():
    data = os.environ.get("XDG_DATA_HOME", "")
    base = Path(data) if data.startswith("/") else Path.home() / ".local/share"
    return base / "codexbar-plasma/cli"


def private_directory(path):
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o022:
        raise ValueError("unsafe_directory")


def read_json(path):
    with path.open("rb") as stream:
        raw = stream.read(16385)
    if len(raw) > 16384:
        raise ValueError("state_size")
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise ValueError("state_shape")
    return value


def installed(root, target=None):
    try:
        info = root.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o022:
            return None
        target = os.readlink(root / "current") if target is None else target
        if not isinstance(target, str) or not RELEASE_DIRECTORY.fullmatch(target):
            return None
        directory = root / target
        if directory.is_symlink() or directory.resolve().parent != (root / "releases").resolve():
            return None
        receipt = read_json(directory / "receipt.json")
        version = receipt.get("version", "")
        digest = receipt.get("sha256", "")
        if not isinstance(version, str) or not re.fullmatch(cli_release.VERSION, version) \
                or not isinstance(digest, str) or not re.fullmatch(r"[a-f0-9]{64}", digest) \
                or target != "releases/v" + version + "-" + digest[:16] \
                or not (directory / "CodexBarCLI").is_file() \
                or (directory / "CodexBarCLI").is_symlink() \
                or os.readlink(directory / "codexbar") != "CodexBarCLI":
            return None
        return dict(version=version, target=target)
    except (OSError, ValueError, TypeError):
        return None


def owns_command(command):
    root = root_path()
    return command == str(root / "current/codexbar") and installed(root) is not None


def state_record(root):
    try:
        state = read_json(root / "state.json")
    except FileNotFoundError:
        return {}
    for key in ("previous", "blockedVersion"):
        value = state.get(key, "")
        pattern = RELEASE_DIRECTORY if key == "previous" else re.compile(cli_release.VERSION)
        if not isinstance(value, str) or (value and not pattern.fullmatch(value)):
            raise ValueError("state_field")
    if type(state.get("lastAttempt", 0)) not in (int, float):
        raise ValueError("state_time")
    activation = state.pop("activation", None)
    if activation is not None:
        if not isinstance(activation, dict):
            raise ValueError("activation_shape")
        for key in ("target", "before", "previous", "blockedVersion"):
            value = activation.get(key, "")
            pattern = re.compile(cli_release.VERSION) if key == "blockedVersion" else RELEASE_DIRECTORY
            if not isinstance(value, str) or (value and not pattern.fullmatch(value)):
                raise ValueError("activation_field")
        current = os.readlink(root / "current") if (root / "current").is_symlink() else ""
        if current != activation.get("target"):
            if current != activation.get("before"):
                raise ValueError("activation_state")
            # A crash before the atomic switch must not discard the earlier rollback target.
            state["previous"] = activation.get("previous", "")
            state["blockedVersion"] = activation.get("blockedVersion", "")
    return state


def status(root):
    current = installed(root)
    state = state_record(root) if root.exists() else {}
    previous = installed(root, state.get("previous", ""))
    return dict(status="ready" if current else "absent", version=current["version"] if current else "",
                path=str(root / "current/codexbar"), previous=previous["version"] if previous else "")


def write_state(root, state):
    temporary = root / (".state-" + uuid.uuid4().hex)
    try:
        with temporary.open("x", encoding="utf-8") as stream:
            json.dump(state, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, root / "state.json")
    finally:
        temporary.unlink(missing_ok=True)


def switch(root, target):
    temporary = root / (".current-" + uuid.uuid4().hex)
    try:
        temporary.symlink_to(target)
        os.replace(temporary, root / "current")
    finally:
        temporary.unlink(missing_ok=True)


def activate(root, target, state, previous, blocked_version=""):
    before = os.readlink(root / "current") if (root / "current").is_symlink() else ""
    if before:
        if not installed(root, before):
            raise ValueError("activation_origin")
        # Grace starts when a version stops being active, including after rollback.
        os.utime(root / before, None)
    state["activation"] = dict(target=target, before=before, previous=state.get("previous", ""),
                               blockedVersion=state.get("blockedVersion", ""))
    state.update(previous=previous, blockedVersion=blocked_version)
    write_state(root, state)
    switch(root, target)


def platform_suffix():
    machine = platform.machine()
    if platform.system() != "Linux" or machine not in ("x86_64", "aarch64"):
        raise ValueError("unsupported_platform")
    try:
        if os.confstr("CS_GNU_LIBC_VERSION"):
            return "linux-" + machine
    except (ValueError, OSError):
        pass
    with open("/proc/self/maps", encoding="utf-8") as stream:
        maps = stream.read(256 * 1024)
    if re.search(r"/[^\s]*ld-musl-[^\s]+\.so\.1", maps):
        return "linux-musl-" + machine
    raise ValueError("unsupported_platform")


def release_assets(release, suffix):
    record = cli_release.compare_release({"version": ""}, release)
    tag = record["tag"]
    name = "CodexBarCLI-" + tag + "-" + suffix + ".tar.gz"
    assets = release.get("assets")
    if not isinstance(assets, list) or len(assets) > 100:
        raise ValueError("assets")
    selected = []
    for expected, maximum in ((name, MAX_ARCHIVE), (name + ".sha256", 4096)):
        matches = [a for a in assets if isinstance(a, dict) and a.get("name") == expected]
        if len(matches) != 1:
            raise ValueError("asset_missing")
        asset = matches[0]
        if asset.get("browser_download_url") != DOWNLOAD_PREFIX + tag + "/" + expected \
                or type(asset.get("size")) is not int or not 0 < asset["size"] <= maximum \
                or not isinstance(asset.get("digest"), str) \
                or not re.fullmatch(r"sha256:[a-f0-9]{64}", asset["digest"]):
            raise ValueError("asset_shape")
        selected.append(asset)
    return record["latest"], selected


class AssetRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        url = urllib.parse.urlsplit(newurl)
        if url.scheme != "https" or url.hostname not in ("release-assets.githubusercontent.com", "objects.githubusercontent.com") \
                or url.username or url.password or url.port not in (None, 443):
            raise ValueError("redirect_host")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def download(asset, destination):
    digest = hashlib.sha256()
    size = 0
    request = urllib.request.Request(asset["browser_download_url"], headers={"User-Agent": "codexbar-plasma"})
    with urllib.request.build_opener(AssetRedirect).open(request, timeout=20) as response, destination.open("xb") as stream:
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            size += len(chunk)
            if size > asset["size"]:
                raise ValueError("download_size")
            digest.update(chunk)
            stream.write(chunk)
    if size != asset["size"] or "sha256:" + digest.hexdigest() != asset["digest"]:
        raise ValueError("checksum")


class ExpandedArchive:
    """Bound decompressed headers and padding as well as extracted file bodies."""
    def __init__(self, stream):
        self.stream = stream
        self.total = 0

    def read(self, size):
        if size < 0 or size > MAX_EXPANDED + 1024 * 1024 - self.total:
            raise ValueError("archive_size")
        raw = self.stream.read(size)
        self.total += len(raw)
        return raw


def unpack(archive, destination):
    """Allow only the official executable, alias, VERSION and flat resource bundle."""
    seen = set()
    expanded = 0
    with gzip.open(archive, "rb") as compressed, \
            tarfile.open(fileobj=ExpandedArchive(compressed), mode="r|") as bundle:
        for member in bundle:
            name = member.name
            if len(seen) >= 256 or name in seen or len(name) > 200 \
                    or str(PurePosixPath(name)) != name:
                raise ValueError("archive_name")
            seen.add(name)
            is_resource = re.fullmatch(r"CodexBar_CodexBarCore\.bundle/[A-Za-z0-9_.-]+", name) is not None
            if name == "codexbar" and member.issym() and member.linkname == "CodexBarCLI":
                continue  # Create this single known alias ourselves after extraction.
            if name == "CodexBar_CodexBarCore.bundle" and member.isdir():
                (destination / name).mkdir(exist_ok=True)
                continue
            if not member.isfile() or not (name in ("CodexBarCLI", "VERSION") or is_resource):
                raise ValueError("archive_type")
            expanded += member.size
            if expanded > MAX_EXPANDED or member.size < 0 \
                    or (name == "VERSION" and member.size > 128) \
                    or (is_resource and member.size > 16 * 1024 * 1024):
                raise ValueError("archive_size")
            target = destination / name
            target.parent.mkdir(exist_ok=True)
            with bundle.extractfile(member) as source, target.open("xb") as output:
                shutil.copyfileobj(source, output, 1024 * 1024)
            target.chmod(0o700 if name == "CodexBarCLI" else 0o600)
    if not {"CodexBarCLI", "codexbar", "VERSION"}.issubset(seen):
        raise ValueError("archive_missing")
    (destination / "codexbar").symlink_to("CodexBarCLI")


def install(root, automatic=False):
    current = installed(root)
    state = state_record(root)
    now = time.time()
    last = state.get("lastAttempt", 0)
    if automatic and isinstance(last, (int, float)) and 0 <= now - last < 86400:
        return status(root)
    # Shared throttle also covers failures and concurrent widget instances.
    state["lastAttempt"] = now
    write_state(root, state)
    version, assets = release_assets(cli_release.latest_release(), platform_suffix())
    if current and tuple(map(int, version.split("."))) <= tuple(map(int, current["version"].split("."))):
        return status(root)
    if automatic and state.get("blockedVersion") == version:
        return status(root)
    with tempfile.TemporaryDirectory(prefix=".install-", dir=root) as staging:
        stage = Path(staging)
        archive, checksum = stage / "archive.tar.gz", stage / "archive.sha256"
        download(assets[0], archive)
        download(assets[1], checksum)
        expected = assets[0]["digest"][7:]
        if checksum.read_text().strip() not in (expected + "  " + assets[0]["name"], expected + " *" + assets[0]["name"]):
            raise ValueError("checksum_file")
        extracted = stage / "release"
        extracted.mkdir()
        unpack(archive, extracted)
        if (extracted / "VERSION").read_text().strip() not in (version, "v" + version):
            raise ValueError("version_file")
        home = stage / "probe-home"
        home.mkdir()
        code, banner = cli_release.bounded_command([str(extracted / "codexbar"), "--version"], seconds=10,
                                                   environment={"HOME": str(home), "PATH": "/usr/bin:/bin", "LC_ALL": "C",
                                                                "XDG_CONFIG_HOME": str(home), "XDG_CACHE_HOME": str(home)})
        if code != 0 or banner != "CodexBar " + version:
            raise ValueError("version_probe")
        (extracted / "receipt.json").write_text(json.dumps(dict(version=version, sha256=expected)))
        target = "releases/v" + version + "-" + expected[:16]
        if (root / target).exists():
            # Replace a retained copy only with freshly verified content, never the active copy.
            if not installed(root, target) or (current and target == current["target"]):
                raise ValueError("existing_release")
            os.rename(root / target, stage / "retained-release")
        os.rename(extracted, root / target)
        activate(root, target, state, current["target"] if current else "")
    return {**status(root), "status": "installed"}


def prune(root):
    """Keep current/previous releases and a seven-day grace period for running CLIs."""
    current = os.readlink(root / "current") if (root / "current").is_symlink() else ""
    state = state_record(root)
    keep = {current, state.get("previous", "")}
    now = time.time()
    for directory in (root / "releases").iterdir():
        target = "releases/" + directory.name
        if target not in keep and RELEASE_DIRECTORY.fullmatch(target) \
                and not directory.is_symlink() and directory.is_dir() \
                and now - directory.stat().st_mtime > 7 * 86400:
            shutil.rmtree(directory)
    for directory in root.glob(".install-*"):
        if not directory.is_symlink() and directory.is_dir() and now - directory.stat().st_mtime > 86400:
            shutil.rmtree(directory)


def run(action, command=""):
    root = root_path()
    if action == "status" or (action == "install" and installed(root)):
        # Selecting an existing private copy is local; only Update now needs GitHub.
        return status(root)
    if action in ("update", "automatic", "rollback") and not owns_command(command):
        return {"status": "external"}
    private_directory(root)
    private_directory(root / "releases")
    descriptor = os.open(root / ".lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return {"status": "busy"}
        try:
            prune(root)
        except OSError:
            pass  # A failed cleanup must not prevent a retry or rollback.
        if action == "rollback":
            state = state_record(root)
            previous = installed(root, state.get("previous", ""))
            current = installed(root)
            if not previous or not current:
                return {"status": "no_previous"}
            activate(root, previous["target"], state, current["target"], current["version"])
            return {**status(root), "status": "restored"}
        result = install(root, automatic=action == "automatic")
        try:
            prune(root)
        except OSError:
            pass  # Cleanup cannot invalidate a completed atomic activation.
        return result
