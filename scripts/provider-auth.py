#!/usr/bin/env python3
"""Adapt official CLI credential commands to bounded, private Plasma prompts.

No authentication or config parsing lives here. The CLI owns both. Device
events stay in memory; only a semantic completion reaches the executable engine.
"""
import argparse
import json
import os
import re
import selectors
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from urllib.parse import urlsplit

MAX_BYTES = 65536
LOGIN_SECONDS = 900


class RequestInterrupted(Exception):
    pass


def cancellation_path(request):
    """Private, credential-free tombstones also cover cancellation before startup."""
    if not re.fullmatch(r"[a-f0-9]{20,100}", request):
        raise ValueError
    directory = Path(tempfile.gettempdir()) / f"codexbar-plasma-login-{os.getuid()}"
    directory.mkdir(mode=0o700, exist_ok=True)
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError
    for entry in directory.iterdir():
        if re.fullmatch(r"[a-f0-9]{20,100}", entry.name):
            try:
                if time.time() - entry.lstat().st_mtime > 1200:
                    entry.unlink()
            except FileNotFoundError:
                pass
    return directory / request


def cancel_login(request):
    path = cancellation_path(request)
    try:
        descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        pass
    else:
        os.close(descriptor)
    return {"status": "cancelled"}


def pending_event(event):
    """Project a released pending event; discard all unknown fields."""
    uri, code, expiry = (event.get(key) for key in ("verificationURI", "userCode", "expiresIn"))
    if not isinstance(uri, str) or len(uri) > 2048 or re.search(r"[\s\x00-\x1f\x7f]", uri):
        raise ValueError
    parsed = urlsplit(uri)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
            or not re.fullmatch(r"[A-Za-z0-9.-]+", parsed.hostname)
            or parsed.port not in (None, 443) or parsed.path != "/login/device"
            or parsed.query or parsed.fragment):
        raise ValueError
    if not isinstance(code, str) or not re.fullmatch(r"[A-Z0-9]{4}-[A-Z0-9]{4}", code):
        raise ValueError
    if type(expiry) is not int or not 1 <= expiry <= LOGIN_SECONDS:
        raise ValueError
    return uri, code, expiry


def login_event(pending, terminal, event):
    """Classify one CLI event without changing login state or performing effects."""
    if not isinstance(event, dict) or terminal is not None:
        return {"kind": "invalid"}
    status = event.get("status")
    if status == "authorization_pending" and not pending:
        return {"kind": "pending", "prompt": pending_event(event)}
    if status == "authorized" and pending:
        return {"kind": "terminal", "status": "ok"}
    if status == "failed":
        conflict = event.get("error") == "Config changed during login. Please try again."
        return {"kind": "terminal", "status": "conflict" if conflict else "failed"}
    return {"kind": "invalid"}


class LoginStream:
    """Bound the entire stream and yield complete JSON lines in receipt order."""

    def __init__(self):
        self.output = bytearray()
        self.total = 0

    def feed(self, block):
        self.total += len(block)
        if self.total > MAX_BYTES:
            raise ValueError
        self.output.extend(block)
        while b"\n" in self.output:
            line, _, self.output = self.output.partition(b"\n")
            yield json.loads(line)

    def incomplete(self):
        return bool(self.output.strip())


def login_dialog(title, message, prompt):
    uri, code, expiry = prompt
    # Explicit stdin keeps the URI/code out of argv, files and the engine cache.
    dialog = spawn(["kdialog", "--title", title, "--textbox", "-", "520", "300"],
                   stdin=subprocess.PIPE, stdout=subprocess.DEVNULL)
    try:
        text = message.replace("%1", uri).replace("%2", code).replace("%3", str(expiry))
        dialog.stdin.write(text.encode("utf-8"))
        dialog.stdin.close()
    except BaseException:
        stop(dialog)
        raise
    return dialog


