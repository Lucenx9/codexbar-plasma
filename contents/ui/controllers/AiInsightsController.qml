import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../AiInsights.js" as AiInsights
import "../CommandLedger.js" as CommandLedger

// Owns the optional AI Insights generation process: one request at a time,
// a per-request nonce and deadline, stale-reply retirement, and interval
// scheduling. It never runs anything while disabled, and it never reads or
// writes configuration: main.qml persists the signals it emits.
Item {
    id: controller

    property bool insightsEnabled: false
    property string provider: "ollama"
    property string model: ""
    property string endpoint: ""
    property bool zdr: true
    property string language: "en"
    property int intervalHours: 0
    property string snapshotText: ""
    property string snapshotId: ""
    property string cacheText: ""
    property string lastAttempt: ""
    property url scriptUrl: Qt.resolvedUrl("../../../scripts/ai-insights.py")

    readonly property var requestContext: AiInsights.context({provider: provider, model: model,
        language: language, endpoint: endpoint, zdr: zdr})
    readonly property string contextKey: AiInsights.contextKey(requestContext)
    readonly property bool configured: requestContext.configured
    readonly property bool busy: lifecycle.activeSource.length > 0
    readonly property string errorReason: lifecycle.errorReason
    readonly property double retryAtMs: lifecycle.retryAtMs

    signal attemptStarted(string timestamp)
    signal generated(string cacheText)

    // Manual generation is explicit and still one request at a time. It waits
    // only for a provider's Retry-After: a fixed key or a started Ollama must
    // not stay blocked for the automatic retry delay.
    function generate() {
        return lifecycle.start(true)
    }

    onInsightsEnabledChanged: {
        if (!insightsEnabled) {
            lifecycle.retire()
            lifecycle.clearFailure()
        } else {
            Qt.callLater(lifecycle.checkIfDue)
        }
    }
    // A late reply must never land on a different language, provider, model,
    // or endpoint, so a context change retires the request in flight.
    onContextKeyChanged: {
        lifecycle.retire()
        lifecycle.clearFailure()
        Qt.callLater(lifecycle.checkIfDue)
    }
    onSnapshotIdChanged: Qt.callLater(lifecycle.checkIfDue)
    onIntervalHoursChanged: Qt.callLater(lifecycle.checkIfDue)
    Component.onCompleted: Qt.callLater(lifecycle.checkIfDue)
    Component.onDestruction: lifecycle.retire()

    Item {
        id: lifecycle

        property string activeSource: ""
        property string activeContextKey: ""
        property string activeSnapshotId: ""
        property int serial: 0
        property string errorReason: ""
        property double retryAtMs: 0
        property double rateLimitedUntilMs: 0

        function clearFailure() {
            errorReason = ""
            retryAtMs = 0
            rateLimitedUntilMs = 0
        }

        function retire() {
            var source = activeSource
            activeSource = ""
            deadline.stop()
            if (source.length > 0) {
                processSource.disconnectSource(source)
            }
        }

        function checkIfDue() {
            var cache = AiInsights.parseCache(controller.cacheText)
            var due = AiInsights.automaticDue({
                enabled: controller.insightsEnabled,
                configured: controller.configured,
                intervalHours: controller.intervalHours,
                busy: controller.busy,
                sufficient: controller.snapshotText.length > 0,
                nowMs: Date.now(),
                retryAtMs: retryAtMs,
                lastAttemptMs: Date.parse(controller.lastAttempt),
                lastSuccessMs: cache ? cache.generatedAtMs : NaN,
                cacheMatchesContext: cache !== null && cache.contextKey === controller.contextKey,
                snapshotId: controller.snapshotId,
                cachedSnapshotId: cache ? cache.snapshotId : ""
            })
            if (due) {
                start(false)
            }
        }

        function start(manual) {
            if (!controller.insightsEnabled || controller.busy || !controller.configured
                    || controller.snapshotText.length === 0
                    || Date.now() < (manual ? rateLimitedUntilMs : retryAtMs)) {
                return false
            }
            var command = AiInsights.command(controller.scriptUrl, "generate", {
                provider: controller.requestContext.provider,
                model: controller.requestContext.model,
                endpoint: controller.requestContext.endpoint,
                zdr: controller.requestContext.zdr,
                language: controller.requestContext.language,
                snapshot: controller.snapshotText
            })
            if (command.length === 0) {
                return false
            }
            errorReason = ""
            serial += 1
            activeContextKey = controller.contextKey
            activeSnapshotId = controller.snapshotId
            activeSource = CommandLedger.withRunNonce(command, serial)
            // Persisted before the request, so a restart cannot repeat it at once.
            controller.attemptStarted(new Date().toISOString())
            deadline.restart()
            processSource.connectSource(activeSource)
            return true
        }

        function fail(reason, retryAfterSeconds) {
            errorReason = reason
            retryAtMs = Date.now() + AiInsights.retryDelayMs(reason, retryAfterSeconds, controller.intervalHours)
            rateLimitedUntilMs = reason === "rate_limited" ? retryAtMs : 0
        }

        function accept(sourceName, data) {
            if (sourceName !== activeSource) {
                return
            }
            var context = activeContextKey
            var snapshot = activeSnapshotId
            retire()
            if (context !== controller.contextKey || !controller.insightsEnabled) {
                return
            }
            var reply = AiInsights.generationReply(data ? data["stdout"] : "")
            if (reply.outcome !== "ok") {
                fail(reply.reason, reply.retryAfterSeconds)
                return
            }
            clearFailure()
            controller.generated(AiInsights.cacheText({
                summary: reply.summary,
                highlights: reply.highlights,
                generatedAtMs: Date.now(),
                contextKey: context,
                provider: controller.requestContext.provider,
                model: controller.requestContext.model,
                language: controller.requestContext.language,
                snapshotId: snapshot
            }))
        }
    }

    Plasma5Support.DataSource {
        id: processSource

        engine: "executable"
        interval: 0
        onNewData: function(sourceName, data) {
            lifecycle.accept(sourceName, data)
        }
    }

    Timer {
        id: deadline

        objectName: "aiInsightsDeadline"
        interval: 95000
        onTriggered: {
            lifecycle.retire()
            lifecycle.fail("timeout", 0)
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: controller.insightsEnabled && controller.intervalHours > 0
        onTriggered: lifecycle.checkIfDue()
    }
}
