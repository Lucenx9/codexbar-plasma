import QtQuick
import QtQuick.Controls as Controls
import QtTest
import "../contents/ui/SafeText.js" as SafeText
import "../contents/ui/ThemeContrast.js" as ThemeContrast
import "../contents/ui/config/ProviderConfigProtocol.js" as ProviderConfigProtocol

TestCase {
    id: testCase
    name: "ProviderFilters"
    when: windowShown
    width: 620
    height: 700
    visible: true

    function i18nc(context, text) { return text; }
    function i18n(text) {
        return text;
    }
    function i18np(one, many, count) {
        return count === 1 ? one : many;
    }

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

    function createProvidersPage() {
        var component = Qt.createComponent("../contents/ui/configProviders.qml");
        if (component.status === Component.Error && /module "org\.kde\.[^"]+" is not installed/.test(component.errorString())) {
            skip("Provider filters need the optional KDE QML modules");
            return null;
        }
        compare(component.status, Component.Ready, component.errorString());
        failOnWarning(/.*/);
        var page = createTemporaryObject(component, testCase, {
            cfg_commandPath: " ",
            width: 620,
            height: 700
        });
        verify(page !== null);
        tryCompare(page, "loading", false);
        wait(0);
        page.retireAllConfigCommands();
        page.loading = false;
        page.errorText = "";
        return page;
    }

    function test_keyboardFiltersSearchAndClearKeepSelectionAndCommands() {
        var component = Qt.createComponent("../contents/ui/configProviders.qml");
        if (component.status === Component.Error && /module "org\.kde\.[^"]+" is not installed/.test(component.errorString())) {
            skip("Provider filters need the optional KDE QML modules");
            return;
        }
        compare(component.status, Component.Ready, component.errorString());
        failOnWarning(/.*/);
        var page = createTemporaryObject(component, testCase, {
            cfg_commandPath: " ",
            width: 620,
            height: 700
        });
        verify(page !== null);
        tryCompare(page, "loading", false);
        wait(0);
        page.retireAllConfigCommands();
        page.loading = false;
        page.errorText = "";
        page.providers = [
            {
                provider: "codex",
                displayName: "Codex",
                enabled: true
            },
            {
                provider: "claude",
                displayName: "Claude",
                enabled: false
            }
        ];
        page.selectedProviderID = "codex";
        var beforeSerial = page.commandRunSerial;
        var bar = findChild(page, "providerFilterBar");
        var search = findChild(page, "providerSearchField");
        verify(bar !== null && search !== null);
        compare(page.visibleProviders.length, 2);
        bar.itemAt(0).forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Right);
        tryCompare(page, "filterScope", "enabled");
        compare(page.visibleProviders.length, 1);
        compare(page.visibleProviders[0].provider, "codex");
        keyClick(Qt.Key_Right);
        tryCompare(page, "filterScope", "disabled");
        compare(page.visibleProviders[0].provider, "claude");
        search.text = "Codex";
        compare(page.visibleProviders.length, 0);
        page.clearProviderFilters();
        compare(page.filterScope, "all");
        compare(search.text, "");
        verify(search.activeFocus);
        compare(page.visibleProviders.length, 2);
        compare(page.selectedProviderID, "codex");
        compare(page.commandRunSerial, beforeSerial);
        compare(page.providers[0].enabled, true);
        compare(page.providers[1].enabled, false);
    }
    function test_official074SetupOffersOnlyCompleteLinuxKeyFlows() {
        var page = createProvidersPage();
        if (!page) return;
        var supported = ["tavily", "linkup", "aerostack", "sailresearch", "sofya"];
        var blocked = ["exa", "cosmic", "tinyapi", "xapi", "future-provider"];
        for (var provider of supported.concat(blocked)) {
            var item = {provider: provider, enabled: false};
            var before = JSON.stringify(item);
            var actions = page.providerActionRows(item);
            compare(actions.filter(function(action) { return action.action === "set-api-key"; }).length,
                supported.indexOf(provider) >= 0 ? 1 : 0, provider);
            actions.filter(function(action) { return action.action === "set-api-key"; }).forEach(function(action) {
                compare(action.icon, "document-encrypt", provider);
            });
            if (provider !== "future-provider") {
                compare(actions.filter(function(action) { return action.action === "docs"; }).length, 1);
                compare(actions.filter(function(action) { return action.action === "dashboard"; }).length, 1);
            }
            compare(JSON.stringify(item), before);
        }
    }

    function test_newKeyActionsShowGuidanceAndDocumentation() {
        var page = createProvidersPage();
        if (!page) return;
        var ids = ["soniox", "abliteration", "chatbox"];
        page.providers = ids.map(function(id) { return {provider: id, displayName: id, enabled: false}; });
        page.handleCliVersionResult("CodexBar 0.83.0", 0);
        for (var id of ids) {
            var item = page.providerByID(id);
            var actions = page.providerActionRows(item);
            compare(actions.filter(function(row) { return row.action === "set-api-key"; }).length, 1, id);
            compare(actions.filter(function(row) { return row.action === "docs"; })[0].url,
                "https://github.com/steipete/CodexBar/blob/main/docs/" + id + ".md");
            compare(actions[0].title, id === "chatbox" ? "Set license key…" : "Set API key…");
        }
        var chatbox = page.providerByID("chatbox");
        verify(page.providerSettingsRows(chatbox).some(function(row) { return row.label === "License key setup"; }));
        verify(page.apiKeyPrompt("chatbox").indexOf("authorize AI requests") >= 0);
        verify(page.apiKeyPrompt("soniox").indexOf("Project keys are not supported") >= 0);
        page.handleCommandPathChanged();
        for (var id of ids) compare(page.supportsApiKeySetup(id), false);
    }

    function test_official077MunitoSetupFollowsCliVersionLifecycle() {
        var page = createProvidersPage();
        if (!page) return;
        function keyActions(provider) {
            return page.providerActionRows({provider: provider, enabled: false}).filter(
                function(action) { return action.action === "set-api-key"; }).length;
        }
        function expectSetup(expected) {
            compare(keyActions("munito"), expected ? 1 : 0);
            compare(keyActions("MUNITO"), expected ? 1 : 0);
            compare(keyActions("futureagi"), 0);
            compare(keyActions("future-provider"), 0);
            var hint = page.providerCliCommandText({provider: "munito", enabled: false});
            compare(hint.indexOf("set-api-key") >= 0, expected);
            if (expected) verify(hint.indexOf("--stdin") >= 0);
        }
        expectSetup(false);
        for (var banner of ["CodexBar 0.76.0", "CodexBar 0.77.0-rc1", "unknown"]) {
            page.handleCliVersionResult(banner, 0);
            expectSetup(false);
        }
        for (var version of ["CodexBar 0.77.0", "CodexBar 0.78.0", "CodexBar 1.0.0"]) {
            page.handleCliVersionResult(version, 0);
            expectSetup(true);
        }
        page.handleCliVersionResult("CodexBar 0.77.0", 1);
        expectSetup(false);
        page.handleCliVersionResult("CodexBar 0.77.0", 0);
        page.handleConfigCommandTimeout({kind: "version"});
        expectSetup(false);
        page.handleCliVersionResult("CodexBar 0.77.0", 0);
        page.handleCommandPathChanged();
        expectSetup(false);
    }

    function test_official075ApiKeySetupFollowsCliVersionLifecycle() {
        var page = createProvidersPage();
        if (!page)
            return;

        function actionCount(provider, name) {
            return page.providerActionRows({provider: provider, enabled: false}).filter(
                function(action) { return action.action === name; }).length;
        }

        var closed = [
            {stdout: "CodexBar 0.74.1", code: 0},
            {stdout: "CodexBar 0.75.0-rc1", code: 0},
            {stdout: "unknown", code: 0},
            {stdout: "CodexBar 0.75.0", code: 1}
        ];
        for (var i = 0; i < closed.length; i++) {
            page.handleCliVersionResult(closed[i].stdout, closed[i].code);
            verify(!page.commandCodeFalApiKeySetupSupported, closed[i].stdout);
            compare(actionCount("commandcode", "set-api-key"), 0);
            compare(actionCount("command-code", "set-api-key"), 0);
            compare(actionCount("COMMANDCODE", "set-api-key"), 0);
            compare(actionCount("fal", "set-api-key"), 0);
            compare(actionCount("FAL", "set-api-key"), 0);
            compare(actionCount("flora", "set-api-key"), 0);
            compare(actionCount("parallel", "set-api-key"), 0);
            compare(actionCount("future-provider", "set-api-key"), 0);
        }

        page.handleCliVersionResult("CodexBar 0.75.0", 0);
        verify(page.commandCodeFalApiKeySetupSupported);
        compare(actionCount("commandcode", "set-api-key"), 1);
        compare(actionCount("command-code", "set-api-key"), 1);
        compare(actionCount("COMMANDCODE", "set-api-key"), 1);
        compare(actionCount("fal", "set-api-key"), 1);
        compare(actionCount("FAL", "set-api-key"), 1);
        compare(actionCount("flora", "set-api-key"), 0);
        compare(actionCount("parallel", "set-api-key"), 0);
        compare(actionCount("future-provider", "set-api-key"), 0);

        compare(actionCount("fal", "docs"), 1);
        compare(actionCount("fal", "dashboard"), 1);
        compare(actionCount("fal", "login"), 1);
        compare(actionCount("flora", "docs"), 1);
        compare(actionCount("flora", "dashboard"), 1);
        compare(actionCount("flora", "login"), 1);
        compare(actionCount("parallel", "docs"), 1);
        compare(actionCount("parallel", "dashboard"), 1);
        compare(actionCount("parallel", "login"), 1);
        compare(actionCount("future-provider", "docs"), 0);
        compare(actionCount("future-provider", "dashboard"), 0);
        compare(actionCount("future-provider", "login"), 0);

        page.handleConfigCommandTimeout({kind: "version"});
        verify(!page.commandCodeFalApiKeySetupSupported);
        compare(actionCount("commandcode", "set-api-key"), 0);
        compare(actionCount("fal", "set-api-key"), 0);

        page.handleCliVersionResult("CodexBar 0.76.0", 0);
        verify(page.commandCodeFalApiKeySetupSupported);
        page.handleCommandPathChanged();
        verify(!page.commandCodeFalApiKeySetupSupported);
        compare(actionCount("commandcode", "set-api-key"), 0);
        compare(actionCount("fal", "set-api-key"), 0);
    }

    // The reload tooltip speaks the button's accessible name through the safe
    // wrapper, so assistive technology and the visible tip never disagree.
    // The explicit parent is declarative nesting spelled out: dropping it
    // changes nothing, and this stays green either way.
    function test_reloadTooltipRoutesAccessibleName() {
        var page = createProvidersPage();
        if (!page)
            return;
        var all = [];
        walkPageObjects(page, all);
        var buttons = all.filter(function(item) {
            return item instanceof Controls.ToolButton && item.icon.name === "view-refresh";
        });
        compare(buttons.length, 1);
        var tips = all.filter(function(item) {
            return item.toString().indexOf("PlainToolTip") >= 0 && item.parent === buttons[0];
        });
        compare(tips.length, 1);
        compare(tips[0].parent, buttons[0]);
        compare(tips[0].plainText, buttons[0].Accessible.name);
    }

    function settingsToggle(page) {
        var all = [];
        walkPageObjects(page, all);
        var matches = all.filter(function(item) {
            return item instanceof Controls.Button && item.Accessible.name === "Settings and diagnostics";
        });
        return matches.length > 0 ? matches[0] : null;
    }

    // A hidden control inside a visible row is still hidden from the user, so
    // both have to be checked: a row-only test would pass on a control the
    // page never shows.
    function controlVisibleInRow(item) {
        var node = item.parent;
        while (node !== null && node.toString().indexOf("RowLayout") === -1)
            node = node.parent;
        return node !== null && node.visible && item.visible;
    }

    // Each descriptor kind shows its own row: flipping a kind hides that
    // row's controls, so the options section cannot silently drop a field.
    function test_descriptorKindRowsShowMatchingControls() {
        var page = createProvidersPage();
        if (!page)
            return;
        page.providers = [{
                provider: "codex",
                displayName: "Codex",
                enabled: true,
                descriptor: {fields: [
                    {id: "apiKey", kind: "secret", title: "API key", description: "Secret",
                        redactedValue: "", valueText: "", value: "", options: [],
                        selectedOptionIndex: -1},
                    {id: "color", kind: "enum", title: "Color", description: "Pick",
                        redactedValue: "", valueText: "", value: "r",
                        options: [{id: "r", title: "Red"}], selectedOptionIndex: 0},
                    {id: "flag", kind: "boolean", title: "Flag", description: "Enable everything",
                        redactedValue: "", valueText: "", value: "false", options: [],
                        selectedOptionIndex: -1}
                ]}
            }];
        page.selectedProviderID = "codex";
        var toggle = settingsToggle(page);
        verify(toggle !== null);
        toggle.clicked();
        verify(toggle.expanded);
        wait(0);
        var all = [];
        walkPageObjects(page, all);
        var optionsLabels = all.filter(function(item) {
            return item.toString().indexOf("PlainControlsLabel") >= 0
                && item.text === "Provider options";
        });
        compare(optionsLabels.length, 1);
        var setButtons = all.filter(function(item) {
            return item instanceof Controls.Button && item.text === "Set…"
                && controlVisibleInRow(item);
        });
        compare(setButtons.length, 1);
        var combos = all.filter(function(item) {
            return item instanceof Controls.ComboBox && item.model !== undefined
                && item.model.length === 1 && controlVisibleInRow(item);
        });
        compare(combos.length, 1);
        var boxes = all.filter(function(item) {
            return item instanceof Controls.CheckBox && item.Accessible.name === "Flag"
                && controlVisibleInRow(item);
        });
        compare(boxes.length, 1);
    }

    // The settings section keeps its headings and the immediate-save notice,
    // so a renamed label cannot drift past review unnoticed.
    function test_settingsSectionLabels() {
        var page = createProvidersPage();
        if (!page)
            return;
        page.providers = [{provider: "openai", displayName: "OpenAI", enabled: true}];
        page.selectedProviderID = "openai";
        var toggle = settingsToggle(page);
        verify(toggle !== null);
        toggle.clicked();
        verify(toggle.expanded);
        wait(0);
        var all = [];
        walkPageObjects(page, all);
        var inspect = all.filter(function(item) {
            return item instanceof Controls.Button && item.text === "Inspect redacted settings";
        });
        compare(inspect.length, 1);
        verify(inspect[0].visible);
        var immediate = all.filter(function(item) {
            return item.text !== undefined
                && String(item.text).indexOf("CodexBar saves provider changes immediately") === 0;
        });
        verify(immediate.length >= 1);
        var cli = all.filter(function(item) {
            return item instanceof Controls.Button && item.Accessible.name === "CLI commands";
        });
        compare(cli.length, 1);
    }

    // The CLI helper on the page prints the same redacted diagnose and
    // set-api-key lines the command builder produces.
    function test_cliCommandsTextShowsHelpfulCommands() {
        var page = createProvidersPage();
        if (!page)
            return;
        page.providers = [{provider: "openai", displayName: "OpenAI", enabled: true}];
        page.selectedProviderID = "openai";
        var toggle = settingsToggle(page);
        verify(toggle !== null);
        toggle.clicked();
        verify(toggle.expanded);
        wait(0);
        var all = [];
        walkPageObjects(page, all);
        var cli = all.filter(function(item) {
            return item instanceof Controls.Button && item.Accessible.name === "CLI commands";
        });
        compare(cli.length, 1);
        cli[0].clicked();
        verify(cli[0].expanded);
        wait(0);
        var areas = [];
        walkPageObjects(page, areas);
        var textAreas = areas.filter(function(item) {
            return item instanceof Controls.TextArea;
        });
        compare(textAreas.length, 1);
        verify(textAreas[0].text.indexOf("diagnose --provider") !== -1);
        verify(textAreas[0].text.indexOf("config set-api-key --provider") !== -1);
        verify(textAreas[0].text.indexOf("openai") !== -1);
    }

    // Provider action titles come from CLI descriptors: the button must route
    // them through the safe label instead of interpreting markup.
    function test_providerActionButtonRendersTitleAsPlainText() {
        var page = createProvidersPage();
        if (!page)
            return;
        var hostile = 'Open <b>Docs</b> & "more"';
        page.providers = [{
                provider: "codex",
                displayName: "Codex",
                enabled: true,
                descriptor: {actions: [{id: "openDocs", title: hostile}]}
            }];
        page.selectedProviderID = "codex";
        wait(0);
        var all = [];
        walkPageObjects(page, all);
        var matches = all.filter(function(item) {
            return item instanceof Controls.Button && item.Accessible.name === hostile;
        });
        compare(matches.length, 1);
        compare(matches[0].text, SafeText.plainButtonText(hostile, matches[0].contentItem !== null));
    }

    // Descriptor titles, descriptions and option labels are untrusted CLI
    // text: every field control must render them as plain text.
    function test_descriptorFieldControlsRenderUntrustedTextAsPlain() {
        var page = createProvidersPage();
        if (!page)
            return;
        var description = "Pick a <img src=x> value & go";
        // Entity-free like the flag below: the desktop native delegate warns
        // on escaped entities at render time, while the <span> wrapper still
        // tells the safe routing apart from a raw assignment. Hostile option
        // text stays covered at the component seam in
        // tst_plain_text_controls.qml.
        var option = "Red";
        // Entity-free on purpose: the desktop native label warns on escaped
        // entities at render time, while the <span> wrapper still tells the
        // safe routing apart from a raw assignment. Hostile checkbox text
        // stays covered at the component seam in tst_plain_text_controls.qml.
        var flag = "Enable everything";
        page.providers = [{
                provider: "codex",
                displayName: "Codex",
                enabled: true,
                descriptor: {fields: [
                    {id: "name", kind: "text", title: "Name", description: description,
                        redactedValue: "", valueText: "", value: "", options: [],
                        selectedOptionIndex: -1},
                    {id: "color", kind: "enum", title: "Color", description: "Pick",
                        redactedValue: "", valueText: "", value: "r",
                        options: [{id: "r", title: option}], selectedOptionIndex: 0},
                    {id: "flag", kind: "boolean", title: "Flag", description: flag,
                        redactedValue: "", valueText: "", value: "false", options: [],
                        selectedOptionIndex: -1}
                ]}
            }];
        page.selectedProviderID = "codex";
        wait(0);
        var all = [];
        walkPageObjects(page, all);
        var fields = all.filter(function(item) {
            return item instanceof Controls.TextField && item.Accessible.description === description;
        });
        compare(fields.length, 1);
        compare(fields[0].placeholderText, SafeText.plainTextAsRichText(description));
        var boxes = all.filter(function(item) {
            return item instanceof Controls.CheckBox && item.Accessible.name === "Flag";
        });
        compare(boxes.length, 1);
        compare(boxes[0].Accessible.description, flag);
        compare(boxes[0].text, SafeText.plainTextAsRichText(flag));
        // Every field row instantiates an enum box; only the enum field feeds
        // it options, so match the one that owns our hostile option.
        var combos = all.filter(function(item) {
            return item instanceof Controls.ComboBox && item.model !== undefined
                && item.model.length === 1;
        });
        compare(combos.length, 1);
        combos[0].popup.open();
        tryCompare(combos[0].popup, "visible", true);
        // Popup visuals live under contentItem; the Popup itself owns no
        // children to walk.
        var popupItems = [];
        walkPageObjects(combos[0].popup.contentItem, popupItems);
        var options = popupItems.filter(function(item) {
            return item.toString().indexOf("PlainItemDelegate") >= 0;
        });
        verify(options.length >= 1);
        compare(options[0].text, SafeText.plainTextAsMnemonicRichText(option));
        combos[0].popup.close();
    }

    function configTimeoutTimer(page) {
        var all = [];
        walkPageObjects(page, all);
        // The sweep timer is the only repeating one-second timer on the
        // page: desktop-style delegates add their own hover timers, so the
        // production interval doubles as the identity here.
        var found = all.filter(function(item) {
            return item.toString().indexOf("Timer") >= 0 && item.repeat === true
                && item.interval === 1000;
        });
        return found.length === 1 ? found[0] : null;
    }

    // The sweep timer must retire a hung command through the expire path:
    // with the timer shortened, an already-overdue entry is disconnected
    // and the page reports the timeout instead of loading forever.
    function test_configTimeoutTimerExpiresHungCommands() {
        var page = createProvidersPage();
        if (!page)
            return;
        var timer = configTimeoutTimer(page);
        verify(timer !== null);
        page.loading = true;
        page.errorText = "";
        page.commands = {
            "synthetic-hung-source": {kind: "list", provider: "codex",
                deadlineMs: Date.now() - 1000}
        };
        // No restart(): the running binding must have started the timer when
        // the overdue entry landed, so shortening the interval is enough.
        timer.interval = 80;
        tryVerify(function() { return !page.loading; }, 5000);
        verify(page.errorText.length > 0);
        verify(page.errorText.indexOf("timed out") !== -1);
        compare(Object.keys(page.commands).length, 0);
    }

    // Switching the command path must retire the in-flight command and
    // clear the roster, so a late reply from the old executable cannot
    // replace the fresh state.
    function test_commandPathChangeRetiresCommandsAndClearsProviders() {
        var page = createProvidersPage();
        if (!page)
            return;
        page.commands = {
            "synthetic-old-source": {kind: "list", provider: "codex",
                deadlineMs: Date.now() + 60000}
        };
        page.providers = [{provider: "codex", displayName: "Codex", enabled: true}];
        page.selectedProviderID = "codex";
        // Blank on purpose: the handler retires and clears before the
        // reloaded commands could run, and the follow-up reload then stays
        // on its early-return path (Plasmoid.configuration is absent here).
        page.cfg_commandPath = "   ";
        compare(Object.keys(page.commands).length, 0);
        compare(page.providers.length, 0);
        compare(page.selectedProviderID, "");
        wait(0);
        page.retireAllConfigCommands();
    }

    function test_savedSourceSelectionPreservesDraftAndReopeningUsesSavedValue() {
        var page = createProvidersPage();
        if (!page) return;
        page.providers = [{provider: "codex", displayName: "Codex", enabled: false}];
        page.selectedProviderID = "codex";
        page.handleCliVersionResult("CodexBar 0.83.0", 0);
        var box = findChild(page, "providerSourceBox");
        var save = findChild(page, "providerSourceSaveButton");
        function read(target, mode) {
            target.savedProviderSources = {"provider:codex": mode};
        }
        read(page, "api");
        compare(box.currentText, "API");
        verify(!save.enabled);
        box.activated(1);
        compare(page.providerSourceDraft, "");
        read(page, "web");
        compare(box.currentText, "Web");
        box.currentIndex = 2;
        box.activated(2);
        page.commands = {"pending-read": {kind: "sources"}};
        verify(!save.enabled);
        page.commands = ({});
        read(page, "oauth");
        compare(box.currentText, "CLI"); // A late read cannot erase a draft.
        page.destroy();
        page = createProvidersPage();
        page.providers = [{provider: "codex", displayName: "Codex", enabled: false}];
        page.selectedProviderID = "codex";
        read(page, "oauth");
        compare(findChild(page, "providerSourceBox").currentText, "OAuth");
    }

    function test_sourceEditorGateSelectionAndPendingState() {
        var page = createProvidersPage();
        if (!page)
            return;
        page.providers = [{provider: "codex", displayName: "Codex", enabled: false},
            {provider: "future", displayName: "Future", enabled: true}];
        page.selectedProviderID = "codex";
        settingsToggle(page).expanded = true;
        var box = findChild(page, "providerSourceBox");
        var save = findChild(page, "providerSourceSaveButton");
        verify(box !== null && save !== null);
        page.handleCliVersionResult("CodexBar 0.72.0", 0);
        verify(!box.visible);
        page.handleCliVersionResult("CodexBar 0.73.0", 0);
        verify(box.visible);
        compare(box.currentIndex, -1);
        compare(box.displayText, "Choose a source");
        verify(!save.enabled);
        box.currentIndex = 1;
        box.activated(1);
        compare(box.displayText, "API");
        verify(save.enabled);
        page.loading = true;
        verify(!box.enabled && !save.enabled);
        page.loading = false;
        verify(save.enabled);
        page.markFieldPending("codex", "key", true);
        verify(!box.enabled && !save.enabled);
        page.markFieldPending("codex", "key", false);
        page.markFieldPending("future", "action", true);
        verify(save.enabled);
        page.markFieldPending("future", "action", false);
        page.markPending("codex", true, false);
        verify(!box.enabled && !save.enabled);
        page.markPending("codex", false);
        verify(save.enabled);
        page.selectedProviderID = "future";
        compare(box.currentIndex, -1);
        verify(!save.enabled);
        page.handleCliVersionResult("unknown", 0);
        verify(!box.visible);
    }

    function test_inventoryModesReplaceLegacyChoicesAndResetSelection() {
        var page = createProvidersPage();
        if (!page) return;
        page.handleCliVersionResult("CodexBar 0.83.0", 0);
        settingsToggle(page).expanded = true;
        function publish(authentication) {
            page.providers = ProviderConfigProtocol.normalizeProviderList([
                {provider: "openrouter", authentication: authentication}, {provider: "future", enabled: false}]);
            page.selectedProviderID = "openrouter";
        }
        publish({sourceModes: ["api", "auto"], supportsConfigAPIKey: true});
        var box = findChild(page, "providerSourceBox");
        var save = findChild(page, "providerSourceSaveButton");
        compare(box.count, 2);
        compare(box.textAt(0), "API");
        compare(box.textAt(1), "Automatic");
        compare(box.currentIndex, -1);
        box.currentIndex = 1;
        box.activated(1);
        verify(save.enabled);
        page.updateProviderEnabled("future", true);
        wait(0);
        compare(box.currentIndex, 1);
        verify(save.enabled);
        publish({sourceModes: ["api"], supportsConfigAPIKey: false});
        compare(box.count, 1);
        compare(box.currentIndex, -1);
        verify(!save.enabled && !page.supportsApiKeySetup("openrouter"));
        publish(undefined);
        compare(box.count, 5);
        verify(page.supportsApiKeySetup("openrouter"));
        publish({sourceModes: []});
        verify(!box.visible);
    }

    function optionsNoticeText(page) {
        var all = [];
        walkPageObjects(page, all);
        var labels = all.filter(function(item) {
            return item.toString().indexOf("PlainControlsLabel") >= 0
                && item.visible
                && (String(item.text).indexOf("Editable provider options") === 0
                    || String(item.text).indexOf("This CodexBar version") === 0);
        });
        return labels.length === 1 ? String(labels[0].text) : "";
    }

    // The options notice must name the source of truth for the current CLI:
    // with descriptors it points at CodexBar, without them it discloses
    // that only the fallback rows remain.
    function test_optionsNoticeFollowsDescriptorsAvailability() {
        var page = createProvidersPage();
        if (!page)
            return;
        page.providers = [{provider: "openai", displayName: "OpenAI", enabled: true}];
        page.selectedProviderID = "openai";
        var toggle = settingsToggle(page);
        verify(toggle !== null);
        toggle.clicked();
        verify(toggle.expanded);
        wait(0);
        page.providerDescriptorsUnavailable = false;
        wait(0);
        verify(optionsNoticeText(page).indexOf("Editable provider options come from CodexBar") === 0);
        page.providerDescriptorsUnavailable = true;
        wait(0);
        verify(optionsNoticeText(page).indexOf("This CodexBar version does not expose editable provider options") === 0);
    }

    // Brand colours survive per provider instead of collapsing to one
    // accent: two branded providers differ, and unbranded ids share the
    // single theme fallback.
    function test_providerColorKeepsBrandIdentityPerProvider() {
        var page = createProvidersPage();
        if (!page)
            return;
        verify(String(page.providerColor("codex")) !== String(page.providerColor("replicate")));
        compare(String(page.providerColor("unknown-xyz")), String(page.providerColor("unknown-abc")));
        verify(String(page.providerColor("unknown-xyz")) !== String(page.providerColor("replicate")));
    }

    // The readable variant keeps the non-text contrast bar on a dark
    // background, so a near-black brand cannot dissolve into it.
    function test_providerReadableColorKeepsContrastOnDarkBackground() {
        var page = createProvidersPage();
        if (!page)
            return;
        var background = Qt.rgba(0, 0, 0, 1);
        var readable = page.providerReadableColor("replicate", background);
        verify(ThemeContrast.contrastRatio(readable, background) >= 3);
    }
    function test_providerPanesKeepSelectionAndKeyboardReachable() {
        var page = createProvidersPage();
        if (!page) return;
        page.providers = Array.from({length: 20}, function(_, i) {
            return {provider: "example" + i, displayName: "Example provider " + i, enabled: true};
        });
        page.selectedProviderID = "example0";
        for (var width of [840, 420]) {
            page.width = width;
            wait(50);
            var list = findChild(page, "providerListScroll");
            var detail = findChild(page, "selectedProviderSurface");
            verify(list.width > 0 && detail.width > 0);
            var listPos = list.mapToItem(page, 0, 0);
            var detailPos = detail.mapToItem(page, 0, 0);
            if (width === 840) {
                verify(detailPos.x > listPos.x + list.width);
                fuzzyCompare(detailPos.y + detail.height, listPos.y + list.height, 1);
            } else verify(detailPos.y >= listPos.y + list.height);
            verify(detailPos.x + detail.width <= page.width);
            var all = [];
            walkPageObjects(page, all);
            var last = all.filter(function(item) {
                return item.providerData && item.providerData.provider === "example19";
            })[0];
            verify(last !== undefined);
            last.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
            compare(page.selectedProviderID, "example19");
            var rowPos = last.mapToItem(list, 0, 0);
            verify(rowPos.y >= -1 && rowPos.y + last.height <= list.height + 1);
            verify(!settingsToggle(page).expanded);
            findChild(page, "providerSearchField").forceActiveFocus();
        }
    }

    function test_providerPaneBottomsAlignWithExpandedDetails() {
        var page = createProvidersPage();
        if (!page) return;
        page.providers = [{provider: "codex", displayName: "Codex", enabled: true}];
        page.selectedProviderID = "codex";
        page.width = 840;
        page.height = 300;
        settingsToggle(page).expanded = true;
        wait(50);
        var list = findChild(page, "providerListScroll");
        var detail = findChild(page, "selectedProviderSurface");
        verify(detail.height > page.flickable.height);
        fuzzyCompare(list.mapToItem(page, 0, list.height).y, detail.mapToItem(page, 0, detail.height).y, 1);
    }

    function test_descriptorActionsStayPlainTextCommands() {
        var page = createProvidersPage();
        if (!page) return;
        page.providers = [{provider: "codex", displayName: "Codex", enabled: true, descriptor: {actions: [
            {id: "openDashboard", title: "Usage dashboard"}, {id: "refreshSession", title: "Refresh session"}]}}];
        page.selectedProviderID = "codex";
        compare(page.providerLinkRow("dashboard"), null);
        var commands = page.selectedProviderCommandRows.map(function(row) { return row.title; });
        verify(commands.indexOf("Refresh session") >= 0 && commands.indexOf("Usage dashboard") >= 0);
    }

    function test_inspectionValuesAlignAndStackWhenNarrow() {
        var page = createProvidersPage();
        if (!page) return;
        page.providers = [{provider: "codex", displayName: "Codex", enabled: true}];
        page.selectedProviderID = "codex";
        settingsToggle(page).expanded = true;
        for (var width of [840, 420]) {
            page.width = width;
            wait(50);
            var all = [];
            walkPageObjects(page, all);
            var values = all.filter(function(item) { return item.objectName === "providerSettingValue"; });
            verify(values.length >= 3);
            var firstX = values[0].mapToItem(page, 0, 0).x;
            for (var value of values) {
                fuzzyCompare(value.mapToItem(page, 0, 0).x, firstX, 1);
                var label = findChild(value.parent, "providerSettingLabel");
                verify(label !== null);
                if (width === 840) verify(value.x >= label.x + label.width);
                else verify(value.y >= label.y + label.height);
            }
        }
    }

    function test_credentialActionVisibilityByVersionAndRegistry() {
        var page = createProvidersPage();
        if (!page) return;
        page.providers = ProviderConfigProtocol.response(JSON.stringify([
            {provider:"copilot", enabled:false}, {provider:"claude", enabled:false},
            {provider:"future-provider", enabled:false}, {provider:"helmcode", enabled:false},
            {provider:"siliconflow", enabled:false}, {provider:"tripo", enabled:false},
            {provider:"workbuddy", enabled:false}, {provider:"claudeplatform", enabled:false}]), "", 0, "list", page.providerTitle).value;
        function actions(provider) {
            return page.providerActionRows(page.providerByID(provider)).map(function(row) { return row.action; });
        }
        page.handleCliVersionResult("CodexBar 0.79.0", 0);
        verify(actions("copilot").indexOf("device-login") < 0);
        verify(actions("claude").indexOf("set-cookie") < 0);
        verify(actions("future-provider").indexOf("clear-credential") < 0);
        page.handleCliVersionResult("CodexBar 0.80.0", 0);
        verify(actions("copilot").indexOf("device-login") >= 0);
        verify(actions("copilot").indexOf("set-api-key") >= 0);
        verify(actions("claude").indexOf("device-login") < 0);
        page.handleCliVersionResult("CodexBar 0.82.0", 0);
        verify(actions("claude").indexOf("set-cookie") >= 0);
        verify(actions("helmcode").indexOf("set-cookie") < 0);
        verify(actions("future-provider").indexOf("clear-credential") >= 0);
        // Links move to the header toolbar; clearing follows every setup command.
        page.selectedProviderID = "copilot";
        var commandActions = page.selectedProviderCommandRows.map(function(row) { return row.action; });
        compare(commandActions[commandActions.length - 1], "clear-credential");
        verify(commandActions.indexOf("device-login") >= 0 && commandActions.indexOf("docs") < 0);
        verify(page.selectedProviderLinkRows.every(function(row) { return row.url.length > 0; }));
        compare(page.providerLinkRow("docs").action, "docs");
        compare(page.providerLinkRow("missing"), null);
        page.handleCliVersionResult("CodexBar 0.83.0", 0);
        verify(actions("siliconflow").indexOf("set-api-key") < 0);
        verify(actions("tripo").indexOf("set-api-key") < 0);
        verify(actions("workbuddy").indexOf("set-cookie") < 0);
        verify(actions("claudeplatform").indexOf("import-session") < 0);
        page.handleCliVersionResult("CodexBar 0.84.0", 0);
        verify(actions("siliconflow").indexOf("set-api-key") >= 0);
        verify(actions("tripo").indexOf("set-api-key") >= 0);
        verify(actions("workbuddy").indexOf("set-cookie") >= 0);
        verify(actions("claudeplatform").indexOf("import-session") >= 0);
        verify(actions("claudeplatform").indexOf("set-cookie") >= 0);
        compare(page.providerTitle("siliconflow"), "SiliconFlow");
        compare(page.providerTitle("tripo"), "Tripo");
        page.handleCliVersionResult("CodexBar 0.84.0", 1);
        verify(actions("siliconflow").indexOf("set-api-key") < 0);
        verify(actions("tripo").indexOf("set-api-key") < 0);
        verify(actions("workbuddy").indexOf("set-cookie") < 0);
        verify(actions("claudeplatform").indexOf("import-session") < 0);
        verify(actions("copilot").indexOf("device-login") < 0);
        compare(Object.keys(page.commands).length, 0);
    }

}
