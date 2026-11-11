"""Private, checksum-verified Linux CLI installations. Never modify external CLIs."""
import fcntl
import hashlib
import gzip
import http.client
import json
import math
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import stat
import subprocess
import tarfile
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

from . import cli_release

MAX_ARCHIVE = 160 * 1024 * 1024
MAX_EXPANDED = 600 * 1024 * 1024
MAX_NOTICE = 16 * 1024 * 1024
RELEASE_DIRECTORY = re.compile(r"releases/v" + cli_release.VERSION + r"-[a-f0-9]{16}")
DOWNLOAD_PREFIX = "https://github.com/steipete/CodexBar/releases/download/"
# A refused download and an unreachable server need different answers, so the
# helper reports which one happened. Repeated refusals are a tampering signal,
# not ordinary network noise, and an unsupported system never becomes ready.
UNVERIFIED = frozenset(("archive_missing", "archive_name", "archive_size", "archive_type",
                        "asset_shape", "assets", "checksum", "checksum_file", "download_size",
                        "redirect_host", "version_file", "version_probe"))
UNSUPPORTED = frozenset(("asset_missing", "unsupported_platform"))


def root_path():
    data = os.environ.get("XDG_DATA_HOME", "")
    base = Path(data) if data.startswith("/") else Path.home() / ".local/share"
    return Path(os.path.realpath(base)) / "codexbar-plasma/cli"


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


def _receipt_version(receipt, target):
    version = receipt.get("version", "")
    digest = receipt.get("sha256", "")
    if not isinstance(version, str) or not re.fullmatch(cli_release.VERSION, version):
        return None
    if not isinstance(digest, str) or not re.fullmatch(r"[a-f0-9]{64}", digest):
        return None
    return version if target == "releases/v" + version + "-" + digest[:16] else None


def _installed_binary(directory):
    return ((directory / "CodexBarCLI").is_file()
            and not (directory / "CodexBarCLI").is_symlink()
            and os.readlink(directory / "codexbar") == "CodexBarCLI")


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
        version = _receipt_version(read_json(directory / "receipt.json"), target)
        if version is None or not _installed_binary(directory):
            return None
        return dict(version=version, target=target)
    except (OSError, ValueError, TypeError):
        return None


def owns_command(command):
    root = root_path()
    # Probes report canonical paths, so symlinked directory prefixes (the
    # managed `current` link, /bin vs /usr/bin) must resolve before comparing.
    # The entry-point filename still has to match: a differently named file in
    # one release directory is not the managed command.
    if not isinstance(command, str) or not command:
        return False
    return os.path.basename(command) == "codexbar" \
        and os.path.realpath(command) == os.path.realpath(root / "current/codexbar") \
        and installed(root) is not None


def _validate_state_fields(record, keys, error):
    for key in keys:
        value = record.get(key, "")
        pattern = re.compile(cli_release.VERSION) if key == "blockedVersion" else RELEASE_DIRECTORY
        if not isinstance(value, str) or (value and not pattern.fullmatch(value)):
            raise ValueError(error)


def _validate_attempt_time(last_attempt):
    try:
        valid_time = type(last_attempt) in (int, float) and math.isfinite(last_attempt)
    except OverflowError:
        valid_time = False
    if not valid_time:
        raise ValueError("state_time")


def _recover_activation(root, state, activation):
    if not isinstance(activation, dict):
        raise ValueError("activation_shape")
    _validate_state_fields(activation, ("target", "before", "previous", "blockedVersion"), "activation_field")
    current = os.readlink(root / "current") if (root / "current").is_symlink() else ""
    if current == activation.get("target"):
        return
    if current != activation.get("before"):
        raise ValueError("activation_state")
    # A crash before the atomic switch must not discard the earlier rollback target.
    state["previous"] = activation.get("previous", "")
    state["blockedVersion"] = activation.get("blockedVersion", "")


def state_record(root):
    try:
        state = read_json(root / "state.json")
    except FileNotFoundError:
        return {}
    _validate_state_fields(state, ("previous", "blockedVersion"), "state_field")
    _validate_attempt_time(state.get("lastAttempt", 0))
    activation = state.pop("activation", None)
    if activation is not None:
        _recover_activation(root, state, activation)
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


def _release_asset(assets, tag, expected, maximum):
    matches = [asset for asset in assets if isinstance(asset, dict) and asset.get("name") == expected]
    if len(matches) != 1:
        raise ValueError("asset_missing")
    asset = matches[0]
    if asset.get("browser_download_url") != DOWNLOAD_PREFIX + tag + "/" + expected:
        raise ValueError("asset_shape")
    if type(asset.get("size")) is not int or not 0 < asset["size"] <= maximum:
        raise ValueError("asset_shape")
    if not isinstance(asset.get("digest"), str) or not re.fullmatch(r"sha256:[a-f0-9]{64}", asset["digest"]):
        raise ValueError("asset_shape")
    return asset


