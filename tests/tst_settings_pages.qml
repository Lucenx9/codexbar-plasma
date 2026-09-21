import QtQuick
import QtTest
import "../contents/ui/SafeText.js" as SafeText

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

    property bool mirroredPage: false

    LayoutMirroring.enabled: mirroredPage
    LayoutMirroring.childrenInherit: true

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
        var managed = findChild(page, "managedCliController");
        if (managed) {
            tryVerify(function() { return managed.activeAction === "status" && !managed.busy; });
        }
        return page;
    }

    function cleanup() {
        mirroredPage = false;
    }

    function test_generalRtlLoadsWithoutWarnings() {
        mirroredPage = true;
        var page = createPage("../contents/ui/configGeneral.qml", {
            cfg_commandPath: " ",
            cfg_refreshInterval: 300,
            cfg_autoUpdateIntervalHours: 24
        });
        if (!page)
            return;
        wait(0);
    }

    function test_existingManagedCopyCanBeSelectedWithoutAProcess() {
        var page = createPage("../contents/ui/configGeneral.qml", {cfg_commandPath: "/usr/bin/codexbar"});
        if (!page) return;
        var managed = findChild(page, "managedCliController");
        managed.activeAction = "status";
        managed.activeSource = "synthetic";
        var path = "/home/test/.local/share/codexbar-plasma/cli/current/codexbar";
        managed.accept("synthetic", {"exit code": 0, stdout: JSON.stringify({
            status: "ready", version: "0.62.0", previous: "", path: path})});
        var button = findChild(page, "installManagedCliButton");
        compare(button.text, "Use managed CLI");
        button.clicked();
        compare(page.cfg_commandPath, path);
        verify(!managed.busy);
        verify(managed.selected);
        compare(button.text, "Update now");
        compare(page.cfg_cliAutomaticUpdates, false);
    }

    function test_installWithWorkingExternalCliAsksForConfirmation() {
        var page = createPage("../contents/ui/configGeneral.qml", {cfg_commandPath: "/usr/bin/codexbar"});
        if (!page) return;
        var managed = findChild(page, "managedCliController");
        managed.activeAction = "status";
        managed.activeSource = "synthetic";
        managed.accept("synthetic", {"exit code": 0, stdout: JSON.stringify({status: "absent"})});
        var updater = findChild(page, "cliReleaseController");
        updater.activeSource = "manual";
        updater.accept("manual", {"exit code": 0, stdout: JSON.stringify({status: "local",
            version: "0.60.4", path: "/usr/bin/codexbar", manager: "external"})});
        var button = findChild(page, "installManagedCliButton");
        compare(button.text, "Install and select managed CLI");
        button.clicked();
        var confirmLabel = findChild(page, "managedInstallConfirmLabel");
        verify(confirmLabel.visible);
        verify(confirmLabel.text.indexOf("/usr/bin/codexbar") >= 0);
        verify(confirmLabel.text.indexOf("0.60.4") >= 0);
        verify(!managed.busy);
        var cancelButton = findChild(page, "cancelManagedInstallButton");
        cancelButton.clicked();
        verify(!confirmLabel.visible);
        verify(!managed.busy);
        button.clicked();
        verify(confirmLabel.visible);
        var confirmButton = findChild(page, "confirmManagedInstallButton");
        // A missing helper fails immediately, so no real download starts and
        // the failed probe retires before teardown.
        managed.scriptUrl = "file:///nonexistent-helper.py";
        confirmButton.clicked();
        verify(page.managedInstallConfirming === false);
        verify(managed.busy);
        verify(managed.activeAction === "install");
        tryVerify(function() { return !managed.busy; });
    }

    function test_installWithoutKnownExternalCliStartsImmediately() {
        var page = createPage("../contents/ui/configGeneral.qml", {cfg_commandPath: "/usr/bin/codexbar"});
        if (!page) return;
        var managed = findChild(page, "managedCliController");
        managed.activeAction = "status";
        managed.activeSource = "synthetic";
        managed.accept("synthetic", {"exit code": 0, stdout: JSON.stringify({status: "absent"})});
        var button = findChild(page, "installManagedCliButton");
        // A missing helper fails immediately, so no real download starts and
        // the failed probe retires before teardown.
        managed.scriptUrl = "file:///nonexistent-helper.py";
        button.clicked();
        verify(!findChild(page, "managedInstallConfirmLabel").visible);
        verify(managed.busy);
        verify(managed.activeAction === "install");
        tryVerify(function() { return !managed.busy; });
    }

    function test_diagnosticsRejectsBlankPath() {
        var page = createPage("../contents/ui/configDiagnostics.qml", {cfg_commandPath: "   "});
        if (!page) return;
        page.runEnvironmentProbe();
        verify(page.environmentProbeFailed);
        compare(page.resolvedCommandPath, "");
        compare(page.diagnosticError, "Set the codexbar command path above.");
    }

    function test_diagnosticsShowsResolvedPathWithSpaces() {
        var page = createPage("../contents/ui/configDiagnostics.qml", {
            cfg_commandPath: "/opt/CodexBar CLI/bin/codexbar"
        });
        if (!page)
            return;

        var versions = findChild(page, "cliVersionsController");
        verify(versions !== null);
        verify(versions.localOnly);
        versions.activeSource = "environment";
        versions.accept("environment", {
            "exit code": 0,
            stdout: JSON.stringify({status: "local", version: "0.61.0",
                path: "/opt/CodexBar CLI/bin/codexbar", manager: "external"})
        });

        var resolvedCommandLabel = findChild(page, "resolvedCommandLabel");
        verify(resolvedCommandLabel !== null);
        compare(resolvedCommandLabel.text, "/opt/CodexBar CLI/bin/codexbar");
        verify(resolvedCommandLabel.text !== "Not checked");
    }

    function test_diagnosticsShowsSystemCliWhenItDiffers() {
        var page = createPage("../contents/ui/configDiagnostics.qml", {
            cfg_commandPath: "/home/test/.local/share/codexbar-plasma/cli/current/codexbar"
        });
        if (!page)
            return;

        var versions = findChild(page, "cliVersionsController");
        versions.activeSource = "selected";
        versions.accept("selected", {
            "exit code": 0,
            stdout: JSON.stringify({status: "local", version: "0.62.0",
                path: "/home/test/.local/share/codexbar-plasma/cli/current/codexbar", manager: "managed"})
        });
        var systemVersions = findChild(page, "systemCliVersionsController");
        verify(systemVersions !== null);
        verify(systemVersions.localOnly);
        systemVersions.activeSource = "system";
        systemVersions.accept("system", {
            "exit code": 0,
            stdout: JSON.stringify({status: "local", version: "0.60.4",
                path: "/usr/bin/codexbar", manager: "external"})
        });

        var label = findChild(page, "systemCliVersionLabel");
        verify(label.visible);
        verify(label.text.indexOf("0.60.4") >= 0);
        verify(label.text.indexOf("/usr/bin/codexbar") >= 0);
    }

    function test_diagnosticsHidesSystemCliWhenItMatchesSelection() {
        var page = createPage("../contents/ui/configDiagnostics.qml", {cfg_commandPath: "codexbar"});
        if (!page)
            return;

        var versions = findChild(page, "cliVersionsController");
        versions.activeSource = "selected";
        versions.accept("selected", {
            "exit code": 0,
            stdout: JSON.stringify({status: "local", version: "0.60.4",
                path: "/usr/bin/codexbar", manager: "external"})
        });
        var systemVersions = findChild(page, "systemCliVersionsController");
        systemVersions.activeSource = "system";
        systemVersions.accept("system", {
            "exit code": 0,
            stdout: JSON.stringify({status: "local", version: "0.60.4",
                path: "/usr/bin/codexbar", manager: "external"})
        });

        verify(!findChild(page, "systemCliVersionLabel").visible);
    }

    function test_diagnosticsReportsUnidentifiedSystemCli() {
        var page = createPage("../contents/ui/configDiagnostics.qml", {cfg_commandPath: "codexbar"});
        if (!page)
            return;

        var versions = findChild(page, "cliVersionsController");
        versions.activeSource = "selected";
        versions.accept("selected", {
            "exit code": 0,
            stdout: JSON.stringify({status: "unknown", version: "",
                path: "/usr/bin/codexbar", manager: "external"})
        });
        var systemVersions = findChild(page, "systemCliVersionsController");
        systemVersions.activeSource = "system";
        systemVersions.accept("system", {
            "exit code": 0,
            stdout: JSON.stringify({status: "unknown", version: "",
                path: "/usr/local/bin/codexbar", manager: "external"})
        });

        var label = findChild(page, "systemCliVersionLabel");
        verify(label.visible);
        compare(label.text, "Could not identify the installed CLI version.");
    }

    function test_restoringDefaultsStaysPendingUntilSaved() {
        var page = createPage("../contents/ui/configGeneral.qml", {
            cfg_commandPath: "/opt/codexbar/bin/codexbar",
            cfg_provider: "codex",
            cfg_source: "cli",
            cfg_refreshInterval: 900,
            cfg_privacyMode: true,
            cfg_cliAutomaticUpdates: true,
            cfg_refreshOnOpen: false,
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
        compare(page.cfg_cliAutomaticUpdates, false);
        compare(page.cfg_refreshOnOpen, true);
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

    // Non-visual children (timers, tooltips, data sources) live in resources
    // and data, not in children, so reaching the timeout timer or the
    // predictive tooltip needs the whole object tree.
    function walkPageObjects(root, out) {
        if (root === null || root === undefined || out.indexOf(root) >= 0)
            return;
        out.push(root);
        var groups = [root.children, root.resources, root.data];
        for (var g = 0; g < groups.length; g++) {
            var kids = groups[g];
            if (kids === undefined || kids === null)
                continue;
            for (var i = 0; i < kids.length; i++)
                walkPageObjects(kids[i], out);
        }
    }

    function notificationCheckBoxes(page) {
        var all = [];
        walkPageObjects(page, all);
        return all.filter(function(item) {
            return item.toString().indexOf("CheckBox") >= 0;
        });
    }

    function diagnosticTimeoutTimer(page) {
        var all = [];
        walkPageObjects(page, all);
        var found = all.filter(function(item) {
            return item.toString().indexOf("Timer") >= 0 && item.repeat === false
                && item.interval > 0 && item.toString().indexOf("cliUpdateDeadline") < 0;
        });
        return found.length === 1 ? found[0] : null;
    }

    function diagnosticProviderField(page) {
        var all = [];
        walkPageObjects(page, all);
        for (var i = 0; i < all.length; i++) {
            if (all[i].placeholderText === "all")
                return all[i];
        }
        return null;
    }

    // The master switch owns the detail toggles: turning it off must disable
    // quota, predictive and reset notices, and its own checked state must
    // follow the applied configuration. The status toggle stays gated on the
    // General status probe and is covered by the threshold test above.
    function test_notificationTogglesFollowMasterSwitch() {
        var page = createPage("../contents/ui/configNotifications.qml", {
            cfg_quotaWarningPercent: 80,
            cfg_quotaCriticalPercent: 95
        });
        if (!page)
            return;
        var boxes = notificationCheckBoxes(page);
        compare(boxes.length, 5);

        page.cfg_enableNotifications = false;
        var masters = boxes.filter(function(box) { return box.enabled; });
        compare(masters.length, 1);
        compare(masters[0].checked, false);

        page.cfg_enableNotifications = true;
        compare(masters[0].checked, true);
        // All but the status toggle, which needs status fetching enabled.
        compare(boxes.filter(function(box) { return box.enabled; }).length, 4);
    }

    // The predictive tooltip must keep routing through plainText so the
    // shared escaping applies; assigning text directly would bypass it.
    // The tooltip is found through its parent checkbox, never by its words.
    function test_predictiveTooltipKeepsPlainTextRouting() {
        var page = createPage("../contents/ui/configNotifications.qml", {
            cfg_quotaWarningPercent: 80,
            cfg_quotaCriticalPercent: 95
        });
        if (!page)
            return;
        var all = [];
        walkPageObjects(page, all);
        var tips = all.filter(function(item) {
            return item.toString().indexOf("PlainToolTip") >= 0;
        });
        compare(tips.length, 1);
        // The predictive checkbox is the one the applied configuration
        // checks here, so the tooltip parent is identified by wiring.
        page.cfg_notifyPredictivePaceWarnings = true;
        var boxes = notificationCheckBoxes(page);
        var predictive = boxes.filter(function(box) { return box.checked; });
        compare(predictive.length, 1);
        verify(tips[0].parent === predictive[0]);
        verify(tips[0].plainText.length > 0);
        compare(tips[0].text, SafeText.plainTextAsRichText(tips[0].plainText));
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

    // A blank diagnostic provider means "all enabled providers": the page
    // must send the redacted diagnose command with a run nonce behind it.
    // /bin/echo settles the DataSource immediately, so the test observes the
    // issued command instead of the source text that built it.
    function test_diagnosticBlankProviderRunsRedactedCommand() {
        var page = createPage("../contents/ui/configDiagnostics.qml", {cfg_commandPath: "/bin/echo"});
        if (!page)
            return;
        var field = diagnosticProviderField(page);
        verify(field !== null);

        field.text = "";
        page.runDiagnostic();
        tryVerify(function() { return !page.diagnosticRunning; }, 5000);
        compare(page.diagnosticOutput, "diagnose --provider all --format json --redact");

        field.text = "codex";
        page.runDiagnostic();
        tryVerify(function() { return !page.diagnosticRunning; }, 5000);
        compare(page.diagnosticOutput, "diagnose --provider codex --format json --redact");
    }

    // The output area renders whatever the page accepted, so a severed
    // binding shows up here even though the accepted property still changes.
    function test_diagnosticOutputAreaFollowsAcceptedOutput() {
        var page = createPage("../contents/ui/configDiagnostics.qml", {cfg_commandPath: "/bin/echo"});
        if (!page)
            return;
        var field = diagnosticProviderField(page);
        verify(field !== null);
        field.text = "";
        page.runDiagnostic();
        tryVerify(function() { return !page.diagnosticRunning; }, 5000);

        var all = [];
        walkPageObjects(page, all);
        var areas = all.filter(function(item) {
            return item.toString().indexOf("TextArea") >= 0;
        });
        compare(areas.length, 1);
        compare(areas[0].text, page.diagnosticOutput);
        verify(areas[0].text.indexOf("diagnose --provider all") >= 0);
    }

    // The timeout timer must retire a hung command through the handler: with
    // no process attached the test shortens the timer itself and observes the
    // retired state and the timeout message, never the timeout constant.
    function test_diagnosticTimeoutRetiresActiveCommand() {
        var page = createPage("../contents/ui/configDiagnostics.qml", {cfg_commandPath: "/bin/echo"});
        if (!page)
            return;
        var timer = diagnosticTimeoutTimer(page);
        verify(timer !== null);
        compare(timer.interval, page.diagnosticCommandTimeoutMs);

        page.activeCommand = "synthetic-hung-source";
        page.diagnosticRunning = true;
        timer.interval = 80;
        timer.restart();
        tryVerify(function() { return !page.diagnosticRunning; }, 5000);
        compare(page.activeCommand, "");
        compare(page.diagnosticError, "Diagnostic command timed out. Try again.");
    }

    // Switching the command path must retire the in-flight command so a late
    // reply from the old executable cannot replace the new page state.
    function test_commandPathChangeRetiresActiveCommand() {
        var page = createPage("../contents/ui/configDiagnostics.qml", {cfg_commandPath: "/bin/echo"});
        if (!page)
            return;
        page.activeCommand = "synthetic-old-source";
        page.diagnosticRunning = true;
        page.cfg_commandPath = "/other/codexbar";
        verify(!page.diagnosticRunning);
        compare(page.activeCommand, "");
    }

    // Accepted output stays inside the diagnostic bound, and a reply for a
    // retired source never replaces the current output.
    function test_diagnosticOutputIsBoundedAndIgnoresStaleSources() {
        var page = createPage("../contents/ui/configDiagnostics.qml", {cfg_commandPath: "/bin/echo"});
        if (!page)
            return;
        page.activeCommand = "synthetic-source";
        page.diagnosticRunning = true;
        var overlong = new Array(70001).join("y");
        page.handleDiagnosticData("synthetic-source", {stdout: overlong, "exit code": 0});
        verify(!page.diagnosticRunning);
        compare(page.diagnosticOutput.length, 65536);

        page.handleDiagnosticData("stale-source", {stdout: "replacement", "exit code": 0});
        verify(page.diagnosticOutput.indexOf("replacement") < 0);
    }
}
