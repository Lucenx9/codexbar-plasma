#!/usr/bin/env python3
"""Prepare only an isolated synthetic CLI for popup setup smoke tests."""

import json
import os
from pathlib import Path
import shutil
import sys
import time

target = Path(os.environ["XDG_DATA_HOME"]) / "codexbar-plasma/cli/current/codexbar"
action = sys.argv[sys.argv.index("--action") + 1]
if action == "install":
    time.sleep(0.3)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(Path(__file__).with_name("fixture-cli"), target)
    target.chmod(0o700)
print(json.dumps(dict(status="ready" if target.exists() else "absent", version="0.77.0",
                     path=str(target) if target.exists() else "")))
