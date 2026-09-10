import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "ProviderRosterController"

    function i18n(text, value) {
        return value === undefined ? text : text.replace("%1", value);
    }

    function createController() {
        var component = Qt.createComponent("../contents/ui/controllers/ProviderRosterController.qml");
        if (component.status === Component.Error && /module "org\.kde\.[^"]+" is not installed/.test(component.errorString())) {
            skip("Provider roster lifecycle checks need the optional KDE QML modules");
            return null;
        }
        compare(component.status, Component.Ready, component.errorString());
        var controller = createTemporaryObject(component, testCase, {active: false, commandPath: "/usr/bin/true"});
        verify(controller !== null);
        return controller;
    }

    function test_deactivationCancelsQueuedLoad() {
        failOnWarning(/.*/);
        var controller = createController();
        if (!controller) return;
        controller.active = true;
        controller.active = false;
        wait(1);
        compare(controller.commandRunSerial, 0);
        verify(!controller.hasPendingProviderRosterCommands());
        verify(!controller.providerRosterLoading);
        compare(controller.providerRosterError, "");
    }

    function test_deactivationRetiresRepliesAndLoadingState() {
        // Plasma can destroy the shell while this test intentionally cancels it.
        // Keep every other warning fatal, including in the queued-load test.
        failOnWarning(/^(?!QProcess: Destroyed while process \("\/bin\/sh"\) is still running\.$).*/);
        var controller = createController();
        if (!controller) return;
        controller.active = true;
        controller.loadProviderRoster();
        var retiredSource = Object.keys(controller.providerRosterCommands)[0];
        verify(retiredSource !== undefined);
        verify(controller.providerRosterLoading);
        controller.providerRosterError = "Previous failure";
        controller.active = false;
        verify(!controller.hasPendingProviderRosterCommands());
        verify(!controller.providerRosterLoading);
        compare(controller.providerRosterError, "");
        controller.handleProviderRosterData(retiredSource, '{"provider":"retired","enabled":true}', "");
        compare(controller.enabledProviderRoster.length, 0);

        controller.active = true;
        controller.loadProviderRoster();
        var currentSource = Object.keys(controller.providerRosterCommands)[0];
        verify(currentSource !== retiredSource);
        controller.handleProviderRosterData(retiredSource, "", "Old failure");
        verify(controller.providerRosterLoading);
        verify(controller.hasPendingProviderRosterCommands());
        compare(controller.providerRosterError, "");
        controller.handleProviderRosterData(currentSource, '{"provider":"codex","enabled":true}', "");
        compare(controller.enabledProviderRoster[0].provider, "codex");
        verify(!controller.providerRosterLoading);
        controller.active = false;
        wait(1);
        compare(controller.commandRunSerial, 2);
        compare(controller.enabledProviderRoster[0].provider, "codex");
        compare(controller.providerRosterError, "");
    }
}
