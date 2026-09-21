import QtQuick
import QtQuick.Controls as Controls
import QtTest
import "../contents/ui/SafeText.js" as SafeText

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
}
