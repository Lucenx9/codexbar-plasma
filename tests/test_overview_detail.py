"""Exercise the overview detail fallback chain with the production QML."""

import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/lib"))
from qml_surfaces import Surface

FUNCTIONS = ("overviewDetailText", "providerPlaceholderText")

QML = '''import QtQuick
import QtTest
TestCase {
    name: "OverviewDetail"

    SOURCE_FUNCTIONS

    function test_account_identity_wins_over_everything() {
        compare(overviewDetailText({
            account: "user@example.test",
            hasIncident: true,
            statusKnown: true,
            status: "Major outage",
            placeholder: "No usage yet",
            source: "oauth"
        }), "user@example.test");
    }

    function test_only_an_active_incident_stands_in_for_identity() {
        compare(overviewDetailText({
            provider: "claude",
            title: "Claude",
            hasIncident: true,
            statusKnown: true,
            status: "Major outage: elevated errors"
        }), "Major outage: elevated errors");
    }

    function test_operational_status_never_poses_as_identity() {
        // Claude's CLI payload carries no account identity; a green status
        // must not fill the line that shows an email for other providers.
        compare(overviewDetailText({
            provider: "claude",
            title: "Claude",
            hasIncident: false,
            statusKnown: true,
            status: "All Systems Operational",
            source: "claude"
        }), "");
    }

    function test_unknown_incident_status_falls_through() {
        // A nonempty status alone must not stand in for identity: the
        // status-known predicate has to carry the rejection on its own, so
        // the chain falls through to the foreign source instead.
        compare(overviewDetailText({
            provider: "claude",
            title: "Claude",
            hasIncident: true,
            statusKnown: false,
            status: "Major outage",
            source: "oauth"
        }), "oauth");
    }

    function test_placeholder_and_foreign_source_fallbacks_remain() {
        compare(overviewDetailText({
            provider: "gemini",
            title: "Gemini",
            placeholder: "No usage yet"
        }), "No usage yet");
        compare(overviewDetailText({
            provider: "codex",
            title: "Codex",
            source: "oauth"
        }), "oauth");
    }

    function test_source_that_repeats_the_provider_is_suppressed() {
        // Each repetition is matched independently: the source equals the
        // title here but differs from the provider id.
        compare(overviewDetailText({
            provider: "claude",
            title: "Claude Team",
            source: "Claude Team"
        }), "");
        // The source equals the provider id but differs from the title.
        compare(overviewDetailText({
            provider: "claude",
            title: "Claude Team",
            source: "claude"
        }), "");
        compare(overviewDetailText(null), "");
    }
}
'''


class OverviewDetailTests(unittest.TestCase):
    def test_overview_detail_fallback_chain_uses_production_qml(self):
        applet = Surface("applet", ROOT)
        main = ROOT / "contents/ui/main.qml"
        source = applet.texts[main]
        applet.texts = {main: source}
        functions = []
        for name in FUNCTIONS:
            signature = re.search(r"function " + name + r"\([^)]*\)", source).group(0)
            functions.append(signature + " {" + applet.function_body(name) + "}")
        qml = QML.replace("SOURCE_FUNCTIONS", "\n".join(functions))
        with tempfile.TemporaryDirectory(prefix="codexbar-overview-detail-") as temporary:
            fixture = Path(temporary) / "tst_overview_detail.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
