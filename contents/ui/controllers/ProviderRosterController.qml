import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../CommandLedger.js" as CommandLedger
import "../Guards.js" as Guards
import "../ProviderIdentity.js" as ProviderIdentity
import "../ProviderOrder.js" as ProviderOrder
import "../SafeText.js" as SafeText

// Owns the read-only enabled-provider roster for settings pages: one CLI
// `config providers` list command per load, with nonce, timeout, and stale
// reply retirement. Pages supply the command path and read `roster`,
// `loading`, and `errorText`; they never touch the DataSource or the ledger.
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
        }
    }

    function boundedCliMessage(value) {
        return SafeText.cliMessage(SafeText.stripLoaderDiagnostics(value), SafeText.maximumCliMessageLength)
    }

    function boundedProviderID(value) {
        if (typeof value !== "string") {
            return ""
        }
        var providerID = value.trim()
        if (providerID.length === 0 || providerID.length > ProviderIdentity.maximumProviderIDLength) {
            return ""
        }
        return ProviderIdentity.providerMapKey(providerID.toLowerCase()).length > 0 ? providerID : ""
    }

    function commandError(payload) {
        if (!payload) {
            return ""
        }
        var probe = Array.isArray(payload) ? (payload.length > 0 ? payload[0] : null) : payload
        if (probe && probe.error && probe.error.message) {
            return boundedCliMessage(probe.error.message)
        }
        return ""
    }

    function providerTitle(value) {
        var words = String(value || "").replace(/[_-]/g, " ").split(" ")
        for (var i = 0; i < words.length; i++) {
            if (words[i].length > 0) {
                words[i] = words[i].charAt(0).toUpperCase() + words[i].slice(1)
            }
        }
        return words.join(" ")
    }

    function shellQuote(value) {
        return Guards.shellQuote(value)
    }

    function loadProviderRoster() {
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

        var trimmed = stdoutText.trim()
        if (trimmed.length === 0) {
            enabledProviderRoster = []
            providerRosterError = stderrText.trim().length > 0
                ? boundedCliMessage(stderrText)
                : i18n("codexbar did not return provider data.")
            return
        }

        var payload
        try {
            payload = JSON.parse(trimmed)
        } catch (error) {
            enabledProviderRoster = []
            providerRosterError = i18n("Could not parse codexbar provider JSON: %1", error.message)
            return
        }

        var message = commandError(payload)
        if (message.length > 0) {
            enabledProviderRoster = []
            providerRosterError = message
            return
        }

        var items = Array.isArray(payload) ? payload : [payload]
        var nextProviders = []
        var itemLimit = Math.min(items.length, ProviderOrder.maximumProviderItems)
        for (var i = 0; i < itemLimit; i++) {
            var item = items[i]
            if (!item || typeof item !== "object" || Array.isArray(item) || item.enabled !== true) {
                continue
            }
            var providerID = boundedProviderID(item.provider)
            if (providerID.length === 0) {
                continue
            }
            var displayName = SafeText.boundedDisplayText(item.displayName, 120)
            nextProviders.push({
                provider: providerID,
                displayName: displayName.length > 0 ? displayName : providerTitle(providerID)
            })
        }
        enabledProviderRoster = nextProviders
        providerRosterError = ""
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
