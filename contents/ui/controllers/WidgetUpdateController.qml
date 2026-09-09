import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../UpdateLogic.js" as UpdateLogic
import "../CommandLedger.js" as CommandLedger
import "../Guards.js" as Guards
import "../ProviderNormalizer.js" as Normalizer
import "../SafeText.js" as SafeText

Item {
    id: controller

    property bool updateChecksEnabled: false
    property bool autoUpdateEnabled: false
    property int autoUpdateIntervalHours: 24
    property string autoUpdateLastCheck: ""
    property url scriptUrl: Qt.resolvedUrl("../../../scripts/update-widget.sh")

    readonly property bool busy: lifecycle.connectedUpdateCommandSource.length > 0
    readonly property string statusText: lifecycle.updateStatusText
    readonly property string errorText: lifecycle.updateErrorText

    signal statusRecorded(string statusText, string errorText)
    signal checkSucceeded(string timestamp)
    signal updateAvailable(string version, string assetUrl)
    signal updateInstalled(string version)

    function checkNow() {
        if (lifecycle.initialized) {
            lifecycle.checkForWidgetUpdate(true);
        }
    }

    onUpdateChecksEnabledChanged: {
        if (!lifecycle.initialized) {
            return;
        }
        if (updateChecksEnabled) {
            Qt.callLater(function () {
                lifecycle.checkForWidgetUpdate(true);
            });
        } else {
            lifecycle.updateRetryPending = false;
            lifecycle.pendingAutomaticUpdateCheck = false;
            updateCheckTimer.stop();
        }
    }
    onAutoUpdateIntervalHoursChanged: {
        if (lifecycle.initialized) {
            lifecycle.scheduleNextUpdateCheck();
        }
    }
    onAutoUpdateEnabledChanged: {
        if (!lifecycle.initialized) {
            return;
        }
        if (updateChecksEnabled && autoUpdateEnabled) {
            Qt.callLater(function () {
                lifecycle.checkForWidgetUpdate(true);
            });
        } else {
            lifecycle.pendingAutomaticUpdateCheck = false;
        }
    }
    Component.onCompleted: {
        lifecycle.initialized = true;
        if (updateChecksEnabled) {
            lifecycle.scheduleNextUpdateCheck();
            Qt.callLater(function () {
                lifecycle.checkForWidgetUpdate(true);
            });
        }
    }

    Item {
        id: lifecycle

        property bool initialized: false
        property int commandRunSerial: 0

        property string connectedUpdateCommandSource: ""
        property bool connectedUpdateInstallMode: false
        property bool pendingAutomaticUpdateCheck: false
        readonly property int widgetUpdateCheckTimeoutMs: 60000
        readonly property int widgetAutoUpdateTimeoutMs: 600000
        readonly property int widgetUpdateMinimumTimerDelayMs: 60000
        readonly property int widgetUpdateRetryBaseDelayMs: 300000
        readonly property int widgetUpdateRetryMaximumDelayMs: 21600000
        property int consecutiveUpdateFailures: 0
        property bool updateRetryPending: false
        property string updateStatusText: ""
        property string updateErrorText: ""

        function shellQuote(value) {
            return Guards.shellQuote(value);
        }

        function boundedWidgetUpdateText(value) {
            return Normalizer.boundedDisplayText(value, 500);
        }

        function boundedCliMessage(value) {
            return SafeText.cliMessage(SafeText.stripLoaderDiagnostics(value), SafeText.maximumCliMessageLength);
        }

        function updateScriptPath() {
            var url = controller.scriptUrl.toString();
            if (url.indexOf("file://") === 0) {
                return decodeURIComponent(url.substring(7));
            }
            return decodeURIComponent(url);
        }

        function buildUpdateCommand(installMode) {
            var scriptPath = updateScriptPath();
            var mode = installMode ? " --install" : " --check";
            var updateCommand = "if [ -x " + shellQuote(scriptPath) + " ]; then " + shellQuote(scriptPath) + mode + "; else printf '%s\\n' " + shellQuote(missingUpdateScriptJson()) + "; fi";
            return "sh -c " + shellQuote(updateCommand);
        }

        function missingUpdateScriptJson() {
            return JSON.stringify({
                status: "error",
                errorCode: "missing_updater",
                message: i18n("Widget updater script is missing from the installed package.")
            });
        }

        function widgetUpdateErrorText(errorCode, errorDetail) {
            var detail = boundedCliMessage(errorDetail);
            switch (String(errorCode || "")) {
            case "missing_updater":
                return i18n("Widget updater script is missing from the installed package.");
            case "missing_tool":
                return detail.length > 0 ? i18n("Widget updater is missing the required tool: %1", detail) : i18n("Widget updater is missing a required tool.");
            case "local_metadata_invalid":
                return i18n("The installed widget metadata is invalid.");
            case "release_fetch_failed":
                return i18n("Could not fetch widget release metadata from GitHub.");
            case "release_metadata_invalid":
                return i18n("Widget release metadata is invalid.");
            case "release_not_immutable":
                return i18n("The available widget release is not immutable.");
            case "release_download_failed":
                return i18n("Could not download the widget release.");
            case "release_integrity_failed":
                return i18n("Widget release integrity verification failed.");
            case "package_invalid":
                return i18n("The widget package does not match the release.");
            case "package_install_failed":
                return i18n("The widget package could not be installed.");
            case "invalid_invocation":
                return i18n("The widget updater command is invalid.");
            default:
                return i18n("Widget update check failed.");
            }
        }

        function updateCheckDue(forceCheck) {
            return UpdateLogic.updateCheckDue(controller.updateChecksEnabled, controller.autoUpdateLastCheck, controller.autoUpdateIntervalHours, Date.now(), forceCheck === true);
        }

        function checkForWidgetUpdate(forceCheck) {
            var requestDecision = UpdateLogic.updateRequestDecision(connectedUpdateCommandSource.length > 0, connectedUpdateInstallMode, pendingAutomaticUpdateCheck, controller.autoUpdateEnabled);
            pendingAutomaticUpdateCheck = requestDecision.pendingAutomaticCheck;
            if (!requestDecision.startNow) {
                return;
            }
            if (!updateCheckDue(forceCheck)) {
                scheduleNextUpdateCheck();
                return;
            }
            var installMode = requestDecision.installMode;
            updateCheckTimer.stop();
            setWidgetUpdateState(i18n("Checking for widget updates..."), "", false);
            connectedUpdateInstallMode = installMode;
            commandRunSerial += 1;
            connectedUpdateCommandSource = CommandLedger.withRunNonce(buildUpdateCommand(installMode), commandRunSerial);
            updateSource.connectSource(connectedUpdateCommandSource);
            updateCommandTimeoutTimer.interval = installMode ? widgetAutoUpdateTimeoutMs : widgetUpdateCheckTimeoutMs;
            updateCommandTimeoutTimer.restart();
        }

        function scheduleNextUpdateCheck(lastCheckOverride) {
            updateCheckTimer.stop();
            updateRetryPending = false;
            if (!controller.updateChecksEnabled || connectedUpdateCommandSource.length > 0) {
                return;
            }
            var lastCheck = lastCheckOverride === undefined ? controller.autoUpdateLastCheck : lastCheckOverride;
            updateCheckTimer.interval = UpdateLogic.nextUpdateCheckDelay(controller.updateChecksEnabled, lastCheck, controller.autoUpdateIntervalHours, Date.now(), widgetUpdateMinimumTimerDelayMs);
            updateCheckTimer.restart();
        }

        function scheduleUpdateRetry() {
            updateCheckTimer.stop();
            updateRetryPending = false;
            if (!controller.updateChecksEnabled || connectedUpdateCommandSource.length > 0) {
                return;
            }
            updateCheckTimer.interval = UpdateLogic.updateRetryDelay(consecutiveUpdateFailures, widgetUpdateRetryBaseDelayMs, widgetUpdateRetryMaximumDelayMs);
            updateRetryPending = true;
            updateCheckTimer.restart();
        }

        function handleUpdateCheckTimer() {
            var forceCheck = updateRetryPending;
            updateRetryPending = false;
            checkForWidgetUpdate(forceCheck);
        }

        function finishUpdateCommand(sourceName, successfulCheck) {
            updateCommandTimeoutTimer.stop();
            updateSource.disconnectSource(sourceName);
            connectedUpdateCommandSource = "";
            connectedUpdateInstallMode = false;
            var completionDecision = UpdateLogic.updateCompletionDecision(pendingAutomaticUpdateCheck, controller.updateChecksEnabled, controller.autoUpdateEnabled);
            pendingAutomaticUpdateCheck = completionDecision.pendingAutomaticCheck;
            var completedAt = "";
            if (successfulCheck === true) {
                consecutiveUpdateFailures = 0;
                completedAt = new Date().toISOString();
                controller.checkSucceeded(completedAt);
            } else {
                consecutiveUpdateFailures = Math.min(31, consecutiveUpdateFailures + 1);
            }
            if (completionDecision.startAutomaticCheck) {
                Qt.callLater(function () {
                    lifecycle.checkForWidgetUpdate(true);
                });
                return;
            }
            if (successfulCheck !== true) {
                scheduleUpdateRetry();
                return;
            }
            scheduleNextUpdateCheck(completedAt);
        }

        function handleUpdateCommandTimeout() {
            if (connectedUpdateCommandSource.length === 0) {
                return;
            }
            var sourceName = connectedUpdateCommandSource;
            finishUpdateCommand(sourceName, false);
            setWidgetUpdateState(i18n("Widget update failed."), i18n("Widget update operation timed out."));
        }

        function setWidgetUpdateState(statusText, errorText, persistState) {
            updateStatusText = boundedWidgetUpdateText(statusText);
            updateErrorText = boundedWidgetUpdateText(errorText);
            if (persistState === false) {
                return;
            }
            controller.statusRecorded(updateStatusText, updateErrorText);
        }

        function handleUpdateData(sourceName, stdoutText, stderrText) {
            if (sourceName !== connectedUpdateCommandSource) {
                return;
            }
            var installMode = connectedUpdateInstallMode;

            var trimmed = stdoutText.trim();
            if (trimmed.length === 0) {
                finishUpdateCommand(sourceName, false);
                setWidgetUpdateState(i18n("Widget update check failed."), stderrText.trim().length > 0 ? boundedCliMessage(stderrText) : i18n("Widget update check returned no data."));
                return;
            }

            var payload;
            try {
                payload = JSON.parse(trimmed);
            } catch (error) {
                finishUpdateCommand(sourceName, false);
                setWidgetUpdateState(i18n("Widget update check failed."), i18n("Could not parse widget update JSON: %1", error.message));
                return;
            }

            var resultIntent = UpdateLogic.resultIntent(payload, installMode);
            applyUpdateResultIntent(resultIntent);
            finishUpdateCommand(sourceName, resultIntent.successful);
        }

        function applyUpdateResultIntent(intent) {
            switch (intent.kind) {
            case "error":
                setWidgetUpdateState(i18n("Widget update check failed."), widgetUpdateErrorText(intent.errorCode, intent.errorDetail));
                return;
            case "available":
                var availableStatus = intent.version.length > 0 ? i18n("Widget update %1 is available.", intent.version) : i18n("A widget update is available.");
                setWidgetUpdateState(availableStatus, "");
                if (intent.notificationKind === "available") {
                    controller.updateAvailable(intent.version, intent.assetUrl);
                }
                return;
            case "installed":
                var restartText = i18n("Restart Plasma to apply the new widget version.");
                setWidgetUpdateState(intent.version.length > 0 ? i18n("Widget update %1 installed. %2", intent.version, restartText) : i18n("Widget update installed. %1", restartText), "");
                if (intent.notificationKind === "installed") {
                    controller.updateInstalled(intent.version);
                }
                return;
            case "current":
                setWidgetUpdateState(i18n("Widget is up to date."), "");
                return;
            case "skipped":
                setWidgetUpdateState(i18n("Widget update skipped."), "");
                return;
            }

            setWidgetUpdateState(i18n("Widget update check failed."), i18n("Unknown widget update status: %1", intent.status));
        }

        Timer {
            id: updateCheckTimer

            repeat: false
            running: false
            triggeredOnStart: false
            onTriggered: lifecycle.handleUpdateCheckTimer()
        }

        Timer {
            id: updateCommandTimeoutTimer

            repeat: false
            onTriggered: lifecycle.handleUpdateCommandTimeout()
        }

        Plasma5Support.DataSource {
            id: updateSource

            engine: "executable"

            onNewData: function (sourceName, data) {
                var rawStdoutText = data && data["stdout"] ? data["stdout"] : "";
                var stdoutText = SafeText.cliJsonText(rawStdoutText);
                var stderrText = data && data["stderr"] ? data["stderr"] : "";
                if (stdoutText === null) {
                    stdoutText = "";
                    stderrText = i18n("Widget updater response exceeded the supported size.");
                }
                lifecycle.handleUpdateData(sourceName, stdoutText, stderrText);
            }
        }
    }
}
