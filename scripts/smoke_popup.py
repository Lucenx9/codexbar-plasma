#!/usr/bin/env python3
"""Run the real applet in plasmawindowed with isolated synthetic CLI data."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET

from smoke.fixture_cli import SCENARIOS

ROOT = Path(__file__).resolve().parent.parent
APPLET_ID = "app.codexbar.smoke"
QML_ERRORS = re.compile(
    r"ReferenceError|TypeError|SyntaxError|RangeError|SMOKE_FAILED|"
    r"is not a type|is not installed|Error loading QML|"
    r"Cannot assign|Unable to assign|Binding loop detected|QJSValue::call\(\) failed", re.IGNORECASE
)


def preview_environment(work, scenario):
    # Do not inherit CLI credentials, config overrides, Qt import paths, or the
    # desktop session bus. Keep only access to the existing display socket.
    env = {key: os.environ[key] for key in
           ("DISPLAY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "XAUTHORITY") if key in os.environ}
    env.update(PATH="/usr/bin:/bin", LANG="C.UTF-8", LC_ALL="C.UTF-8", TZ="UTC",
               XDG_CONFIG_HOME=str(work / "config"), XDG_DATA_HOME=str(work / "data"),
               XDG_CACHE_HOME=str(work / "cache"), XDG_STATE_HOME=str(work / "state"),
               XDG_CONFIG_DIRS=str(work / "system-config"), XDG_DATA_DIRS="/usr/local/share:/usr/share",
               CODEXBAR_CONFIG=str(work / "config/codexbar/config.json"),
               CODEXBAR_SMOKE_SCENARIO=scenario, QT_QUICK_BACKEND="software",
               QT_FORCE_STDERR_LOGGING="1", XDG_CURRENT_DESKTOP="KDE",
               QT_QPA_PLATFORMTHEME="kde", QT_QUICK_CONTROLS_STYLE="org.kde.desktop")
    for name in ("config", "data", "cache", "state", "system-config"):
        (work / name).mkdir()
    return env


def stage_applet(work, scenario, image_path):
    package = work / "data/plasma/plasmoids" / APPLET_ID
    package.mkdir(parents=True)
    shutil.copytree(ROOT / "contents", package / "contents")
    metadata = json.loads((ROOT / "metadata.json").read_text())
    metadata["KPlugin"].update(Id=APPLET_ID, Name="CodexBar smoke test")
    (package / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")

    fixture_cli = work / "codexbar-fixture"
    fixture_source = (ROOT / "scripts/smoke/fixture_cli.py").read_text()
    fixture_cli.write_text("#!" + sys.executable + "\n" + fixture_source.split("\n", 1)[1])
    fixture_cli.chmod(0o700)
    # Change defaults before the QML engine creates bindings or runs startup
    # handlers. Disabling effects after Component.onCompleted would be too late.
    config_path = package / "contents/config/main.xml"
    ns = {"k": "http://www.kde.org/standards/kcfg/1.0"}
    ET.register_namespace("", ns["k"])
    config = ET.parse(config_path)
    defaults = {"commandPath": str(fixture_cli), "refreshInterval": "0",
                "enableNotifications": "false", "updateChecksEnabled": "false",
                "autoUpdateEnabled": "false", "updateNotificationsEnabled": "false"}
    for key, value in defaults.items():
        entry = config.find(f".//k:entry[@name='{key}']/k:default", ns)
        if entry is None:
            raise RuntimeError(f"Missing smoke configuration entry: {key}")
        entry.text = value
    config.write(config_path, encoding="utf-8", xml_declaration=True)

    ui = package / "contents/ui"
    shutil.copyfile(ROOT / "scripts/smoke/Capture.qml", ui / "SmokeCapture.qml")
    main_path = ui / "main.qml"
    main = main_path.read_text().rstrip()
    if not main.endswith("}"):
        raise RuntimeError("Cannot attach capture to the applet root")
    main_path.write_text(main[:-1] + "\n    SmokeCapture {\n        applet: root\n"
                        + "        scenario: " + json.dumps(scenario) + "\n"
                        + "        imagePath: " + json.dumps(str(image_path)) + "\n    }\n}\n")
    # Stable default typography; long-text exercises the same doubled text size
    # used in the existing visual review, without changing the desktop settings.
    size = 20 if scenario == "long-text" else 10
    (work / "config/kdeglobals").write_text(
        f"[General]\nfont=Noto Sans,{size},-1,5,50,0,0,0,0,0\n"
        f"smallestReadableFont=Noto Sans,{size - 2},-1,5,50,0,0,0,0,0\n"
        "[Icons]\nTheme=breeze\n")


def stop_preview(process):
    # Include delayed fixture CLI children, even when plasmawindowed exited first.
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=2)
    except ProcessLookupError:
        pass
    except subprocess.TimeoutExpired:
        pass
    finally:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()


def run_preview(command, env, work, log_path, scenario, timeout):
    marker = "SMOKE_CAPTURED:" + scenario
    with log_path.open("w") as log:
        process = subprocess.Popen(command, env=env, cwd=work, stdout=log,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                output = log_path.read_text(errors="replace")
                if QML_ERRORS.search(output):
                    raise RuntimeError("QML or fixture error; see " + str(log_path))
                if marker in output:
                    break
                if process.poll() is not None:
                    raise RuntimeError("Preview exited before capture; see " + str(log_path))
                time.sleep(0.1)
            else:
                raise RuntimeError("Timed out waiting for the scenario; see " + str(log_path))
        finally:
            stop_preview(process)
    if QML_ERRORS.search(log_path.read_text(errors="replace")):
        raise RuntimeError("QML or fixture error; see " + str(log_path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=("all",) + SCENARIOS, default="all")
    parser.add_argument("--output", type=Path, help="New artifact directory; default: dist/smoke/run-*")
    parser.add_argument("--timeout", type=int, default=30, help="Seconds per scenario, 1–120")
    args = parser.parse_args()
    if not 1 <= args.timeout <= 120:
        parser.error("--timeout must be between 1 and 120")
    if not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
        parser.error("A graphical Plasma session is required (DISPLAY or WAYLAND_DISPLAY).")
    for tool in ("plasmawindowed", "dbus-run-session"):
        if not shutil.which(tool):
            parser.error(f"Required command not found: {tool}")
    if args.output:
        output = args.output.resolve()
        if output.exists():
            parser.error("--output must name a new directory; existing artifacts are never overwritten")
        output.mkdir(parents=True, exist_ok=False)
    else:
        parent = ROOT / "dist/smoke"
        parent.mkdir(parents=True, exist_ok=True)
        output = Path(tempfile.mkdtemp(prefix="run-", dir=parent))
    scenarios = SCENARIOS if args.scenario == "all" else (args.scenario,)
    print(f"Smoke artifacts: {output}", flush=True)
    results = []
    for scenario in scenarios:
        try:
            with tempfile.TemporaryDirectory(prefix="codexbar-smoke-") as temporary:
                work = Path(temporary)
                env = preview_environment(work, scenario)
                image_path = output / (scenario + ".png")
                stage_applet(work, scenario, image_path)
                command = [shutil.which("dbus-run-session"), "--", shutil.which("plasmawindowed"), APPLET_ID]
                run_preview(command, env, work, output / (scenario + ".log"), scenario, args.timeout)
                if not image_path.is_file() or image_path.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
                    raise RuntimeError("Missing or invalid screenshot")
            results.append({"scenario": scenario, "passed": True})
            print(f"PASS {scenario}", flush=True)
        except (OSError, RuntimeError) as error:
            results.append({"scenario": scenario, "passed": False, "error": str(error)})
            print(f"FAIL {scenario}: {error}", file=sys.stderr, flush=True)
    (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    return 0 if all(result["passed"] for result in results) else 1


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(128 + signum))
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
