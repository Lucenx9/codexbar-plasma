import QtQuick
import QtQuick.Controls as Controls
import QtTest
import "../contents/ui/SafeText.js" as SafeText
import "../contents/ui/ThemeContrast.js" as ThemeContrast

TestCase {
    id: testCase
    name: "ProviderFilters"
    when: windowShown
    width: 620
    height: 700
    visible: true

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
            return item.toString().indexOf("PlainToolTip") >= 0;
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
            return item instanceof Controls.Button && item.text === "Set..."
                && controlVisibleInRow(item);
        });
        compare(setButtons.length, 1);
        var combos = all.filter(function(item) {
            return item instanceof Controls.ComboBox && item.model !== undefined
                && item.model.length === 1 && controlVisibleInRow(item);
        });
        compare(combos.length, 1);
        var boxes = all.filter(function(item) {
            return item instanceof Controls.CheckBox && item.Accessible.name === "Enable everything"
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
            return item.plainText !== undefined
                && String(item.plainText).indexOf("Provider changes are saved by CodexBar immediately") === 0;
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
            return item instanceof Controls.CheckBox && item.Accessible.name === flag;
        });
        compare(boxes.length, 1);
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
}
