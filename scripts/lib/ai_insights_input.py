"""One-use private files for the QML-to-helper AI usage snapshot handoff."""
import configparser
import os
from pathlib import Path
import re
import stat
import tempfile
import time
import uuid

MAX_BYTES = 16 * 1024
MAX_FILE_BYTES = MAX_BYTES * 2 + 128
MAX_AGE = 300


def input_root():
    return Path(tempfile.gettempdir()) / f"codexbar-plasma-ai-{os.getuid()}"


def private_directory(path):
    path.mkdir(mode=0o700, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError("unsafe_input_directory")


def request_directory(request):
    if not isinstance(request, str) or not re.fullmatch(r"[a-f0-9]{32}", request):
        raise ValueError("invalid_input_request")
    root = input_root()
    private_directory(root)
    directory = root / request
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError("unsafe_input_directory")
    return directory


def discard(request):
    try:
        directory = request_directory(request)
    except FileNotFoundError:
        return
    # Never recursively remove a directory or follow a payload symlink.
    (directory / "payload.ini").unlink(missing_ok=True)
    directory.rmdir()


def prepare():
    root = input_root()
    private_directory(root)
    # A killed preparation may leave an empty file; a crash after writing may
    # leave data. Only expired, validated requests in this private root qualify.
    for entry in root.iterdir():
        if re.fullmatch(r"[a-f0-9]{32}", entry.name):
            try:
                if time.time() - entry.lstat().st_mtime > MAX_AGE:
                    discard(entry.name)
            except (OSError, ValueError):
                pass
    request = uuid.uuid4().hex
    directory = root / request
    directory.mkdir(mode=0o700)
    path = directory / "payload.ini"
    descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
    os.close(descriptor)
    return {"status": "ready", "request": request, "path": str(path)}


def consume(request):
    directory = request_directory(request)
    try:
        if not 0 <= time.time() - directory.stat().st_mtime <= MAX_AGE:
            raise ValueError("expired_input")
        descriptor = os.open(directory / "payload.ini", os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(descriptor, "rb") as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() \
                    or info.st_mode & 0o077 or info.st_nlink != 1 or info.st_size > MAX_FILE_BYTES:
                raise ValueError("unsafe_input_file")
            raw = stream.read(MAX_FILE_BYTES + 1)
        if len(raw) > MAX_FILE_BYTES:
            raise ValueError("input_size")
        config = configparser.ConfigParser(interpolation=None)
        try:
            config.read_string(raw.decode("ascii"))
            encoded = config.get("General", "snapshot", raw=True)
        except configparser.Error:
            raise ValueError("invalid_input_file") from None
        if not re.fullmatch(r"(?:[0-9a-f]{2})+", encoded):
            raise ValueError("invalid_input_file")
        snapshot = bytes.fromhex(encoded)
        if not snapshot or len(snapshot) > MAX_BYTES:
            raise ValueError("input_size")
        return snapshot.decode("utf-8")
    finally:
        discard(request)
