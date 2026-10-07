import QtQuick
import "../UpdateNotificationState.js" as UpdateNotificationState

Item {
    id: controller

    required property var configuration
    property bool enableNotifications: true
    property bool privacyMode: false
    property var dispatcher: notificationDispatcher
    property string lastNotifiedUpdateVersion: configuration.lastNotifiedUpdateVersion || ""
    // Each queued update retains its own release action until activation.
    property var pendingUpdateReleaseUrls: ({})
    readonly property bool updateNotificationsEnabled: configuration.updateNotificationsEnabled !== false

    signal releasePageRequested(string url)

    function send(title, body, urgency, actionLabel) {
        var cleanTitle = privacyMode ? "CodexBar" : String(title || "CodexBar").trim()
        var cleanBody = privacyMode ? i18n("Usage or status changed. Open CodexBar for details.") : String(body || "").trim()
        return dispatcher.send(cleanTitle, cleanBody, urgency, actionLabel)
    }

    function notifyAvailableUpdate(version, url, releaseUrl) {
        if (!enableNotifications || !updateNotificationsEnabled) {
            return
        }
        var candidate = UpdateNotificationState.widgetCandidate(version, url, lastNotifiedUpdateVersion)
        if (!candidate) return
        var cleanVersion = candidate.version
        var memoKey = candidate.memoKey
        // Widget announcements persist even if the transport cannot start.
        lastNotifiedUpdateVersion = memoKey
        configuration.lastNotifiedUpdateVersion = memoKey
        var title = i18n("CodexBar widget update available")
        var body = cleanVersion.length > 0
            ? i18n("Version %1 is available.", cleanVersion)
            : i18n("A new widget version is available.")
        var releasePageUrl = UpdateNotificationState.safeReleaseUrl(releaseUrl)
        var actionLabel = releasePageUrl.length > 0 ? i18n("Open release page") : ""
        var sourceName = send(title, body, "normal", actionLabel)
        pendingUpdateReleaseUrls = UpdateNotificationState.register(
            pendingUpdateReleaseUrls, sourceName, releasePageUrl)
    }

    function handleUpdateNotificationActivated(sourceName) {
        var result = UpdateNotificationState.consume(pendingUpdateReleaseUrls, sourceName)
        pendingUpdateReleaseUrls = result.nextPending
        if (result.releaseUrl.length > 0) releasePageRequested(result.releaseUrl)
    }

    function notifyInstalledUpdate(version) {
        if (!enableNotifications || !updateNotificationsEnabled) {
            return
        }
        var cleanVersion = String(version || "").trim()
        var title = i18n("CodexBar widget update installed")
        var restartText = i18n("Restart Plasma to apply the new widget version.")
        var body = cleanVersion.length > 0
            ? i18n("Version %1 was installed. %2", cleanVersion, restartText)
            : i18n("A widget update was installed. %1", restartText)
        send(title, body, "normal")
    }

    function notifyAvailableCliUpdate(version, releaseUrl) {
        if (!enableNotifications || configuration.cliUpdateNotificationsEnabled === false
                || configuration.cliUpdateLastNotifiedVersion === version) return
        var releasePageUrl = UpdateNotificationState.safeReleaseUrl(releaseUrl)
        var actionLabel = releasePageUrl.length > 0 ? i18n("Open release page") : ""
        var sourceName = send(i18n("CodexBar CLI release available"),
            i18n("Upstream CLI %1 is available. Update using your installation method.", version),
            "normal", actionLabel)
        // CLI announcements remain retryable until a send has actually started.
        if (UpdateNotificationState.usableSource(sourceName)) {
            configuration.cliUpdateLastNotifiedVersion = version
            pendingUpdateReleaseUrls = UpdateNotificationState.register(
                pendingUpdateReleaseUrls, sourceName, releasePageUrl)
        }
    }

    NotificationDispatcher {
        id: notificationDispatcher
        onActivated: function(sourceName) {
            controller.handleUpdateNotificationActivated(sourceName)
        }
    }
}
