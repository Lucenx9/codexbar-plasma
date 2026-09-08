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
    property int localizationStep: 0
    property var panelUsageSnapshot
    property var compactPanelItem
    property var displaySettingsPage
    property var providerSettingsPage
    readonly property bool settingsScenario: scenario.indexOf("settings-") === 0
    readonly property bool panelDefaultsScenario: scenario === "panel-default" || scenario === "panel-default-single"
    readonly property bool readmePanelScenario: scenario.indexOf("readme-panel-") === 0
    readonly property bool standardPanelScenario: scenario === "panel-standard" || scenario === "readme-panel-standard"
    readonly property bool panelAppearanceScenario: scenario === "panel-standard" || scenario === "panel-minimal"
        || scenario === "panel-minimal-single" || readmePanelScenario
    readonly property bool readmeScenario: scenario.indexOf("readme-") === 0
    readonly property int expectedProviderCount: scenario === "panel-minimal-single" || scenario === "panel-default-single"
        ? 1 : (readmeScenario ? 3 : 2)

    Loader {
        id: configurationPreview
        parent: capture.applet.fullRepresentationItem
        active: capture.settingsScenario
        visible: active
        z: 100
        sourceComponent: SettingsPreview {
            applet: capture.applet
            pageSource: ({"settings-general": "configGeneral.qml", "settings-display": "configDisplay.qml",
                "settings-advanced": "configAdvanced.qml", "settings-debug": "configDebug.qml"})[capture.scenario]
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
            width: Math.max(240, panel.compactItem ? panel.compactItem.implicitWidth + 48 : 240)
            height: 84
            color: panel.compactItem ? panel.compactItem.Kirigami.Theme.backgroundColor : Kirigami.Theme.backgroundColor
            Loader {
                id: panel
                readonly property Item compactItem: item as Item
                sourceComponent: capture.applet.compactRepresentation
                onLoaded: capture.compactPanelItem = item
                anchors.centerIn: parent
                width: compactItem ? compactItem.implicitWidth : 0
                height: capture.panelAppearanceScenario || capture.panelDefaultsScenario ? 44 : 40
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
        var component = Qt.createComponent(Qt.resolvedUrl("configDisplay.qml"));
        verifyScenario(component.status === Component.Ready, component.errorString());
        displaySettingsPage = component.createObject(capture, {
            cfg_commandPath: applet.commandPath,
            cfg_panelQuotaLane: "secondary",
            cfg_providerOrder: "claude,codex",
            cfg_panelVisibilityRules: '{"text":{"condition":"usageAtLeast","usedPercent":50}}'
        });
        var page = displaySettingsPage;
        verifyScenario(page !== null, "display settings did not load");
        var oldRules = page.cfg_panelVisibilityRules;
        page.applyMinimalPanelPreset();
        verifyScenario(page.cfg_panelStyle === "minimal" && page.cfg_showMultiProviderInPanel
            && !page.cfg_showProviderInPanel && !page.cfg_showPercentInPanel && !page.cfg_showCreditsInPanel,
            "minimal preset did not configure its panel elements");
        verifyScenario(page.cfg_panelQuotaLane === "secondary" && page.cfg_providerOrder === "claude,codex"
            && page.cfg_panelVisibilityRules === oldRules, "preset changed quota, order or visibility rules");
        verifyScenario(config.panelStyle === "standard", "settings took effect before Apply");
        config.panelStyle = standardPanelScenario ? "standard" : page.cfg_panelStyle;
        config.showMultiProviderInPanel = page.cfg_showMultiProviderInPanel;
        config.showProviderInPanel = page.cfg_showProviderInPanel;
        config.showPercentInPanel = page.cfg_showPercentInPanel;
        config.showCreditsInPanel = page.cfg_showCreditsInPanel;
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

    function scenarioReady() {
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
            if (expectedProviderCount >= 2 && (!claude || claude.error.length > 0 || claude.rows.length !== 2))
                return false;
            verifyScenario(applet.providers === panelUsageSnapshot, "panel preset reloaded usage");
            verifyScenario(applet.minimalPanel === !standardPanelScenario, "panel style did not reach the renderer");
            verifyScenario(applet.compactText() === "", "minimal preset left panel text visible");
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
                        && (capture.applet.loading || capture.applet.providers.length !== capture.expectedProviderCount))
                    return;
                if (capture.panelDefaultsScenario) {
                    if (capture.applet.costLoading || panelPreview.item === null)
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
