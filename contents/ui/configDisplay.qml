import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import "components" as Components
import "CommandLedger.js" as CommandLedger
import "Guards.js" as Guards
import "PanelDisplay.js" as PanelDisplay
import "ProviderIdentity.js" as ProviderIdentity
import "ProviderOrder.js" as ProviderOrder
import "PanelElements.js" as PanelElements
import "SafeText.js" as SafeText

KCM.SimpleKCM {
    id: page

    property string cfg_commandPath
    property string cfg_commandPathDefault: "codexbar"
    property alias cfg_usageBarsShowUsed: usageBarsShowUsedCheck.checked
    property bool cfg_usageBarsShowUsedDefault: false
    property alias cfg_showQuotaWarningMarkers: showQuotaWarningMarkersCheck.checked
    property bool cfg_showQuotaWarningMarkersDefault: true
    property string cfg_menuBarDisplayMode: "percent"
    property string cfg_menuBarDisplayModeDefault: "percent"
    property alias cfg_showPopupTabLabels: showPopupTabLabelsCheck.checked
    property bool cfg_showPopupTabLabelsDefault: true
    property string cfg_providerOrder: ""
    property string cfg_providerOrderDefault: ""
    property alias cfg_resetTimesShowAbsolute: resetTimesShowAbsoluteCheck.checked
    property bool cfg_resetTimesShowAbsoluteDefault: false
    property alias cfg_showProviderChangelogs: showProviderChangelogsCheck.checked
    property bool cfg_showProviderChangelogsDefault: false
    property alias cfg_showProviderInPanel: showProviderCheck.checked
    property bool cfg_showProviderInPanelDefault: true
    property alias cfg_showPercentInPanel: showPercentCheck.checked
    property bool cfg_showPercentInPanelDefault: true
    property alias cfg_showMultiProviderInPanel: showMultiProviderCheck.checked
    property bool cfg_showMultiProviderInPanelDefault: false
    property string cfg_panelElementOrder: "identity,status,text,meters"
    property string cfg_panelElementOrderDefault: "identity,status,text,meters"
    property alias cfg_autoSelectProvider: autoSelectProviderCheck.checked
    property bool cfg_autoSelectProviderDefault: false
    property string cfg_overviewProviderIDs: ""
    property string cfg_overviewProviderIDsDefault: ""
    property alias cfg_showCreditsInPanel: showCreditsCheck.checked
    property bool cfg_showCreditsInPanelDefault: false

    readonly property int maxOverviewProviders: 3
    readonly property string overviewNoneValue: "__none__"
    readonly property string commandPath: (cfg_commandPath || "codexbar").trim()
    property var enabledProviderRoster: []
    readonly property var orderedEnabledProviderRoster: ProviderOrder.orderedItems(
        enabledProviderRoster, cfg_providerOrder)
    property bool providerRosterLoading: false
    property string providerRosterError: ""
    property var providerRosterCommands: ({})
    property int commandRunSerial: 0
    readonly property int providerRosterCommandTimeoutMs: 60000

    // Qt.callLater coalesces this with the loadProviderRoster call the
    // cfg_commandPathChanged handler queues when Plasma injects the stored
    // command path during page creation, so opening the page spawns one CLI
    // list command, not two.
    Component.onCompleted: Qt.callLater(loadProviderRoster)

    onCfg_commandPathChanged: Qt.callLater(loadProviderRoster)

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

    function panelElementTitle(elementID) {
        switch (elementID) {
        case "identity":
            return i18n("Provider icon")
        case "status":
            return i18n("Service status")
        case "text":
            return i18n("Usage text")
        case "meters":
            return i18n("Provider meters")
        default:
            return ""
        }
    }

    function revealFocusedOrderButton(upButton, downButton) {
        var button = upButton && upButton.activeFocus ? upButton
            : (downButton && downButton.activeFocus ? downButton : null)
        if (!button) {
            return
        }
        var position = page.flickable.contentItem.mapFromItem(button, 0, 0)
        page.ensureVisible(button, position.x - button.x, position.y - button.y)
    }

    function restoreOrderFocus(repeater, key, delta) {
        for (var i = 0; i < repeater.count; i++) {
            var row = repeater.itemAt(i)
            if (row && row.orderKey === key) {
                var button = delta < 0 ? row.upButton : row.downButton
                if (!button.enabled) {
                    button = delta < 0 ? row.downButton : row.upButton
                }
                button.forceActiveFocus(Qt.TabFocusReason)
                revealFocusedOrderButton(row.upButton, row.downButton)
                return
            }
        }
    }

    function movePanelElement(index, delta, keyboardFocus) {
        var key = PanelElements.normalizedOrder(cfg_panelElementOrder)[index]
        cfg_panelElementOrder = PanelElements.movedOrder(
            cfg_panelElementOrder,
            index,
            delta).join(",")
        if (keyboardFocus) {
            Qt.callLater(restoreOrderFocus, panelOrderRepeater, key, delta)
        }
    }

    function moveProvider(index, delta, keyboardFocus) {
        var item = orderedEnabledProviderRoster[index]
        var key = item ? item.provider : ""
        cfg_providerOrder = ProviderOrder.movedOrder(
            enabledProviderRoster,
            cfg_providerOrder,
            index,
            delta)
        if (keyboardFocus) {
            // Repeater replaces the delegates when the order changes. Restore
            // focus by provider identity so repeated keyboard moves stay local.
            Qt.callLater(restoreOrderFocus, providerOrderRepeater, key, delta)
        }
    }

    onCfg_menuBarDisplayModeChanged: {
        var nextIndex = displayModeIndex(cfg_menuBarDisplayMode)
        if (displayModeCombo.currentIndex !== nextIndex) {
            displayModeCombo.currentIndex = nextIndex
        }
    }

    function loadProviderRoster() {
        disconnectProviderRosterCommands()
        if (commandPath.length === 0) {
            enabledProviderRoster = []
            providerRosterError = i18n("Set the codexbar command path in the General page.")
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
        for (var i = 0; i < orderedEnabledProviderRoster.length; i++) {
            automatic.push(orderedEnabledProviderRoster[i].provider)
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
            if (providerID.length === 0 || Guards.hasOwnKey(seen, selectionKey)) {
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
        for (var j = 0; j < orderedEnabledProviderRoster.length; j++) {
            var candidate = orderedEnabledProviderRoster[j].provider
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

    function providerTitle(value) {
        var words = String(value || "").replace(/[_-]/g, " ").split(" ")
        for (var i = 0; i < words.length; i++) {
            if (words[i].length > 0) {
                words[i] = words[i].charAt(0).toUpperCase() + words[i].slice(1)
            }
        }
        return words.join(" ")
    }

    function providerIconSource(providerID) {
        var fileName = ProviderIdentity.providerIconFileName(providerID)
        return fileName.length > 0
            ? Qt.resolvedUrl("../icons/providers/" + fileName)
            : "view-statistics"
    }

    function shellQuote(value) {
        return Guards.shellQuote(value)
    }

    Kirigami.FormLayout {
        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Popup")
            Kirigami.FormData.isSection: true
        }

        Controls.CheckBox {
            id: showPopupTabLabelsCheck
            Layout.fillWidth: true
            text: i18n("Show text labels in the tab bar")
        }

        ColumnLayout {
            Kirigami.FormData.label: i18n("Provider order:")
            Kirigami.FormData.labelAlignment: Qt.AlignTop
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            spacing: Kirigami.Units.smallSpacing / 2

            Components.PlainControlsLabel {
                Layout.fillWidth: true
                visible: page.providerRosterLoading
                text: i18n("Loading providers...")
                opacity: 0.7
            }

            Components.PlainControlsLabel {
                Layout.fillWidth: true
                visible: !page.providerRosterLoading
                    && page.orderedEnabledProviderRoster.length === 0
                    && page.providerRosterError.length === 0
                text: i18n("No enabled providers available.")
                opacity: 0.7
                wrapMode: Text.WordWrap
            }

            Components.PlainInlineMessage {
                Layout.fillWidth: true
                type: Kirigami.MessageType.Error
                plainText: page.providerRosterError
                visible: page.providerRosterError.length > 0
            }

            Repeater {
                id: providerOrderRepeater

                model: page.orderedEnabledProviderRoster

                delegate: RowLayout {
                    required property var modelData
                    required property int index
                    readonly property string orderKey: modelData.provider
                    readonly property Item upButton: providerMoveUp
                    readonly property Item downButton: providerMoveDown
                    // The layout may place a rebuilt row after focus is restored.
                    onYChanged: page.revealFocusedOrderButton(upButton, downButton)

                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: page.providerIconSource(modelData.provider)
                        fallback: "view-statistics"
                        isMask: true
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    }

                    Components.PlainControlsLabel {
                        text: modelData.displayName
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Controls.ToolButton {
                        id: providerMoveUp

                        icon.name: "go-up"
                        enabled: index > 0
                        Accessible.name: i18n("Move %1 up", modelData.displayName)
                        Controls.ToolTip.text: Accessible.name
                        Controls.ToolTip.visible: hovered
                        Controls.ToolTip.delay: Kirigami.Units.toolTipDelay
                        onClicked: page.moveProvider(index, -1, visualFocus)
                    }

                    Controls.ToolButton {
                        id: providerMoveDown

                        icon.name: "go-down"
                        enabled: index < page.orderedEnabledProviderRoster.length - 1
                        Accessible.name: i18n("Move %1 down", modelData.displayName)
                        Controls.ToolTip.text: Accessible.name
                        Controls.ToolTip.visible: hovered
                        Controls.ToolTip.delay: Kirigami.Units.toolTipDelay
                        onClicked: page.moveProvider(index, 1, visualFocus)
                    }
                }
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Panel")
            Kirigami.FormData.isSection: true
        }

        Controls.CheckBox {
            id: showProviderCheck
            Layout.fillWidth: true
            text: i18n("Show provider name in panel")
        }

        Controls.CheckBox {
            id: showPercentCheck
            Layout.fillWidth: true
            text: i18n("Show usage text in panel")
        }

        Controls.CheckBox {
            id: showMultiProviderCheck
            Layout.fillWidth: true
            text: i18n("Show multi-provider meters in panel")
        }

        Controls.CheckBox {
            id: showCreditsCheck
            Layout.fillWidth: true
            text: i18n("Show credits in panel")
        }

        Controls.CheckBox {
            id: autoSelectProviderCheck
            Layout.fillWidth: true
            text: i18n("Auto-select highest-usage provider")
        }

        Components.PlainControlsLabel {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            text: i18n("Usage text and provider meters are available only in horizontal panels.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.WordWrap
        }

        Controls.ComboBox {
            id: displayModeCombo
            Kirigami.FormData.label: i18n("Panel text:")
            textRole: "text"
            valueRole: "value"
            model: [
                {
                    text: page.cfg_usageBarsShowUsed
                        ? i18n("Percent used")
                        : i18n("Percent left"),
                    value: PanelDisplay.percentMode,
                    description: ""
                },
                {
                    text: i18n("Pace"), value: PanelDisplay.paceMode,
                    description: i18n("Shows the expected used or left percentage at this point in the window.")
                },
                {
                    text: i18n("Usage and pace"), value: PanelDisplay.bothMode,
                    description: i18n("Shows current usage alongside the expected used or left percentage.")
                },
                {
                    text: i18n("Reset time"), value: PanelDisplay.resetTimeMode,
                    description: i18n("Appears when the provider supplies a reset time.")
                },
                {
                    text: i18n("Run-out forecast"), value: PanelDisplay.runOutMode,
                    description: i18n("Appears only when the quota is forecast to run out before reset.")
                }
            ]
            enabled: showPercentCheck.checked
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
            onModelChanged: currentIndex = page.displayModeIndex(page.cfg_menuBarDisplayMode)
            Component.onCompleted: currentIndex = page.displayModeIndex(page.cfg_menuBarDisplayMode)
            onActivated: page.cfg_menuBarDisplayMode = currentValue
        }

        Components.PlainControlsLabel {
            id: displayModeDescription

            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            text: displayModeCombo.currentIndex >= 0
                ? displayModeCombo.model[displayModeCombo.currentIndex].description : ""
            visible: showPercentCheck.checked && text.length > 0
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.WordWrap
        }

        ColumnLayout {
            Kirigami.FormData.label: i18n("Element order:")
            Kirigami.FormData.labelAlignment: Qt.AlignTop
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            spacing: Kirigami.Units.smallSpacing / 2

            Repeater {
                id: panelOrderRepeater

                model: PanelElements.normalizedOrder(page.cfg_panelElementOrder)

                delegate: RowLayout {
                    required property var modelData
                    required property int index
                    readonly property string orderKey: modelData
                    readonly property Item upButton: panelMoveUp
                    readonly property Item downButton: panelMoveDown
                    onYChanged: page.revealFocusedOrderButton(upButton, downButton)

                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Components.PlainControlsLabel {
                        text: i18n("%1.", index + 1)
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        opacity: 0.7
                    }

                    Components.PlainControlsLabel {
                        text: page.panelElementTitle(modelData)
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Controls.ToolButton {
                        id: panelMoveUp

                        icon.name: "go-up"
                        enabled: index > 0
                        Accessible.name: i18n("Move %1 up", page.panelElementTitle(modelData))
                        Controls.ToolTip.text: Accessible.name
                        Controls.ToolTip.visible: hovered
                        Controls.ToolTip.delay: Kirigami.Units.toolTipDelay
                        onClicked: page.movePanelElement(index, -1, visualFocus)
                    }

                    Controls.ToolButton {
                        id: panelMoveDown

                        icon.name: "go-down"
                        enabled: index < PanelElements.defaultOrder.length - 1
                        Accessible.name: i18n("Move %1 down", page.panelElementTitle(modelData))
                        Controls.ToolTip.text: Accessible.name
                        Controls.ToolTip.visible: hovered
                        Controls.ToolTip.delay: Kirigami.Units.toolTipDelay
                        onClicked: page.movePanelElement(index, 1, visualFocus)
                    }
                }
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Usage details")
            Kirigami.FormData.isSection: true
        }

        Controls.CheckBox {
            id: usageBarsShowUsedCheck
            Layout.fillWidth: true
            text: i18n("Show usage as percent used")
        }

        Controls.CheckBox {
            id: showQuotaWarningMarkersCheck
            Layout.fillWidth: true
            text: i18n("Show quota warnings on usage meters")
        }

        Controls.CheckBox {
            id: resetTimesShowAbsoluteCheck
            Layout.fillWidth: true
            text: i18n("Show reset times as clock time")
        }

        Controls.CheckBox {
            id: showProviderChangelogsCheck
            Layout.fillWidth: true
            text: i18n("Show provider changelog links")
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Overview")
            Kirigami.FormData.isSection: true
        }

        ColumnLayout {
            id: overviewProviderSelection

            Kirigami.FormData.label: i18n("Overview providers:")
            Kirigami.FormData.labelAlignment: Qt.AlignTop
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Components.PlainControlsLabel {
                Layout.fillWidth: true
                text: i18np("Choose up to %1 provider", "Choose up to %1 providers", page.maxOverviewProviders)
                opacity: 0.7
                wrapMode: Text.WordWrap
            }

            Components.PlainControlsLabel {
                Layout.fillWidth: true
                visible: page.providerRosterLoading
                text: i18n("Loading providers...")
                opacity: 0.7
            }

            Components.PlainControlsLabel {
                Layout.fillWidth: true
                visible: !page.providerRosterLoading && page.enabledProviderRoster.length === 0 && page.providerRosterError.length === 0
                text: i18n("No enabled providers available for Overview.")
                opacity: 0.7
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: page.orderedEnabledProviderRoster

                delegate: Controls.CheckBox {
                    Layout.fillWidth: true
                    required property var modelData

                    readonly property bool selected: page.overviewProviderSelected(modelData.provider)

                    text: SafeText.plainTextAsRichText(modelData.displayName)
                    Accessible.name: modelData.displayName
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
            page.handleProviderRosterData(sourceName, stdoutText, stderrText)
        }
    }

    Timer {
        id: providerRosterCommandTimeoutTimer

        interval: 1000
        repeat: true
        running: page.hasPendingProviderRosterCommands()
        triggeredOnStart: false
        onTriggered: page.expireProviderRosterCommands(Date.now())
    }
}