def release_assets(release, suffix):
    record = cli_release.compare_release({"version": ""}, release)
    tag = record["tag"]
    name = "CodexBarCLI-" + tag + "-" + suffix + ".tar.gz"
    assets = release.get("assets")
    if not isinstance(assets, list) or len(assets) > 100:
        raise ValueError("assets")
    selected = [_release_asset(assets, tag, expected, maximum)
                for expected, maximum in ((name, MAX_ARCHIVE), (name + ".sha256", 4096))]
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
    if size < asset["size"]:
        # A body cut short is a dropped connection, not refused content.
        raise ConnectionError("download_incomplete")
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


def _validate_archive_name(name, seen):
    if len(seen) >= 256 or name in seen or len(name) > 200 \
            or str(PurePosixPath(name)) != name or ".." in PurePosixPath(name).parts:
        raise ValueError("archive_name")


def _validate_archive_file(member, expanded):
    if not member.isfile():
        raise ValueError("archive_type")
    limits = {"CodexBarCLI": MAX_EXPANDED, "VERSION": 128, "THIRD_PARTY_NOTICES": MAX_NOTICE}
    is_resource = re.fullmatch(r"CodexBar_CodexBarCore\.bundle/[A-Za-z0-9_.-]+", member.name) is not None
    maximum = 16 * 1024 * 1024 if is_resource else limits.get(member.name)
    if maximum is None:
        raise ValueError("archive_type")
    expanded += member.size
    if not 0 <= member.size <= maximum or expanded > MAX_EXPANDED:
        raise ValueError("archive_size")
    return expanded


def _extract_archive_member(bundle, member, destination, expanded):
    name = member.name
    if name == "codexbar" and member.issym() and member.linkname == "CodexBarCLI":
        return expanded  # Create this single known alias ourselves after extraction.
    if name == "CodexBar_CodexBarCore.bundle" and member.isdir():
        (destination / name).mkdir(exist_ok=True)
        return expanded
    expanded = _validate_archive_file(member, expanded)
    target = destination / name
    target.parent.mkdir(exist_ok=True)
    with bundle.extractfile(member) as source, target.open("xb") as output:
        shutil.copyfileobj(source, output, 1024 * 1024)
    target.chmod(0o700 if name == "CodexBarCLI" else 0o600)
    return expanded


def unpack(archive, destination):
    """Allow only the official executable, alias, metadata and flat resource bundle."""
    seen = set()
    expanded = 0
    with gzip.open(archive, "rb") as compressed, \
            tarfile.open(fileobj=ExpandedArchive(compressed), mode="r|") as bundle:
        for member in bundle:
            _validate_archive_name(member.name, seen)
            seen.add(member.name)
            expanded = _extract_archive_member(bundle, member, destination, expanded)
    if not {"CodexBarCLI", "codexbar", "VERSION"}.issubset(seen):
        raise ValueError("archive_missing")
    (destination / "codexbar").symlink_to("CodexBarCLI")


def probe_version(command, version, home):
    try:
        code, banner = cli_release.bounded_command([str(command), "--version"], seconds=10,
                                                 environment={"HOME": str(home), "PATH": "/usr/bin:/bin", "LC_ALL": "C",
                                                              "XDG_CONFIG_HOME": str(home), "XDG_CACHE_HOME": str(home)})
        return code == 0 and banner == "CodexBar " + version
    except (OSError, ValueError, subprocess.SubprocessError):
        return False


def _require_release_text(path, accepted, error):
    try:
        value = path.read_text()
    except UnicodeDecodeError:
        raise ValueError(error) from None
    if value.strip() not in accepted:
        raise ValueError(error)


def _prepare_release(stage, version, assets):
    archive, checksum = stage / "archive.tar.gz", stage / "archive.sha256"
    download(assets[0], archive)
    download(assets[1], checksum)
    expected = assets[0]["digest"][7:]
    _require_release_text(checksum, (expected + "  " + assets[0]["name"], expected + " *" + assets[0]["name"]),
                          "checksum_file")
    extracted = stage / "release"
    extracted.mkdir()
    unpack(archive, extracted)
    _require_release_text(extracted / "VERSION", (version, "v" + version), "version_file")
    home = stage / "probe-home"
    home.mkdir()
    if not probe_version(extracted / "codexbar", version, home):
        raise ValueError("version_probe")
    (extracted / "receipt.json").write_text(json.dumps(dict(version=version, sha256=expected)))
    return extracted, "releases/v" + version + "-" + expected[:16]


