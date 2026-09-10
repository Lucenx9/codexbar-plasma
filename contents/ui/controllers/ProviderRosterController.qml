import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../CommandLedger.js" as CommandLedger
import "../Guards.js" as Guards
import "../ProviderRoster.js" as ProviderRoster
import "../SafeText.js" as SafeText

// Owns the read-only enabled-provider roster for settings pages: one CLI
// `config providers` list command per load, with nonce, timeout, and stale
// reply retirement. Pages supply the command path and read
// `enabledProviderRoster`, `providerRosterLoading`, and `providerRosterError`;
// they never touch the DataSource or the ledger.
// `active` gates loading so a collapsed section never spawns a CLI process.
Item {
    id: controller

    property string commandPath: ""
    property bool active: true
    property var enabledProviderRoster: []
    property bool providerRosterLoading: false
    property string providerRosterError: ""
    property var providerRosterCommands: ({})
    property int commandRunSerial: 0
    readonly property int providerRosterCommandTimeoutMs: 60000

    // Qt.callLater coalesces this with the load a commandPath change queues
    // when the host page injects the stored path during creation, so
    // activation spawns one CLI list command, not two.
    Component.onCompleted: if (active) Qt.callLater(loadProviderRoster)

    onCommandPathChanged: if (active) Qt.callLater(loadProviderRoster)

    onActiveChanged: {
        if (active) {
            Qt.callLater(loadProviderRoster)
        } else {
            disconnectProviderRosterCommands()
            providerRosterLoading = false
            providerRosterError = ""
        }
    }

    function shellQuote(value) {
        return Guards.shellQuote(value)
    }

    function loadProviderRoster() {
        if (!active) {
            return
        }
        disconnectProviderRosterCommands()
        if (commandPath.length === 0) {
            enabledProviderRoster = []
            providerRosterError = i18n("Set the codexbar command path in Diagnostics.")
            providerRosterLoading = false
            return
        }

        providerRosterLoading = true
        providerRosterError = ""
        var command = [
            shellQuote(commandPath),
            "config",
            "providers",
            "--format",
            "json",
            "--json-only"
        ].join(" ")
        commandRunSerial += 1
        var sourceName = CommandLedger.withRunNonce(command, commandRunSerial)
        var descriptor = CommandLedger.descriptor(
            "enabledProviderRoster", "", Date.now(),
            providerRosterCommandTimeoutMs, providerRosterCommandTimeoutMs)
        providerRosterCommands = CommandLedger.opened(
            providerRosterCommands, sourceName, descriptor)
        providerRosterSource.connectSource(sourceName)
    }

    function disconnectProviderRosterCommands() {
        var sourceNames = CommandLedger.sourcesOfKind(
            providerRosterCommands, "enabledProviderRoster")
        for (var i = 0; i < sourceNames.length; i++) {
            var sourceName = sourceNames[i]
            providerRosterSource.disconnectSource(sourceName)
        }
        providerRosterCommands = ({})
    }

    function hasPendingProviderRosterCommands() {
        return CommandLedger.hasKind(providerRosterCommands, "enabledProviderRoster")
    }

    function expireProviderRosterCommands(nowMs) {
        var expired = CommandLedger.expired(providerRosterCommands, nowMs)
        if (expired.length === 0) {
            return
        }
        var remaining = providerRosterCommands
        for (var i = 0; i < expired.length; i++) {
            var sourceName = expired[i].sourceName
            providerRosterSource.disconnectSource(sourceName)
            remaining = CommandLedger.closed(remaining, sourceName)
        }

        providerRosterCommands = remaining
        enabledProviderRoster = []
        providerRosterLoading = false
        providerRosterError = i18n("Loading providers timed out. Try again.")
    }

    function handleProviderRosterData(sourceName, stdoutText, stderrText) {
        if (!CommandLedger.find(providerRosterCommands, sourceName)) {
            return
        }

        providerRosterCommands = CommandLedger.closed(providerRosterCommands, sourceName)
        providerRosterLoading = false

        var result = ProviderRoster.response(stdoutText, stderrText)
        enabledProviderRoster = result.providers
        switch (result.outcome) {
        case "empty":
            providerRosterError = i18n("codexbar did not return provider data.")
            break
        case "tooLarge":
            providerRosterError = i18n("codexbar response exceeded the supported size.")
            break
        case "invalidJson":
            providerRosterError = i18n("Could not parse codexbar provider JSON: %1", result.message)
            break
        default:
            providerRosterError = result.message
        }
    }

    Plasma5Support.DataSource {
        id: providerRosterSource

        engine: "executable"
        interval: 0

        onNewData: function(sourceName, data) {
            var rawStdoutText = data && data["stdout"] ? data["stdout"] : ""
            var stdoutText = SafeText.cliJsonText(rawStdoutText)
            var stderrText = data && data["stderr"] ? data["stderr"] : ""
            if (stdoutText === null) {
                stdoutText = ""
                stderrText = i18n("codexbar response exceeded the supported size.")
            }
            disconnectSource(sourceName)
            controller.handleProviderRosterData(sourceName, stdoutText, stderrText)
        }
    }

    Timer {
        id: providerRosterCommandTimeoutTimer

        interval: 1000
        repeat: true
        running: controller.hasPendingProviderRosterCommands()
        triggeredOnStart: false
        onTriggered: controller.expireProviderRosterCommands(Date.now())
    }
}
