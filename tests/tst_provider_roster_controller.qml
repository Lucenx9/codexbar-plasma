import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "ProviderRosterController"

    function i18n(text, value) {
        return value === undefined ? text : text.replace("%1", value);
    }

    function createController(properties) {
        var component = Qt.createComponent("../contents/ui/controllers/ProviderRosterController.qml");
        if (component.status === Component.Error && /module "org\.kde\.[^"]+" is not installed/.test(component.errorString())) {
            skip("Provider roster lifecycle checks need the optional KDE QML modules");
            return null;
        }
        compare(component.status, Component.Ready, component.errorString());
        var controller = createTemporaryObject(component, testCase, Object.assign({active: false, commandPath: "/usr/bin/true"}, properties || {}));
        verify(controller !== null);
        return controller;
    }

    function findSweepTimer(controller) {
        var groups = [controller.children, controller.resources, controller.data];
        for (var g = 0; g < groups.length; g++) {
            var kids = groups[g];
            if (kids === undefined || kids === null)
                continue;
            for (var i = 0; i < kids.length; i++) {
                if (kids[i].triggeredOnStart !== undefined)
                    return kids[i];
            }
        }
        return null;
    }

    function qprocessFilter() {
        return /^(?!QProcess: Destroyed while process \("\/bin\/sh"\) is still running\.$).*/;
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

    // Creating the controller already active queues exactly one roster
    // load: the completion hook and the injected command path coalesce.
    function test_creationWithActiveQueuesSingleLoad() {
        failOnWarning(qprocessFilter());
        var controller = createController({active: true});
        if (!controller) return;
        tryVerify(function() { return controller.commandRunSerial === 1; }, 10000);
        wait(50);
        compare(controller.commandRunSerial, 1);
    }

    // Creating the controller already active without a command path
    // reports the missing path: only the completion hook can queue that
    // first load, since no path change ever fires.
    function test_activeCreationWithoutPathSurfacesConfigurationError() {
        failOnWarning(qprocessFilter());
        var controller = createController({active: true, commandPath: ""});
        if (!controller) return;
        tryVerify(function() { return controller.providerRosterError === "Set the codexbar command path in Diagnostics."; }, 10000);
        compare(controller.commandRunSerial, 0);
        verify(!controller.providerRosterLoading);
    }

    // A command-path change on an active controller queues a reload.
    function test_commandPathChangeQueuesReload() {
        failOnWarning(qprocessFilter());
        var controller = createController();
        if (!controller) return;
        controller.active = true;
        tryVerify(function() { return controller.commandRunSerial === 1; }, 10000);
        controller.commandPath = "/usr/bin/false";
        tryVerify(function() { return controller.commandRunSerial === 2; }, 10000);
    }

    // An overdue roster command releases loading with the timeout error,
    // and its late reply is dropped instead of replacing the outcome.
    function test_expiredCommandsSurfaceTimeoutAndDropLateReplies() {
        failOnWarning(qprocessFilter());
        var controller = createController();
        if (!controller) return;
        controller.active = true;
        controller.loadProviderRoster();
        var staleSource = Object.keys(controller.providerRosterCommands)[0];
        verify(staleSource !== undefined);
        controller.expireProviderRosterCommands(Date.now() + 120000);
        verify(!controller.providerRosterLoading);
        compare(controller.providerRosterError, "Loading providers timed out. Try again.");
        compare(controller.enabledProviderRoster.length, 0);
        verify(!controller.hasPendingProviderRosterCommands());
        controller.handleProviderRosterData(staleSource, '{"provider":"codex","enabled":true}', "");
        compare(controller.enabledProviderRoster.length, 0);
        compare(controller.providerRosterError, "Loading providers timed out. Try again.");
        verify(!controller.providerRosterLoading);
    }

    // A newer refresh retires the previous run: the stale reply is
    // dropped while the current run stays pending, then settles it.
    function test_newerRefreshRetiresStaleReply() {
        failOnWarning(qprocessFilter());
        var controller = createController();
        if (!controller) return;
        controller.active = true;
        controller.loadProviderRoster();
        var staleSource = Object.keys(controller.providerRosterCommands)[0];
        controller.loadProviderRoster();
        var currentSource = Object.keys(controller.providerRosterCommands)[0];
        verify(staleSource !== undefined);
        verify(currentSource !== undefined);
        verify(currentSource !== staleSource);
        controller.handleProviderRosterData(staleSource, '{"provider":"stale","enabled":true}', "");
        verify(controller.providerRosterLoading);
        verify(controller.hasPendingProviderRosterCommands());
        compare(controller.providerRosterError, "");
        controller.handleProviderRosterData(currentSource, '{"provider":"codex","enabled":true}', "");
        compare(controller.enabledProviderRoster[0].provider, "codex");
        verify(!controller.providerRosterLoading);
    }

    // The load reaches the executable DataSource and its answer settles
    // the controller: empty CLI output releases loading with the
    // empty-roster error.
    function test_connectedLoadSettlesThroughDataSource() {
        failOnWarning(qprocessFilter());
        var controller = createController();
        if (!controller) return;
        controller.active = true;
        tryVerify(function() {
            return controller.commandRunSerial > 0 && !controller.providerRosterLoading && !controller.hasPendingProviderRosterCommands();
        }, 10000);
        compare(controller.providerRosterError, "codexbar did not return provider data.");
        compare(controller.enabledProviderRoster.length, 0);
    }

    // The expiry sweep runs while a roster command is pending and stops
    // once its reply settles the controller.
    function test_timeoutSweepTracksPendingCommands() {
        // Offscreen has no animation driver, so stopping the sweep timer
        // without an event-loop turn warns; that platform noise is not
        // the behavior under test.
        failOnWarning(/^(?!QProcess: Destroyed while process \("\/bin\/sh"\) is still running\.$|QUnifiedTimer::stopAnimationDriver: driver is not running$).*/);
        var controller = createController();
        if (!controller) return;
        controller.active = true;
        controller.loadProviderRoster();
        var timer = findSweepTimer(controller);
        verify(timer !== null);
        verify(timer.running);
        var source = Object.keys(controller.providerRosterCommands)[0];
        controller.handleProviderRosterData(source, '{"provider":"codex","enabled":true}', "");
        verify(!timer.running);
    }
}
