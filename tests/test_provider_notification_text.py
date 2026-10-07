"""Exercise production provider notification text against every shipped catalog."""

import gettext
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MESSAGES = (
    "%1 status issue", "%1 quota critical", "%1 quota warning", "%1 is %2% used",
    "%1 pace warning", "%1 may run out in %2", "%1 limit reset", "%1 is back to %2% used",
)
QML = '''import QtQuick
import QtTest
import "SOURCE_URL/components" as Components
TestCase {
    id: testCase
    name: "ProviderNotificationCatalogs"
    property var messages: ({})
    Components.ProviderNotificationText {
        id: subject
        function i18n(source) { return testCase.i18n.apply(testCase, arguments); }
    }
    function i18n(source) {
        var text = messages[source] || source;
        for (var i = 1; i < arguments.length; i++) text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function test_messages_data() { return CASES; }
    function test_messages(data) {
        messages = data.messages;
        for (var row of data.expected) {
            compare(subject.message(row.intent, {title: "Provider", status: "CLI <status>"},
                {label: "Lane", usedPercent: 95.6}, "Reset label", "ETA label"), row.message);
        }
    }
}
'''


class ProviderNotificationCatalogTests(unittest.TestCase):
    def test_all_catalogs_preserve_notification_arguments(self):
        with tempfile.TemporaryDirectory(prefix="codexbar-notification-catalogs-") as directory:
            temporary = Path(directory)
            cases = []
            for language in ("en", "it", "fr", "de", "es", "pt_BR"):
                catalog = gettext.NullTranslations()
                if language != "en":
                    compiled = temporary / (language + ".mo")
                    subprocess.run(["msgfmt", "-o", str(compiled), str(ROOT / "po" / (language + ".po"))],
                                   check=True, capture_output=True)
                    with compiled.open("rb") as stream:
                        catalog = gettext.GNUTranslations(stream)
                messages = {source: catalog.gettext(source) for source in MESSAGES}

                def text(source, *arguments):
                    result = messages[source]
                    for index, argument in enumerate(arguments, 1):
                        result = result.replace("%" + str(index), str(argument))
                    return result

                cases.append({"tag": language, "messages": messages, "expected": [
                    {"intent": {"kind": "status", "severity": "major"}, "message": {
                        "title": text("%1 status issue", "Provider"), "body": "CLI <status>", "urgency": "critical"}},
                    {"intent": {"kind": "quota", "severity": "major"}, "message": {
                        "title": text("%1 quota critical", "Provider"),
                        "body": text("%1 is %2% used", "Lane", 96) + ". Reset label", "urgency": "critical"}},
                    {"intent": {"kind": "quota", "severity": "minor"}, "message": {
                        "title": text("%1 quota warning", "Provider"),
                        "body": text("%1 is %2% used", "Lane", 96) + ". Reset label", "urgency": "normal"}},
                    {"intent": {"kind": "pace"}, "message": {
                        "title": text("%1 pace warning", "Provider"),
                        "body": text("%1 may run out in %2", "Lane", "ETA label"), "urgency": "normal"}},
                    {"intent": {"kind": "reset"}, "message": {
                        "title": text("%1 limit reset", "Provider"),
                        "body": text("%1 is back to %2% used", "Lane", 96), "urgency": "low"}},
                ]})
            fixture = temporary / "tst_provider_notification_catalogs.qml"
            fixture.write_text(QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
                               .replace("CASES", json.dumps(cases)))
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("SKIP", output)
            self.assertNotIn("QWARN", output)
