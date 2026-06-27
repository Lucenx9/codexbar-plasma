import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

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
    readonly property string overviewNoneValue: "__none__"
    readonly property string commandPath: (cfg_commandPath || "codexbar").trim()
    property var overviewProviders: []
    property bool overviewProvidersLoading: false
    property string overviewProvidersError: ""
    property var overviewProviderCommands: ({})

    Component.onCompleted: loadOverviewProviders()

    onCfg_commandPathChanged: Qt.callLater(loadOverviewProviders)

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
        var next = copyObject(overviewProviderCommands)
        next[command] = true
        overviewProviderCommands = next
        overviewProviderSource.connectSource(command)
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
                ? stderrText.trim()
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
        for (var i = 0; i < items.length; i++) {
            var item = items[i]
            if (!item || !item.provider || item.enabled !== true) {
                continue
            }
            nextProviders.push({
                provider: String(item.provider),
                displayName: item.displayName && String(item.displayName).trim().length > 0
                    ? String(item.displayName).trim()
                    : providerTitle(item.provider)
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
            return String(probe.error.message)
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
            if (providerID.length === 0 || seen[providerID]) {
                continue
            }
            seen[providerID] = true
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
            selectedSet[selected[i]] = true
        }

        if (checked) {
            if (!selectedSet[providerID] && selected.length >= maxOverviewProviders) {
                return
            }
            selectedSet[providerID] = true
        } else {
            delete selectedSet[providerID]
        }

        var ordered = []
        for (var j = 0; j < overviewProviders.length; j++) {
            var candidate = overviewProviders[j].provider
            if (selectedSet[candidate] && ordered.indexOf(candidate) === -1) {
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
            if (selectedSet[prior] && ordered.indexOf(prior) === -1) {
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
            if (Object.prototype.hasOwnProperty.call(item, key)) {
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
            id: autoSelectProviderCheck
            text: i18n("Auto-select highest-usage provider")
        }

        ColumnLayout {
            Kirigami.FormData.label: i18n("Overview providers:")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                Layout.fillWidth: true
                text: i18n("Choose up to %1 providers", page.maxOverviewProviders)
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
                    onClicked: page.toggleOverviewProvider(modelData.provider, checked)
                }
            }

            Controls.Button {
                text: i18n("Use first %1 providers automatically", page.maxOverviewProviders)
                enabled: page.cfg_overviewProviderIDs.length > 0
                onClicked: page.resetOverviewProvidersToAutomatic()
            }
        }

        Controls.CheckBox {
            id: showCreditsCheck
            text: i18n("Show credits in panel")
        }
    }

    Plasma5Support.DataSource {
        id: overviewProviderSource

        engine: "executable"
        interval: 0

        onNewData: function(sourceName, data) {
            var stdoutText = data && data["stdout"] ? data["stdout"] : ""
            var stderrText = data && data["stderr"] ? data["stderr"] : ""
            disconnectSource(sourceName)
            page.handleOverviewProviderData(sourceName, stdoutText, stderrText)
        }
    }
}
