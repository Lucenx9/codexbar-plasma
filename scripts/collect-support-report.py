#!/usr/bin/env python3
"""Collect allowlisted, offline support facts; never emit command diagnostics."""
import argparse
import json
import os
import re
import shutil
import subprocess
from lib.cli_release import bounded_command, local_record


def output(argv, seconds=3):
    try:
        code, text = bounded_command(argv, seconds=seconds)
        return text if code == 0 else ""
    except (OSError, ValueError, subprocess.SubprocessError):
        return ""


def version(text, pattern):
    match = re.search(pattern + r"\s*([0-9]{1,6}\.[0-9]{1,6}(?:\.[0-9]{1,6})?)\b", text)
    return match[1] if match else ""


def environment_record():
    # kinfo is optional. Its other fields (hostname, hardware, user/session
    # details) never leave this process. Version probes require no display.
    environment = {**os.environ, "LC_ALL": "C", "QT_QPA_PLATFORM": "offscreen"}
    try:
        code, info = bounded_command(["kinfo"], environment=environment)
        info = info if code == 0 else ""
    except (OSError, ValueError, subprocess.SubprocessError):
        info = ""
    plasma = version(info, r"KDE Plasma Version:")
    frameworks = version(info, r"KDE Frameworks Version:")
    qt = version(info, r"Qt Version:")
    if not plasma:
        # Do not launch another plasmashell for a support probe: its startup can
        # fail before argument parsing on headless/broken desktop sessions.
        package = output(["dpkg-query", "-W", "-f=${Version}", "plasma-workspace"])
        plasma = version(package, r"^(?:[0-9]+:)?")
    if not frameworks:
        package = output(["dpkg-query", "-W", "-f=${Version}", "libkf6coreaddons6"])
        frameworks = version(package, r"^(?:[0-9]+:)?")
    if not frameworks:
        frameworks = version(output(["kf6-config", "--version"]), r"KDE Frameworks:")
    if not qt:
        for tool in ("qtpaths6", "qtpaths-qt6", "qtpaths"):
            banner = output([tool, "--qt-version"])
            if re.fullmatch(r"6\.[0-9]{1,6}\.[0-9]{1,6}", banner):
                qt = banner
                break
    return {"plasma": plasma, "frameworks": frameworks, "qt": qt}


def provider_record(command):
    # This released CLI interface lists enablement only. No config dump,
    # descriptors, account discovery, authentication or quota requests.
    raw = output([command, "config", "providers", "--format", "json", "--json-only"], seconds=5)
    try:
        payload = json.loads(raw)
    except (ValueError, TypeError):
        return {"status": "unavailable", "enabled": []}
    if not isinstance(payload, list) or len(payload) > 256:
        return {"status": "unavailable", "enabled": []}
    enabled = []
    for item in payload:
        if not isinstance(item, dict) or not isinstance(item.get("enabled"), bool) \
                or not isinstance(item.get("provider"), str) \
                or not re.fullmatch(r"[a-z][a-z0-9_-]{0,127}", item["provider"]) \
                or item["provider"] in ("prototype", "constructor"):
            return {"status": "unavailable", "enabled": []}
        if item["enabled"] and item["provider"] not in enabled:
            enabled.append(item["provider"])
    return {"status": "checked", "enabled": enabled}


def collect(command):
    selected = local_record(command)
    system = selected if command == "codexbar" else local_record("codexbar")
    return {"environment": environment_record(), "selected": selected, "system": system,
            "providers": provider_record(selected["path"]) if selected["path"] else {
                "status": "unavailable", "enabled": []},
            "tools": {tool: bool(shutil.which(tool)) for tool in (
                "python3", "timeout", "kpackagetool6", "notify-send", "curl", "jq", "sha256sum", "flock")}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--command", required=True)
    args = parser.parse_args()
    print(json.dumps(collect(args.command)))


if __name__ == "__main__":
    main()
