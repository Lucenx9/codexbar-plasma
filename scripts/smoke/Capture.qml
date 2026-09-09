import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

// Added only to a temporary copy of main.qml by smoke_popup.py.
Item {
    id: capture

    required property var applet
    required property string scenario
    required property string imagePath
    property bool prepared: false
    property bool navigationVerified: false
    property bool cacheRestart: false
    property double cacheSavedAtMs: 0
    property int costDetailsStep: 0
    property var costSnapshot: null
    property var costSelectionProviderMemo: null
    property var costSelectionPointsMemo: null
    property string costSelectionDayMemo: ""
    property int localizationStep: 0
    property var panelUsageSnapshot
    property var compactPanelItem
    property var displaySettingsPage
    property var providerSettingsPage
    property int settingsBehaviorStep: 0
    property int settingsCommandSerial: 0
    property var settingsCostSnapshot
    property var settingsProviderSnapshot
    readonly property bool settingsScenario: scenario.indexOf("settings-") === 0
    readonly property bool panelInformationScenario: scenario.indexOf("panel-information") === 0
    readonly property bool panelDefaultsScenario: scenario === "panel-default" || scenario === "panel-default-single"
    readonly property bool readmePanelScenario: scenario.indexOf("readme-panel-") === 0
    readonly property bool verticalPanelScenario: scenario.indexOf("panel-vertical") === 0
    readonly property bool capsulePanelScenario: verticalPanelScenario || scenario === "panel-small" || scenario === "panel-dual-edge"
    readonly property bool standardPanelScenario: scenario === "panel-standard" || scenario === "readme-panel-standard"
        || scenario === "panel-vertical" || scenario === "panel-small" || scenario === "panel-dual-edge"
        || scenario === "panel-information" || scenario === "panel-information-single"
    readonly property bool panelAppearanceScenario: scenario === "panel-standard" || scenario === "panel-minimal"
        || scenario === "panel-minimal-single" || readmePanelScenario || capsulePanelScenario || panelInformationScenario
    readonly property bool readmeScenario: scenario.indexOf("readme-") === 0
    readonly property int expectedProviderCount: scenario === "panel-information-single" || scenario === "panel-minimal-single" || scenario === "panel-default-single"
        ? 1 : (readmeScenario ? 3 : 2)

    Loader {
        id: configurationPreview
        parent: capture.applet.fullRepresentationItem
        active: capture.settingsScenario
        visible: active
        z: 100
        sourceComponent: SettingsPreview {
            applet: capture.applet
            width: capture.scenario === "settings-panel-narrow" ? 420 : 840
            viewportHeight: capture.scenario === "settings-panel-scrolled" ? 500 : 0
            pageSource: ({"settings-general": "configGeneral.qml", "settings-panel": "configPanel.qml",
                "settings-panel-advanced": "configPanel.qml", "settings-panel-narrow": "configPanel.qml",
                "settings-panel-information": "configPanel.qml",
                "settings-panel-scrolled": "configPanel.qml",
                "settings-popup": "configPopup.qml", "settings-notifications": "configNotifications.qml",
                "settings-diagnostics": "configDiagnostics.qml"})[capture.scenario]
        }
    }

    Loader {
        id: settingsPreview
        active: capture.scenario.indexOf("localization-") === 0
        visible: false
        source: "configGeneral.qml"
    }

    Loader {
        id: panelPreview
        parent: capture.applet.fullRepresentationItem
        anchors.centerIn: parent
        active: capture.scenario === "panel-rules" || capture.panelAppearanceScenario || capture.panelDefaultsScenario
        z: 100
        sourceComponent: Rectangle {
            width: capture.verticalPanelScenario ? 84 : Math.max(240, panel.compactItem ? panel.compactItem.implicitWidth + 48 : 240)
            height: capture.verticalPanelScenario ? Math.max(160, panel.height + 48) : 84
            color: panel.compactItem ? panel.compactItem.Kirigami.Theme.backgroundColor : Kirigami.Theme.backgroundColor
            Loader {
                id: panel
                readonly property Item compactItem: item as Item
                sourceComponent: capture.applet.compactRepresentation
                onLoaded: capture.compactPanelItem = item
                anchors.centerIn: parent
                width: capture.verticalPanelScenario ? 44 : (compactItem ? compactItem.implicitWidth : 0)
                height: capture.verticalPanelScenario ? (compactItem ? compactItem.implicitHeight : 0)
                    : (capture.scenario === "panel-small" || capture.panelInformationScenario ? 24
                        : (capture.panelAppearanceScenario || capture.panelDefaultsScenario ? 44 : 40))
            }
        }
    }

    Loader {
        id: providerSettingsPreview
        parent: capture.applet.fullRepresentationItem
        anchors.fill: parent
        active: capture.scenario === "provider-settings"
        visible: active
        z: 100
        sourceComponent: Rectangle {
            color: Kirigami.Theme.backgroundColor
            Loader {
                id: settingsPageLoader
                anchors.fill: parent
                source: "configProviders.qml"
                onLoaded: {
                    capture.providerSettingsPage = item;
                    item.cfg_commandPath = capture.applet.commandPath;
                }
            }
        }
    }

    function verifyScenario(condition, message) {
        if (!condition)
            throw new Error("SMOKE_FAILED: " + message);
    }

    function verifyGeneralDefaults(page) {
        var config = applet.Plasmoid.configuration;
        var row = applet.providers[applet.providerIndexForID("codex")].rows[0];
        verifyScenario(applet.displayPercent(row) === 43 && !applet.notifyLimitResets,
            "fresh defaults must show used quota and leave reset notifications off");
        verifyScenario(!config.showProviderInPanel && !config.showPercentInPanel
            && config.showMultiProviderInPanel && !applet.minimalPanel,
            "fresh defaults must show Standard icons and meters without panel text");
        config.usageBarsShowUsed = false;
        config.notifyLimitResets = true;
        config.panelStyle = "minimal";
        config.showProviderInPanel = true;
        config.showPercentInPanel = true;
        config.showMultiProviderInPanel = false;
        verifyScenario(applet.displayPercent(row) === 57 && applet.notifyLimitResets,
            "explicit preferences must override the defaults");
        page.cfg_usageBarsShowUsed = false;
        page.cfg_notifyLimitResets = true;
        page.cfg_panelStyle = "minimal";
        page.cfg_showProviderInPanel = true;
        page.cfg_showPercentInPanel = true;
        page.cfg_showMultiProviderInPanel = false;
        page.restoreUserDefaults();
        verifyScenario(page.defaultValuesPrepared && page.cfg_usageBarsShowUsed && !page.cfg_notifyLimitResets,
            "Restore all defaults did not prepare the new defaults");
        verifyScenario(!config.usageBarsShowUsed && config.notifyLimitResets,
            "restoring pending defaults changed the live configuration before Apply");
        verifyScenario(page.cfg_panelStyle === "standard" && !page.cfg_showProviderInPanel
            && !page.cfg_showPercentInPanel && page.cfg_showMultiProviderInPanel,
            "Restore all defaults did not prepare the Standard icon-and-meter preset");
        verifyScenario(applet.minimalPanel && config.showProviderInPanel && config.showPercentInPanel
            && !config.showMultiProviderInPanel,
            "restoring pending panel defaults changed the live configuration before Apply");
        config.usageBarsShowUsed = true;
        config.notifyLimitResets = false;
        config.panelStyle = "standard";
        config.showProviderInPanel = false;
        config.showPercentInPanel = false;
        config.showMultiProviderInPanel = true;
        page.defaultsActionRequested = false;
    }

    function verifyPanelDefaults() {
        var config = applet.Plasmoid.configuration;
        panelUsageSnapshot = applet.providers;
        verifyScenario(!applet.minimalPanel && !config.showProviderInPanel
            && !config.showPercentInPanel && config.showMultiProviderInPanel,
            "fresh panel defaults must use Standard icons and meters");
        verifyScenario(applet.compactText() === "" && applet.compactProviders().length === expectedProviderCount,
            "fresh panel defaults lost a provider meter or retained text");
        config.showProviderInPanel = true;
        config.showPercentInPanel = true;
        config.showMultiProviderInPanel = false;
        var selectedProvider = applet.selectedCompactProvider();
        verifyScenario(selectedProvider && applet.compactText().indexOf("%") >= 0
            && applet.compactText().indexOf(selectedProvider.title) >= 0
            && applet.compactProviders().length === 0,
            "explicit text and meter preferences must override the defaults");
        config.showProviderInPanel = false;
        config.showPercentInPanel = false;
        verifyScenario(compactPanelItem && applet.compactText() === "" && compactPanelItem.showPrimaryIdentity
            && compactPanelItem.implicitWidth > 0,
            "hiding panel text and meters lost the icon fallback");
        config.showMultiProviderInPanel = true;
        config.panelQuotaLane = "tertiary";
        verifyScenario(compactPanelItem && applet.compactProviders().length === 0 && compactPanelItem.showPrimaryIdentity,
            "missing quotas lost the icon fallback");
        config.panelQuotaLane = "auto";
        verifyScenario(applet.providers === panelUsageSnapshot, "panel defaults reloaded usage");
    }

    function preparePanelAppearance() {
        var config = applet.Plasmoid.configuration;
        panelUsageSnapshot = applet.providers;
        verifyScenario(config.panelStyle === "standard", "existing installations must retain standard appearance");
        var component = Qt.createComponent(Qt.resolvedUrl("configPanel.qml"));
        verifyScenario(component.status === Component.Ready, component.errorString());
        displaySettingsPage = component.createObject(capture, {
            cfg_panelQuotaLane: "secondary",
            cfg_panelVisibilityRules: '{"text":{"condition":"usageAtLeast","usedPercent":50}}'
        });
        var page = displaySettingsPage;
        verifyScenario(page !== null, "panel settings did not load");
        var oldRules = page.cfg_panelVisibilityRules;
        page.applyMinimalPanelPreset();
        verifyScenario(page.cfg_panelStyle === "minimal" && page.cfg_showMultiProviderInPanel
            && !page.cfg_showProviderInPanel && !page.cfg_showPercentInPanel && !page.cfg_showCreditsInPanel,
            "minimal preset did not configure its panel elements");
        verifyScenario(page.cfg_panelQuotaLane === "secondary"
            && page.cfg_panelVisibilityRules === oldRules, "preset changed quota or visibility rules");
        verifyScenario(config.panelStyle === "standard", "settings took effect before Apply");
        config.panelStyle = standardPanelScenario ? "standard" : page.cfg_panelStyle;
        if (scenario === "panel-dual-edge") config.usageBarsShowUsed = false;
        config.showMultiProviderInPanel = page.cfg_showMultiProviderInPanel;
        config.showProviderInPanel = page.cfg_showProviderInPanel;
        config.showPercentInPanel = page.cfg_showPercentInPanel;
        config.showCreditsInPanel = page.cfg_showCreditsInPanel;
        if (panelInformationScenario) {
            config.showPercentInPanel = true;
            applet.openProviderFromPanel(scenario === "panel-information-minimal" ? "claude" : "codex");
        }
        page.destroy();
        displaySettingsPage = null;
        component.destroy();
        if (scenario === "panel-minimal-single") {
            verifyScenario(applet.compactProviders().length === 1, "minimal preset hid the single-provider quota");
            config.panelStyle = "unknown";
            verifyScenario(!applet.minimalPanel && applet.compactProviders().length === 1,
                "unknown style did not preserve Standard single-provider behavior");
            config.panelStyle = "minimal";
            config.showMultiProviderInPanel = false;
            verifyScenario(applet.compactProviders().length === 0, "single-provider meter ignored visibility checkbox");
            config.showMultiProviderInPanel = true;
            config.panelQuotaLane = "tertiary";
            verifyScenario(applet.compactProviders().length === 0, "single-provider meter ignored missing quota");
            config.panelQuotaLane = "auto";
            config.panelVisibilityRules = '{"meters":{"condition":"usageAtLeast","usedPercent":100}}';
            verifyScenario(applet.compactProviders().length === 0, "single-provider meter ignored visibility rules");
            config.panelVisibilityRules = "{}";
            verifyScenario(applet.compactProviders().length === 1, "single-provider meter did not recover");
        }
    }

    function namedItems(item, name) {
        var found = item.objectName === name ? [item] : [];
        var children = item.children || [];
        for (var i = 0; i < children.length; i++)
            found = found.concat(namedItems(children[i], name));
        return found;
    }

    function verifyCapsulePanel() {
        var panel = compactPanelItem;
        var tracks = namedItems(panel, "panelMeterTrack");
        var expected = scenario === "panel-dual-edge" ? 3 : expectedProviderCount * 2;
        verifyScenario(tracks.length === expected, "automatic capsules lost a quota or invented a missing one");
        for (var i = 0; i < tracks.length; i++) {
            var track = tracks[i];
            var origin = track.mapToItem(panel, 0, 0);
            var end = track.mapToItem(panel, track.width, track.height);
            verifyScenario(track.width > 0 && track.height >= 3 && origin.x >= 0 && origin.y >= 0
                && end.x <= panel.width + 1 && end.y <= panel.height + 1, "capsule is clipped by the panel");
        }
        if (scenario === "panel-dual-edge") {
            var fills = namedItems(panel, "panelMeterFill");
            verifyScenario(fills[1].width === 0 && tracks[1].border.width > 0,
                "exhausted remaining quota lost its warning track");
        }
        verifyScenario(applet.providers === panelUsageSnapshot, "panel appearance refetched or mutated usage");
    }

    function preparePanelScenario() {
        var config = applet.Plasmoid.configuration;
        var codex = applet.providers[applet.providerIndexForID("codex")];
        panelUsageSnapshot = applet.providers;
        applet.openProviderFromPanel("codex");
        config.showProviderInPanel = true;
        config.showPercentInPanel = true;
        config.showMultiProviderInPanel = true;
        config.usageBarsShowUsed = true;
        config.panelQuotaLane = "secondary";
        verifyScenario(applet.panelDisplayRow(codex, "percent").usedPercent === 28, "secondary quota not selected");
        verifyScenario(applet.compactText().indexOf("28%") >= 0, "text does not show the selected quota");
        verifyScenario(applet.switcherMetricRow(codex).usedPercent === 43, "panel preference changed popup quota");
        config.panelQuotaLane = "tertiary";
        verifyScenario(applet.panelDisplayRow(codex, "percent") === null, "missing quota fell back to another lane");
        verifyScenario(applet.compactProviders().length === 0, "missing quotas retained meters");
        verifyScenario(applet.compactText().indexOf("%") < 0, "missing quota retained a percentage");
        config.panelQuotaLane = "primary";
        config.panelVisibilityRules = JSON.stringify({text: {condition: "usageAtLeast", usedPercent: 50},
            meters: {condition: "usageAtLeast", usedPercent: 50}});
        verifyScenario(applet.compactText() === "", "text condition did not hide healthy usage");
        verifyScenario(applet.compactProviders().length === 1 && applet.compactProviders()[0].provider === "claude",
            "meter rules were not evaluated per provider");
        config.usageBarsShowUsed = false;
        verifyScenario(applet.compactText() === "" && applet.compactProviders().length === 1,
            "left-percent preference changed the used-percent condition");
        config.panelVisibilityRules = '{"text":{"condition":"resetWithin","resetMinutes":60}}';
        var originalClock = applet.panelClockMs;
        verifyScenario(applet.compactText() === "", "distant reset satisfied the condition");
        applet.panelClockMs = Date.parse(codex.rows[0].resetsAt) - 1800000;
        verifyScenario(applet.compactText().length > 0, "reset condition did not advance with the clock");
        applet.panelClockMs = Date.parse(codex.rows[0].resetsAt) + 1;
        verifyScenario(applet.compactText() === "", "expired reset satisfied the condition");
        applet.panelClockMs = originalClock;
        config.panelVisibilityRules = '{"text":{"condition":"runOut"},"meters":{"condition":"runOut"}}';
        verifyScenario(applet.compactText() === "" && applet.compactProviders().length === 0,
            "absent forecasts satisfied the condition");
        config.panelQuotaLane = "auto";
        config.panelVisibilityRules = "{}";
        verifyScenario(applet.compactText().indexOf("57%") >= 0 && applet.compactProviders().length === 2,
            "defaults did not restore the original panel");
        config.showPercentInPanel = false;
        config.showMultiProviderInPanel = false;
        verifyScenario(applet.compactText().indexOf("%") < 0 && applet.compactProviders().length === 0,
            "rules overrode the visibility checkboxes");
        config.showPercentInPanel = true;
        config.showMultiProviderInPanel = true;
        config.panelQuotaLane = "secondary";
        console.log("SMOKE_PANEL_RULES_VERIFIED");
    }

    function verifyEmptyPanelRules() {
        var config = applet.Plasmoid.configuration;
        var wasLoading = applet.loading;
        var conditions = ["usageAtLeast", "resetWithin", "runOut"];
        for (var busy = 0; busy < 2; busy++) {
            applet.loading = busy === 1;
            for (var i = 0; i < conditions.length; i++) {
                config.panelVisibilityRules = JSON.stringify({text: {condition: conditions[i]}});
                verifyScenario(applet.compactText() === "", "missing data bypassed the text condition");
            }
            config.panelVisibilityRules = "{}";
            verifyScenario(applet.compactText().length > 0, "Always lost its loading or empty text");
        }
        applet.loading = wasLoading;
    }

    Component.onCompleted: {
        applet.expanded = true;
        console.log("SMOKE_LOADED:" + scenario);
    }

    // plasmawindowed owns the window background in a different QML engine;
    // grabToImage callbacks cannot cross that boundary. Supply the same theme
    // background inside the popup's engine so its capture is opaque.
    Rectangle {
        parent: capture.applet.fullRepresentationItem
        anchors.fill: parent
        z: -1
        color: Kirigami.Theme.backgroundColor
    }

    function verifyTabNavigation() {
        var popup = applet.fullRepresentationItem;
        var strip = findItem(popup, "providerTabsFlickable");
        var previous = findItem(popup, "previousTabsButton");
        var next = findItem(popup, "nextTabsButton");
        verifyScenario(strip && previous && next, "tab navigation controls missing");
        verifyScenario(previous.visible && next.visible, "overflow controls are hidden");
        verifyScenario(previous.x + previous.width <= strip.x
            && next.x >= strip.x + strip.width, "scroll controls overlap tabs");
        verifyScenario(!previous.enabled && next.enabled, "incorrect controls at start of strip");
        var focus = strip.selectedTab.nextItemInFocusChain(true);
        var visited = 0;
        while (strip.containsTab(focus) && visited < 20) {
            focus.forceActiveFocus(Qt.TabFocusReason);
            var position = focus.mapToItem(strip, 0, 0);
            verifyScenario(position.x >= -1 && position.x + focus.width <= strip.width + 1,
                "keyboard focus was not revealed immediately");
            visited++;
            focus = focus.nextItemInFocusChain(true);
        }
        verifyScenario(visited === 13, "not every global and provider tab is keyboard reachable");
        verifyScenario(previous.enabled && !next.enabled, "incorrect controls at end of strip");
        applet.selectedProviderID = "example-7";
        applet.selectGlobalView("overview");
        verifyScenario(strip.contentX === 0, "selection was not revealed immediately");
        navigationVerified = true;
    }

    function verifyCostDetails() {
        var section = findItem(applet.fullRepresentationItem, "providerLocalCostSection");
        var chart = findItem(section, "providerCostChart");
        var details = findItem(section, "costDrillDownSection");
        var toggle = findItem(section, "costDetailsToggle");
        if (!section || !chart || !details || !toggle)
            return false;
        if (costDetailsStep >= 8)
            return verifyCostSelectionRefresh(section, chart, details);
        if (!section.tokenCost)
            return false;
        if (costDetailsStep === 0) {
            verifyScenario(!details.visible && !section.detailsExpanded, "provider details must start collapsed");
            chart.hoveredIndex = 0;
            costSnapshot = applet.tokenCosts;
            var metric = findItem(section, "providerCostMetricCombo");
            metric.activated(1);
            costDetailsStep = 1;
            return false;
        }
        if (costDetailsStep === 1) {
            verifyScenario(applet.costHistoryShowsTokens && applet.tokenCosts === costSnapshot && !applet.costLoading,
                "provider metric switch must reuse the same payload");
            chart.hoveredIndex = 0;
            verifyScenario(!details.visible && section.selectedDay === null, "hover must not expand the popup");
            chart.hoveredIndex = -1;
            chart.moveSelection(1);
            costDetailsStep = 2;
            return false;
        }
        if (costDetailsStep === 2) {
            verifyScenario(details.visible && details.modelRows.length === 1
                && details.modelRows[0].label === "Earlier model", "first day leaked period models");
            chart.hoveredIndex = chart.points.length - 1;
            verifyScenario(details.modelRows[0].label === "Earlier model", "hover replaced the selected day");
            chart.hoveredIndex = -1;
            chart.moveSelection(1);
            costDetailsStep = 3;
            return false;
        }
        if (costDetailsStep === 3) {
            verifyScenario(section.selectedDay !== null && details.modelRows.length === 0,
                "missing daily models must not fall back to the period");
            verifyScenario(hasText(details, i18n("No model breakdown for this day.")), "missing model notice absent");
            findItem(section, "providerCostMetricCombo").activated(0);
            costDetailsStep = 4;
            return false;
        }
        if (costDetailsStep === 4) {
            verifyScenario(section.selectedDay === null && !details.visible, "metric change kept a stale day");
            if (scenario === "popup-cost-tokens") {
                verifyScenario(chart.points.length === 0, "token-only data became a cost chart");
                verifyScenario(hasText(section, i18n("Cost unavailable")), "missing cost became a zero");
                findItem(section, "providerCostMetricCombo").activated(1);
                costDetailsStep = 5;
                return false;
            }
            costDetailsStep = 5;
        }
        if (costDetailsStep === 5) {
            toggle.clicked();
            costDetailsStep = 6;
            return false;
        }
        if (costDetailsStep === 6) {
            verifyScenario(section.detailsExpanded && details.visible && details.modelRows.length === 3,
                "expanded period details must retain all period models");
            var originalMetricIndex = applet.costHistoryShowsTokens ? 1 : 0;
            var metricCombo = findItem(section, "providerCostMetricCombo");
            metricCombo.activated(1 - originalMetricIndex);
            verifyScenario(section.detailsExpanded && details.visible,
                "metric change collapsed explicitly expanded period details");
            metricCombo.activated(originalMetricIndex);
            toggle.clicked();
            chart.moveSelection(-1);
            costDetailsStep = 7;
            return false;
        }
        verifyScenario(details.visible && details.modelRows.length === 2
            && details.modelRows[0].label === "Example reasoning model", "latest day model selection failed");
        verifyScenario(details.modelRows[0].value === (scenario === "popup-cost-tokens" ? "50K tokens" : "$1.40 · 50K tokens"),
            "selected model amounts differ from the daily contract");
        verifyScenario(applet.tokenCosts === costSnapshot && !applet.costLoading,
            "day selection or expansion reloaded cost history");
        costDetailsStep = 8;
        return false;
    }

    function replaceCostSelectionProvider(providerData) {
        applet.providers = applet.providers.map(function(item) {
            return item.provider === providerData.provider ? providerData : item;
        });
    }

    function verifyCostSelectionRefresh(section, chart, details) {
        if (costDetailsStep === 15) {
            if (applet.costLoading || !section.tokenCost)
                return false;
        } else {
            verifyScenario(applet.tokenCosts === costSnapshot && !applet.costLoading,
                "selection reconciliation fetched cost data");
        }
        var next;
        switch (costDetailsStep) {
        case 8:
            costSelectionProviderMemo = section.providerData;
            costSelectionDayMemo = section.selectedDay.label;
            replaceCostSelectionProvider(JSON.parse(JSON.stringify(section.providerData)));
            break;
        case 9:
            verifyScenario(details.visible && section.selectedDay.label === costSelectionDayMemo,
                "identical background refresh cleared the pinned day");
            next = JSON.parse(JSON.stringify(section.providerData));
            next.tokenCost.daily = [next.tokenCost.daily[next.tokenCost.daily.length - 1], next.tokenCost.daily[0]];
            verifyScenario(typeof next.tokenCost.daily[0].tokens === "number"
                && isFinite(next.tokenCost.daily[0].tokens), "refresh fixture must have a measured token count");
            next.tokenCost.daily[0].tokens++;
            replaceCostSelectionProvider(next);
            break;
        case 10:
            verifyScenario(details.visible && chart.selectedIndex === 0
                && section.selectedDay.label === costSelectionDayMemo,
                "shrinking history lost the pinned day or clamped to another day");
            verifyScenario(section.selectedDay.tokens === costSelectionProviderMemo.tokenCost.daily[
                costSelectionProviderMemo.tokenCost.daily.length - 1].tokens + 1,
                "pinned details retained stale amounts after refresh");
            next = JSON.parse(JSON.stringify(costSelectionProviderMemo));
            replaceCostSelectionProvider(next);
            break;
        case 11:
            verifyScenario(details.visible && chart.selectedIndex === chart.points.length - 1
                && section.selectedDay.label === costSelectionDayMemo,
                "reordered history replaced the pinned day");
            next = JSON.parse(JSON.stringify(section.providerData));
            next.tokenCost.daily.pop();
            replaceCostSelectionProvider(next);
            break;
        case 12:
            verifyScenario(section.selectedDay === null && chart.selectedIndex === -1 && !details.visible,
                "a day outside the new window remained pinned");
            replaceCostSelectionProvider(costSelectionProviderMemo);
            chart.moveSelection(-1);
            section.detailsExpanded = true;
            chart.hoveredIndex = 0;
            costSelectionPointsMemo = chart.points;
            next = applet.copyObject(section.providerData);
            next.account = "another-synthetic-account";
            replaceCostSelectionProvider(next);
            break;
        case 13:
            verifyScenario(chart.points === costSelectionPointsMemo && chart.selectedIndex === -1
                && chart.hoveredIndex === -1 && section.selectedDay === null
                && !section.detailsExpanded && !details.visible,
                "account change retained details for the same cached cost snapshot");
            replaceCostSelectionProvider(costSelectionProviderMemo);
            next = applet.copyObject(section.providerData);
            next.account = "";
            next.organization = "First synthetic organization";
            replaceCostSelectionProvider(next);
            chart.moveSelection(-1);
            verifyScenario(section.selectedDay !== null, "organization account fixture must pin a day");
            next = applet.copyObject(next);
            next.organization = "Second synthetic organization";
            replaceCostSelectionProvider(next);
            break;
        case 14:
            verifyScenario(chart.points === costSelectionPointsMemo && section.selectedDay === null
                && chart.selectedIndex === -1 && !details.visible,
                "organization-based account change retained the pinned day");
            replaceCostSelectionProvider(costSelectionProviderMemo);
            chart.moveSelection(-1);
            applet.setCostHistoryDays(7);
            applet.applyTokenCosts();
            verifyScenario(applet.tokenCosts === costSnapshot && section.tokenCost === null && section.selectedDay === null
                && chart.selectedIndex === -1 && !details.visible,
                "requested range change retained the previous cached payload or selection");
            applet.setCostHistoryDays(30);
            break;
        case 15:
            verifyScenario(section.selectedDay === null && !details.visible,
                "range refresh restored the previous pin");
            costSnapshot = applet.tokenCosts;
            chart.moveSelection(-1);
            break;
        default:
            verifyScenario(details.visible && section.selectedDay.label === costSelectionDayMemo
                && details.modelRows[0].label === "Example reasoning model",
                "selection did not recover after scope changes");
            return true;
        }
        costDetailsStep++;
        return false;
    }

    function verifyCostCoverage() {
        var section = findItem(applet.fullRepresentationItem, "providerLocalCostSection");
        var chart = findItem(section, "providerCostChart");
        var details = findItem(section, "costDrillDownSection");
        var empty = findItem(section, "costModelsEmptyNotice");
        var partial = findItem(section, "costModelsPartialNotice");
        if (!section || !section.tokenCost || !chart || !details || !empty || !partial)
            return false;
        if (costDetailsStep === 0) {
            costSnapshot = applet.tokenCosts;
            findItem(section, "costDetailsToggle").clicked();
            costDetailsStep++;
            return false;
        }
        verifyScenario(applet.tokenCosts === costSnapshot && !applet.costLoading,
            "cost coverage inspection fetched data");
        if (costDetailsStep === 5) {
            verifyScenario(section.selectedDay === null && details.visible
                && (scenario === "popup-cost-missing-tokens"
                    ? empty.visible && empty.text === i18n("No model breakdown for this period.")
                    : partial.visible), "period model notices did not recover after day inspection");
            return true;
        }
        if (scenario === "popup-cost-missing-tokens") {
            verifyScenario(section.tokenCost.today.tokens === null && section.tokenCost.totals.tokens === null,
                "missing summary tokens became zero");
            verifyScenario(hasText(section, i18n("Tokens unavailable")), "missing token notice absent");
            verifyScenario(applet.spendTotalLine() === i18n("%1 total", applet.amountString(
                section.tokenCost.totals.cost, section.tokenCost.totals.currency)),
                "aggregate spend summary fabricated a token count");
            for (var i = 0; i < section.tokenCost.daily.length; i++)
                verifyScenario(section.tokenCost.daily[i].tokens === null, "gap filling invented token counts");
            if (costDetailsStep === 1) {
                verifyScenario(empty.visible && empty.text === i18n("No model breakdown for this period.")
                    && !partial.visible, "missing period models must have an explicit empty state");
                findItem(section, "providerCostMetricCombo").activated(1);
            } else if (costDetailsStep === 2) {
                verifyScenario(chart.points.length === 0, "missing token history became a zero-valued chart");
                findItem(section, "providerCostMetricCombo").activated(0);
            } else if (costDetailsStep === 3) {
                chart.selectedIndex = chart.points.length - 1;
            } else {
                verifyScenario(section.selectedDay.tokens === null && empty.visible
                    && empty.text === i18n("No model breakdown for this day.") && !partial.visible,
                    "missing day models or tokens lost their unknown state");
                section.clearDaySelection();
                costDetailsStep = 5;
                return false;
            }
        } else {
            if (costDetailsStep === 1) {
                verifyScenario(section.tokenCost.modelsTruncated === true
                    && details.modelRows.length === 6 && partial.visible && !empty.visible,
                    "period model cap hid its truncation notice");
                chart.moveSelection(1);
            } else if (costDetailsStep === 2) {
                verifyScenario(section.selectedDay !== null && details.modelRows.length === 1
                    && !partial.visible, "complete day inherited period truncation");
                chart.selectedIndex = chart.points.length - 1;
            } else {
                verifyScenario(section.selectedDay.modelsTruncated === true
                    && details.modelRows.length === 6 && partial.visible && !empty.visible,
                    "daily model cap hid its truncation notice");
                section.clearDaySelection();
                costDetailsStep = 5;
                return false;
            }
        }
        costDetailsStep++;
        return false;
    }

    function verifySettingsPanelPreview(page) {
        var preview = findItem(page, "panelSettingsPreview");
        var renderer = findItem(page, "panelPreviewRenderer");
        verifyScenario(preview && renderer, "panel settings preview missing");
        var disclosure = findItem(page, "panelAdvancedButton");
        var options = findItem(page, "panelAdvancedOptions");
        var textMode = findItem(page, "panelTextMode");
        var additional = findItem(page, "panelAdditionalOptions");
        verifyScenario(additional && !additional.visible, "additional information is visible by default");
        verifyScenario(disclosure && options && textMode && !options.visible && !textMode.visible,
            "panel details or text format are visible by default");
        var snapshots = applet.providers;
        var serial = applet.commandRunSerial;
        var liveStyle = applet.Plasmoid.configuration.panelStyle;
        page.cfg_showPercentInPanel = true;
        page.cfg_showProviderInPanel = true;
        page.cfg_panelElementOrder = "meters,text,identity,status";
        verifyScenario(renderer.primaryText.indexOf("42%") >= 0
            && renderer.applet.panelElementOrder()[0] === "meters", "preview ignored pending text or order");
        page.cfg_panelStyle = "minimal";
        verifyScenario(renderer.minimalStyle && !renderer.animationsEnabled && !renderer.interactive,
            "preview did not apply pending style immediately");
        preview.scenario = "nearLimit";
        verifyScenario(renderer.primaryText.indexOf("98%") >= 0, "near-limit preview did not update");
        page.cfg_panelVisibilityRules = '{"meters":{"condition":"usageAtLeast","usedPercent":95}}';
        verifyScenario(renderer.applet.compactProviders().length === 1, "preview ignored conditional meters");
        preview.scenario = "missing";
        verifyScenario(renderer.applet.compactProviders().length === 0 && renderer.implicitWidth > 0,
            "no-data preview lost icon fallback");
        preview.scenario = "incident";
        verifyScenario(renderer.incidentProvider !== null, "incident preview lost service status");
        page.cfg_panelVisibilityRules = "{}";
        page.cfg_panelStyle = "standard";
        page.cfg_panelElementOrder = "identity,status,text,meters";
        preview.scenario = "normal";
        verifyScenario(renderer.inlinePrimaryText && !renderer.showPrimaryIdentity,
            "selected text has a duplicate provider identity");
        page.additionalExpanded = true;
        verifyScenario(additional.visible && textMode.visible, "additional information did not expose the text format");
        page.additionalExpanded = false;
        verifyScenario(!textMode.visible && page.cfg_showPercentInPanel,
            "collapsing additional information changed the panel content");
        page.cfg_showPercentInPanel = false;
        page.cfg_showProviderInPanel = false;
        page.advancedExpanded = true;
        verifyScenario(options.visible && !textMode.visible, "disclosure did not reveal only its own options");
        page.cfg_panelQuotaLane = "secondary";
        page.cfg_panelVisibilityRules = '{"meters":{"condition":"usageAtLeast","usedPercent":70}}';
        var summary = page.advancedSummary;
        page.advancedExpanded = false;
        verifyScenario(!options.visible && page.advancedSummary === summary
            && page.cfg_panelQuotaLane === "secondary", "collapsing details reset a pending setting");
        page.cfg_panelQuotaLane = "auto";
        page.cfg_panelVisibilityRules = "{}";
        verifyScenario(applet.Plasmoid.configuration.panelStyle === liveStyle
            && !applet.Plasmoid.configuration.showPercentInPanel
            && applet.providers === snapshots && applet.commandRunSerial === serial,
            "pending preview changed live settings or executed a command");
    }

    function verifyPopupContent() {
        var popup = applet.fullRepresentationItem;
        var config = applet.Plasmoid.configuration;
        var pace = findItem(popup, "usagePaceLabel");
        var marker = findItem(popup, "usagePaceMarker");
        var credits = findItem(popup, "creditsSection");
        var details = findItem(popup, "providerDetailsSection");
        if (!pace || !marker || !credits || !details)
            return false;
        if (!navigationVerified) {
            verifyScenario(pace.visible && marker.visible && credits.visible && details.visible,
                "optional content changed default visibility");
            var providers = applet.providers;
            var costs = applet.tokenCosts;
            var memo = applet.notificationMemo;
            var serial = applet.commandRunSerial;
            config.showPopupPace = false;
            config.showPopupCredits = false;
            config.showPopupProviderDetails = false;
            verifyScenario(!pace.visible && !marker.visible && !credits.visible && !details.visible,
                "popup content switches left a section visible");
            verifyScenario(applet.providers === providers && applet.tokenCosts === costs
                && applet.notificationMemo === memo && applet.commandRunSerial === serial,
                "popup content switches changed data, notifications or commands");
            config.showPopupPace = true;
            config.showPopupCredits = true;
            config.showPopupProviderDetails = true;
            verifyScenario(pace.visible && marker.visible && credits.visible && details.visible,
                "popup content did not return without fetching");
            config.showPopupPace = false;
            config.showPopupCredits = false;
            config.showPopupProviderDetails = false;
            navigationVerified = true;
        }
        return !pace.visible && !credits.visible && !details.visible;
    }

    function containsPrivateText(item) {
        if (!item || item.visible === false)
            return false;
        var values = [item.text, item.plainText, item.Accessible.name];
        for (var value of values) {
            if (typeof value === "string" && /demo@example|Example team|Example project|Another project|Documentation site|Unpriced experiment|Example model|Earlier model/.test(value))
                return true;
        }
        for (var child of item.children) {
            if (containsPrivateText(child))
                return true;
        }
        return false;
    }

    function verifyPrivacy() {
        if (!applet.privacyMode)
            return false;
        if (scenario === "privacy-provider" && (applet.accountLoadingForProvider("codex")
                || applet.accountOptionsForProvider("codex").length !== 2))
            return false;
        if (scenario === "privacy-sessions" && (applet.sessionsLoading || applet.sessions.length !== 2))
            return false;
        verifyScenario(applet.providers === settingsProviderSnapshot && applet.tokenCosts === settingsCostSnapshot,
            "privacy mode mutated source snapshots");
        verifyScenario(applet.panelToolTipText().indexOf("demo@example.com") < 0,
            "panel tooltip exposes account in privacy mode");
        if (scenario === "privacy-provider") {
            var options = applet.accountOptionsForProvider("codex");
            verifyScenario(applet.accountDisplayLabel(options[0], 0) === "Account 1"
                && applet.accountIsSelected(options[0], applet.presentedProviderData),
                "private account labels changed default account selection");
            verifyScenario(applet.accountLabel(options[0]) === "demo@example.com",
                "privacy mode changed the account command key");
            var cursor = JSON.parse(JSON.stringify(applet.selectedProviderData));
            cursor.provider = "cursor";
            cursor.rows[0].usedPercent = 100;
            cursor.rows[0].leftPercent = 0;
            cursor.providerCost = {percentUsed: 32, spendLine: "Example team billing"};
            var privateCursor = applet.providerPresentation(cursor);
            verifyScenario(applet.panelDisplayRow(privateCursor, "percent").usedPercent === 32
                && applet.switcherMetricRow(privateCursor).usedPercent === 32,
                "privacy changed Cursor's included-plan quota fallback");
        }
        if (scenario === "privacy-sessions") {
            var sessionView = findItem(applet.fullRepresentationItem, "sessionsView");
            verifyScenario(sessionView !== null, "sessions view is missing");
            sessionView.copySessionValue("demo@example.com", "privacy-test");
            verifyScenario(sessionView.copiedValueKey === "", "private session allowed copying");
        }
        verifyScenario(!containsPrivateText(applet.fullRepresentationItem), "private text remains visible");
        if (scenario === "privacy-cost-details")
            return verifyPrivateCostDetails();
        return true;
    }

    function verifyPrivateCostDetails() {
        var section = findItem(applet.fullRepresentationItem, "providerLocalCostSection");
        var chart = findItem(section, "providerCostChart");
        var details = findItem(section, "costDrillDownSection");
        if (!section || !section.tokenCost || !chart || !details)
            return false;
        verifyScenario(section.tokenCost.windowLabel === applet.costHistoryWindowLabel(section.tokenCost, 30)
            && section.tokenCost.valueMode === "estimated", "privacy lost the cost period or estimation qualifier");
        verifyScenario(applet.tokenCosts === settingsCostSnapshot, "private drill-down changed cost snapshots");
        if (settingsBehaviorStep === 0) {
            costSelectionProviderMemo = applet.selectedProviderData;
            findItem(section, "costDetailsToggle").clicked();
            verifyScenario(details.modelRows.length === 6 && details.modelRows[0].label === "Model 1"
                && findItem(section, "costModelsPartialNotice").visible,
                "private period models lost amounts, anonymity or truncation");
            chart.moveSelection(-1);
        } else if (settingsBehaviorStep === 1) {
            verifyScenario(section.selectedDay !== null && details.modelRows.length === 6
                && details.modelRows[0].label === "Model 1"
                && findItem(section, "costModelsPartialNotice").visible,
                "private daily models lost amounts, anonymity or truncation");
            findItem(section, "providerCostMetricCombo").activated(1);
        } else if (settingsBehaviorStep === 2) {
            verifyScenario(section.selectedDay === null, "private metric switch retained its day pin");
            chart.moveSelection(-1);
            var next = JSON.parse(JSON.stringify(applet.selectedProviderData));
            next.account = "";
            next.organization = "Example team A";
            replaceCostSelectionProvider(next);
        } else if (settingsBehaviorStep === 3) {
            verifyScenario(section.selectedDay === null, "private account switch retained its day pin");
            chart.moveSelection(-1);
            var nextOrganization = JSON.parse(JSON.stringify(applet.selectedProviderData));
            nextOrganization.organization = "Example team B";
            replaceCostSelectionProvider(nextOrganization);
        } else if (settingsBehaviorStep === 4) {
            verifyScenario(section.selectedDay === null, "private organization switch retained its day pin");
            replaceCostSelectionProvider(costSelectionProviderMemo);
        } else {
            chart.selectedIndex = chart.points.length - 1;
            applet.costErrorText = "demo@example.com private cost error";
            verifyScenario(section.costErrorText === i18n("Details hidden by privacy mode."),
                "private cost error was exposed");
            findItem(applet.fullRepresentationItem, "providerScroll").contentItem.contentY = section.y;
            return true;
        }
        // Source identity changes above simulate an account switch, not a CLI refresh.
        settingsProviderSnapshot = applet.providers;
        settingsBehaviorStep++;
        return false;
    }

    function verifyRefreshOnOpen() {
        var config = applet.Plasmoid.configuration;
        if (settingsBehaviorStep === 0) {
            settingsCommandSerial = applet.commandRunSerial;
            settingsCostSnapshot = applet.tokenCosts;
            applet.usageLastRefreshAttemptAtMs = Date.now() - 300001;
            applet.usageLastCompletedAtMs = Date.now() - 300001;
            applet.refreshUsageOnOpen();
            verifyScenario(applet.commandRunSerial === settingsCommandSerial, "default popup opening refreshed usage");
            config.refreshOnOpen = true;
            applet.usageLastCompletedAtMs = Date.now();
            applet.refreshUsageOnOpen();
            verifyScenario(applet.commandRunSerial === settingsCommandSerial, "fresh popup opening refreshed usage");
            applet.usageLastCompletedAtMs = Date.now() - 300001;
            applet.expanded = false;
            applet.expanded = true;
            settingsBehaviorStep = 1;
            return false;
        }
        if (applet.loading || applet.commandRunSerial === settingsCommandSerial)
            return false;
        var serial = applet.commandRunSerial;
        applet.refreshUsageOnOpen();
        verifyScenario(applet.commandRunSerial === serial && applet.tokenCosts === settingsCostSnapshot,
            "reopening fresh popup fetched usage or local history");
        return true;
    }

    function scenarioReady() {
        if (scenario === "usage-cache-restart") {
            if (applet.providers.length !== 2)
                return false;
            if (cacheRestart) {
                verifyScenario(applet.providers.every(function(item) {
                    return item.usageStale === true && item.account === "" && item.rows.length === 2;
                }), "restarted process did not restore redacted stale quotas");
                verifyScenario(applet.loading && applet.usageLastCompletedAtMs < 0,
                    "restored cache was counted as a successful refresh");
                return true;
            }
            if (applet.loading || !Plasmoid.configuration.usageCache)
                return false;
            if (!cacheSavedAtMs)
                cacheSavedAtMs = Date.now();
            // Allow Plasma's deferred KConfig sync to reach disk before exiting.
            return Date.now() - cacheSavedAtMs > 6000;
        }
        if (scenario === "usage-retention") {
            if (navigationVerified)
                return true;
            if (applet.loading || applet.costLoading || applet.providers.length !== 2)
                return false;
            var previous = applet.providers;
            var measuredAt = previous[0].lastGoodAtMs;
            for (var includePrimary of [true, false]) {
                var extraPayload = {provider: "codex", usage: {
                    updatedAt: new Date(measuredAt).toISOString(),
                    extraRateWindows: [
                        {title: "Private extra A", window: {usedPercent: 90}},
                        {title: "Private extra B", window: {usedPercent: 0}}
                    ]
                }};
                if (includePrimary)
                    extraPayload.usage.primary = {usedPercent: 72};
                applet.commitUsageSnapshot([applet.normalizeProvider(extraPayload)]);
                for (var restart = 0; restart < 2; restart++) {
                    applet.providers = [];
                    applet.restoreUsageCache();
                    var extraRows = applet.providers[0].rows.filter(function(row) { return row.lane === "extra"; });
                    verifyScenario(extraRows.length === 2 && extraRows[0].usedPercent === 90
                        && extraRows[1].usedPercent === 0 && applet.providers[0].usageStale
                        && applet.providers[0].rows.length === (includePrimary ? 3 : 2),
                        "cache restoration lost extra-only, multiple, or measured-zero quota windows");
                    verifyScenario(Plasmoid.configuration.usageCache.indexOf("Private extra") < 0,
                        "extra quota cache persisted provider prose");
                }
            }
            applet.commitUsageSnapshot(previous);
            applet.parseOutput("{", "Synthetic malformed response");
            verifyScenario(applet.providers.length === 2 && applet.providers[0].rows.length === 2,
                "a malformed refresh erased the last valid quotas");
            verifyScenario(applet.providers[0].usageStale && applet.providers[0].lastGoodAtMs === measuredAt,
                "a failed refresh changed the measurement time");
            verifyScenario(applet.notificationObservations().every(function(item) { return item.pending; }),
                "retained usage is eligible for notifications");
            verifyScenario(applet.panelToolTipText().indexOf("Last known usage") >= 0,
                "panel tooltip presents retained usage as current");
            var emptyMeter = applet.normalizeProvider({provider: "codex"});
            emptyMeter.usageStale = true;
            emptyMeter.lastGoodAtMs = measuredAt;
            verifyScenario(applet.panelMeterDescription(emptyMeter) === applet.lastGoodUsageText(emptyMeter),
                "missing retained quota adds an orphan separator to its accessible description");
            var statusFailure = applet.providerErrorPayload("codex", "Synthetic account failure");
            statusFailure.status = {indicator: "major", incidentId: "synthetic-incident", description: "Synthetic outage"};
            applet.setNotificationProviderRefreshPending("codex", true);
            applet.commitUsageSnapshot([applet.normalizeProvider(statusFailure), previous[1]]);
            var statusObservation = applet.notificationObservations()[0];
            verifyScenario(applet.providers[0].usageStale && applet.providers[0].rows.length === 2
                && applet.providers[0].hasIncident && statusObservation.statusKnown
                && statusObservation.statusActive && !statusObservation.pending && statusObservation.rows.length === 0,
                "retained quotas hid a fresh incident or supplied stale notification evidence");
            statusFailure.status = {indicator: "none", description: "Operational"};
            applet.commitUsageSnapshot([applet.normalizeProvider(statusFailure), previous[1]]);
            statusObservation = applet.notificationObservations()[0];
            verifyScenario(applet.providers[0].usageStale && !applet.providers[0].hasIncident
                && statusObservation.statusKnown && !statusObservation.statusActive && !statusObservation.pending,
                "a fresh incident resolution was lost during quota failure");
            applet.expireStaleUsage(measuredAt + 24 * 60 * 60 * 1000 + 1);
            verifyScenario(applet.providers[0].rows.length === 0 && applet.providers[0].statusKnown
                && applet.providers[0].status === "Operational", "quota expiry erased fresh service status");
            applet.commitUsageSnapshot(previous);
            applet.parseOutput("null", "");
            verifyScenario(applet.providers[0].rows.length === 2, "invalid envelope erased quotas");
            verifyScenario(applet.notificationObservations().every(function(item) { return item.pending; }),
                "retained service status was promoted to a fresh observation");
            var sourceName = applet.commandWithRunNonce("synthetic timeout");
            var descriptor = applet.buildCommandDescriptor("providerConfig", "");
            var descriptors = {};
            descriptors[sourceName] = descriptor;
            applet.activeCommandDescriptors = descriptors;
            applet.handleCommandTimeout(sourceName, descriptor);
            verifyScenario(applet.providers[0].rows.length === 2, "timeout erased quotas");
            applet.finishProviderFallback([previous[0],
                applet.normalizeProvider(applet.providerErrorPayload("claude", "Synthetic provider timeout"))]);
            verifyScenario(!applet.providers[0].usageStale && applet.providers[1].usageStale,
                "partial refresh did not distinguish current and retained providers");
            verifyScenario(applet.providerTokenCost("codex") !== null && applet.providerTokenCost("claude") !== null,
                "retention fixture needs cost snapshots for both providers");
            verifyScenario(applet.providers[0].tokenCost !== null && applet.providers[1].tokenCost === null,
                "provider fallback reattached token costs to retained usage");
            applet.parseCostOutput("{", "Synthetic cost failure", applet.costHistoryDays);
            verifyScenario(applet.providers[1].tokenCost === null,
                "cost refresh reattached token costs to retained usage");
            var retainedHistoryDays = applet.costHistoryDays;
            applet.setCostHistoryDays(7);
            applet.setCostHistoryDays(retainedHistoryDays);
            verifyScenario(applet.providers[0].tokenCost !== null && applet.providers[1].tokenCost === null,
                "range selection reattached token costs to retained usage");
            applet.commitUsageSnapshot(previous);
            verifyScenario(applet.providers.every(function(item) { return !item.usageStale && !item.error; }),
                "successful refresh did not clear stale state");
            verifyScenario(applet.providers.every(function(item) { return item.tokenCost !== null; }),
                "successful usage refresh did not restore token costs");
            var ancientAccount = applet.copyObject(previous[0]);
            ancientAccount.updatedAt = new Date(Date.now() - 25 * 60 * 60 * 1000).toISOString();
            applet.replaceProviderSnapshot("codex", ancientAccount);
            verifyScenario(applet.providers[0].usageStale && applet.providers[0].tokenCost === null,
                "account selection attached token costs to an ancient measurement");
            applet.commitUsageSnapshot(previous);
            for (var creditBalance of [0, 12]) {
                var oldCreditTime = new Date(Date.now() - 25 * 60 * 60 * 1000).toISOString();
                var creditOnly = applet.normalizeProvider({provider: "codex",
                    credits: {remaining: creditBalance, updatedAt: oldCreditTime}});
                verifyScenario(creditOnly.updatedAt === oldCreditTime && creditOnly.rows.length === 0,
                    "credits-only fixture did not use the supplemental timestamp");
                applet.commitUsageSnapshot([creditOnly, previous[1]]);
                verifyScenario(!applet.providers[0].usageStale && applet.providers[0].credits === creditBalance
                    && applet.providers[0].rows.length === 0 && applet.providers[0].error === ""
                    && applet.lastUpdatedText.indexOf("Showing last known usage") < 0,
                    "a successful credits-only response entered quota retention or lost its balance");
                applet.expireStaleUsage(Date.now() + 60000);
                verifyScenario(applet.providers[0].credits === creditBalance && applet.providers[0].error === ""
                    && JSON.parse(Plasmoid.configuration.usageCache).snapshots.length === 1
                    && JSON.parse(Plasmoid.configuration.usageCache).snapshots[0].provider === "claude",
                    "quota expiry erased current credits or cached a provider without measured quotas");
            }
            applet.commitUsageSnapshot(previous);
            var saved = Plasmoid.configuration.usageCache;
            verifyScenario(saved.length > 0 && saved.indexOf("demo@example.com") < 0
                && saved.indexOf("Example team") < 0 && saved.indexOf("pace") < 0,
                "persisted cache is missing or contains identity/forecast data");
            var oldCache = JSON.parse(saved);
            oldCache.snapshots[0].windows.primary.usedPercent = 9;
            var configStamp = applet.providerConfigStamp;
            for (var initialCache of ["", "{broken", JSON.stringify(oldCache)]) {
                applet.providerConfigStamp = "";
                Plasmoid.configuration.usageCache = initialCache;
                applet.providers = [];
                applet.commitUsageSnapshot(previous);
                var earlyUpdateLabel = applet.lastUpdatedText;
                verifyScenario(Plasmoid.configuration.usageCache === initialCache,
                    "usage overwrote saved quotas before the configuration context was known");
                applet.handleProviderConfigWatch(configStamp);
                verifyScenario(Plasmoid.configuration.usageCache.length > 0
                    && JSON.parse(Plasmoid.configuration.usageCache).snapshots[0].windows.primary.usedPercent
                        === previous[0].rows[0].usedPercent,
                    "late checksum did not persist the first successful refresh or left an older cache");
                verifyScenario(applet.lastUpdatedText === earlyUpdateLabel,
                    "late checksum erased the successful early refresh label");
            }
            applet.providerConfigStamp = "";
            Plasmoid.configuration.usageCache = saved;
            applet.providers = [];
            applet.commitUsageSnapshot([previous[0]]);
            applet.handleProviderConfigWatch(configStamp);
            verifyScenario(applet.providers.length === 2 && !applet.providers[0].usageStale
                && applet.providers[1].usageStale && applet.providers[1].rows.length > 0
                && applet.providers[1].lastGoodAtMs === previous[1].lastGoodAtMs
                && JSON.parse(Plasmoid.configuration.usageCache).snapshots.length === 2,
                "partial early refresh evicted an unrefreshed provider from memory or disk cache");
            verifyScenario(applet.lastUpdatedText === i18n("Showing last known usage"),
                "partial early refresh did not mark the restored provider as last known");
            applet.providerConfigStamp = "";
            Plasmoid.configuration.usageCache = saved;
            applet.providers = [];
            applet.commitUsageSnapshot([previous[0],
                applet.normalizeProvider(applet.providerErrorPayload("claude", "Early failure"))]);
            applet.handleProviderConfigWatch(configStamp);
            verifyScenario(!applet.providers[0].usageStale && applet.providers[1].usageStale
                && JSON.parse(Plasmoid.configuration.usageCache).snapshots.length === 2,
                "late checksum failed to merge and save partial success with retained quotas");
            applet.providers = [];
            applet.restoreUsageCache();
            verifyScenario(applet.providers.length === 2 && applet.providers[0].account === ""
                && applet.providers[0].usageStale && applet.providers[0].lastGoodAtMs === measuredAt,
                "cache restoration lost quotas, freshness, or redaction");
            verifyScenario(applet.providers.every(function(item) { return item.tokenCost === null; }),
                "cache restoration attached token costs to retained quotas");
            applet.providers = [applet.normalizeProvider(applet.providerErrorPayload("codex", "Early failure")), previous[1]];
            applet.restoreUsageCache();
            verifyScenario(applet.providers[0].usageStale && applet.providers[0].rows.length === 2
                && !applet.providers[1].usageStale, "late checksum discarded early failures or replaced healthy data");
            var healthy = applet.providers[1];
            applet.expireStaleUsage(measuredAt + 24 * 60 * 60 * 1000 + 1);
            verifyScenario(applet.providers[0].rows.length === 0 && applet.providers[0].error === "Early failure"
                && applet.providers[1] === healthy && applet.lastUpdatedText === "",
                "in-memory expiry kept old quotas, lost the error, or replaced healthy usage");
            verifyScenario(applet.providerUsageTimestamp(applet.providers[0]) === ""
                && applet.providers[0].lastGoodAtMs === 0 && applet.providers[0].usageStale === false,
                "an expired provider displays another provider's update time");
            applet.providers = [];
            Plasmoid.configuration.usageCache = saved;
            applet.restoreUsageCache();
            applet.expireStaleUsage(Math.max(applet.providers[0].lastGoodAtMs, applet.providers[1].lastGoodAtMs)
                + 24 * 60 * 60 * 1000 + 1);
            verifyScenario(applet.providers.every(function(item) { return item.rows.length === 0 && item.error.length > 0; })
                && Plasmoid.configuration.usageCache === "", "expired restart data survived in memory or on disk");
            applet.commitUsageSnapshot(previous);
            applet.selectedProviderID = "codex";
            applet.selectionInitialized = true;
            applet.invalidateUsageData("codex");
            verifyScenario(applet.providers.length === 2 && applet.providers[0].rows.length === 0
                && applet.providers[1].rows.length === 2 && applet.selectedProviderID === "codex"
                && JSON.parse(Plasmoid.configuration.usageCache).snapshots.length === 1
                && JSON.parse(Plasmoid.configuration.usageCache).snapshots[0].provider === "claude",
                "account invalidation reused quotas, moved selection, or dropped healthy cache");
            applet.providers = [];
            Plasmoid.configuration.usageCache = saved;
            applet.providerConfigStamp = "changed configuration";
            applet.restoreUsageCache();
            verifyScenario(applet.providers.length === 0 && Plasmoid.configuration.usageCache === "",
                "changed configuration restored another scope's usage");
            applet.commitUsageSnapshot(previous);
            applet.startProviderFallbackForProviders([]);
            verifyScenario(applet.providers.length === 0 && Plasmoid.configuration.usageCache === "",
                "disabling every provider retained cached quotas");
            applet.commitUsageSnapshot(previous);
            applet.failUsageRefresh("Synthetic network failure. Try again.");
            applet.selectedProviderID = "codex";
            applet.selectionInitialized = true;
            navigationVerified = true;
            return true;
        }
        if (readmeScenario && !readmePanelScenario) {
            if (!prepared || applet.loading || applet.costLoading || applet.providers.length !== 3)
                return false;
            if (scenario === "readme-sessions")
                return applet.sessionsSelected && !applet.sessionsLoading && applet.sessions.length === 4;
            if (scenario === "readme-spend")
                return applet.spendSelected && applet.spendProviderCosts().length === 2;
            if (scenario === "readme-codex")
                return applet.selectedProviderID === "codex" && !!applet.tokenCosts.codex;
            return applet.overviewSelected;
        }
        if (settingsScenario) {
            var preview = configurationPreview.item as SettingsPreview;
            if (preview === null || !preview.ready)
                return false;
            if (scenario === "settings-general" && !navigationVerified) {
                verifyGeneralDefaults(preview.page);
                navigationVerified = true;
            }
            if (scenario.indexOf("settings-panel") === 0 && !navigationVerified) {
                verifySettingsPanelPreview(preview.page);
                if (scenario === "settings-panel-advanced") {
                    preview.page.advancedExpanded = true;
                    preview.page.cfg_panelQuotaLane = "secondary";
                    preview.page.cfg_panelVisibilityRules = '{"meters":{"condition":"usageAtLeast","usedPercent":70}}';
                    preview.page.cfg_showPercentInPanel = true;
                    findItem(preview.page, "panelSettingsPreview").scenario = "nearLimit";
                } else if (scenario === "settings-panel-narrow") {
                    preview.page.font.pointSize *= 1.3;
                    preview.page.additionalExpanded = true;
                    preview.page.cfg_showProviderInPanel = true;
                    preview.page.cfg_showPercentInPanel = true;
                    preview.page.cfg_showCreditsInPanel = true;
                } else if (scenario === "settings-panel-information") {
                    preview.page.additionalExpanded = true;
                    preview.page.cfg_showPercentInPanel = true;
                } else if (scenario === "settings-panel-scrolled") {
                    preview.page.additionalExpanded = true;
                    preview.page.advancedExpanded = true;
                    preview.page.cfg_showPercentInPanel = true;
                }
                navigationVerified = true;
                return false;
            }
            if (scenario.indexOf("settings-panel") === 0) {
                if (scenario === "settings-panel-scrolled") {
                    var endY = preview.page.flickable.contentHeight - preview.page.flickable.height;
                    if (preview.page.flickable.contentY < endY - 1) {
                        preview.page.flickable.contentY = endY;
                        return false;
                    }
                    var pinnedPreview = findItem(preview.page, "panelSettingsPreview");
                    var previewTop = pinnedPreview.mapToItem(preview.page, 0, 0).y;
                    verifyScenario(previewTop >= 0 && previewTop + pinnedPreview.height <= preview.page.height,
                        "panel preview disappeared while scrolling the advanced options");
                }
                var tracks = namedItems(preview.page, "panelMeterTrack");
                var renderer = findItem(preview.page, "panelPreviewRenderer");
                var expectedTracks = scenario === "settings-panel-advanced" ? 2 : 4;
                verifyScenario(tracks.length === expectedTracks, "settings preview lost its quota capsules");
                for (var i = 0; i < tracks.length; i++) {
                    var end = tracks[i].mapToItem(renderer, tracks[i].width, tracks[i].height);
                    verifyScenario(tracks[i].width > 0 && tracks[i].height >= 3
                        && end.x <= renderer.width + 1 && end.y <= renderer.height + 1,
                        "settings preview clipped a quota capsule");
                }
                var labels = namedItems(preview.page, "panelProviderText").filter(function(item) { return item.visible; });
                if (preview.page.cfg_showPercentInPanel) {
                    verifyScenario(renderer.inlinePrimaryText && !renderer.showPrimaryIdentity && labels.length === 1,
                        "settings preview did not group selected text with its meter");
                    var label = labels[0];
                    verifyScenario(label.width > 0 && label.mapToItem(renderer, label.width, 0).x <= renderer.width + 1,
                        "settings preview clipped the selected provider text");
                }
            }
            return true;
        }
        if (scenario === "provider-settings") {
            var page = providerSettingsPage;
            if (!page || page.loading || page.providers.length !== 5)
                return false;
            if (!navigationVerified) {
                var bar = findItem(page, "providerFilterBar");
                var search = findItem(page, "providerSearchField");
                var serial = page.commandRunSerial;
                var selected = page.selectedProviderID;
                bar.setCurrentIndex(1);
                verifyScenario(page.visibleProviders.length === 2, "enabled provider filter failed");
                bar.setCurrentIndex(2);
                verifyScenario(page.visibleProviders.length === 3, "disabled provider filter failed");
                search.text = "missing-provider";
                verifyScenario(page.visibleProviders.length === 0, "empty provider search failed");
                page.clearProviderFilters();
                verifyScenario(page.visibleProviders.length === 5 && page.selectedProviderID === selected
                    && page.commandRunSerial === serial, "filters changed provider selection or executed a command");
                bar.setCurrentIndex(1);
                navigationVerified = true;
            }
            return true;
        }
        if (scenario === "tabs-overflow") {
            if (!prepared || applet.providers.length !== 10)
                return false;
            var strip = findItem(applet.fullRepresentationItem, "providerTabsFlickable");
            var next = findItem(applet.fullRepresentationItem, "nextTabsButton");
            if (!strip || !strip.interactive || !next || !next.visible)
                return false;
            if (!navigationVerified)
                verifyTabNavigation();
            return true;
        }
        if (scenario === "loading")
            return applet.loading && applet.providers.length === 0;
        if (applet.loading || applet.costLoading || applet.providers.length !== expectedProviderCount)
            return false;
        var codex = applet.providers[applet.providerIndexForID("codex")];
        var claude = applet.providers[applet.providerIndexForID("claude")];
        if (!codex || codex.rows.length !== 2 || codex.error.length > 0)
            return false;
        if (panelAppearanceScenario) {
            var expectedClaudeRows = scenario === "panel-dual-edge" ? 1 : 2;
            if (expectedProviderCount >= 2 && (!claude || claude.error.length > 0 || claude.rows.length !== expectedClaudeRows))
                return false;
            verifyScenario(applet.providers === panelUsageSnapshot, "panel preset reloaded usage");
            verifyScenario(applet.minimalPanel === !standardPanelScenario, "panel style did not reach the renderer");
            if (panelInformationScenario) {
                if (!compactPanelItem) return false;
                var labels = namedItems(compactPanelItem, "panelProviderText").filter(function(item) { return item.visible; });
                verifyScenario(compactPanelItem.inlinePrimaryText && !compactPanelItem.showPrimaryIdentity && labels.length === 1,
                    "selected panel text duplicated or lost its provider identity");
                verifyScenario(labels[0].text === applet.compactText() && labels[0].width > 0,
                    "selected panel text is missing");
                verifyCapsulePanel();
            } else {
                verifyScenario(applet.compactText() === "", "minimal preset left panel text visible");
            }
            return panelPreview.item !== null && applet.compactProviders().length === expectedProviderCount;
        }
        if (panelDefaultsScenario) {
            if (prepared)
                verifyScenario(applet.providers === panelUsageSnapshot, "panel defaults reloaded usage");
            return prepared && panelPreview.item !== null && applet.compactText() === ""
                && applet.compactProviders().length === expectedProviderCount;
        }
        if (!claude)
            return false;
        if (scenario === "partial-error")
            return applet.selectedProviderID === "claude" && claude.error.indexOf("Synthetic provider timeout") >= 0;
        if (claude.error.length > 0 || claude.rows.length !== 2)
            return false;
        if (scenario === "popup-cost-missing-tokens" || scenario === "popup-cost-partial-models")
            return verifyCostCoverage();
        if (scenario.indexOf("popup-cost-") === 0)
            return applet.selectedProviderID === "codex" && verifyCostDetails();
        if (scenario === "popup-content")
            return verifyPopupContent();
        if (scenario === "refresh-on-open")
            return verifyRefreshOnOpen();
        if (scenario.indexOf("privacy-") === 0)
            return verifyPrivacy();
        if (scenario.indexOf("localization-") === 0) {
            var language = scenario.substring("localization-".length);
            var expected = {
                it: ["Panoramica", "Sessioni", "1 ora", "2 ore"],
                fr: ["Vue d'ensemble", "Sessions", "1 heure", "2 heures"],
                de: ["Übersicht", "Sitzungen", "1 Stunde", "2 Stunden"],
                es: ["Resumen", "Sesiones", "1 hora", "2 horas"],
                pt_BR: ["Visão geral", "Sessões", "1 hora", "2 horas"]
            }[language];
            verifyScenario(i18n("Overview") === expected[0], "package catalog did not load");
            verifyScenario(i18n("Sessions") === expected[1], "session label did not translate");
            verifyScenario(i18np("%1 hour", "%1 hours", 1) === expected[2], "singular translation failed");
            verifyScenario(i18np("%1 hour", "%1 hours", 2) === expected[3], "plural translation failed");
            if (language === "pt_BR")
                verifyScenario(i18np("%1 hour", "%1 hours", 0) === "0 hora", "Brazilian Portuguese zero form failed");
            var countLabels = {
                it: [["token", "token"], ["richiesta", "richieste"], ["punto", "punti"]],
                fr: [["jeton", "jetons"], ["requête", "requêtes"], ["point", "points"]],
                de: [["Token", "Tokens"], ["Anfrage", "Anfragen"], ["Punkt", "Punkte"]],
                es: [["token", "tokens"], ["solicitud", "solicitudes"], ["punto", "puntos"]],
                pt_BR: [["token", "tokens"], ["requisição", "requisições"], ["ponto", "pontos"]]
            }[language];
            var countUnits = ["tokens", "requests", "points"];
            for (var unitIndex = 0; unitIndex < countUnits.length; unitIndex++) {
                var singular = countLabels[unitIndex][0];
                var plural = countLabels[unitIndex][1];
                var unit = countUnits[unitIndex];
                verifyScenario(applet.usageCountText(0, unit) === "0 "
                    + (language === "fr" || language === "pt_BR" ? singular : plural), "zero count translation failed");
                verifyScenario(applet.dashboardPartText({kind: unit, value: 1}) === "1 " + singular,
                    "singular dashboard count translation failed");
                verifyScenario(applet.usageCountText(2, unit) === "2 " + plural, "plural count translation failed");
                verifyScenario(applet.usageCountText(1000, unit) === "1K " + plural, "compact count translation failed");
                verifyScenario(applet.usageCountText(4294967297, unit) === "4.3B " + plural,
                    "large count overflowed the plural argument");
            }
            var oneToken = "1 " + countLabels[0][0];
            verifyScenario(applet.costValueLine(1, 1, "USD") === applet.amountString(1, "USD") + " - " + oneToken,
                "cost summary lost the singular token count");
            verifyScenario(applet.costLine("Example", 1, 1, "USD") === i18n("%1: %2", "Example",
                applet.amountString(1, "USD") + " - " + oneToken), "labeled cost summary lost the singular token count");
            verifyScenario(hasText(applet.fullRepresentationItem, expected[0]), "translated popup label missing");
            if (settingsPreview.status !== Loader.Ready)
                return false;
            verifyScenario(hasText(settingsPreview.item, i18n("Fetch provider service status")),
                "translated settings label missing");
            var sessionLabels = {
                it: ["Attiva", "Inattiva", "Applicazione desktop", "Riga di comando"],
                fr: ["Active", "Inactive", "Application de bureau", "Ligne de commande"],
                de: ["Aktiv", "Inaktiv", "Desktop-Anwendung", "Befehlszeile"],
                es: ["Activa", "Inactiva", "Aplicación de escritorio", "Línea de comandos"],
                pt_BR: ["Ativa", "Inativa", "Aplicativo de desktop", "Linha de comando"]
            }[language];
            if (localizationStep === 0) {
                if (!applet.overviewSelected)
                    return false;
                applet.openProviderFromPanel("codex");
                localizationStep = 1;
                return false;
            }
            if (localizationStep === 1) {
                if (applet.selectedProviderID !== "codex")
                    return false;
                var expectedPace = i18n("%1% in deficit", 13) + " | "
                    + i18n("Expected %1% used", 30) + " | "
                    + i18n("Runs out in %1", expected[2]);
                verifyScenario(codex.rows[0].pace === expectedPace, "pace summary did not translate");
                if (!hasText(applet.fullRepresentationItem, expectedPace))
                    return false;
                applet.selectGlobalView("sessions");
                localizationStep = 2;
                return false;
            }
            if (!applet.sessionsSelected || applet.sessionsLoading || applet.sessions.length !== 2)
                return false;
            for (var labelIndex = 0; labelIndex < 2; labelIndex++) {
                if (!hasText(applet.fullRepresentationItem, sessionLabels[labelIndex]))
                    return false;
            }
            verifyScenario(applet.sessionSourceText("desktopApp") === sessionLabels[2], "desktop source did not translate");
            verifyScenario(applet.sessionSourceText("cli") === sessionLabels[3], "command line source did not translate");
            return true;
        }
        if (scenario === "legacy-dashboard") {
            if (applet.selectedProviderID !== "codex")
                return false;
            var dashboard = codex.usageDashboard;
            var dashboardSection = findItem(applet.fullRepresentationItem, "usageDashboardSection");
            verifyScenario(dashboard !== null && dashboard.rows.length === 3, "legacy dashboard rows missing");
            verifyScenario(dashboard.kpis[0].value === "0", "legacy dashboard lost explicit zero");
            verifyScenario(dashboard.rows[0].label === "Credits remaining", "legacy label adapter failed");
            verifyScenario(dashboard.rows[1].value === "$1.25 · 1.2K tokens", "legacy period formatting changed");
            verifyScenario(dashboard.rows[2].value === "Example model (0 requests)", "legacy top model formatting changed");
            verifyScenario(claude.usageDashboard === null && claude.providerDetails.length === 1,
                "legacy dashboard overrode generic details");
            return dashboardSection !== null && dashboardSection.visible && dashboardSection.rows.length === 3;
        }
        if (scenario === "panel-rules") {
            verifyScenario(applet.providers === panelUsageSnapshot, "panel settings reloaded usage");
            return panelPreview.item !== null && applet.compactProviders().length === 2;
        }
        if (scenario === "long-text")
            return applet.selectedProviderID === "codex" && !applet.accountLoadingForProvider("codex") && applet.accountOptionsForProvider("codex").length === 2 && codex.account.length > 50;
        if (scenario.indexOf("provider-header") === 0)
            return applet.selectedProviderID === "codex" && codex.hasIncident;
        if (scenario.indexOf("project-") === 0) {
            if (!applet.spendSelected || !applet.tokenCosts.codex)
                return false;
            var section = findItem(applet.fullRepresentationItem, "projectCostSection");
            if (!section || section.projectData.rows.length !== 4)
                return false;
            var rows = section.projectData.rows;
            var expectedFirst = scenario === "project-tokens" ? "Documentation site"
                : (scenario === "project-long-text"
                    ? "Example project with a long display name for the engineering and documentation team"
                    : "CodexBar Plasma");
            var expectedCost = scenario === "project-range" ? 2.75 : 5.5;
            if (rows[0].label !== expectedFirst
                    || (scenario !== "project-tokens" && rows[0].cost !== expectedCost)
                    || JSON.stringify(rows).indexOf("/private/") >= 0) {
                console.error("SMOKE_FAILED: unexpected project presentation");
                return false;
            }
            return true;
        }
        return applet.overviewSelected;
    }

    function findItem(item, name) {
        if (item.objectName === name)
            return item;
        for (var i = 0; i < item.children.length; i++) {
            var found = findItem(item.children[i], name);
            if (found)
                return found;
        }
        return null;
    }

    function hasText(item, text) {
        if (item.text === text)
            return true;
        for (var i = 0; i < item.children.length; i++) {
            if (hasText(item.children[i], text))
                return true;
        }
        return false;
    }

    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            var popup = capture.applet.fullRepresentationItem;
            if (!popup || popup.width <= 0 || popup.height <= 0)
                return;
            if (!capture.prepared) {
                capture.applet.expanded = true;
                if (capture.scenario !== "loading"
                        && !(capture.scenario === "usage-cache-restart" && capture.cacheRestart)
                        && (capture.applet.loading || capture.applet.providers.length !== capture.expectedProviderCount))
                    return;
                if (capture.panelDefaultsScenario) {
                    if (capture.applet.costLoading || panelPreview.item === null || capture.compactPanelItem === null
                            || capture.compactPanelItem === undefined)
                        return;
                    capture.verifyPanelDefaults();
                } else if (capture.readmePanelScenario) {
                    capture.preparePanelAppearance();
                } else if (capture.readmeScenario) {
                    popup.Window.window.width = 640;
                    popup.Window.window.height = capture.scenario === "readme-overview"
                        || capture.scenario === "readme-sessions" ? 400 : 660;
                    if (capture.scenario === "readme-codex")
                        capture.applet.openProviderFromPanel("codex");
                    else
                        capture.applet.selectGlobalView(capture.scenario.substring("readme-".length));
                } else if (capture.scenario === "loading") {
                    capture.verifyEmptyPanelRules();
                } else if (capture.scenario === "tabs-overflow") {
                    var providers = capture.applet.providers.slice();
                    for (var i = 0; i < 8; i++) {
                        var provider = Object.assign({}, providers[0]);
                        provider.provider = "example-" + i;
                        provider.title = "Example " + (i + 1);
                        providers.push(provider);
                    }
                    capture.applet.providers = providers;
                    capture.applet.selectGlobalView("overview");
                } else if (capture.scenario === "panel-rules") {
                    capture.preparePanelScenario();
                } else if (capture.panelAppearanceScenario) {
                    capture.preparePanelAppearance();
                } else if (capture.scenario === "long-text") {
                    capture.applet.openProviderFromPanel("codex");
                    capture.applet.loadAccounts("codex");
                } else if (capture.scenario.indexOf("popup-cost-") === 0) {
                    if (capture.applet.costLoading || !capture.applet.tokenCosts.codex)
                        return;
                    popup.Window.window.width = 640;
                    popup.Window.window.height = 880;
                    capture.applet.openProviderFromPanel("codex");
                } else if (capture.scenario === "popup-content") {
                    capture.applet.openProviderFromPanel("codex");
                } else if (capture.scenario.indexOf("privacy-") === 0) {
                    if (capture.applet.costLoading || !capture.applet.tokenCosts.codex)
                        return;
                    capture.settingsProviderSnapshot = capture.applet.providers;
                    capture.settingsCostSnapshot = capture.applet.tokenCosts;
                    capture.applet.Plasmoid.configuration.privacyMode = true;
                    if (capture.scenario === "privacy-provider" || capture.scenario === "privacy-cost-details") {
                        capture.applet.openProviderFromPanel("codex");
                        if (capture.scenario === "privacy-provider") {
                            capture.applet.loadAccounts("codex");
                        } else {
                            popup.Window.window.width = 640;
                            popup.Window.window.height = 880;
                        }
                    } else {
                        capture.applet.selectGlobalView(capture.scenario.substring("privacy-".length));
                    }
                } else if (capture.scenario === "legacy-dashboard" || capture.scenario.indexOf("provider-header") === 0) {
                    capture.applet.openProviderFromPanel("codex");
                } else if (capture.scenario.indexOf("project-") === 0) {
                    if (capture.applet.costLoading || !capture.applet.tokenCosts.codex)
                        return;
                    capture.applet.selectGlobalView("spend");
                    if (capture.scenario === "project-range") {
                        capture.applet.setCostHistoryDays(7);
                        if (capture.applet.spendProviderCosts().length !== 0)
                            console.error("SMOKE_FAILED: stale project range remained visible");
                    } else if (capture.scenario === "project-tokens") {
                        var previousCosts = capture.applet.tokenCosts;
                        capture.applet.setCostHistoryMetric("tokens");
                        if (capture.applet.costLoading || capture.applet.tokenCosts !== previousCosts)
                            console.error("SMOKE_FAILED: metric switch reloaded project history");
                    }
                } else if (capture.scenario === "normal" || capture.scenario.indexOf("localization-") === 0)
                    capture.applet.selectGlobalView("overview");
                else if (capture.scenario === "partial-error")
                    capture.applet.openProviderFromPanel("claude");
                capture.prepared = true;
            }
            if (capture.scenarioReady()) {
                if (capture.scenario === "legacy-dashboard") {
                    var dashboard = capture.findItem(popup, "usageDashboardSection");
                    capture.findItem(popup, "providerScroll").contentItem.contentY = dashboard.y;
                }
                if (capture.scenario.indexOf("project-") === 0) {
                    var section = capture.findItem(popup, "projectCostSection");
                    var scroll = capture.findItem(popup, "spendHistoryScroll");
                    scroll.contentItem.contentY = section.y;
                }
                console.log("SMOKE_READY:" + capture.scenario);
                stop();
                settle.start();
            }
        }
    }

    Timer {
        id: settle

        // Let layout and tab animations settle after the state is established.
        interval: 600
        onTriggered: {
            if (!capture.scenarioReady()) {
                console.error("SMOKE_FAILED: scenario changed before capture");
                return;
            }
            if (capture.scenario === "normal") {
                var next = capture.findItem(capture.applet.fullRepresentationItem, "nextTabsButton");
                capture.verifyScenario(next !== null && !next.visible, "scroll controls appear when tabs fit");
            }
            if (capture.panelAppearanceScenario) capture.verifyCapsulePanel();
            var popup = capture.settingsScenario ? configurationPreview.item
                : capture.scenario === "panel-rules" || capture.panelAppearanceScenario || capture.panelDefaultsScenario
                ? panelPreview.item : (capture.scenario === "provider-settings"
                    ? providerSettingsPreview.item : capture.applet.fullRepresentationItem);
            console.log("SMOKE_CAPTURE_START:" + capture.scenario);
            var accepted = popup.grabToImage(function (result) {
                if (result.saveToFile(capture.imagePath))
                    console.log("SMOKE_CAPTURED:" + capture.scenario);
                else
                    console.error("SMOKE_FAILED: could not save popup screenshot");
            });
            if (!accepted)
                console.error("SMOKE_FAILED: could not capture popup");
        }
    }
}
