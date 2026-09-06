import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

// Added only to a temporary copy of main.qml by smoke_popup.py.
Item {
    id: capture

    required property var applet
    required property string scenario
    required property string imagePath
    property bool prepared: false
    property var panelUsageSnapshot

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
        active: capture.scenario === "panel-rules"
        z: 100
        sourceComponent: Rectangle {
            width: Math.max(240, panel.compactItem ? panel.compactItem.implicitWidth + 48 : 240)
            height: 84
            color: Kirigami.Theme.backgroundColor
            Loader {
                id: panel
                readonly property Item compactItem: item as Item
                sourceComponent: capture.applet.compactRepresentation
                anchors.centerIn: parent
                width: compactItem ? compactItem.implicitWidth : 0
                height: 40
            }
        }
    }

    function verifyScenario(condition, message) {
        if (!condition)
            throw new Error("SMOKE_FAILED: " + message);
    }

    function preparePanelScenario() {
        var config = applet.Plasmoid.configuration;
        var codex = applet.providers[applet.providerIndexForID("codex")];
        panelUsageSnapshot = applet.providers;
        applet.openProviderFromPanel("codex");
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

    function scenarioReady() {
        if (scenario === "loading")
            return applet.loading && applet.providers.length === 0;
        if (applet.loading || applet.costLoading || applet.providers.length !== 2)
            return false;
        var codex = applet.providers[applet.providerIndexForID("codex")];
        var claude = applet.providers[applet.providerIndexForID("claude")];
        if (!codex || !claude || codex.rows.length !== 2 || codex.error.length > 0)
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
                es: ["Resumen", "Sesiones", "1 hora", "2 horas"]
            }[language];
            verifyScenario(i18n("Overview") === expected[0], "package catalog did not load");
            verifyScenario(i18n("Sessions") === expected[1], "session label did not translate");
            verifyScenario(i18np("%1 hour", "%1 hours", 1) === expected[2], "singular translation failed");
            verifyScenario(i18np("%1 hour", "%1 hours", 2) === expected[3], "plural translation failed");
            verifyScenario(hasText(applet.fullRepresentationItem, expected[0]), "translated popup label missing");
            if (settingsPreview.status !== Loader.Ready)
                return false;
            verifyScenario(hasText(settingsPreview.item, i18n("Fetch provider service status")),
                "translated settings label missing");
            return applet.overviewSelected;
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
                if (capture.scenario !== "loading" && (capture.applet.loading || capture.applet.providers.length !== 2))
                    return;
                if (capture.scenario === "loading") {
                    capture.verifyEmptyPanelRules();
                } else if (capture.scenario === "panel-rules") {
                    capture.preparePanelScenario();
                } else if (capture.scenario === "long-text") {
                    capture.applet.openProviderFromPanel("codex");
                    capture.applet.loadAccounts("codex");
                } else if (capture.scenario === "legacy-dashboard") {
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
            var popup = capture.scenario === "panel-rules" ? panelPreview.item : capture.applet.fullRepresentationItem;
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
