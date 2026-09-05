"""Portable checks for preview isolation, fixture limits, and failure reporting."""

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import smoke_popup as smoke
from smoke.fixture_cli import response, usage


class SmokePopupTests(unittest.TestCase):
    def test_environment_drops_host_config_credentials_and_session_bus(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {
            "CODEXBAR_CONFIG": "/host/config.json", "XDG_DATA_HOME": "/host/data",
            "DBUS_SESSION_BUS_ADDRESS": "host-bus", "OPENAI_API_KEY": "synthetic-test-value",
            "QML_IMPORT_PATH": "/host/imports", "WAYLAND_DISPLAY": "wayland-test",
        }, clear=True):
            work = Path(temporary)
            env = smoke.preview_environment(work, "normal")
            self.assertEqual(env["CODEXBAR_CONFIG"], str(work / "config/codexbar/config.json"))
            self.assertEqual(env["XDG_DATA_HOME"], str(work / "data"))
            self.assertEqual(env["WAYLAND_DISPLAY"], "wayland-test")
            for key in ("DBUS_SESSION_BUS_ADDRESS", "OPENAI_API_KEY", "QML_IMPORT_PATH"):
                self.assertNotIn(key, env)

    def test_staging_uses_separate_id_and_safe_defaults_without_changing_sources(self):
        sources = ("contents/ui/main.qml", "contents/config/main.xml", "metadata.json")
        before = {name: (smoke.ROOT / name).read_bytes() for name in sources}
        with tempfile.TemporaryDirectory(prefix="smoke with spaces '") as temporary:
            work = Path(temporary)
            smoke.preview_environment(work, "normal")
            image = work / 'capture "quoted".png'
            smoke.stage_applet(work, "normal", image)
            package = work / "data/plasma/plasmoids" / smoke.APPLET_ID
            self.assertEqual(json.loads((package / "metadata.json").read_text())["KPlugin"]["Id"], smoke.APPLET_ID)
            tree = ET.parse(package / "contents/config/main.xml")
            ns = {"k": "http://www.kde.org/standards/kcfg/1.0"}
            values = {entry.attrib["name"]: entry.find("k:default", ns).text
                      for entry in tree.findall(".//k:entry", ns)}
            self.assertEqual(values["commandPath"], str(work / "codexbar-fixture"))
            for key in ("enableNotifications", "updateChecksEnabled", "autoUpdateEnabled",
                        "updateNotificationsEnabled"):
                self.assertEqual(values[key], "false")
            self.assertIn(json.dumps(str(image)), (package / "contents/ui/main.qml").read_text())
        self.assertEqual(before, {name: (smoke.ROOT / name).read_bytes() for name in sources})

    def test_wayland_only_preview_selects_a_graphical_backend(self):
        for display in (None, ""):
            host = {"WAYLAND_DISPLAY": "wayland-test", "QT_QPA_PLATFORM": "offscreen"}
            if display is not None:
                host["DISPLAY"] = display
            with self.subTest(display=display), tempfile.TemporaryDirectory() as temporary:
                with patch.dict(os.environ, host, clear=True):
                    env = smoke.preview_environment(Path(temporary), "normal")
                self.assertEqual(env.get("QT_QPA_PLATFORM"), "wayland")

    def test_x11_available_preview_keeps_qt_platform_autodetection(self):
        for wayland_display in (None, "wayland-test"):
            host = {"DISPLAY": ":1", "QT_QPA_PLATFORM": "offscreen"}
            if wayland_display is not None:
                host["WAYLAND_DISPLAY"] = wayland_display
            with self.subTest(wayland_display=wayland_display), tempfile.TemporaryDirectory() as temporary:
                with patch.dict(os.environ, host, clear=True):
                    env = smoke.preview_environment(Path(temporary), "normal")
                self.assertNotIn("QT_QPA_PLATFORM", env)

    def test_partial_failure_preserves_healthy_usage(self):
        now = datetime(2026, 9, 1, tzinfo=timezone.utc)
        healthy = usage("codex", "partial-error", now)
        failed = usage("claude", "partial-error", now)
        self.assertEqual(healthy["usage"]["primary"]["usedPercent"], 43)
        self.assertNotIn("error", healthy)
        self.assertIn("error", failed)
        self.assertNotIn("usage", failed)

    def test_fixture_refuses_commands_outside_the_preview_contract(self):
        now = datetime(2026, 9, 1, tzinfo=timezone.utc)
        for args in (["config", "set-api-key"], ["usage", "--provider", "unexpected"], []):
            with self.subTest(args=args), self.assertRaisesRegex(ValueError, "unsupported"):
                response(args, "normal", now)

    def test_project_fixture_changes_totals_with_the_requested_range(self):
        now = datetime(2026, 9, 1, tzinfo=timezone.utc)
        command = ["cost", "--format", "json", "--json-only", "--days"]
        month = response(command + ["30"], "project-costs", now)[0]
        week = response(command + ["7"], "project-range", now)[0]
        self.assertEqual(month["projects"][0]["totalCost"], 5.5)
        self.assertEqual(week["projects"][0]["totalCost"], 2.75)
        self.assertEqual(week["historyDays"], 7)
        self.assertNotIn("totalCost", month["projects"][2])
        self.assertEqual(month["projects"][3]["totalCost"], 0)
        self.assertNotIn("projects", response(command + ["30"], "normal", now)[0])

    def test_qml_failure_wins_even_if_capture_marker_is_present(self):
        for error in ("TypeError: synthetic failure",
                      "QJSValue::call() failed: cannot call function with argument created in a different engine"):
            with self.subTest(error=error), tempfile.TemporaryDirectory() as temporary:
                work = Path(temporary)
                command = [sys.executable, "-c", f"print({('SMOKE_CAPTURED:normal' + chr(10) + error)!r}, flush=True)"]
                with self.assertRaisesRegex(RuntimeError, "QML or fixture error"):
                    smoke.run_preview(command, {}, work, work / "preview.log", "normal", 2)

    def test_early_exit_cannot_be_reported_as_a_pass(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            with self.assertRaisesRegex(RuntimeError, "exited before capture"):
                smoke.run_preview([sys.executable, "-c", "pass"], {}, work, work / "preview.log", "normal", 2)

    def test_timeout_stops_delayed_child_processes(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            command = [sys.executable, "-c",
                       "import subprocess, sys, time; "
                       "subprocess.Popen([sys.executable, '-c', "
                       "\"import time; from pathlib import Path; time.sleep(0.7); Path('leaked').touch()\"]); "
                       "time.sleep(5)"]
            with self.assertRaisesRegex(RuntimeError, "Timed out"):
                smoke.run_preview(command, {}, work, work / "preview.log", "normal", 0.2)
            subprocess.run([sys.executable, "-c", "import time; time.sleep(0.8)"], check=True)
            self.assertFalse((work / "leaked").exists())


if __name__ == "__main__":
    unittest.main()
