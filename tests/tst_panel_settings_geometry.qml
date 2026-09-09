import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Window
import QtTest

TestCase {
    id: testCase
    name: "PanelSettingsGeometry"
    when: windowShown
    visible: true
    width: 600
    height: 500

    property bool mirroredPage: false
    property var measuredItems: []
    property var positions: []

    LayoutMirroring.enabled: mirroredPage
    LayoutMirroring.childrenInherit: true

    function i18n(text, value, second) {
        var result = value === undefined ? text : text.replace("%1", value);
        return second === undefined ? result : result.replace("%2", second);
    }

    function i18np(singular, plural, count) {
        return (count === 1 ? singular : plural).replace("%1", count);
    }

    Connections {
        target: testCase.Window.window

        function onFrameSwapped() {
            if (testCase.measuredItems.length > 0) {
                testCase.positions.push(testCase.measuredItems.map(function (item) {
                    return item.mapToItem(testCase, 0, 0).x;
                }));
            }
        }
    }

    function createPage(properties) {
        var component = Qt.createComponent("../contents/ui/configPanel.qml");
        if (component.status === Component.Error && /module "org\.kde\.[^"]+" is not installed/.test(component.errorString())) {
            skip("Panel geometry checks need the optional KDE QML modules");
            return null;
        }
        compare(component.status, Component.Ready, component.errorString());
        failOnWarning(/.*/);
        var page = createTemporaryObject(component, testCase, Object.assign({
            width: testCase.width,
            height: testCase.height,
            cfg_showMultiProviderInPanel: true
        }, properties || {}));
        verify(page !== null);
        return page;
    }

    function cleanup() {
        measuredItems = [];
        positions = [];
        mirroredPage = false;
    }

    function test_openingKeepsTextStill_data() {
        return [
            {
                tag: "compact",
                pageWidth: 600,
                pageHeight: 500,
                fontSize: 13,
                rtl: false
            },
            {
                tag: "wide",
                pageWidth: 840,
                pageHeight: 900,
                fontSize: 13,
                rtl: false
            },
            {
                tag: "narrow",
                pageWidth: 420,
                pageHeight: 640,
                fontSize: 13,
                rtl: false
            },
            {
                tag: "large-font",
                pageWidth: 600,
                pageHeight: 500,
                fontSize: 20,
                rtl: false
            },
            {
                tag: "rtl",
                pageWidth: 600,
                pageHeight: 500,
                fontSize: 13,
                rtl: true
            }
        ];
    }

    function test_openingKeepsTextStill(data) {
        width = data.pageWidth;
        height = data.pageHeight;
        mirroredPage = data.rtl;
        var page = createPage({
            "font.pixelSize": data.fontSize
        });
        if (!page)
            return;
        var names = ["panelSettingsPreview", "panelStandardStyle", "panelAdditionalButton", "panelAdvancedButton"];
        measuredItems = names.map(function (name) {
            var item = findChild(page, name);
            verify(item !== null, name);
            return item;
        });
        // Hidden form controls finish resolving their size after the first paint.
        wait(1000);
        measuredItems = [];
        verify(positions.length > 0, "No rendered frames were observed");
        for (var frame = 1; frame < positions.length; frame++) {
            for (var item = 0; item < names.length; item++) {
                verify(Math.abs(positions[frame][item] - positions[0][item]) < 0.5, names[item] + " shifted from " + positions[0][item] + " to " + positions[frame][item]);
            }
        }
    }

    function test_expandedOptionsKeepScrolling_data() {
        return [
            {
                tag: "ltr",
                rtl: false
            },
            {
                tag: "rtl",
                rtl: true
            }
        ];
    }

    function test_expandedOptionsKeepScrolling(data) {
        width = 600;
        height = 500;
        mirroredPage = data.rtl;
        var page = createPage({
            cfg_panelQuotaLane: "secondary",
            cfg_showPercentInPanel: true
        });
        if (!page)
            return;
        var additional = findChild(page, "panelAdditionalButton");
        additional.forceActiveFocus();
        keyClick(Qt.Key_Space);
        verify(page.additionalExpanded);
        var advanced = findChild(page, "panelAdvancedButton");
        advanced.forceActiveFocus();
        keyClick(Qt.Key_Space);
        verify(page.advancedExpanded);
        var bar = page.contentItem.Controls.ScrollBar.vertical;
        tryVerify(function () {
            return bar.visible && bar.size < 1;
        });
        verify(bar.interactive);
        verify(bar.policy !== Controls.ScrollBar.AlwaysOff);
        var before = page.flickable.contentY;
        bar.increase();
        tryVerify(function () {
            return page.flickable.contentY > before;
        });
        var position = bar.mapToItem(page, 0, 0);
        verify(data.rtl ? position.x < bar.width : position.x >= page.width - bar.width * 2, "Scrollbar is on the wrong side");
        page.additionalExpanded = false;
        page.advancedExpanded = false;
        compare(page.cfg_panelQuotaLane, "secondary");
        verify(page.cfg_showPercentInPanel);
    }
}