def stop(process, group=True):
    if process is None:
        return
    # Also stop descendants after their immediate parent has already exited.
    try:
        if group:
            os.killpg(process.pid, signal.SIGTERM)
        else:
            process.terminate()
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=1)
    except subprocess.TimeoutExpired:
        pass
    try:
        if group:
            os.killpg(process.pid, signal.SIGKILL)
        else:
            process.kill()
    except ProcessLookupError:
        pass
    process.wait()
    for stream in (process.stdin, process.stdout):
        if stream is not None:
            stream.close()


def spawn(arguments, **kwargs):
    kwargs.setdefault("start_new_session", True)
    return subprocess.Popen(arguments, stderr=subprocess.DEVNULL, **kwargs)


def session_import_result(output, exit_code):
    """Console import emits one terminal event, without a device-code phase."""
    event = json.loads(output)
    if not isinstance(event, dict):
        return {"status": "failed"}
    if event.get("status") == "authorized":
        valid = exit_code == 0 and "error" not in event
        return {"status": "ok" if valid else "failed"}
    if event.get("status") == "failed" and exit_code != 0:
        if event.get("error") == "Config changed during login. Please try again.":
            return {"status": "conflict"}
    return {"status": "failed"}


def credential_arguments(cli, action, provider):
    """Choose the released writer and its input/output contract."""
    if action == "import-session":
        if provider != "claudeplatform":
            raise ValueError
        arguments = [cli, "config", "login", "--provider", provider, "--json"]
    else:
        arguments = [cli, "config", action, "--provider", provider, "--format", "json", "--json-only"]
    if action in ("set-cookie", "import-session"):
        arguments.append("--stdin")
    return arguments


def credential_result(output, exit_code, provider, action):
    """Discard private CLI details and require the writer's terminal contract."""
    if action == "import-session":
        return session_import_result(output, exit_code)
    if exit_code != 0:
        return {"status": "failed"}
    result = json.loads(output)
    if not isinstance(result, dict):
        return {"status": "failed"}
    if result.get("provider") != provider:
        return {"status": "failed"}
    if "error" in result:
        return {"status": "failed"}
    return stored_credential_result(result, action)


def stored_credential_result(result, action):
    """Validate the provider-matched cookie or clear result without its private fields."""
    if action == "set-cookie":
        if type(result.get("enabled")) is bool:
            return {"status": "ok", "enabled": result["enabled"]}
        return {"status": "failed"}
    if action != "clear-credential":
        return {"status": "failed"}
    cleared = result.get("cleared")
    if not isinstance(cleared, list):
        return {"status": "failed"}
    if any(item not in ("apiKey", "cookieHeader") for item in cleared):
        return {"status": "failed"}
    return {"status": "ok"}


