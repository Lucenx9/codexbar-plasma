#!/usr/bin/env python3
"""Read the selected CLI's version/owner and optionally the latest upstream release.

Never install packages or alter the selected executable. All output is a bounded
semantic record; command errors and remote prose are deliberately omitted.
"""
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import subprocess
import time
import urllib.request

RELEASE_API = "https://api.github.com/repos/steipete/CodexBar/releases/latest"
RELEASE_PREFIX = "https://github.com/steipete/CodexBar/releases/tag/"
VERSION = r"(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})"


def bounded_command(argv, seconds=3, environment=None):
    """Drain a bounded pipe with a deadline, including children holding it open."""
    with subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          start_new_session=True, env=environment if environment is not None else {**os.environ, "LC_ALL": "C"}) as process:
        output = bytearray()
        deadline = time.monotonic() + seconds
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                while True:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0 or not selector.select(remaining):
                        raise ValueError("command_timeout")
                    chunk = os.read(process.stdout.fileno(), 4096)
                    if not chunk:
                        break
                    output.extend(chunk)
                    if len(output) > 16384:
                        raise ValueError("command_output")
            code = process.wait(timeout=max(0.01, deadline - time.monotonic()))
            return code, output.decode("utf-8", errors="replace").strip()
        finally:
            # Also retire any descendants of a wrapper after collecting its banner.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def installation_manager(path):
    from lib.managed_cli import owns_command
    if owns_command(path):
        return "managed"
    # Inspect both the launcher and its symlink target. A positive ownership
    # query is evidence of a package manager, never evidence of an AUR origin.
    paths = list(dict.fromkeys([path, os.path.realpath(path)]))
    for manager, argv in (
        ("pacman", ["pacman", "-Qqo"]),
        ("dpkg", ["dpkg-query", "-S"]),
        ("rpm", ["rpm", "-qf", "--qf", "%{NAME}"]),
        ("apk", ["apk", "info", "--who-owns"]),
    ):
        executable = shutil.which(argv[0])
        if not executable:
            continue
        for candidate in paths:
            try:
                code, output = bounded_command([executable, *argv[1:], candidate])
                if code == 0 and output:
                    return manager
            except (OSError, ValueError, subprocess.SubprocessError):
                pass
    # Do not label an arbitrary user path as a manual download or a source build.
    # Homebrew's own formula prefix plus its installed receipt establishes origin.
    brew = shutil.which("brew")
    if brew:
        try:
            code, prefix = bounded_command([brew, "--prefix", "codexbar"])
            real_path = Path(os.path.realpath(path))
            formula = Path(prefix).resolve()
            if code == 0 and prefix.startswith("/") and real_path.is_relative_to(formula) \
                    and (formula / "INSTALL_RECEIPT.json").is_file():
                return "homebrew"
        except (OSError, ValueError, subprocess.SubprocessError):
            pass
    return "external"


def local_record(command):
    record = {"status": "missing", "version": "", "path": "", "manager": "external",
              "latest": "", "tag": ""}
    if not command or len(command) > 4096 or any(ord(c) < 32 for c in command):
        return record
    path = shutil.which(command)
    if not path:
        return record
    path = os.path.abspath(path)
    if len(path) > 4096 or any(ord(c) < 32 for c in path):
        return record
    record["path"] = path
    record["manager"] = installation_manager(path)
    try:
        code, banner = bounded_command([path, "--version"], seconds=5)
        match = re.fullmatch(r"CodexBar (" + VERSION + r"(?:[-+][0-9A-Za-z.-]{1,64})?)", banner)
        if code == 0 and match:
            record.update(status="local", version=match[1])
        else:
            record["status"] = "unknown"
    except (OSError, ValueError, subprocess.SubprocessError):
        record["status"] = "unknown"
    return record


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def latest_release():
    request = urllib.request.Request(RELEASE_API, headers={
        "Accept": "application/vnd.github+json", "User-Agent": "codexbar-plasma",
        "X-GitHub-Api-Version": "2022-11-28",
    })
    with urllib.request.build_opener(NoRedirect).open(request, timeout=10) as response:
        raw = response.read(1024 * 1024 + 1)
    if len(raw) > 1024 * 1024:
        raise ValueError("release_size")
    return json.loads(raw)


def compare_release(record, release):
    if not isinstance(release, dict) or release.get("draft") is not False \
            or release.get("prerelease") is not False:
        raise ValueError("release_shape")
    tag = release.get("tag_name")
    if not isinstance(tag, str) or not re.fullmatch("v" + VERSION, tag) \
            or release.get("html_url") != RELEASE_PREFIX + tag:
        raise ValueError("release_tag")
    latest = tag[1:]
    record.update(latest=latest, tag=tag)
    if re.fullmatch(VERSION, record["version"]):
        installed_parts = tuple(map(int, record["version"].split(".")))
        latest_parts = tuple(map(int, latest.split(".")))
        record["status"] = "available" if latest_parts > installed_parts else "current"
    else:
        record["status"] = "uncomparable"
    return record


def check(command, local_only=False):
    record = local_record(command)
    if local_only or record["status"] == "missing":
        return record
    try:
        return compare_release(record, latest_release())
    except (OSError, ValueError):
        record["status"] = "network_error"
        return record
