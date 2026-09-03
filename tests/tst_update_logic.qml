import QtQuick
import QtTest
import "../contents/ui/UpdateLogic.js" as UpdateLogic

TestCase {
    name: "UpdateLogic"

    readonly property double nowMs: Date.UTC(2026, 6, 31, 12, 0, 0)

    function test_lastCheckTimestampIsParsedOnceAtTheBoundary() {
        var timestamp = "2026-07-31T11:00:00.000Z"

        compare(UpdateLogic.lastCheckMs("  " + timestamp + "  "), Date.parse(timestamp))
        verify(isNaN(UpdateLogic.lastCheckMs("not-a-date")))
        verify(isNaN(UpdateLogic.lastCheckMs("x".repeat(65))))
        verify(isNaN(UpdateLogic.lastCheckMs({ value: timestamp })))
    }

    function test_disabledChecksStayDisabledWhenForced() {
        compare(UpdateLogic.updateCheckDue(false, "", 12, nowMs, true), false)
    }

    function test_missingTimestampIsDue() {
        compare(UpdateLogic.updateCheckDue(true, "", 12, nowMs, false), true)
    }

    function test_recentTimestampIsNotDue() {
        var recent = new Date(nowMs - 60 * 60 * 1000).toISOString()
        compare(UpdateLogic.updateCheckDue(true, recent, 12, nowMs, false), false)
    }

    function test_forcedCheckIgnoresRecentTimestamp() {
        var recent = new Date(nowMs - 60 * 60 * 1000).toISOString()
        compare(UpdateLogic.updateCheckDue(true, recent, 12, nowMs, true), true)
    }

    function test_staleTimestampIsDue() {
        var stale = new Date(nowMs - 13 * 60 * 60 * 1000).toISOString()
        compare(UpdateLogic.updateCheckDue(true, stale, 12, nowMs, false), true)
    }

    function test_nextDelayUsesRemainingInterval() {
        var recent = new Date(nowMs - 11 * 60 * 60 * 1000).toISOString()
        compare(UpdateLogic.nextUpdateCheckDelay(true, recent, 12, nowMs, 60000), 60 * 60 * 1000)
    }

    function test_nextDelayRunsSoonWhenAlreadyDueOrMissing() {
        var stale = new Date(nowMs - 13 * 60 * 60 * 1000).toISOString()
        compare(UpdateLogic.nextUpdateCheckDelay(true, stale, 12, nowMs, 60000), 60000)
        compare(UpdateLogic.nextUpdateCheckDelay(true, "", 12, nowMs, 60000), 60000)
    }

    function test_clockRollbackMakesTheCheckDueAndSchedulesItSoon() {
        var future = new Date(nowMs + 24 * 60 * 60 * 1000).toISOString()
        compare(UpdateLogic.updateCheckDue(true, future, 12, nowMs, false), true)
        compare(UpdateLogic.nextUpdateCheckDelay(true, future, 12, nowMs, 60000), 60000)
    }

    function test_nextDelayIsZeroWhenChecksAreDisabled() {
        compare(UpdateLogic.nextUpdateCheckDelay(false, "", 12, nowMs, 60000), 0)
    }

    function test_firstFailureUsesTheBaseRetryDelay() {
        compare(UpdateLogic.updateRetryDelay(1, 300000, 21600000), 300000)
    }

    function test_retryDelayDoublesAfterEachFailure() {
        compare(UpdateLogic.updateRetryDelay(2, 300000, 21600000), 600000)
        compare(UpdateLogic.updateRetryDelay(3, 300000, 21600000), 1200000)
    }

    function test_retryDelayStopsAtTheMaximum() {
        compare(UpdateLogic.updateRetryDelay(20, 300000, 21600000), 21600000)
    }

    function test_automaticInstallRequestedDuringManualCheckRunsAfterCompletion() {
        var manualRequest = UpdateLogic.updateRequestDecision(
            false, false, false, false)

        compare(manualRequest.startNow, true)
        compare(manualRequest.installMode, false)

        var automaticRequest = UpdateLogic.updateRequestDecision(
            true, manualRequest.installMode, false, true)

        compare(automaticRequest.startNow, false)
        compare(automaticRequest.pendingAutomaticCheck, true)

        var manualResult = UpdateLogic.resultIntent({ status: "available" },
            manualRequest.installMode)

        compare(manualResult.notificationKind, "available")

        var completion = UpdateLogic.updateCompletionDecision(
            automaticRequest.pendingAutomaticCheck, true, true)

        compare(completion.startAutomaticCheck, true)
        compare(completion.pendingAutomaticCheck, false)
    }

    function test_activeAutomaticInstallDoesNotQueueDuplicateCheck() {
        var request = UpdateLogic.updateRequestDecision(true, true, false, true)

        compare(request.startNow, false)
        compare(request.pendingAutomaticCheck, false)
    }

    function test_disablingAutomaticUpdatesCancelsPendingCheck() {
        var completion = UpdateLogic.updateCompletionDecision(true, true, false)

        compare(completion.startAutomaticCheck, false)
        compare(completion.pendingAutomaticCheck, false)
    }

    function test_availableResultRequestsNotificationWithoutAutomaticInstall() {
        var intent = UpdateLogic.resultIntent({
            status: "available",
            remoteVersion: "v0.2.24",
            assetUrl: "https://github.com/Lucenx9/codexbar-plasma/releases/download/v0.2.24/codexbar-plasma.plasmoid"
        }, false)

        compare(intent.kind, "available")
        compare(intent.successful, true)
        compare(intent.version, "v0.2.24")
        compare(intent.notificationKind, "available")
    }

    function test_availableResultStaysQuietDuringAutomaticInstall() {
        var intent = UpdateLogic.resultIntent({ status: "available" }, true)

        compare(intent.notificationKind, "")
    }

    function test_installedResultRequestsInstalledNotification() {
        var intent = UpdateLogic.resultIntent({
            status: "installed",
            remoteVersion: "v0.2.24"
        }, true)

        compare(intent.kind, "installed")
        compare(intent.successful, true)
        compare(intent.version, "v0.2.24")
        compare(intent.notificationKind, "installed")
    }

    function test_terminalQuietResultsAreSuccessful() {
        var currentIntent = UpdateLogic.resultIntent({ status: "current" }, false)
        var skippedIntent = UpdateLogic.resultIntent({ status: "skipped" }, false)

        compare(currentIntent.kind, "current")
        compare(currentIntent.successful, true)
        compare(currentIntent.notificationKind, "")
        compare(skippedIntent.kind, "skipped")
        compare(skippedIntent.successful, true)
        compare(skippedIntent.notificationKind, "")
    }

    function test_errorResultKeepsOnlySemanticErrorFields() {
        var intent = UpdateLogic.resultIntent({
            status: "error",
            errorCode: "missing_tool",
            errorDetail: "jq",
            message: "raw updater message"
        }, false)

        compare(intent.kind, "error")
        compare(intent.successful, false)
        compare(intent.errorCode, "missing_tool")
        compare(intent.errorDetail, "jq")
        verify(!intent.hasOwnProperty("message"))
    }

    function test_unknownResultCarriesTheStrictStatusForLocalization() {
        var intent = UpdateLogic.resultIntent({ status: "future-status" }, false)

        compare(intent.kind, "unknown")
        compare(intent.successful, false)
        compare(intent.status, "future-status")
    }

    function test_resultIntentRejectsOversizedRetainedFields() {
        var oversized = new Array(4097).join("x")
        var availableIntent = UpdateLogic.resultIntent({
            status: "available",
            remoteVersion: oversized,
            assetUrl: oversized
        }, false)
        var errorIntent = UpdateLogic.resultIntent({
            status: "error",
            errorCode: oversized,
            errorDetail: oversized
        }, false)
        var unknownIntent = UpdateLogic.resultIntent({ status: oversized }, false)

        compare(availableIntent.version, "")
        compare(availableIntent.assetUrl, "")
        compare(errorIntent.errorCode, "")
        compare(errorIntent.errorDetail, "")
        compare(unknownIntent.status, "")
    }

    function test_resultIntentIgnoresInheritedPayloadFields() {
        var intent = UpdateLogic.resultIntent(Object.create({
            status: "installed",
            remoteVersion: "v9.9.9"
        }), false)

        compare(intent.kind, "unknown")
        compare(intent.status, "")
        compare(intent.version, "")
        compare(intent.notificationKind, "")
    }

    function test_resultIntentDoesNotCoerceStructuredOrBlankFields() {
        var structuredIntent = UpdateLogic.resultIntent({
            status: "available",
            remoteVersion: { value: "v9.9.9" },
            assetUrl: ["https://example.com/widget"]
        }, false)
        var blankIntent = UpdateLogic.resultIntent({
            status: "available",
            remoteVersion: "   "
        }, false)

        compare(structuredIntent.version, "")
        compare(structuredIntent.assetUrl, "")
        compare(blankIntent.version, "")
    }

    function test_resultIntentKeepsOnlyHttpsAssetUrls() {
        var httpsIntent = UpdateLogic.resultIntent({
            status: "available",
            assetUrl: "  HTTPS://example.com/widget  "
        }, false)

        compare(httpsIntent.assetUrl, "HTTPS://example.com/widget")
        compare(UpdateLogic.resultIntent({
            status: "available",
            assetUrl: "http://example.com/widget"
        }, false).assetUrl, "")
        compare(UpdateLogic.resultIntent({
            status: "available",
            assetUrl: "javascript:alert(1)"
        }, false).assetUrl, "")
        compare(UpdateLogic.resultIntent({
            status: "available",
            assetUrl: "file:///tmp/widget"
        }, false).assetUrl, "")
    }
}
