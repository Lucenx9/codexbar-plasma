import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "PanelPreviewSurface"
    when: windowShown
    width: 600
    height: 300
    visible: true

    function init() {
        failOnWarning(/.*/);
    }

    function i18n(text) {
        for (var i = 1; i < arguments.length; ++i) {
            text = text.replace("%" + i, arguments[i]);
        }
        return text;
    }
    function i18np(singular, plural, count) {
        return i18n(count === 1 ? singular : plural, count);
    }

    Component {
        id: settingsComponent
        QtObject {
            property string cfg_panelStyle: "standard"
            property string cfg_panelElementOrder: "identity,status,text,meters"
            property string cfg_panelQuotaLane: "auto"
            property string cfg_panelVisibilityRules: "{}"
            property string cfg_menuBarDisplayMode: "percent"
            property bool cfg_showMultiProviderInPanel: true
            property bool cfg_autoSelectProvider: false
            property bool cfg_showProviderInPanel: false
            property bool cfg_showPercentInPanel: false
            property bool cfg_showCreditsInPanel: false
        }
    }

    function createPreview(settings) {
        var component = Qt.createComponent("../contents/ui/components/PanelSettingsPreview.qml");
        if (component.status === Component.Error && /module "org\.kde\.[^"]+" is not installed/.test(component.errorString())) {
            skip("Panel preview checks need the optional KDE QML modules");
            return null;
        }
        compare(component.status, Component.Ready, component.errorString());
        var preview = createTemporaryObject(component, testCase, {
            configPage: settings,
            width: 580
        });
        verify(preview !== null);
        return preview;
    }

    function test_pendingSettingsRenderWithoutWritesOrInteractivePanelActions() {
        var settings = createTemporaryObject(settingsComponent, testCase);
        var preview = createPreview(settings);
        if (!preview) {
            return;
        }
        var renderer = findChild(preview, "panelPreviewRenderer");
        verify(renderer !== null);
        verify(!renderer.interactive && !renderer.animationsEnabled);
        compare(renderer.primaryText, "");
        verify(renderer.hasProviderMeters);
        settings.cfg_showProviderInPanel = true;
        settings.cfg_showPercentInPanel = true;
        tryCompare(renderer, "primaryText", "Codex 42% used");
        verify(renderer.inlinePrimaryText && !renderer.showPrimaryIdentity);
        settings.cfg_panelStyle = "minimal";
        tryCompare(renderer, "minimalStyle", true);
        settings.cfg_panelQuotaLane = "secondary";
        tryCompare(renderer, "primaryText", "Codex 27% used");
        preview.usageBarsShowUsed = false;
        tryCompare(renderer, "primaryText", "Codex 73% left");
        settings.cfg_showCreditsInPanel = true;
        tryCompare(renderer, "primaryText", "Codex 73% left 125cr");
        settings.cfg_autoSelectProvider = true;
        tryCompare(renderer, "primaryText", "Claude 39% left");
        verify(renderer.inlinePrimaryText && !renderer.showPrimaryIdentity);
        settings.cfg_panelElementOrder = "text,meters,identity,status";
        compare(renderer.applet.panelElementOrder(), ["text", "meters", "identity", "status"]);
        verify(!renderer.inlinePrimaryText && renderer.showPrimaryIdentity);
        settings.cfg_showMultiProviderInPanel = false;
        tryCompare(renderer, "hasProviderMeters", false);
        mouseClick(renderer);
        compare(settings.cfg_panelQuotaLane, "secondary");
        compare(settings.cfg_showMultiProviderInPanel, false);
        verify(renderer.width > 0 && renderer.height > 0);
    }

    function test_textKeepsItsIdentityWhenSelectedMeterIsFilteredOut() {
        var settings = createTemporaryObject(settingsComponent, testCase, {
            cfg_showPercentInPanel: true,
            cfg_panelVisibilityRules: '{"meters":{"condition":"usageAtLeast","usedPercent":50}}'
        });
        var preview = createPreview(settings);
        if (!preview) return;
        var renderer = findChild(preview, "panelPreviewRenderer");
        compare(renderer.primaryText, "42% used");
        compare(renderer.meterProviders.length, 1);
        compare(renderer.meterProviders[0].provider, "claude");
        verify(!renderer.inlinePrimaryText && renderer.showPrimaryIdentity);
        settings.cfg_panelVisibilityRules = '{}';
        tryCompare(renderer, "inlinePrimaryText", true);
        verify(!renderer.showPrimaryIdentity);
        settings.cfg_panelVisibilityRules = '{"text":{"condition":"usageAtLeast","usedPercent":80}}';
        tryCompare(renderer, "primaryText", "");
        verify(!renderer.inlinePrimaryText && !renderer.showPrimaryIdentity);
        verify(renderer.hasProviderMeters);
    }

    function test_customOrderKeepsOnlyTheIdentityNeededToIdentifyText() {
        var settings = createTemporaryObject(settingsComponent, testCase, {
            cfg_showProviderInPanel: true,
            cfg_showPercentInPanel: true,
            cfg_panelElementOrder: "identity,text,status,meters"
        });
        var preview = createPreview(settings);
        if (!preview) return;
        var renderer = findChild(preview, "panelPreviewRenderer");
        verify(renderer.hasProviderMeters && !renderer.inlinePrimaryText);
        verify(renderer.showPrimaryIdentity, "Independent text needs an identity among several meters");
        settings.cfg_autoSelectProvider = true;
        tryCompare(renderer, "primaryText", "Claude 58% used");
        verify(renderer.showPrimaryIdentity);
        settings.cfg_panelVisibilityRules = '{"meters":{"condition":"usageAtLeast","usedPercent":50}}';
        tryCompare(renderer, "showPrimaryIdentity", false);
        compare(renderer.meterProviders.length, 1);
        verify(!renderer.showPrimaryIdentity);
        settings.cfg_showMultiProviderInPanel = false;
        tryCompare(renderer, "showPrimaryIdentity", true);
        verify(renderer.primaryText.length > 0);
    }

    function test_scenarioControlsUpdateRulesMetricsAndMissingData() {
        var settings = createTemporaryObject(settingsComponent, testCase, {
            cfg_showPercentInPanel: true,
            cfg_panelVisibilityRules: '{"text":{"condition":"usageAtLeast","usedPercent":80},"meters":{"condition":"usageAtLeast","usedPercent":80}}'
        });
        var preview = createPreview(settings);
        if (!preview) {
            return;
        }
        var renderer = findChild(preview, "panelPreviewRenderer");
        compare(renderer.primaryText, "");
        verify(!renderer.hasProviderMeters);
        var combo = findChild(preview, "panelPreviewScenario");
        combo.forceActiveFocus();
        keyClick(Qt.Key_Down);
        tryCompare(preview, "scenario", "nearLimit");
        tryCompare(renderer, "primaryText", "98% used");
        verify(renderer.hasProviderMeters);
        settings.cfg_menuBarDisplayMode = "runOut";
        tryCompare(renderer, "primaryText", "20 minutes");
        settings.cfg_menuBarDisplayMode = "resetTime";
        tryCompare(renderer, "primaryText", "Resets 30 min");
        preview.resetTimesShowAbsolute = true;
        tryVerify(function () {
            return renderer.primaryText !== "Resets 30 min";
        });
        preview.scenario = "missing";
        tryCompare(renderer, "primaryText", "");
        verify(!renderer.hasProviderMeters);
        verify(renderer.showPrimaryIdentity);
        preview.scenario = "incident";
        tryVerify(function () {
            return renderer.incidentProvider !== null;
        });
        compare(renderer.incidentProvider.status, "Service incident");
        compare(settings.cfg_panelVisibilityRules, '{"text":{"condition":"usageAtLeast","usedPercent":80},"meters":{"condition":"usageAtLeast","usedPercent":80}}');
    }

    function test_runOutRequiresAForecastAndDurationsUseWholeUnits() {
        var settings = createTemporaryObject(settingsComponent, testCase, {
            cfg_showPercentInPanel: true, cfg_menuBarDisplayMode: "runOut"
        });
        var preview = createPreview(settings);
        if (!preview) return;
        var renderer = findChild(preview, "panelPreviewRenderer");
        compare(renderer.primaryText, "");
        preview.scenario = "incident";
        compare(renderer.primaryText, "");
        preview.scenario = "nearLimit";
        compare(renderer.primaryText, "20 minutes");
        compare(preview.metricText({paceOnTop: true, paceEtaSeconds: 120}), "");
        compare(preview.metricText({paceOnTop: false, paceEtaSeconds: 0}), "");
        compare(preview.metricText({paceOnTop: false, paceEtaSeconds: 90}), "2 minutes");
        compare(preview.metricText({paceOnTop: false, paceEtaSeconds: 7200}), "2 hours");
        compare(preview.metricText({paceOnTop: false, paceEtaSeconds: 172800}), "2 days");
        settings.cfg_menuBarDisplayMode = "resetTime";
        compare(preview.metricText({resetMinutes: 1.5}), "Resets 2 min");
        compare(preview.metricText({resetMinutes: 90}), "Resets 1h 30m");
        compare(preview.metricText({resetMinutes: 1500}), "Resets 1d 1h");
    }
}
