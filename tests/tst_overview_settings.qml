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

    property bool mirroredPage: false
    LayoutMirroring.enabled: mirroredPage
    LayoutMirroring.childrenInherit: true

    function cleanup() {
        mirroredPage = false;
    }

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

    function test_compactSectionHeadings_data() {
        return [{tag: "narrow", width: 420}, {tag: "wide", width: 840}];
    }

    function test_compactSectionHeadings(data) {
        var page = createPage({width: data.width});
        if (!page)
            return;
        waitForRosterSettled(page);
        waitForRendering(page);
        var items = [];
        walkObjects(page, items);
        var headings = items.filter(function(item) {
            return item.visible && item.level === 3
                && item.Accessible.role === Accessible.Heading;
        });
        compare(headings.map(function(heading) { return heading.text; }),
            ["Usage details", "Popup content", "Providers", "Hidden items"]);

        var previousOption = checkByText(page, "Show quota warnings on usage meters");
        verify(previousOption !== null);
        var optionBottom = previousOption.mapToItem(page, 0, previousOption.height).y;
        var popupHeading = headings[1];
        var headingTop = popupHeading.mapToItem(page, 0,
            popupHeading.height - popupHeading.contentHeight).y;
        var gap = headingTop - optionBottom;
        verify(gap <= previousOption.height + popupHeading.contentHeight / 2,
            "The next heading should stay close to the end of the previous section, gap: " + gap);
    }

    function test_manualSelectionKeepsDisabledProvidersAndAllowsMoreThanThree() {
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
        for (var label of ["Codex", "Groq", "Cursor", "OpenAI"]) {
            var check = providerCheck(page, label);
            verify(check !== null, label);
            verify(check.enabled, label + " must remain selectable");
            check.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
            verify(check.checked, label);
        }
        compare(page.cfg_overviewProviderIDs, "codex,groq,cursor,openai,claude,gemini,copilot");

        var codex = providerCheck(page, "Codex");
        codex.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(page.cfg_overviewProviderIDs, "groq,cursor,openai,claude,gemini,copilot");
    }

    function test_fullSelectionKeepsExistingCheckboxesEditable() {
        var absent = Array.from({length: 255}, function(_, index) { return "absent-" + index; });
        var saved = ["codex"].concat(absent).join(",");
        var page = createPage({cfg_overviewProviderIDs: saved});
        if (!page)
            return;
        var controller = waitForRosterSettled(page);
        controller.enabledProviderRoster = [
            {provider: "codex", displayName: "Codex"},
            {provider: "claude", displayName: "Claude"}
        ];
        var codex = providerCheck(page, "Codex");
        var claude = providerCheck(page, "Claude");
        verify(codex.checked && codex.enabled);
        verify(!claude.checked && !claude.enabled);
        compare(page.cfg_overviewProviderIDs, saved);

        codex.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        verify(claude.enabled);
        claude.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(page.cfg_overviewProviderIDs, ["claude"].concat(absent).join(","));
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
        var disclosure = findChild(page, "hiddenItemsDisclosure");
        verify(!disclosure.expanded);
        verify(!buttons[0].visible);
        disclosure.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        verify(disclosure.expanded);
        verify(buttons[0].visible);
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
            return now.some(function(item) { return item.text === "None. Use a row's hide button in the popup."; });
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
    function test_emptyOrderLabelStaysAtTopOfWrappedError_data() {
        return [{tag: "ltr", rtl: false}, {tag: "rtl", rtl: true}];
    }

    function test_emptyOrderLabelStaysAtTopOfWrappedError(data) {
        mirroredPage = data.rtl;
        var page = createPage({width: 840});
        if (!page) return;
        var controller = waitForRosterSettled(page);
        controller.enabledProviderRoster = [];
        controller.providerRosterError = "The provider list could not be loaded. ".repeat(12);
        waitForRendering(page);
        var all = [];
        walkObjects(page, all);
        var labels = all.filter(function(item) {
            return item.text === "Provider order:" && item.verticalAlignment !== undefined;
        });
        compare(labels.length, 1);
        var label = labels[0];
        verify(label.height > label.implicitHeight * 2,
            "The empty roster message must wrap across multiple lines");
        compare(label.verticalAlignment, Text.AlignTop,
            "An empty roster label must stay at the top of its status message");
    }

    function test_explicitOverviewModePreservesAutomaticContract_data() {
        return [{tag: "ltr", rtl: false}, {tag: "rtl", rtl: true}];
    }

    function test_explicitOverviewModePreservesAutomaticContract(data) {
        mirroredPage = data.rtl;
        var page = createPage({cfg_overviewProviderIDs: "  "});
        if (!page) return;
        var controller = waitForRosterSettled(page);
        controller.providerRosterError = "";
        controller.enabledProviderRoster = [
            {provider: "codex", displayName: "Codex"},
            {provider: "claude", displayName: "Claude"},
            {provider: "gemini", displayName: "Gemini"},
            {provider: "cursor", displayName: "Cursor"}
        ];
        wait(0);
        var automatic = findChild(page, "overviewAutomaticRadio");
        var custom = findChild(page, "overviewCustomRadio");
        verify(automatic.checked && !custom.checked);
        verify(!providerCheck(page, "Codex").visible);
        verify(findChild(page, "overviewAutomaticHint").visible);
        verify(!providerCheck(page, "Codex").enabled);
        waitForRendering(custom);
        var customPosition = custom.mapToItem(page, 0, 0);
        custom.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(page.cfg_overviewProviderIDs, "codex,claude,gemini");
        verify(custom.checked && !automatic.checked);
        var codex = providerCheck(page, "Codex");
        verify(codex.visible);
        verify(findChild(page, "overviewAutomaticHint").visible);
        waitForRendering(custom);
        compare(custom.mapToItem(page, 0, 0), customPosition,
            "The manual choice must stay still when its checklist appears");
        var inset = custom.indicator.width + custom.spacing;
        var childPosition = codex.mapToItem(page, 0, 0);
        var leadingInset = data.rtl
            ? customPosition.x + custom.width - childPosition.x - codex.width
            : childPosition.x - customPosition.x;
        verify(Math.abs(leadingInset - inset) < 1,
            "Manual content must align with the radio text in " + data.tag);
        verify(!providerCheck(page, "Cursor").checked);
        verify(codex.enabled);
        codex.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(page.cfg_overviewProviderIDs, "claude,gemini");
        automatic.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(page.cfg_overviewProviderIDs, "");
        verify(!providerCheck(page, "Codex").visible);
        verify(!providerCheck(page, "Codex").enabled);
        verify(providerCheck(page, "Codex").checked);
        controller.enabledProviderRoster = [];
        custom.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(page.cfg_overviewProviderIDs, OverviewProviders.noneValue);
        verify(custom.checked);
    }

    function test_hiddenItemsDisclosureKeepsPendingRestores() {
        var page = createPage({cfg_popupHiddenUsageRows: JSON.stringify([
            {provider: "codex", row: "secondary"},
            {provider: "claude", row: "primary"}
        ])});
        if (!page) return;
        waitForRosterSettled(page);
        var disclosure = findChild(page, "hiddenItemsDisclosure");
        verify(!disclosure.expanded);
        compare(disclosure.plainText, "0 sections, 2 usage rows");
        var original = page.cfg_popupHiddenUsageRows;
        disclosure.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(page.cfg_popupHiddenUsageRows, original);
        var restore = findChild(page, "restoreHiddenUsageRowButton");
        restore.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        var pending = page.cfg_popupHiddenUsageRows;
        compare(JSON.parse(pending).length, 1);
        compare(disclosure.plainText, "0 sections, 1 usage row");
        verify(disclosure.visualFocus);
        keyClick(Qt.Key_Space);
        verify(!disclosure.expanded);
        verify(disclosure.activeFocus);
        compare(page.cfg_popupHiddenUsageRows, pending);
        keyClick(Qt.Key_Space);
        verify(disclosure.expanded);
        compare(page.cfg_popupHiddenUsageRows, pending);
        verify(findChild(page, "restoreHiddenUsageRowButton").visible);
    }

    function test_restoringLastHiddenSectionRevealsKeyboardFocus_data() {
        return [{tag: "keyboard-after-canceled-click", keyboard: true},
                {tag: "click-after-tab-focus", keyboard: false}];
    }

    function test_restoringLastHiddenSectionRevealsKeyboardFocus(data) {
        var page = createPage({height: 130, cfg_popupHiddenDetailSections: JSON.stringify([
            {provider: "codex", section: "v1:" + Qt.md5("Generic details")}
        ])});
        if (!page) return;
        waitForRosterSettled(page);
        var disclosure = findChild(page, "hiddenItemsDisclosure");
        disclosure.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        var restore = findChild(page, "restoreProviderDetailSectionsButton");
        waitForRendering(restore);
        var viewport = page.flickable;
        viewport.contentY = restore.mapToItem(viewport.contentItem, 0, 0).y;
        verify(disclosure.mapToItem(viewport, 0, disclosure.height).y < 0);
        if (!data.keyboard) {
            restore.forceActiveFocus(Qt.TabFocusReason);
            mouseClick(restore);
            compare(page.cfg_popupHiddenDetailSections, "");
            verify(!disclosure.activeFocus);
            return;
        }
        mousePress(restore);
        mouseMove(restore, -12, restore.height / 2);
        mouseRelease(restore, -12, restore.height / 2);
        compare(page.hiddenDetailSections.length, 1);
        verify(restore.activeFocus);
        keyClick(Qt.Key_Space);
        compare(page.cfg_popupHiddenDetailSections, "");
        verify(disclosure.visualFocus);
        verify(disclosure.expanded);
        tryVerify(function() {
            var top = disclosure.mapToItem(viewport, 0, 0).y;
            return top >= 0 && top + disclosure.height <= viewport.height;
        });
    }

}
