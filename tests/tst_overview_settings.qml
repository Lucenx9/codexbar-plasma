import QtQuick
import QtQuick.Controls as Controls
import QtTest
import "../contents/ui/OverviewProviders.js" as OverviewProviders

TestCase {
    id: testCase
    name: "OverviewSettings"
    when: windowShown
    visible: true
    width: 600
    height: 900

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    function i18np(singular, plural, count) {
        return (count === 1 ? singular : plural).replace("%1", count);
    }

    function providerCheck(item, label) {
        if (item instanceof Controls.CheckBox && item.Accessible.name === label) {
            return item;
        }
        var children = item.children || [];
        for (var child of children) {
            var match = providerCheck(child, label);
            if (match)
                return match;
        }
        return null;
    }

    function createPage(properties) {
        var component = Qt.createComponent("../contents/ui/configPopup.qml");
        if (component.status === Component.Error && /module "org\.kde\.[^"]+" is not installed/.test(component.errorString())) {
            skip("Overview settings checks need the optional KDE QML modules");
            return null;
        }
        compare(component.status, Component.Ready, component.errorString());
        failOnWarning(/.*/);
        var page = createTemporaryObject(component, testCase, Object.assign({
            width: testCase.width,
            height: testCase.height,
            cfg_commandPath: "true",
            cfg_overviewProviderIDs: ""
        }, properties || {}));
        verify(page !== null);
        return page;
    }

    function waitForRosterSettled(page) {
        var controller = findChild(page, "providerRosterController");
        verify(controller !== null);
        tryVerify(function () {
            return controller.commandRunSerial > 0 && !controller.providerRosterLoading && !controller.hasPendingProviderRosterCommands();
        });
        return controller;
    }

    function walkObjects(root, out) {
        if (root === null || root === undefined || out.indexOf(root) >= 0)
            return;
        out.push(root);
        var groups = [root.children, root.resources, root.data];
        for (var g = 0; g < groups.length; g++) {
            var kids = groups[g];
            if (kids === undefined || kids === null)
                continue;
            for (var i = 0; i < kids.length; i++)
                walkObjects(kids[i], out);
        }
    }

    function checkByText(page, label) {
        var all = [];
        walkObjects(page, all);
        var matches = all.filter(function(item) {
            return item instanceof Controls.CheckBox && item.text === label;
        });
        return matches.length > 0 ? matches[0] : null;
    }

    function test_disabledSelectionsLeaveRoomForEnabledProviders() {
        var page = createPage({cfg_overviewProviderIDs: "claude,gemini,copilot"});
        if (!page)
            return;
        var controller = waitForRosterSettled(page);
        controller.providerRosterError = "";
        controller.enabledProviderRoster = [
            {
                provider: "codex",
                displayName: "Codex"
            },
            {
                provider: "groq",
                displayName: "Groq"
            },
            {
                provider: "cursor",
                displayName: "Cursor"
            },
            {
                provider: "openai",
                displayName: "OpenAI"
            }
        ];
        compare(page.selectedOverviewProviderCount(), 0);
        for (var label of ["Codex", "Groq", "Cursor"]) {
            var check = providerCheck(page, label);
            verify(check !== null, label);
            verify(check.enabled, label + " must remain selectable");
            check.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
            verify(check.checked, label);
        }
        compare(page.selectedOverviewProviderCount(), 3);
        verify(!providerCheck(page, "OpenAI").enabled);
        compare(OverviewProviders.configuredProviderIDs(page.cfg_overviewProviderIDs).join(","), "codex,groq,cursor,claude,gemini,copilot");

        var codex = providerCheck(page, "Codex");
        codex.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(page.selectedOverviewProviderCount(), 2);
        verify(providerCheck(page, "OpenAI").enabled);
        compare(OverviewProviders.configuredProviderIDs(page.cfg_overviewProviderIDs).join(","), "groq,cursor,claude,gemini,copilot");
    }

    // Rows hidden from the popup are listed by provider and row name, from
    // the stored IDs alone, and Restore removes only its own entry.
    function test_hiddenUsageRowsListAndRestore() {
        var page = createPage({cfg_popupHiddenUsageRows: JSON.stringify([
            {provider: "codex", row: "secondary"},
            {provider: "claude", row: "extra:opus-weekly"}
        ])});
        if (!page)
            return;
        var controller = waitForRosterSettled(page);
        controller.providerRosterError = "";
        controller.enabledProviderRoster = [{provider: "codex", displayName: "Codex CLI"}];
        var all = [];
        walkObjects(page, all);
        var texts = all.map(function(item) { return item.text; });
        verify(texts.indexOf("Codex CLI: Weekly") >= 0, texts.join("|"));
        verify(texts.indexOf("Claude: Extra window opus-weekly") >= 0, texts.join("|"));
        var buttons = all.filter(function(item) { return item.objectName === "restoreHiddenUsageRowButton"; });
        compare(buttons.length, 2);
        compare(buttons[0].Accessible.name, "Restore Codex CLI: Weekly");
        buttons[0].forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(JSON.parse(page.cfg_popupHiddenUsageRows), [{provider: "claude", row: "extra:opus-weekly"}]);
        tryVerify(function() {
            var now = [];
            walkObjects(page, now);
            return now.filter(function(item) { return item.objectName === "restoreHiddenUsageRowButton"; }).length === 1;
        });
        page.restoreHiddenUsageRow({provider: "claude", row: "extra:opus-weekly"});
        compare(page.cfg_popupHiddenUsageRows, "");
        tryVerify(function() {
            var now = [];
            walkObjects(page, now);
            return now.some(function(item) { return item.text === "None. Hide a usage row with its button in the popup."; });
        });
    }

    // The usage-details checkboxes own their configuration keys: flipping
    // one must write only its own key.
    function test_usageDetailsTogglesWriteConfiguration() {
        var page = createPage();
        if (!page)
            return;
        waitForRosterSettled(page);
        var cases = [
            {label: "Show usage as percent used", key: "cfg_usageBarsShowUsed"},
            {label: "Show quota warnings on usage meters", key: "cfg_showQuotaWarningMarkers"},
            {label: "Show reset times as clock time", key: "cfg_resetTimesShowAbsolute"}
        ];
        for (var i = 0; i < cases.length; i++) {
            var box = checkByText(page, cases[i].label);
            verify(box !== null, cases[i].label);
            var before = page[cases[i].key];
            box.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
            compare(page[cases[i].key], !before);
            keyClick(Qt.Key_Space);
            compare(page[cases[i].key], before);
        }
    }

    // Provider display names arrive from the CLI: markup in a name must
    // render as text, never as structure, in the overview checklist.
    function test_providerDisplayNamesEscapeMarkup() {
        var page = createPage();
        if (!page)
            return;
        var controller = waitForRosterSettled(page);
        controller.providerRosterError = "";
        controller.enabledProviderRoster = [
            {provider: "codex", displayName: "<b>Bold</b> & \"Quoted\""}
        ];
        var check = providerCheck(page, "<b>Bold</b> & \"Quoted\"");
        verify(check !== null);
        verify(check.text.indexOf("<b>") === -1);
        verify(check.text.indexOf("&lt;b&gt;") >= 0);
    }

    // Order-button tooltips must label their own button: a static tooltip
    // leaves keyboard users without a target.
    function test_orderTooltipsFollowMoveButtons() {
        var page = createPage();
        if (!page)
            return;
        var controller = waitForRosterSettled(page);
        controller.providerRosterError = "";
        controller.enabledProviderRoster = [
            {provider: "codex", displayName: "Codex"},
            {provider: "claude", displayName: "Claude"}
        ];
        var all = [];
        walkObjects(page, all);
        var moveTips = all.filter(function(item) {
            return item.toString().indexOf("PlainToolTip") >= 0
                && item.parent && item.parent.Accessible
                && String(item.parent.Accessible.name).indexOf("Move ") === 0;
        });
        compare(moveTips.length, 4);
        for (var i = 0; i < moveTips.length; i++) {
            verify(moveTips[i].plainText.length > 0);
            compare(moveTips[i].plainText, moveTips[i].parent.Accessible.name);
        }
    }
}
