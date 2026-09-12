import QtQuick
import QtTest

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
}
