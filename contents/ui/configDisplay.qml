import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import "ProviderIdentity.js" as ProviderIdentity
import "SafeText.js" as SafeText

KCM.SimpleKCM {
    id: page

    property string cfg_commandPath
    property string cfg_commandPathDefault
    property alias cfg_usageBarsShowUsed: usageBarsShowUsedCheck.checked
    property bool cfg_usageBarsShowUsedDefault
    property alias cfg_showQuotaWarningMarkers: showQuotaWarningMarkersCheck.checked
    property bool cfg_showQuotaWarningMarkersDefault
    property string cfg_menuBarDisplayMode: "percent"
    property string cfg_menuBarDisplayModeDefault
    property alias cfg_resetTimesShowAbsolute: resetTimesShowAbsoluteCheck.checked
    property bool cfg_resetTimesShowAbsoluteDefault
    property alias cfg_showProviderChangelogs: showProviderChangelogsCheck.checked
    property bool cfg_showProviderChangelogsDefault
    property alias cfg_showProviderInPanel: showProviderCheck.checked
    property bool cfg_showProviderInPanelDefault
    property alias cfg_showPercentInPanel: showPercentCheck.checked
    property bool cfg_showPercentInPanelDefault
    property alias cfg_showMultiProviderInPanel: showMultiProviderCheck.checked
    property bool cfg_showMultiProviderInPanelDefault
    property alias cfg_autoSelectProvider: autoSelectProviderCheck.checked
    property bool cfg_autoSelectProviderDefault
    property string cfg_overviewProviderIDs: ""
    property string cfg_overviewProviderIDsDefault
    property alias cfg_showCreditsInPanel: showCreditsCheck.checked
    property bool cfg_showCreditsInPanelDefault

    readonly property int maxOverviewProviders: 3
    readonly property int maximumProviderItems: 256
    readonly property string overviewNoneValue: "__none__"
    readonly property string commandPath: (cfg_commandPath || "codexbar").trim()
    property var overviewProviders: []
    property bool overviewProvidersLoading: false
    property string overviewProvidersError: ""
    property var overviewProviderCommands: ({})
    property int commandRunSerial: 0
    readonly property int overviewProviderCommandTimeoutMs: 60000

    Component.onCompleted: loadOverviewProviders()

    onCfg_commandPathChanged: Qt.callLater(loadOverviewProviders)

    function boundedCliMessage(value) {
        return SafeText.cliMessage(value, SafeText.maximumCliMessageLength)
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

    function providerSelectionKey(providerID) {
        return JSON.stringify(String(providerID || ""))
    }

    function displayModeIndex(value) {
        for (var i = 0; i < displayModeCombo.model.length; i++) {
            if (displayModeCombo.model[i].value === value) {
                return i
            }
        }
        return 0
    }

    onCfg_menuBarDisplayModeChanged: {
        var nextIndex = displayModeIndex(cfg_menuBarDisplayMode)
        if (displayModeCombo.currentIndex !== nextIndex) {
            displayModeCombo.currentIndex = nextIndex
        }
    }

    function loadOverviewProviders() {
        disconnectOverviewProviderCommands()
        if (commandPath.length === 0) {
            overviewProviders = []
            overviewProvidersError = i18n("Set the codexbar command path in the General page.")
            overviewProvidersLoading = false
            return
        }

        overviewProvidersLoading = true
        overviewProvidersError = ""
        var command = [
            shellQuote(commandPath),
            "config",
            "providers",
            "--format",
            "json",
            "--json-only"
        ].join(" ")
        var sourceName = commandWithRunNonce(command)
        var next = copyObject(overviewProviderCommands)
        next[sourceName] = {
            deadlineMs: Date.now() + overviewProviderCommandTimeoutMs
        }
        overviewProviderCommands = next
        overviewProviderSource.connectSource(sourceName)
    }

    function commandWithRunNonce(command) {
        if (command.length === 0) {
            return ""
        }
        commandRunSerial += 1
        return "CODEXBAR_PLASMA_RUN=" + commandRunSerial + " " + command
    }

    function disconnectOverviewProviderCommands() {
        for (var command in overviewProviderCommands) {
            overviewProviderSource.disconnectSource(command)
        }
        overviewProviderCommands = ({})
    }

    function hasPendingOverviewProviderCommands() {
        for (var sourceName in overviewProviderCommands) {
            if (Object.prototype.hasOwnProperty.call(overviewProviderCommands, sourceName)) {
                return true
            }
        }
        return false
    }

    function expireOverviewProviderCommands(nowMs) {
        var commands = copyObject(overviewProviderCommands)
        var expiredCount = 0
        for (var sourceName in commands) {
            if (!Object.prototype.hasOwnProperty.call(commands, sourceName)) {
                continue
            }
            var descriptor = commands[sourceName]
            var deadline = descriptor ? Number(descriptor.deadlineMs) : 0
            if (!isFinite(deadline) || deadline <= 0 || nowMs < deadline) {
                continue
            }
            overviewProviderSource.disconnectSource(sourceName)
            delete commands[sourceName]
            expiredCount++
        }
        if (expiredCount === 0) {
            return
        }

        overviewProviderCommands = commands
        overviewProviders = []
        overviewProvidersLoading = false
        overviewProvidersError = i18n("Loading providers timed out. Try again.")
    }

    function handleOverviewProviderData(sourceName, stdoutText, stderrText) {
        if (!overviewProviderCommands[sourceName]) {
            return
        }

        var remaining = copyObject(overviewProviderCommands)
        delete remaining[sourceName]
        overviewProviderCommands = remaining
        overviewProvidersLoading = false

        var trimmed = stdoutText.trim()
        if (trimmed.length === 0) {
            overviewProviders = []
            overviewProvidersError = stderrText.trim().length > 0
                ? boundedCliMessage(stderrText)
                : i18n("codexbar did not return provider data.")
            return
        }

        var payload
        try {
            payload = JSON.parse(trimmed)
        } catch (error) {
            overviewProviders = []
            overviewProvidersError = i18n("Could not parse codexbar provider JSON: %1", error.message)
            return
        }

        var message = commandError(payload)
        if (message.length > 0) {
            overviewProviders = []
            overviewProvidersError = message
            return
        }

        var items = Array.isArray(payload) ? payload : [payload]
        var nextProviders = []
        var itemLimit = Math.min(items.length, maximumProviderItems)
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
        overviewProviders = nextProviders
        overviewProvidersError = ""
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

    function resolvedOverviewProviderIDs() {
        var configured = parseOverviewProviderIDs(cfg_overviewProviderIDs)
        if (String(cfg_overviewProviderIDs || "").trim().length > 0) {
            return configured
        }

        var automatic = []
        for (var i = 0; i < overviewProviders.length; i++) {
            automatic.push(overviewProviders[i].provider)
            if (automatic.length >= maxOverviewProviders) {
                break
            }
        }
        return automatic
    }

    function parseOverviewProviderIDs(value) {
        var raw = String(value || "").trim()
        if (raw.length === 0 || raw === overviewNoneValue) {
            return []
        }

        var parts = raw.split(",")
        var result = []
        var seen = ({})
        for (var i = 0; i < parts.length; i++) {
            var providerID = String(parts[i] || "").trim()
            var selectionKey = providerSelectionKey(providerID)
            if (providerID.length === 0 || Object.prototype.hasOwnProperty.call(seen, selectionKey)) {
                continue
            }
            seen[selectionKey] = true
            result.push(providerID)
            if (result.length >= maxOverviewProviders) {
                break
            }
        }
        return result
    }

    function overviewProviderIDsText(providerIDs) {
        return providerIDs.length > 0 ? providerIDs.join(",") : overviewNoneValue
    }

    function overviewProviderSelected(providerID) {
        return resolvedOverviewProviderIDs().indexOf(providerID) !== -1
    }

    function toggleOverviewProvider(providerID, checked) {
        var selected = resolvedOverviewProviderIDs()
        var selectedSet = ({})
        for (var i = 0; i < selected.length; i++) {
            selectedSet[providerSelectionKey(selected[i])] = true
        }

        var providerKey = providerSelectionKey(providerID)
        if (checked) {
            if (!selectedSet[providerKey] && selected.length >= maxOverviewProviders) {
                return
            }
            selectedSet[providerKey] = true
        } else {
            delete selectedSet[providerKey]
        }

        var ordered = []
        for (var j = 0; j < overviewProviders.length; j++) {
            var candidate = overviewProviders[j].provider
            if (selectedSet[providerSelectionKey(candidate)] && ordered.indexOf(candidate) === -1) {
                ordered.push(candidate)
                if (ordered.length >= maxOverviewProviders) {
                    break
                }
            }
        }
        // Preserve previously-selected providers that are no longer in the
        // enabled list, so disabling a provider elsewhere does not silently
        // drop it from the overview selection on the next toggle.
        for (var k = 0; k < selected.length && ordered.length < maxOverviewProviders; k++) {
            var prior = selected[k]
            if (selectedSet[providerSelectionKey(prior)] && ordered.indexOf(prior) === -1) {
                ordered.push(prior)
            }
        }
        cfg_overviewProviderIDs = overviewProviderIDsText(ordered)
    }

    function resetOverviewProvidersToAutomatic() {
        cfg_overviewProviderIDs = ""
    }

    function selectedOverviewProviderCount() {
        return resolvedOverviewProviderIDs().length
    }

    function copyObject(item) {
        var copy = ({})
        for (var key in item) {
            if (Object.prototype.hasOwnProperty.call(item, key)
                    && key !== "__proto__" && key !== "prototype" && key !== "constructor") {
                copy[key] = item[key]
            }
        }
        return copy
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
        return "'" + String(value).replace(/'/g, "'\\''") + "'"
    }

    Kirigami.FormLayout {
        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Panel")
            Kirigami.FormData.isSection: true
        }

        Controls.ComboBox {
            id: displayModeCombo
            Kirigami.FormData.label: i18n("Display mode:")
            textRole: "text"
            valueRole: "value"
            model: [
                { text: i18n("Percent"), value: "percent" },
                { text: i18n("Pace"), value: "pace" },
                { text: i18n("Percent and pace"), value: "both" },
                { text: i18n("Reset time"), value: "resetTime" }
            ]
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
            Component.onCompleted: currentIndex = page.displayModeIndex(page.cfg_menuBarDisplayMode)
            onActivated: page.cfg_menuBarDisplayMode = currentValue
        }

        Controls.CheckBox {
            id: showProviderCheck
            text: i18n("Show provider in panel")
        }

        Controls.CheckBox {
            id: showPercentCheck
            text: i18n("Show percent in panel")
        }

        Controls.CheckBox {
            id: showMultiProviderCheck
            text: i18n("Show multi-provider details in panel")
        }

        Controls.CheckBox {
            id: showCreditsCheck
            text: i18n("Show credits in panel")
        }

        Controls.CheckBox {
            id: autoSelectProviderCheck
            text: i18n("Auto-select highest-usage provider")
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Usage details")
            Kirigami.FormData.isSection: true
        }

        Controls.CheckBox {
            id: usageBarsShowUsedCheck
            text: i18n("Show usage as percent used")
        }

        Controls.CheckBox {
            id: showQuotaWarningMarkersCheck
            text: i18n("Show quota warning markers")
        }

        Controls.CheckBox {
            id: resetTimesShowAbsoluteCheck
            text: i18n("Show reset times as clock time")
        }

        Controls.CheckBox {
            id: showProviderChangelogsCheck
            text: i18n("Show provider changelog links")
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Overview")
            Kirigami.FormData.isSection: true
        }

        ColumnLayout {
            Kirigami.FormData.label: i18n("Overview providers:")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                Layout.fillWidth: true
                text: i18np("Choose up to %1 provider", "Choose up to %1 providers", page.maxOverviewProviders)
                opacity: 0.7
                wrapMode: Text.WordWrap
            }

            Controls.Label {
                Layout.fillWidth: true
                visible: page.overviewProvidersLoading
                text: i18n("Loading providers...")
                opacity: 0.7
            }

            Controls.Label {
                Layout.fillWidth: true
                visible: !page.overviewProvidersLoading && page.overviewProviders.length === 0 && page.overviewProvidersError.length === 0
                text: i18n("No enabled providers available for Overview.")
                opacity: 0.7
                wrapMode: Text.WordWrap
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                type: Kirigami.MessageType.Error
                text: page.overviewProvidersError
                visible: page.overviewProvidersError.length > 0
            }

            Repeater {
                model: page.overviewProviders

                delegate: Controls.CheckBox {
                    required property var modelData

                    readonly property bool selected: page.overviewProviderSelected(modelData.provider)

                    text: modelData.displayName
                    checked: selected
                    enabled: selected || page.selectedOverviewProviderCount() < page.maxOverviewProviders
                    onClicked: {
                        page.toggleOverviewProvider(modelData.provider, checked)
                        // Clicking severs the binding on `checked`; restore it so the box reflects the
                        // actual selection (e.g. when a click is rejected by the max-providers cap).
                        checked = Qt.binding(function() { return selected })
                    }
                }
            }

            Controls.Button {
                text: i18n("Use first %1 providers automatically", page.maxOverviewProviders)
                enabled: page.cfg_overviewProviderIDs.length > 0
                onClicked: page.resetOverviewProvidersToAutomatic()
            }
        }
    }

    Plasma5Support.DataSource {
        id: overviewProviderSource

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
            page.handleOverviewProviderData(sourceName, stdoutText, stderrText)
        }
    }

    Timer {
        id: overviewProviderCommandTimeoutTimer

        interval: 1000
        repeat: true
        running: page.hasPendingOverviewProviderCommands()
        triggeredOnStart: false
        onTriggered: page.expireOverviewProviderCommands(Date.now())
    }
}
