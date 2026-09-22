"""Exercise the popup dashboard sections with the production QML blocks."""

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
import QtTest
import org.kde.kirigami as Kirigami
import "SOURCE_URL/components" as Components
TestCase {
    id: testCase
    name: "UsageDashboard"
    when: windowShown
    width: 600
    height: 550
    visible: true
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    function i18n(text) { return text; }

    readonly property string hostileKpiLabel: "Load <img src=\\"http://127.0.0.1/probe\\"> & <kpi>"
    readonly property string hostileKpiValue: "1&2 <b>left</b>"
    readonly property string hostileRowLabel: "Tokens <i>used</i> & <rows>"
    readonly property string hostileRowValue: "4>5 <u>tokens</u>"
    readonly property string hostileDetailTitle: "Detail <img src=\\"http://127.0.0.1/probe\\"> & <section>"
    readonly property string hostileDetailLabel: "Limit <b>label</b>"
    readonly property string hostileDetailValue: "9&10 <i>value</i>"

    Component {
        id: harness
        ColumnLayout {
            id: fullRoot
            width: 560
            property var applet: fakeApplet
            QtObject {
                id: fakeApplet
                property bool showPopupProviderDetails: true
                property real secondaryTextOpacity: 0.7
                property real valueTextOpacity: 0.85
                property var presentedProviderData: ({
                    provider: "codex",
                    providerDetails: [{
                        title: testCase.hostileDetailTitle,
                        rows: [{label: testCase.hostileDetailLabel,
                                value: testCase.hostileDetailValue,
                                secondaryValue: ""}],
                        chart: null
                    }],
                    usageDashboard: {
                        kpis: [{label: testCase.hostileKpiLabel,
                                value: testCase.hostileKpiValue}],
                        rows: [{label: testCase.hostileRowLabel,
                                value: testCase.hostileRowValue}]
                    }
                })
                function providerReadableColor(provider, bg) { return "#3aa655"; }
            }
            ColumnLayout {
                DETAILS_BLOCK
            }
            ColumnLayout {
                DASHBOARD_BLOCK
            }
        }
    }

    function walkTree(item, out) {
        if (item === null || item === undefined || out.indexOf(item) >= 0)
            return;
        out.push(item);
        var groups = [item.children, item.resources, item.data];
        for (var g = 0; g < groups.length; g++) {
            var kids = groups[g];
            if (kids === undefined || kids === null)
                continue;
            for (var i = 0; i < kids.length; i++)
                walkTree(kids[i], out);
        }
    }

    function createSubject() {
        var subject = createTemporaryObject(harness, testCase);
        verify(subject !== null);
        return subject;
    }

    // The dashboard section owns its heading and renders every KPI and row
    // the CLI reports, keeping hostile text literal.
    function test_dashboardSectionRendersKpisAndRows() {
        var subject = createSubject();
        var all = [];
        walkTree(subject, all);
        var headings = all.filter(function (item) {
            return item.text === "Usage dashboard";
        });
        compare(headings.length, 1);
        var section = all.filter(function (item) {
            return item.objectName === "usageDashboardSection";
        });
        compare(section.length, 1);
        verify(section[0].visible);
        compare(section[0].kpis.length, 1);
        compare(section[0].rows.length, 1);
        var labels = all.filter(function (item) {
            return item.text === testCase.hostileKpiLabel
                || item.text === testCase.hostileKpiValue
                || item.text === testCase.hostileRowLabel
                || item.text === testCase.hostileRowValue;
        });
        compare(labels.length, 4);
    }

    // Each reported detail entry gets its own detail section.
    function test_detailsEntriesEachGetASection() {
        var subject = createSubject();
        var all = [];
        walkTree(subject, all);
        var sections = all.filter(function (item) {
            return item.toString().indexOf("ProviderDetailSection") >= 0
                && item.objectName !== undefined
                && item.sectionData !== undefined;
        });
        compare(sections.length, 1);
        var titles = all.filter(function (item) {
            return item.text === testCase.hostileDetailTitle;
        });
        verify(titles.length > 0);
        var values = all.filter(function (item) {
            return item.text === testCase.hostileDetailValue;
        });
        verify(values.length > 0);
    }

    // An empty snapshot hides both sections instead of rendering shells.
    function test_emptySnapshotHidesBothSections() {
        var subject = createSubject();
        subject.applet.presentedProviderData = ({
            provider: "codex", providerDetails: [], usageDashboard: null
        });
        var dashboard = null;
        var details = null;
        var all = [];
        walkTree(subject, all);
        var found = all.filter(function (item) {
            return item.objectName === "usageDashboardSection";
        });
        compare(found.length, 1);
        dashboard = found[0];
        found = all.filter(function (item) {
            return item.objectName === "providerDetailsSection";
        });
        compare(found.length, 1);
        details = found[0];
        tryVerify(function() { return !dashboard.visible && !details.visible; });
    }
}
'''


class UsageDashboardTests(unittest.TestCase):
    def test_popup_dashboard_sections_render(self):
        surface = Surface("applet", ROOT)
        details = surface.id_block("providerDetailsSection")
        dashboard = surface.id_block("usageDashboardSection")
        # The harness resolves sibling components from the same directory,
        # while production resolves them implicitly. The delegate wiring
        # itself is pinned by the QML section-count assertion below, not by
        # reading the production source here.
        qml = QML.replace("SOURCE_URL", (ROOT / "contents/ui").as_uri())
        qml = qml.replace("DETAILS_BLOCK", details.replace(
            "PlainHeading {", "Components.PlainHeading {").replace(
            "PlainPlasmaLabel {", "Components.PlainPlasmaLabel {"))
        qml = qml.replace("DASHBOARD_BLOCK", dashboard.replace(
            "PlainHeading {", "Components.PlainHeading {").replace(
            "PlainPlasmaLabel {", "Components.PlainPlasmaLabel {"))
        with tempfile.TemporaryDirectory(prefix="codexbar-dashboard-") as temporary:
            fixture = Path(temporary) / "tst_dashboard.qml"
            fixture.write_text(qml)
            result = subprocess.run(
                [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
