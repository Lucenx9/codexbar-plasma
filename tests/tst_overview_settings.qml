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

    function i18n(text, value) {
        return value === undefined ? text : text.replace("%1", value);
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

    function test_disabledSelectionsLeaveRoomForEnabledProviders() {
        var component = Qt.createComponent("../contents/ui/configPopup.qml");
        if (component.status === Component.Error && /module "org\.kde\.[^"]+" is not installed/.test(component.errorString())) {
            skip("Overview settings checks need the optional KDE QML modules");
            return;
        }
        compare(component.status, Component.Ready, component.errorString());
        failOnWarning(/.*/);
        var page = createTemporaryObject(component, testCase, {
            width: testCase.width,
            height: testCase.height,
            cfg_commandPath: "true",
            cfg_overviewProviderIDs: "claude,gemini,copilot"
        });
        verify(page !== null);
        var controller = findChild(page, "providerRosterController");
        verify(controller !== null);
        tryVerify(function () {
            return controller.commandRunSerial > 0 && !controller.providerRosterLoading && !controller.hasPendingProviderRosterCommands();
        });
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
}
