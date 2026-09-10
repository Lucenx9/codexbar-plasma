import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "components" as Components
import "controllers" as Controllers
import "Guards.js" as Guards
import "ProviderIdentity.js" as ProviderIdentity
import "ProviderOrder.js" as ProviderOrder
import "SafeText.js" as SafeText

KCM.SimpleKCM {
    id: page

    readonly property Controls.ScrollView scrollView: contentItem as Controls.ScrollView

    // Reserve the themed scrollbar width even when initial overflow disappears.
    Binding {
        target: page.scrollView
        property: page.mirrored ? "leftPadding" : "rightPadding"
        value: page.scrollView.Controls.ScrollBar.vertical.implicitWidth
    }

    property string cfg_commandPath
    property string cfg_commandPathDefault: "codexbar"
    property alias cfg_usageBarsShowUsed: usageBarsShowUsedCheck.checked
    property bool cfg_usageBarsShowUsedDefault: true
    property alias cfg_showQuotaWarningMarkers: showQuotaWarningMarkersCheck.checked
    property bool cfg_showQuotaWarningMarkersDefault: true
    property alias cfg_showPopupPace: showPopupPaceCheck.checked
    property bool cfg_showPopupPaceDefault: true
    property alias cfg_showPopupCredits: showPopupCreditsCheck.checked
    property bool cfg_showPopupCreditsDefault: true
    property alias cfg_showPopupProviderDetails: showPopupProviderDetailsCheck.checked
    property bool cfg_showPopupProviderDetailsDefault: true
    property alias cfg_showPopupTabLabels: showPopupTabLabelsCheck.checked
    property bool cfg_showPopupTabLabelsDefault: true
    property string cfg_providerOrder: ""
    property string cfg_providerOrderDefault: ""
    property alias cfg_resetTimesShowAbsolute: resetTimesShowAbsoluteCheck.checked
    property bool cfg_resetTimesShowAbsoluteDefault: false
    property alias cfg_showProviderChangelogs: showProviderChangelogsCheck.checked
    property bool cfg_showProviderChangelogsDefault: false
    property string cfg_overviewProviderIDs: ""
    property string cfg_overviewProviderIDsDefault: ""

    readonly property int maxOverviewProviders: 3
    readonly property string overviewNoneValue: "__none__"
    readonly property string commandPath: (cfg_commandPath || "codexbar").trim()
    readonly property alias enabledProviderRoster: providerRosterController.enabledProviderRoster
    readonly property alias providerRosterLoading: providerRosterController.providerRosterLoading
    readonly property alias providerRosterError: providerRosterController.providerRosterError
    readonly property var orderedEnabledProviderRoster: ProviderOrder.orderedItems(
        enabledProviderRoster, cfg_providerOrder)

    Controllers.ProviderRosterController {
        id: providerRosterController
        objectName: "providerRosterController"

        commandPath: page.commandPath
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

    function resolvedOverviewProviderIDs() {
        var configured = parseOverviewProviderIDs(cfg_overviewProviderIDs)
        if (String(cfg_overviewProviderIDs || "").trim().length > 0) {
            return configured
        }

        var automatic = []
        for (var i = 0; i < orderedEnabledProviderRoster.length; i++) {
            var automaticID = ProviderOrder.normalizedProviderID(orderedEnabledProviderRoster[i].provider)
            if (automaticID.length === 0 || automatic.indexOf(automaticID) !== -1) {
                continue
            }
            automatic.push(automaticID)
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
            var providerID = ProviderOrder.normalizedProviderID(parts[i])
            if (providerID.length === 0 || Guards.hasOwnKey(seen, providerID)) {
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
        return resolvedOverviewProviderIDs().indexOf(ProviderOrder.normalizedProviderID(providerID)) !== -1
    }

    function toggleOverviewProvider(providerID, checked) {
        var selected = resolvedOverviewProviderIDs()
        var selectedSet = ({})
        for (var i = 0; i < selected.length; i++) {
            selectedSet[selected[i]] = true
        }

        var key = ProviderOrder.normalizedProviderID(providerID)
        if (key.length === 0) {
            return
        }
        if (checked) {
            if (!Guards.hasOwnKey(selectedSet, key) && selected.length >= maxOverviewProviders) {
                return
            }
            selectedSet[key] = true
        } else if (Guards.hasOwnKey(selectedSet, key)) {
            delete selectedSet[key]
        }

        var ordered = []
        for (var j = 0; j < orderedEnabledProviderRoster.length; j++) {
            var candidate = ProviderOrder.normalizedProviderID(orderedEnabledProviderRoster[j].provider)
            if (candidate.length > 0 && Guards.hasOwnKey(selectedSet, candidate) && ordered.indexOf(candidate) === -1) {
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
            if (Guards.hasOwnKey(selectedSet, prior) && ordered.indexOf(prior) === -1) {
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

    function providerIconSource(providerID) {
        var fileName = ProviderIdentity.providerIconFileName(providerID)
        return fileName.length > 0
            ? Qt.resolvedUrl("../icons/providers/" + fileName)
            : "view-statistics"
    }

    Kirigami.FormLayout {
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
            id: resetTimesShowAbsoluteCheck
            Layout.fillWidth: true
            text: i18n("Show reset times as clock time")
        }

        Controls.CheckBox {
            id: showQuotaWarningMarkersCheck
            Layout.fillWidth: true
            text: i18n("Show quota warnings on usage meters")
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Popup")
            Kirigami.FormData.isSection: true
        }

        Controls.CheckBox {
            id: showPopupPaceCheck
            objectName: "showPopupPaceCheck"
            Layout.fillWidth: true
            text: i18n("Show pace forecasts")
        }

        Controls.CheckBox {
            id: showPopupCreditsCheck
            objectName: "showPopupCreditsCheck"
            Layout.fillWidth: true
            text: i18n("Show credits and reset credits")
        }

        Controls.CheckBox {
            id: showPopupProviderDetailsCheck
            objectName: "showPopupProviderDetailsCheck"
            Layout.fillWidth: true
            text: i18n("Show provider details and charts")
        }

        Controls.CheckBox {
            id: showPopupTabLabelsCheck
            Layout.fillWidth: true
            text: i18n("Show text labels in the tab bar")
        }

        Controls.CheckBox {
            id: showProviderChangelogsCheck
            Layout.fillWidth: true
            text: i18n("Show provider changelog links")
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

                        Components.PlainToolTip {
                            plainText: providerMoveUp.Accessible.name
                            visible: providerMoveUp.hovered
                            delay: Kirigami.Units.toolTipDelay
                        }

                        onClicked: page.moveProvider(index, -1, visualFocus)
                    }

                    Controls.ToolButton {
                        id: providerMoveDown

                        icon.name: "go-down"
                        enabled: index < page.orderedEnabledProviderRoster.length - 1
                        Accessible.name: i18n("Move %1 down", modelData.displayName)

                        Components.PlainToolTip {
                            plainText: providerMoveDown.Accessible.name
                            visible: providerMoveDown.hovered
                            delay: Kirigami.Units.toolTipDelay
                        }

                        onClicked: page.moveProvider(index, 1, visualFocus)
                    }
                }
            }
        }

        ColumnLayout {
            id: overviewProviderSelection

            Kirigami.FormData.label: i18n("Overview providers:")
            Kirigami.FormData.labelAlignment: Qt.AlignTop
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
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
}
