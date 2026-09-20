import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../CliUpdate.js" as CliUpdate
import "../CommandLedger.js" as CommandLedger
import "../UpdateLogic.js" as UpdateLogic

Item {
    id: controller

    property string commandPath: "codexbar"
    property bool automaticChecks: false
    property bool localOnly: false
    property string lastCheck: ""
    property string completedCheck: ""
    property url scriptUrl: Qt.resolvedUrl("../../../scripts/check-cli-update.py")
    readonly property bool busy: activeSource.length > 0
    property var result: CliUpdate.response("")
    property bool checked: false
    property string activeSource: ""
    property int serial: 0
    property double retryAfter: 0
    property bool initialized: false
    property bool forceNextCheck: false
    signal checkedRelease(string timestamp)
    signal updateAvailable(string version, string releaseUrl)

    readonly property string guidanceText: {
        if (result.manager === "homebrew")
            return i18n("Managed by Homebrew. Update through Homebrew.")
        if (result.manager !== "external")
            return i18n("Managed by %1. Update through your package manager; its version may lag behind upstream.", result.manager)
        return i18n("External installation. Update using your original installation method.")
    }
    readonly property string statusText: {
        if (busy) return i18n("Checking...")
        if (!checked) return i18n("Not checked")
        switch (result.status) {
        case "available": return i18n("Upstream CLI %1 is available. Installed: %2.", result.latest, result.version)
        case "current": return i18n("CLI %1 is current or newer than the latest stable release.", result.version)
        case "local": return result.version
        case "missing": return i18n("CodexBar CLI not found.")
        case "unknown": return i18n("Could not identify the installed CLI version.")
        case "uncomparable": return i18n("Latest stable CLI: %1. The installed version cannot be compared automatically.", result.latest)
        default: return localOnly ? i18n("Could not identify the installed CLI version.")
            : i18n("Could not check CLI releases. Try again later.")
        }
    }

    function retire() {
        var source = activeSource
        activeSource = ""
        deadline.stop()
        if (source.length > 0) processSource.disconnectSource(source)
    }
    function reset() {
        retire()
        checked = false
        completedCheck = ""
        result = CliUpdate.response("")
        retryAfter = 0
        forceNextCheck = initialized
        Qt.callLater(checkIfDue)
    }
    onCommandPathChanged: reset()
    onLocalOnlyChanged: reset()
    onAutomaticChecksChanged: {
        if (!automaticChecks) retire()
        else Qt.callLater(checkIfDue)
    }
    Component.onCompleted: {
        initialized = true
        Qt.callLater(checkIfDue)
    }
    Component.onDestruction: retire()

    function checkIfDue() {
        if (automaticChecks && !localOnly && Date.now() >= retryAfter
                && UpdateLogic.updateCheckDue(true, completedCheck || lastCheck, 24, Date.now(), forceNextCheck)) checkNow()
    }
    function checkNow() {
        if (busy) return
        var command = CliUpdate.command(scriptUrl, commandPath, localOnly)
        if (!command) {
            checked = true
            result = CliUpdate.response(commandPath.trim().length === 0
                ? '{"status":"missing"}' : "")
            retryAfter = Date.now() + 60 * 60 * 1000
            return
        }
        forceNextCheck = false
        serial += 1
        activeSource = CommandLedger.withRunNonce(command, serial)
        deadline.restart()
        processSource.connectSource(activeSource)
    }
    function accept(sourceName, data) {
        if (sourceName !== activeSource) return
        retire()
        checked = true
        result = CliUpdate.response(data && Number(data["exit code"]) === 0 ? data["stdout"] : "")
        retryAfter = Date.now() + 60 * 60 * 1000
        if (["available", "current", "uncomparable"].indexOf(result.status) >= 0) {
            completedCheck = new Date().toISOString()
            checkedRelease(completedCheck)
            if (result.status === "available") updateAvailable(result.latest, result.releaseUrl)
        }
    }
    Plasma5Support.DataSource {
        id: processSource
        engine: "executable"
        interval: 0
        onNewData: function(sourceName, data) { controller.accept(sourceName, data) }
    }
    Timer {
        id: deadline
        objectName: "cliUpdateDeadline"
        interval: 50000
        onTriggered: {
            controller.retire()
            controller.checked = true
            controller.result = CliUpdate.response("")
            controller.retryAfter = Date.now() + 60 * 60 * 1000
        }
    }
    Timer {
        interval: 60000
        repeat: true
        running: controller.automaticChecks && !controller.localOnly
        onTriggered: controller.checkIfDue()
    }
}
