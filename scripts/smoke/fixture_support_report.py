#!/usr/bin/env python3
"""Synthetic support facts; never inspect a real desktop or run a CLI."""
import json

print(json.dumps({
    "environment": {"plasma": "6.5.0", "frameworks": "6.19.0", "qt": "6.9.2"},
    "selected": {"status": "local", "version": "0.73.0", "manager": "managed",
                 "path": "/home/demo/.local/share/codexbar-plasma/cli/current/codexbar"},
    "system": {"status": "local", "version": "0.67.0", "manager": "dpkg", "path": "/usr/bin/codexbar"},
    "providers": {"status": "checked", "enabled": ["codex", "claude"]},
    "tools": {name: True for name in ("python3", "timeout", "kpackagetool6", "notify-send", "curl", "jq", "sha256sum", "flock")}
}))
