import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "PanelStyleSettings"
    when: windowShown
    width: 600
    height: 900
    visible: true

    function i18n(text, value) {
        return value === undefined ? text : text.replace("%1", value);
    }
    function i18np(singular, plural, count) {
        return (count === 1 ? singular : plural).replace("%1", count);
    }

    function createPage(properties) {
        var component = Qt.createComponent("../contents/ui/configPanel.qml");
        if (component.status === Component.Error && /module "org\.kde\.[^"]+" is not installed/.test(component.errorString())) {
            skip("Panel settings checks need the optional KDE QML modules");
            return;
        }
        compare(component.status, Component.Ready, component.errorString());
        failOnWarning(/.*/);
        var page = createTemporaryObject(component, testCase, Object.assign({
            width: 600, height: 900, cfg_showMultiProviderInPanel: true
        }, properties || {}));
        verify(page !== null);
        return page;
    }

    function storedValues(page) {
        var values = {};
        for (var key in page) {
            if (key.indexOf("cfg_") === 0 && !key.endsWith("Default"))
                values[key] = page[key];
        }
        return JSON.stringify(values);
    }

    function test_selectionPresetAndDefaultsStaySynchronized() {
        var page = createPage({
            cfg_showProviderInPanel: true,
            cfg_showPercentInPanel: true,
            cfg_showCreditsInPanel: true,
            cfg_showMultiProviderInPanel: false,
            cfg_panelQuotaLane: "secondary",
            cfg_panelElementOrder: "meters,status,text,identity",
            cfg_panelVisibilityRules: '{"meters":{"condition":"usageAtLeast","usedPercent":70}}'
        });
        if (!page) return;
        var standard = findChild(page, "panelStandardStyle");
        var minimal = findChild(page, "panelMinimalStyle");
        verify(standard.checked && !minimal.checked);
        minimal.forceActiveFocus();
        keyClick(Qt.Key_Space);
        compare(page.cfg_panelStyle, "minimal");
        verify(!standard.checked && minimal.checked);
        verify(page.cfg_showProviderInPanel && page.cfg_showPercentInPanel && page.cfg_showCreditsInPanel && !page.cfg_showMultiProviderInPanel);
        standard.forceActiveFocus();
        keyClick(Qt.Key_Space);
        compare(page.cfg_panelStyle, "standard");
        keyClick(Qt.Key_Right);
        compare(page.cfg_panelStyle, "minimal");
        keyClick(Qt.Key_Left);
        compare(page.cfg_panelStyle, "standard");
        page.applyMinimalPanelPreset();
        tryCompare(minimal, "checked", true);
        verify(!page.cfg_showProviderInPanel && !page.cfg_showPercentInPanel && !page.cfg_showCreditsInPanel && page.cfg_showMultiProviderInPanel);
        compare(page.cfg_panelQuotaLane, "secondary");
        compare(page.cfg_panelElementOrder, "meters,status,text,identity");
        compare(page.cfg_panelVisibilityRules, '{"meters":{"condition":"usageAtLeast","usedPercent":70}}');
        page.cfg_panelStyle = page.cfg_panelStyleDefault;
        tryCompare(standard, "checked", true);
        page.cfg_panelStyle = "unrecognized";
        verify(standard.checked && !minimal.checked);
        compare(page.cfg_panelStyle, "unrecognized");
    }

    function test_disclosureAndContextKeepPendingValues() {
        var page = createPage({cfg_panelQuotaLane: "secondary", cfg_menuBarDisplayMode: "resetTime"});
        if (!page) return;
        var button = findChild(page, "panelAdvancedButton");
        var options = findChild(page, "panelAdvancedOptions");
        var quota = findChild(page, "panelQuotaCombo");
        var text = findChild(page, "panelTextMode");
        var textCheck = findChild(page, "panelUsageTextCheck");
        var additional = findChild(page, "panelAdditionalButton");
        verify(!page.additionalExpanded && !textCheck.visible);
        verify(!options.visible && !quota.visible && !text.visible);
        var saved = storedValues(page);
        button.forceActiveFocus();
        keyClick(Qt.Key_Space);
        verify(page.advancedExpanded && options.visible && quota.visible);
        keyClick(Qt.Key_Space);
        verify(!page.advancedExpanded && !options.visible && !quota.visible);
        compare(storedValues(page), saved);
        verify(button.activeFocus);
        additional.forceActiveFocus();
        keyClick(Qt.Key_Space);
        verify(page.additionalExpanded && textCheck.visible);
        compare(storedValues(page), saved);
        textCheck.forceActiveFocus();
        keyClick(Qt.Key_Space);
        verify(text.visible);
        compare(text.currentValue, "resetTime");
        keyClick(Qt.Key_Space);
        verify(!text.visible);
        compare(storedValues(page), saved);
        additional.forceActiveFocus();
        keyClick(Qt.Key_Space);
        verify(!textCheck.visible && additional.activeFocus);
        page.cfg_showProviderInPanel = true;
        page.cfg_showPercentInPanel = true;
        page.cfg_showCreditsInPanel = true;
        verify(page.additionalSummary.indexOf("Provider name") >= 0);
        verify(page.additionalSummary.indexOf("Reset time") >= 0);
        verify(page.additionalSummary.indexOf("Credits") >= 0);
        // Hidden controls remain bound when Plasma restores defaults.
        page.cfg_panelQuotaLane = page.cfg_panelQuotaLaneDefault;
        page.cfg_menuBarDisplayMode = page.cfg_menuBarDisplayModeDefault;
        button.forceActiveFocus();
        keyClick(Qt.Key_Space);
        compare(quota.currentValue, "auto");
        page.cfg_showPercentInPanel = true;
        compare(text.currentValue, "percent");
    }

    function test_reorderingKeepsLayoutAndKeyboardFocusAfterDisclosure() {
        var page = createPage();
        if (!page) return;
        var layout = findChild(page, "panelOrderLayout");
        for (var i = 0; i < 3; i++) {
            page.advancedExpanded = false;
            page.cfg_panelElementOrder = "meters,text,identity,status";
            page.cfg_panelElementOrder = page.cfg_panelElementOrderDefault;
            page.advancedExpanded = true;
            page.movePanelElement(0, 1, true);
            tryCompare(page, "cfg_panelElementOrder", "status,identity,text,meters");
            tryVerify(function() {
                var rows = layout.children.filter(item => item.orderKey !== undefined);
                var identity = rows.find(item => item.orderKey === "identity");
                return rows.length === 4 && identity && identity.downButton.activeFocus
                    && layout.height > 0 && rows.every(item => item.width > 0 && item.height > 0
                        && item.y + item.height <= layout.height + 1);
            });
            keyClick(Qt.Key_Space);
            tryCompare(page, "cfg_panelElementOrder", "status,text,identity,meters");
        }
    }

    function test_closedSummaryReflectsEffectiveCustomizations() {
        var page = createPage();
        if (!page) return;
        var baseline = page.advancedSummary;
        page.cfg_panelVisibilityRules = '{"text":{"condition":"always","usedPercent":95}}';
        page.cfg_panelElementOrder = "identity,identity,status,text,meters,unknown";
        page.cfg_panelQuotaLane = "unknown";
        compare(page.advancedSummary, baseline);
        page.cfg_panelQuotaLane = "secondary";
        verify(page.advancedSummary.indexOf("Secondary") >= 0);
        page.cfg_panelElementOrder = "meters,identity,status,text";
        verify(page.advancedSummary.indexOf("Custom element order") >= 0);
        page.cfg_panelVisibilityRules = '{"text":{"condition":"runOut"},"meters":{"condition":"usageAtLeast","usedPercent":95}}';
        verify(page.advancedSummary.indexOf("2 visibility rules") >= 0);
        page.cfg_autoSelectProvider = true;
        verify(page.advancedSummary.indexOf("Highest-usage provider") >= 0);
        verify(!page.advancedExpanded);
        page.cfg_panelQuotaLane = "auto";
        page.cfg_panelElementOrder = page.cfg_panelElementOrderDefault;
        page.cfg_panelVisibilityRules = "{}";
        page.cfg_autoSelectProvider = false;
        compare(page.advancedSummary, baseline);
    }

    function test_panelProviderSelectionStaysPendingAndFollowsRoster() {
        var page = createPage();
        if (!page) return;
        // The roster loads only while the selection is expanded; these checks
        // inject the roster directly so no CLI process is spawned here. The
        // expansion gating itself is asserted by scripts/test_ui_regressions.sh.
        var controller = findChild(page, "panelProviderRosterController");
        verify(controller);
        verify(!controller.active);
        verify(!page.providersExpanded);
        compare(page.providersSummary, "All enabled providers");

        controller.enabledProviderRoster = [
            {provider: "codex", displayName: "Codex"},
            {provider: "claude", displayName: "Claude"}
        ];
        compare(page.orderedPanelProviderRoster.length, 2);
        compare(page.resolvedPanelProviderIDs().join(","), "codex,claude");

        // Toggling from the automatic set keeps the other automatic providers,
        // matching the Overview selection behavior.
        page.togglePanelProvider("claude", true);
        compare(page.cfg_panelProviderIDs, "codex,claude");
        compare(page.providersSummary, "2 providers selected");

        // Toggles follow roster order and keep selected providers that are
        // missing from the current roster.
        page.cfg_panelProviderIDs = "claude,gemini";
        page.togglePanelProvider("codex", true);
        compare(page.cfg_panelProviderIDs, "codex,claude,gemini");
        page.togglePanelProvider("claude", false);
        compare(page.cfg_panelProviderIDs, "codex,gemini");
        compare(page.providersSummary, "2 providers selected");

        page.cfg_panelProviderIDs = "__none__";
        compare(page.providersSummary, "No providers selected");
        page.cfg_panelProviderIDs = "";
        compare(page.providersSummary, "All enabled providers");
    }

    function test_absentSelectionsDoNotBlockEnabledProviders() {
        var page = createPage();
        if (!page) return;
        var controller = findChild(page, "panelProviderRosterController");
        controller.enabledProviderRoster = [{provider: "copilot", displayName: "Copilot"}];
        page.cfg_panelProviderIDs = "codex,claude,gemini,cursor";
        compare(page.selectedPanelProviderCount(), 0);
        page.togglePanelProvider("copilot", true);
        verify(page.panelProviderSelected("copilot"));
        compare(page.selectedPanelProviderCount(), 1);
        verify(page.panelProviderSelected("codex"));
    }
}
