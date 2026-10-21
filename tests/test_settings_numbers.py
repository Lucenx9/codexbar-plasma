"""Type into the production Settings number editors with Qt and KDE styles."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/lib"))
from qml_surfaces import Surface

QML = '''import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import QtTest
TestCase {
    id: page
    name: "SettingsNumbers"
    width: 600
    height: 600
    visible: true
    when: windowShown
    property int cfg_costHistoryDays: 30
    function editCostHistoryDays(value) { cfg_costHistoryDays = value; }
    function i18n(text, value) { return value === undefined ? text : text.replace("%1", value); }
    function i18np(one, many, count) { return (count === 1 ? one : many).replace("%1", count); }
    function refreshPresetIndex(value) { return -1; }
    QtObject { id: refreshPresetCombo; property int currentValue: -1; property int currentIndex: -1 }
    QtObject { id: costUsageEnabledCheck; property bool checked: true }
    QtObject { id: identifiedTokensCheck; property bool checked: true }
    QtObject { id: updateChecksEnabledCheck; property bool checked: true }
    SOURCE_EDITORS
    function test_typing_data() {
        return [
            {tag: "refresh", field: refreshIntervalSpin, value: 1200},
            {tag: "history", field: costHistoryDaysSpin, value: 45},
            {tag: "identified", field: identifiedDaysSpin, value: 90},
            {tag: "updates", field: autoUpdateIntervalHoursSpin, value: 48},
            {tag: "warning", field: quotaWarningPercentSpin, value: 85},
            {tag: "critical", field: quotaCriticalPercentSpin, value: 99},
            {tag: "refresh-de", field: refreshIntervalSpin, value: 1200, locale: "de_DE"},
            {tag: "refresh-fr", field: refreshIntervalSpin, value: 1200, locale: "fr_FR"},
            {tag: "refresh-it", field: refreshIntervalSpin, value: 1200, locale: "it_IT"}
        ];
    }
    function test_typing(data) {
        var field = data.field;
        field.locale = Qt.locale(data.locale || "C");
        field.value = data.tag === "warning" ? 80 : field.from;
        field.contentItem.forceActiveFocus(Qt.TabFocusReason);
        field.contentItem.selectAll();
        for (var digit of String(data.value)) keyClick(Qt.Key_0 + Number(digit));
        keyClick(Qt.Key_Return);
        compare(field.value, data.value);
        compare(field.valueFromText(field.textFromValue(data.value, field.locale), field.locale), data.value);
        compare(field.valueFromText("", field.locale), data.value);
    }
    function test_localizedRoundTrip_data() {
        var rows = [];
        for (var locale of ["ar_EG", "fa_IR", "bn_BD"]) {
            for (var row of test_typing_data().slice(0, 6)) {
                rows.push({tag: row.tag + "-" + locale, field: row.field,
                    value: row.value, locale: locale});
            }
        }
        return rows;
    }
    function test_localizedRoundTrip(data) {
        var field = data.field;
        field.locale = Qt.locale(data.locale);
        field.value = field.from;
        var text = field.textFromValue(data.value, field.locale);
        compare(field.valueFromText(text, field.locale), data.value);
        field.contentItem.forceActiveFocus(Qt.TabFocusReason);
        field.contentItem.text = text;
        keyClick(Qt.Key_Return);
        compare(field.value, data.value);
    }
}
'''


class SettingsNumbersTests(unittest.TestCase):
    def test_typing_preserves_every_digit_in_both_styles(self):
        editors = []
        for surface_name, names in (
            ("general", ("refreshIntervalSpin", "costHistoryDaysSpin", "identifiedDaysSpin", "autoUpdateIntervalHoursSpin")),
            ("notifications", ("quotaWarningPercentSpin", "quotaCriticalPercentSpin")),
        ):
            surface = Surface(surface_name, ROOT)
            editors.extend("Controls.SpinBox {" + surface.id_block(name) + "}" for name in names)
        with tempfile.TemporaryDirectory(prefix="codexbar-settings-numbers-") as temporary:
            fixture = Path(temporary) / "tst_numbers.qml"
            fixture.write_text(QML.replace("SOURCE_EDITORS", "\n".join(editors)))
            for style in ("Basic", "org.kde.desktop"):
                with self.subTest(style=style):
                    result = subprocess.run(
                        [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                        env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software",
                             "QT_QUICK_CONTROLS_STYLE": style},
                        capture_output=True, text=True, timeout=30)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
