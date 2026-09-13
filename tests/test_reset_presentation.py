"""Verify localized reset adapters, local dates, and live QML clock bindings."""

from datetime import datetime
import gettext
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "scripts/lib"))
from compile_translations import compile_catalogs
from qml_surfaces import Surface


class ResetPresentationTests(unittest.TestCase):
    def test_translated_resets_follow_local_time_and_live_clock(self):
        applet = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        applet.texts = {main: main.read_text()}
        applet.files = [main]
        signatures = {"resetText": "window, absolute", "resetLabel": "value", "usageResetText": "row"}
        adapters = "\n".join(f"function {name}({args}) {{ {applet.function_body(name)} }}"
                             for name, args in signatures.items())
        with tempfile.TemporaryDirectory(prefix="codexbar-reset-labels-") as temporary:
            directory = Path(temporary)
            compile_catalogs(directory / "locale")
            cases = []
            for language in ("en", "it", "fr", "de", "es", "pt_BR"):
                catalog = gettext.translation("plasma_applet_app.codexbar.plasma", directory / "locale",
                                              languages=[language], fallback=language == "en")
                messages = {key: value for key, value in getattr(catalog, "_catalog", {}).items()
                            if isinstance(key, str)}

                def text(source, *values):
                    result = catalog.gettext(source)
                    for index, value in enumerate(values, 1):
                        result = result.replace("%" + str(index), str(value))
                    return result

                plurals = {source: {count: catalog.ngettext(source, source, count) for count in (1, 2, 59)}
                           for source in ("%1 min", "%1h", "%1d")}

                def plural(source, count):
                    return plurals[source][count].replace("%1", str(count))

                cases.append({"tag": language, "messages": messages, "plurals": plurals,
                              "rows": [
                                  {"offset": -1, "expected": text("now")},
                                  {"offset": 1, "expected": plural("%1 min", 1)},
                                  {"offset": 90000, "expected": plural("%1 min", 2)},
                                  {"offset": 3570000, "expected": plural("%1h", 1)},
                                  {"offset": 7200000, "expected": plural("%1h", 2)},
                                  {"offset": 9000000, "expected": text("%1h %2m", 2, 30)},
                                  {"offset": 86400000, "expected": plural("%1d", 1)},
                                  {"offset": 172800000, "expected": plural("%1d", 2)},
                                  {"offset": 90000000, "expected": text("%1d %2h", 1, 1)}],
                              "hour": plural("%1h", 1), "minutes": plural("%1 min", 59),
                              "label": text("Resets %1", "2h 30m")})
            qml = '''import QtQuick
import QtTest
import "SOURCE_URL/ResetPresentation.js" as ResetPresentation
import "SOURCE_URL/PrivacyPresentation.js" as PrivacyPresentation
TestCase {
    name: "ResetAdapters"
    property var messages: ({})
    property var plurals: ({})
    property double panelClockMs: Date.UTC(2026, 8, 13, 12)
    property bool resetTimesShowAbsolute: false
    property bool privacyMode: false
    property var row: null
    readonly property string observedReset: usageResetText(row)
    function i18n(source) {
        var result = messages[source] || source;
        for (var i = 1; i < arguments.length; i++)
            result = result.replace("%" + i, String(arguments[i]));
        return result;
    }
    function i18np(one, many, count) {
        return plurals[one][count].replace("%1", String(count));
    }
    ADAPTERS
    function test_resets_data() { return RESET_CASES; }
    function test_resets(data) {
        row = null;
        messages = data.messages;
        plurals = data.plurals;
        resetTimesShowAbsolute = false;
        privacyMode = false;
        panelClockMs = Date.UTC(2026, 8, 13, 12);
        for (var reset of data.rows)
            compare(resetText({resetsAt: panelClockMs + reset.offset}, false), reset.expected);
        for (var absolute of ABSOLUTE_CASES)
            compare(resetText({resetsAt: absolute.timestamp}, true), absolute.expected);
        compare(resetLabel("Resets2h30m"), data.label);
        compare(resetLabel("Resets unknown future text"), "unknown future text");

        row = {resetsAt: "2026-09-13T13:00:00Z", resetDescription: "stale description"};
        compare(observedReset, data.hour);
        panelClockMs += 60000;
        compare(observedReset, data.minutes);
        privacyMode = true;
        compare(observedReset, data.minutes);
        resetTimesShowAbsolute = true;
        compare(observedReset, ABSOLUTE_CASES[0].expected);
        compare(row.resetDescription, "stale description");
        row = {resetDescription: "Synthetic fallback"};
        compare(observedReset, "");
        privacyMode = false;
        compare(observedReset, "Synthetic fallback");
        row = {reset: "Legacy reset"};
        compare(observedReset, "Legacy reset");
        row = null;
    }
}
'''.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri()).replace("ADAPTERS", adapters)
            qml = qml.replace("RESET_CASES", json.dumps(cases))
            for timezone in ("UTC", "Europe/Rome", "America/Los_Angeles"):
                with self.subTest(timezone=timezone):
                    dates = ["2026-09-13T13:00:00Z", "2026-03-08T10:30:00Z", "2026-11-01T09:30:00Z"]
                    absolute = [{"timestamp": value, "expected": datetime.fromisoformat(value.replace("Z", "+00:00"))
                                 .astimezone(ZoneInfo(timezone)).strftime("%a %H:%M")} for value in dates]
                    fixture = directory / "tst_reset_adapters.qml"
                    fixture.write_text(qml.replace("ABSOLUTE_CASES", json.dumps(absolute)))
                    result = subprocess.run(
                        [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                        env={**os.environ, "TZ": timezone, "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8",
                             "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                        capture_output=True, text=True, timeout=30)
                    output = result.stdout + result.stderr
                    self.assertEqual(result.returncode, 0, output)
                    self.assertNotIn("SKIP", output)
                    self.assertNotIn("QWARN", output)


if __name__ == "__main__":
    unittest.main()