def _replace_release(root, target, extracted, current_target):
    retained = None
    if (root / target).exists():
        # Replace a retained copy only with freshly verified content, never the active copy.
        if not installed(root, target) or target == current_target:
            raise ValueError("existing_release")
        # Keep recovery outside staging: even a failed restore must survive
        # TemporaryDirectory cleanup for manual recovery.
        retained = root / (".retained-" + uuid.uuid4().hex)
        os.rename(root / target, retained)
    try:
        os.rename(extracted, root / target)
    except OSError:
        if retained is not None:
            os.rename(retained, root / target)
        raise
    if retained is not None:
        try:
            shutil.rmtree(retained)
        except OSError:
            pass  # The verified replacement is already in place.


def install(root, automatic=False):
    current = installed(root)
    state = state_record(root)
    now = time.time()
    last = state.get("lastAttempt", 0)
    if automatic and 0 <= now - last < 86400:
        return status(root)
    # Shared throttle also covers failures and concurrent widget instances.
    state["lastAttempt"] = now
    write_state(root, state)
    # Reject an unsupported system before spending a request on the release API.
    suffix = platform_suffix()
    version, assets = release_assets(cli_release.latest_release(), suffix)
    if current and tuple(map(int, version.split("."))) <= tuple(map(int, current["version"].split("."))):
        return status(root)
    if automatic and state.get("blockedVersion") == version:
        return status(root)
    current_target = current["target"] if current else ""
    with tempfile.TemporaryDirectory(prefix=".install-", dir=root) as staging:
        extracted, target = _prepare_release(Path(staging), version, assets)
        _replace_release(root, target, extracted, current_target)
        activate(root, target, state, current_target)
    return {**status(root), "status": "installed"}


def prune(root):
    """Keep current/previous releases; others get a one-hour grace period for running CLIs.

    Widget-started CLI processes are bounded well below an hour, and upstream ships
    near-daily ~170 MB builds, so a longer grace only accumulates stale copies.
    """
    current = os.readlink(root / "current") if (root / "current").is_symlink() else ""
    state = state_record(root)
    keep = {current, state.get("previous", "")}
    now = time.time()
    for directory in (root / "releases").iterdir():
        target = "releases/" + directory.name
        if target not in keep and RELEASE_DIRECTORY.fullmatch(target) \
                and not directory.is_symlink() and directory.is_dir() \
                and now - directory.stat().st_mtime > 3600:
            shutil.rmtree(directory)
    for directory in root.glob(".install-*"):
        if not directory.is_symlink() and directory.is_dir() and now - directory.stat().st_mtime > 86400:
            shutil.rmtree(directory)


def failure_status(error):
    """Name a failure without leaking paths, remote prose or local detail."""
    if isinstance(error, tarfile.TarError):
        # The digest already matched, so a broken archive is still content we refuse.
        return "unverified"
    # urllib wraps only connection setup; a timeout or disconnect while waiting
    # for or reading the response surfaces as the underlying error.
    if isinstance(error, (urllib.error.URLError, http.client.HTTPException, TimeoutError, ConnectionError)):
        return "network"
    code = str(error) if isinstance(error, ValueError) else ""
    if code in UNVERIFIED:
        return "unverified"
    if code in UNSUPPORTED:
        return "unsupported"
    return "error"


def _probe_installed_release(root, release):
    with tempfile.TemporaryDirectory(prefix="codexbar-cli-probe-") as home:
        return probe_version(root / release["target"] / "codexbar", release["version"], home)


def _reuse_installation(root):
    current = installed(root)
    if not current:
        return None
    if not _probe_installed_release(root, current):
        return {"status": "unusable"}
    return status(root)


def _rollback(root, expected_previous):
    state = state_record(root)
    previous = installed(root, state.get("previous", ""))
    current = installed(root)
    if not previous or not current:
        return {"status": "no_previous"}
    if expected_previous != previous["version"]:
        return {**status(root), "status": "stale"}
    if not _probe_installed_release(root, previous):
        return {"status": "no_previous"}
    activate(root, previous["target"], state, current["target"], current["version"])
    _prune_if_possible(root)
    return {**status(root), "status": "restored"}


def _prune_if_possible(root):
    try:
        prune(root)
    except OSError:
        pass  # Cleanup must not prevent retry/rollback or invalidate a completed activation.


def _run_locked(root, action, expected_previous):
    """Execute a mutating action while the shared installation lock is held."""
    if action == "rollback":
        return _rollback(root, expected_previous)
    _prune_if_possible(root)
    result = install(root, automatic=action == "automatic")
    _prune_if_possible(root)
    return result


def run(action, command="", expected_previous=""):
    root = root_path()
    if action == "status":
        return status(root)
    if action == "install":
        reused = _reuse_installation(root)
        if reused is not None:
            return reused
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
        return _run_locked(root, action, expected_previous)
