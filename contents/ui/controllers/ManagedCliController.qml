import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../ManagedCli.js" as ManagedCli
import "../CommandLedger.js" as CommandLedger
import "../Guards.js" as Guards

Item {
    id: controller
    property string commandPath: "codexbar"
    property bool automaticUpdates: false
    property url scriptUrl: Qt.resolvedUrl("../../../scripts/manage-cli.py")
    property var result: ManagedCli.response("")
    property string activeSource: ""
    property string activeAction: ""
    property int serial: 0
    property double nextAttempt: 0
    property bool statusRefreshPending: false
    readonly property bool busy: activeSource.length > 0
    readonly property bool selected: result.path.length > 0 && commandPath.trim() === result.path && result.version.length > 0
    signal installed(string path)
    signal changed()

    readonly property string statusText: {
        if (busy) return activeAction === "status" ? i18n("Checking…") : i18n("Preparing the managed CLI…")
        switch (result.status) {
        case "ready": return i18n("Managed CLI %1 is installed.", result.version)
        case "installed": return i18n("Managed CLI %1 is ready.", result.version)
        case "restored": return i18n("Restored CLI %1. Automatic updates will skip the replaced version.", result.version)
        case "absent": return i18n("No managed CLI installed.")
        case "external": return i18n("Select the managed CLI before updating it.")
        case "busy": return i18n("Another widget is updating the managed CLI. Try again shortly.")
        case "no_previous": return i18n("No previous CLI version is available.")
        case "stale": return i18n("The managed CLI changed to %1. Check the version to restore and try again.", result.version)
        case "network": return i18n("Could not reach the release server. Try again later.")
        case "unsupported": return i18n("No official CLI build is available for this system.")
        case "unverified": return i18n("The downloaded CLI failed verification and was discarded.")
        case "unusable": return i18n("The existing managed CLI could not be verified. Choose another CLI in Settings > Diagnostics.")
        default: return i18n("Could not prepare the managed CLI. Check the installed version and try again.")
        }
    }

    function retire() {
        var source = activeSource
        activeSource = ""
        deadline.stop()
        if (source.length > 0) processSource.disconnectSource(source)
    }
    function run(action, expectedPrevious) {
        if (busy) return
        var command = ManagedCli.command(scriptUrl, action, commandPath, expectedPrevious)
        if (!command) return
        activeAction = action
        serial += 1
        activeSource = CommandLedger.withRunNonce(command, serial, Date.now() + "-" + Math.random())
        deadline.restart()
        processSource.connectSource(activeSource)
    }
    function refreshStatus() {
        statusRefreshPending = true
        if (busy) return
        statusRefreshPending = false
        run("status")
    }
    onBusyChanged: {
        if (!busy && statusRefreshPending) Qt.callLater(refreshStatus)
    }
    function accept(sourceName, data) {
        if (sourceName !== activeSource) return
        var action = activeAction
        retire()
        result = ManagedCli.nextResponse(result,
            data && Guards.exitCode(data["exit code"]) === 0 ? data["stdout"] : "", action === "status")
        if (action === "install" && ["installed", "ready"].indexOf(result.status) >= 0) installed(result.path)
        if (["installed", "restored"].indexOf(result.status) >= 0) changed()
    }
    function checkIfDue() {
        if (!automaticUpdates || busy || Date.now() < nextAttempt) return
        nextAttempt = Date.now() + 60 * 60 * 1000
        // The helper checks exact managed ownership before any network or filesystem mutation.
        run("automatic")
    }
    onCommandPathChanged: {
        retire()
        // Installation facts belong to the shared private directory, not the selected command.
        nextAttempt = 0
        Qt.callLater(checkIfDue)
    }
    onAutomaticUpdatesChanged: {
        if (!automaticUpdates && activeAction === "automatic") retire()
        else Qt.callLater(checkIfDue)
    }
    Component.onCompleted: Qt.callLater(checkIfDue)
    Component.onDestruction: retire()
    Plasma5Support.DataSource {
        id: processSource
        engine: "executable"
        interval: 0
        onNewData: function(sourceName, data) { controller.accept(sourceName, data) }
    }
    Timer {
        id: deadline
        objectName: "managedCliDeadline"
        interval: 615000
        onTriggered: {
            controller.retire()
            controller.result = ManagedCli.nextResponse(controller.result, "")
        }
    }
    Timer {
        interval: 60000
        repeat: true
        running: controller.automaticUpdates
        onTriggered: controller.checkIfDue()
    }
}