def credential(cli, action, provider):
    parent = os.getppid()
    secret_input = action in ("set-cookie", "import-session")
    value = sys.stdin.buffer.read(MAX_BYTES + 1) if secret_input else b""
    if secret_input and (not value.strip() or len(value) > MAX_BYTES):
        return {"status": "failed"}
    arguments = credential_arguments(cli, action, provider)
    process = spawn(arguments, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    try:
        # Drain bounded output while feeding stdin; neither pipe may block
        # the other, including a CLI that refuses before reading the cookie.
        os.set_blocking(process.stdin.fileno(), False)
        os.set_blocking(process.stdout.fileno(), False)
        output, offset = bytearray(), 0
        deadline = time.monotonic() + 55
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            selector.register(process.stdin, selectors.EVENT_WRITE)
            # Keep watching the owner even after stdout closes: a wrapper may
            # still be running, or leave a descendant holding the output pipe.
            while selector.get_map() or process.poll() is None:
                if os.getppid() != parent or time.monotonic() >= deadline:
                    return {"status": "failed"}
                for key, _mask in selector.select(0.1):
                    if key.fileobj is process.stdin:
                        if offset < len(value):
                            try:
                                offset += os.write(process.stdin.fileno(), value[offset:])
                            except BrokenPipeError:
                                offset = len(value)
                        if offset == len(value):
                            selector.unregister(process.stdin)
                            process.stdin.close()
                    else:
                        block = os.read(process.stdout.fileno(), 4096)
                        if not block:
                            selector.unregister(process.stdout)
                        output.extend(block)
                        if len(output) > MAX_BYTES:
                            return {"status": "failed"}
        return credential_result(output, process.returncode, provider, action)
    finally:
        stop(process)


def login(cli, title, message, supervised, request=""):
    cancellation = cancellation_path(request) if request else None
    parent = os.getppid()
    if not shutil.which("kdialog"):
        return {"status": "unavailable"}
    if supervised and (parent <= 1 or os.getpgrp() != parent):
        return {"status": "unavailable"}
    cancelled = False

    def on_signal(_signum, _frame):
        nonlocal cancelled
        cancelled = True

    old_handlers = {sig: signal.signal(sig, on_signal) for sig in (signal.SIGTERM, signal.SIGINT)}
    process, dialog = None, None
    try:
        if cancellation is not None and cancellation.exists():
            return {"status": "cancelled"}
        process = spawn([cli, "config", "login", "--provider", "copilot", "--json"],
                        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE)
        os.set_blocking(process.stdout.fileno(), False)
        deadline = time.monotonic() + 60
        pending, terminal = False, None
        stream = LoginStream()
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            eof = False
            while not eof or process.poll() is None:
                if (cancelled or (cancellation is not None and cancellation.exists())
                        or (supervised and os.getppid() != parent)):
                    return {"status": "cancelled"}
                if dialog is not None and dialog.poll() is not None:
                    dialog_status = dialog.returncode
                    stop(dialog)
                    dialog = None
                    if dialog_status != 0:
                        return {"status": "cancelled" if dialog_status == 1 else "failed"}
                if time.monotonic() >= deadline:
                    return {"status": "expired" if pending and terminal is None else "failed"}
                for _key, _mask in selector.select(0.1):
                    block = os.read(process.stdout.fileno(), 4096)
                    if not block:
                        eof = True
                        selector.unregister(process.stdout)
                        break
                    for event in stream.feed(block):
                        decision = login_event(pending, terminal, event)
                        if decision["kind"] == "pending":
                            pending = True
                            deadline = time.monotonic() + decision["prompt"][2]
                            dialog = login_dialog(title, message, decision["prompt"])
                        elif decision["kind"] == "terminal":
                            terminal = decision["status"]
                            stop(dialog)
                            dialog = None
                            deadline = time.monotonic() + 5
                        else:
                            return {"status": "failed"}
        if stream.incomplete() or terminal is None or (terminal == "ok" and process.returncode != 0):
            return {"status": "failed"}
        return {"status": terminal}
    finally:
        stop(dialog)
        stop(process)
        if cancellation is not None:
            cancellation.unlink(missing_ok=True)
        for sig, handler in old_handlers.items():
            signal.signal(sig, handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", required=True)
    parser.add_argument("--action", choices=("set-cookie", "clear-credential", "login", "cancel-login", "import-session"), required=True)
    parser.add_argument("--provider", required=True)
    parser.add_argument("--title", default="")
    parser.add_argument("--message", default="")
    parser.add_argument("--supervised", action="store_true")
    parser.add_argument("--request", default="")
    args = parser.parse_args()

    def interrupt(_signum, _frame):
        # selectors.select() catches InterruptedError internally. Use a
        # distinct exception so cancellation reaches process-group cleanup.
        # Repeated timeout/group signals must not interrupt that cleanup.
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        raise RequestInterrupted

    signal.signal(signal.SIGTERM, interrupt)
    signal.signal(signal.SIGINT, interrupt)
    result = {"status": "failed"}
    try:
        if args.action == "cancel-login":
            if args.provider == "copilot":
                result = cancel_login(args.request)
        elif args.action == "login":
            if args.provider == "copilot":
                result = login(args.cli, args.title, args.message, args.supervised, args.request)
        else:
            result = credential(args.cli, args.action, args.provider)
    except (OSError, ValueError, UnicodeError, subprocess.TimeoutExpired, RequestInterrupted):
        pass
    # No raw CLI error, URI, user code, credential or config path is returned.
    print(json.dumps({**result, "provider": args.provider}))


if __name__ == "__main__":
    main()
