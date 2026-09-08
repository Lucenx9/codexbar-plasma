import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "PanelStyleSettings"
    when: windowShown
    width: 600
    height: 900
    visible: true

    function i18n(text) {
        return text;
    }
    function i18np(singular, plural, count) {
        return count === 1 ? singular : plural;
    }

    function test_selectionPresetAndDefaultsStaySynchronized() {
        var component = Qt.createComponent("../contents/ui/configPanel.qml");
        if (component.status === Component.Error && /module "org\.kde\.[^"]+" is not installed/.test(component.errorString())) {
            skip("Panel settings checks need the optional KDE QML modules");
            return;
        }
        compare(component.status, Component.Ready, component.errorString());
        failOnWarning(/.*/);
        var page = createTemporaryObject(component, testCase, {
            width: 600,
            height: 900,
            cfg_showProviderInPanel: true,
            cfg_showPercentInPanel: true,
            cfg_showCreditsInPanel: true,
            cfg_showMultiProviderInPanel: false,
            cfg_panelQuotaLane: "secondary",
            cfg_panelElementOrder: "meters,status,text,identity",
            cfg_panelVisibilityRules: '{"meters":{"condition":"usageAtLeast","usedPercent":70}}'
        });
        verify(page !== null);
        var combo = findChild(page, "panelStyleCombo");
        verify(combo !== null);
        combo.forceActiveFocus();
        keyClick(Qt.Key_Down);
        compare(page.cfg_panelStyle, "minimal");
        verify(page.cfg_showProviderInPanel && page.cfg_showPercentInPanel && page.cfg_showCreditsInPanel && !page.cfg_showMultiProviderInPanel);
        keyClick(Qt.Key_Up);
        compare(page.cfg_panelStyle, "standard");
        page.applyMinimalPanelPreset();
        tryCompare(combo, "currentIndex", 1);
        verify(!page.cfg_showProviderInPanel && !page.cfg_showPercentInPanel && !page.cfg_showCreditsInPanel && page.cfg_showMultiProviderInPanel);
        compare(page.cfg_panelQuotaLane, "secondary");
        compare(page.cfg_panelElementOrder, "meters,status,text,identity");
        compare(page.cfg_panelVisibilityRules, '{"meters":{"condition":"usageAtLeast","usedPercent":70}}');
        page.cfg_panelStyle = page.cfg_panelStyleDefault;
        tryCompare(combo, "currentIndex", 0);
        page.cfg_panelStyle = "unrecognized";
        compare(combo.currentIndex, 0);
    }
}
