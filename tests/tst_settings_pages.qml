import QtQuick
import QtTest

// General owns the global defaults action; Notifications owns the quota
// thresholds both of them share. Both pages read applied configuration, so
// every runtime-owned binding has to resolve without a plasmoid for these
// checks to observe the pending KCM state at all.
TestCase {
    id: testCase
    name: "SettingsPages"
    when: windowShown
    width: 620
    height: 760
    visible: true

    function i18n(text, value, second) {
        var result = value === undefined ? text : String(text).replace("%1", value);
        return second === undefined ? result : result.replace("%2", second);
    }
    function i18np(singular, plural, count) {
        return String(count === 1 ? singular : plural).replace("%1", count);
    }

    function createPage(source, properties) {
        var component = Qt.createComponent(source);
        if (component.status === Component.Error
                && /module "org\.kde\.[^"]+" is not installed/.test(component.errorString())) {
            skip("Settings page checks need the optional KDE QML modules");
            return null;
        }
        compare(component.status, Component.Ready, component.errorString());
        failOnWarning(/.*/);
        var page = createTemporaryObject(component, testCase, Object.assign({
            width: testCase.width,
            height: testCase.height
        }, properties || {}));
        verify(page !== null);
        return page;
    }

    function test_restoringDefaultsStaysPendingUntilSaved() {
        var page = createPage("../contents/ui/configGeneral.qml", {
            cfg_commandPath: "/opt/codexbar/bin/codexbar",
            cfg_provider: "codex",
            cfg_source: "cli",
            cfg_refreshInterval: 900,
            cfg_privacyMode: true,
            cfg_refreshOnOpen: true,
            cfg_includeStatus: true,
            cfg_costUsageEnabled: false,
            cfg_costHistoryDays: 90,
            cfg_costHistoryMetric: "tokens",
            cfg_quotaWarningPercent: 70,
            cfg_quotaCriticalPercent: 90,
            cfg_enableNotifications: false,
            cfg_autoUpdateIntervalHours: 48,
            cfg_menuBarDisplayMode: "pace",
            cfg_panelStyle: "minimal",
            cfg_panelQuotaLane: "primary",
            cfg_panelVisibilityRules: '{"text":{"condition":"runOut"}}',
            cfg_providerOrder: "claude,codex",
            cfg_overviewProviderIDs: "codex"
        });
        if (!page)
            return;
        compare(page.userSettingsAreDefault(), false);
        compare(page.defaultValuesPrepared, false);

        page.restoreUserDefaults();
        // Values this page only holds so one action reaches the other pages have
        // to reach their schema default too, not just the ones with controls here.
        compare(page.cfg_commandPath, "codexbar");
        compare(page.cfg_provider, "");
        compare(page.cfg_source, "");
        compare(page.cfg_refreshInterval, 300);
        compare(page.cfg_privacyMode, false);
        compare(page.cfg_refreshOnOpen, false);
        compare(page.cfg_includeStatus, false);
        compare(page.cfg_costUsageEnabled, true);
        compare(page.cfg_costHistoryDays, 30);
        compare(page.cfg_costHistoryMetric, "cost");
        compare(page.cfg_quotaWarningPercent, 80);
        compare(page.cfg_quotaCriticalPercent, 95);
        compare(page.cfg_enableNotifications, true);
        compare(page.cfg_autoUpdateIntervalHours, 24);
        compare(page.cfg_menuBarDisplayMode, "percent");
        compare(page.cfg_panelStyle, "standard");
        compare(page.cfg_panelQuotaLane, "auto");
        compare(page.cfg_panelVisibilityRules, "{}");
        compare(page.cfg_providerOrder, "");
        compare(page.cfg_overviewProviderIDs, "");
        compare(page.userSettingsAreDefault(), true);
        // The confirmation has to survive until Plasma saves, so Cancel can still
        // keep the stored settings.
        compare(page.defaultValuesPrepared, true);

        page.saveConfig();
        compare(page.defaultValuesPrepared, false);
        compare(page.costHistoryDaysEditPending, false);
        compare(page.costHistoryMetricEditPending, false);
    }

    function test_intervalControlsKeepTheirValueOnUnparsableText() {
        var page = createPage("../contents/ui/configGeneral.qml", {
            cfg_refreshInterval: 900,
            cfg_autoUpdateIntervalHours: 48
        });
        if (!page)
            return;
        var presetCombo = findChild(page, "refreshPresetCombo");
        var intervalSpin = findChild(page, "refreshIntervalSpin");
        var daysSpin = findChild(page, "costHistoryDaysSpin");
        var hoursSpin = findChild(page, "autoUpdateIntervalHoursSpin");
        verify(presetCombo !== null && intervalSpin !== null);
        verify(daysSpin !== null && hoursSpin !== null);

        // A stored preset selects its own entry and hides the custom field.
        compare(presetCombo.currentValue, 900);
        verify(!intervalSpin.visible);

        // Text without digits must not substitute an unrelated value: the
        // interval spin renders "No periodic refresh" for a disabled interval.
        compare(intervalSpin.valueFromText("", Qt.locale()), 900);
        compare(intervalSpin.valueFromText("No periodic refresh", Qt.locale()), 900);
        compare(intervalSpin.valueFromText("120 s", Qt.locale()), 120);
        // The history window mirrors the applied configuration rather than the
        // injected pending value, which resolves to the schema default here.
        compare(daysSpin.value, 30);
        compare(daysSpin.valueFromText("", Qt.locale()), 30);
        compare(hoursSpin.valueFromText("", Qt.locale()), 48);
        compare(hoursSpin.valueFromText("6 hours", Qt.locale()), 6);
        compare(page.cfg_refreshInterval, 900);
        compare(page.cfg_autoUpdateIntervalHours, 48);

        // An interval outside the presets keeps the combo on its custom entry.
        page.cfg_refreshInterval = 240;
        tryCompare(presetCombo, "currentValue", -1);
        verify(intervalSpin.visible);
    }

    function test_quotaThresholdsKeepCriticalAboveWarning() {
        var page = createPage("../contents/ui/configNotifications.qml", {
            cfg_quotaWarningPercent: 70,
            cfg_quotaCriticalPercent: 90
        });
        if (!page)
            return;
        var warningSpin = findChild(page, "quotaWarningPercentSpin");
        var criticalSpin = findChild(page, "quotaCriticalPercentSpin");
        var statusCheck = findChild(page, "notifyStatusIncidentsCheck");
        verify(warningSpin !== null && criticalSpin !== null && statusCheck !== null);
        compare(criticalSpin.from, 70);

        // Unparsable text keeps the configured threshold on both spin boxes.
        compare(warningSpin.valueFromText("", Qt.locale()), 70);
        compare(criticalSpin.valueFromText("", Qt.locale()), 90);
        compare(warningSpin.valueFromText("85% used", Qt.locale()), 85);

        // Raising the warning above the critical value carries critical with it,
        // so the widget never holds an unreachable critical threshold.
        page.cfg_quotaWarningPercent = 96;
        compare(criticalSpin.from, 96);
        compare(page.cfg_quotaCriticalPercent, 96);

        // Status incident notices stay unavailable while status fetching is off.
        verify(!statusCheck.enabled);
    }
}
