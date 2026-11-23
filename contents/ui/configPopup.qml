import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import "components" as Components
import "controllers" as Controllers
import "general/ConfigValueSync.js" as ConfigValueSync
import "OverviewProviders.js" as OverviewProviders
import "PopupHiddenRows.js" as PopupHiddenRows
import "PopupHiddenSections.js" as PopupHiddenSections
import "ProviderIdentity.mjs" as ProviderIdentity
import "ProviderOrder.js" as ProviderOrder
import "SafeText.mjs" as SafeText

KCM.SimpleKCM {
    id: page

    readonly property Controls.ScrollView scrollView: contentItem as Controls.ScrollView
    readonly property real scrollbarWidth: scrollView.Controls.ScrollBar.vertical.implicitWidth
    readonly property real formFieldWidth: Math.min(Kirigami.Units.gridUnit * 24,
        Math.max(0, availableWidth - scrollbarWidth))

    // Reserve the themed scrollbar width even when initial overflow disappears.
    Binding {
        target: page.scrollView
        property: page.mirrored ? "leftPadding" : "rightPadding"
        value: page.scrollbarWidth
    }

    property string cfg_commandPath
    property string cfg_commandPathDefault: "codexbar"
    property alias cfg_usageBarsShowUsed: usageBarsShowUsedCheck.checked
    property bool cfg_usageBarsShowUsedDefault: true
    property alias cfg_showQuotaWarningMarkers: showQuotaWarningMarkersCheck.checked
    property bool cfg_showQuotaWarningMarkersDefault: true
    property alias cfg_showPopupPace: showPopupPaceCheck.checked
    property bool cfg_showPopupPaceDefault: true
    property alias cfg_showMonthlyDailyAllowance: monthlyDailyAllowanceCheck.checked
    property bool cfg_showMonthlyDailyAllowanceDefault: false
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
    property string cfg_popupHiddenDetailSections: ""
    property string cfg_popupHiddenDetailSectionsDefault: ""
    property string cfg_popupHiddenUsageRows: ""
    property string cfg_popupHiddenUsageRowsDefault: ""

    readonly property string commandPath: (cfg_commandPath || "codexbar").trim()
    readonly property alias enabledProviderRoster: providerRosterController.enabledProviderRoster
    readonly property alias providerRosterLoading: providerRosterController.providerRosterLoading
    readonly property alias providerRosterError: providerRosterController.providerRosterError
    readonly property var orderedEnabledProviderRoster: ProviderOrder.orderedItems(
        enabledProviderRoster, cfg_providerOrder)
    readonly property var overviewRosterProviderIDs: orderedEnabledProviderRoster.map(function(item) {
        return item.provider
    })
    readonly property var resolvedOverviewProviderIDs: OverviewProviders.resolvedProviderIDs(
        overviewRosterProviderIDs, cfg_overviewProviderIDs)
    readonly property var hiddenDetailSections: PopupHiddenSections.parse(cfg_popupHiddenDetailSections)
    readonly property var hiddenDetailProviders: PopupHiddenSections.providers(hiddenDetailSections)
    readonly property var hiddenUsageRows: PopupHiddenRows.parse(cfg_popupHiddenUsageRows)
    // The popup hides and restores rows and sections live, and Plasma writes
    // every cfg_* value of the current page on Apply. Follow those changes
    // while keeping this page's pending restores, so Apply never writes a
    // stale list over them.
    readonly property string persistedPopupHiddenUsageRows: Plasmoid.configuration
        ? Plasmoid.configuration.popupHiddenUsageRows || "" : cfg_popupHiddenUsageRowsDefault
    readonly property string persistedPopupHiddenDetailSections: Plasmoid.configuration
        ? Plasmoid.configuration.popupHiddenDetailSections || "" : cfg_popupHiddenDetailSectionsDefault
    // The stored lists this page last followed, set once on creation: a
    // binding could update before the change handlers read it.
    property string hiddenUsageRowsBase: ""
    property string hiddenDetailSectionsBase: ""
    Component.onCompleted: {
        hiddenUsageRowsBase = persistedPopupHiddenUsageRows
        hiddenDetailSectionsBase = persistedPopupHiddenDetailSections
    }
    onPersistedPopupHiddenUsageRowsChanged: syncHiddenUsageRowsFromPersisted()
    onPersistedPopupHiddenDetailSectionsChanged: syncHiddenDetailSectionsFromPersisted()

    function syncHiddenUsageRowsFromPersisted() {
        cfg_popupHiddenUsageRows = ConfigValueSync.hiddenUsageRowsAfterPersistedChange(
            cfg_popupHiddenUsageRows, hiddenUsageRowsBase, persistedPopupHiddenUsageRows)
        hiddenUsageRowsBase = persistedPopupHiddenUsageRows
    }

    function syncHiddenDetailSectionsFromPersisted() {
        cfg_popupHiddenDetailSections = ConfigValueSync.hiddenDetailSectionsAfterPersistedChange(
            cfg_popupHiddenDetailSections, hiddenDetailSectionsBase, persistedPopupHiddenDetailSections)
        hiddenDetailSectionsBase = persistedPopupHiddenDetailSections
    }

    Components.ProviderNames {
        id: providerNames
    }

    Components.RateWindowLabels {
        id: rateWindowLabels
    }

    function hiddenRowProviderTitle(providerID) {
        for (var i = 0; i < enabledProviderRoster.length; i++) {
            if (enabledProviderRoster[i].provider === providerID) {
                return enabledProviderRoster[i].displayName
            }
        }
        return providerNames.titleForKey(ProviderIdentity.resolveProviderKey(providerID), providerID)
    }

    // Rows are stored without provider prose, so an extra window is named by
    // its CLI identifier here.
    function hiddenRowLabel(entry) {
        return entry.row.indexOf("extra:") === 0
            ? i18n("Extra window %1", entry.row.slice(6))
            : rateWindowLabels.labelForLane(ProviderIdentity.resolveProviderKey(entry.provider), entry.row)
    }

    function restoreProviderDetailSections(providerID) {
        cfg_popupHiddenDetailSections = PopupHiddenSections.serialize(
            PopupHiddenSections.restoredProvider(hiddenDetailSections, providerID))
    }

    function restoreHiddenUsageRow(entry) {
        cfg_popupHiddenUsageRows = PopupHiddenRows.serialize(
            PopupHiddenRows.restored(hiddenUsageRows, entry.provider, entry.row))
    }

    function focusHiddenItems() {
        hiddenItemsDisclosure.forceActiveFocus(Qt.TabFocusReason)
        var position = page.flickable.contentItem.mapFromItem(hiddenItemsDisclosure, 0, 0)
        page.ensureVisible(hiddenItemsDisclosure, position.x - hiddenItemsDisclosure.x,
            position.y - hiddenItemsDisclosure.y)
    }

    component HiddenItemRestoreButton: Components.PlainButton {
        property bool keyboardRelease: false
        signal restoreRequested()

        flat: true
        icon.name: "view-visible"

        onPressed: keyboardRelease = false
        Keys.onReleased: function(event) {
            // Observe the activation key and let the native button emit clicked.
            keyboardRelease = pressed && (event.key === Qt.Key_Space || event.key === Qt.Key_Select)
            event.accepted = false
        }
        onClicked: {
            if (keyboardRelease) {
                page.focusHiddenItems()
            }
            restoreRequested()
        }
    }

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

    function toggleOverviewProvider(providerID, checked) {
        cfg_overviewProviderIDs = OverviewProviders.selectionText(OverviewProviders.toggledSelection(
            overviewRosterProviderIDs, resolvedOverviewProviderIDs, providerID, checked))
    }

    function resetOverviewProvidersToAutomatic() {
        cfg_overviewProviderIDs = ""
    }

    function providerIconSource(providerID) {
        var fileName = ProviderIdentity.providerIconFileName(providerID)
        return fileName.length > 0
            ? Qt.resolvedUrl("../icons/providers/" + fileName)
            : "view-statistics"
    }

    component PopupSectionHeading: ColumnLayout {
        property alias text: heading.text

        Layout.fillWidth: true
        Layout.maximumWidth: providersForm.wideMode ? providersForm.implicitWidth : Infinity
        Layout.alignment: Qt.AlignHCenter
        spacing: Kirigami.Units.smallSpacing

        Components.PlainHeading {
            id: heading

            Layout.fillWidth: true
            horizontalAlignment: providersForm.wideMode ? Text.AlignHCenter : Text.AlignLeft
            wrapMode: Text.WordWrap
            level: 3
            type: Kirigami.Heading.Type.Primary
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }
    }

    component PopupFormGroup: Kirigami.FormLayout {
        twinFormLayouts: [providersForm]
        wideMode: providersForm.wideMode
    }

    ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        PopupSectionHeading {
            text: i18n("Usage details")
        }

        PopupFormGroup {
            Controls.CheckBox {
                id: usageBarsShowUsedCheck
                implicitWidth: 0
                Layout.fillWidth: true
                text: i18n("Show usage as percent used")
            }

            Controls.CheckBox {
                id: resetTimesShowAbsoluteCheck
                implicitWidth: 0
                Layout.fillWidth: true
                text: i18n("Show reset times as clock time")
            }

            Controls.CheckBox {
                id: showQuotaWarningMarkersCheck
                implicitWidth: 0
                Layout.fillWidth: true
                text: i18n("Show quota warnings on usage meters")
            }
        }

        PopupSectionHeading {
            Layout.topMargin: Kirigami.Units.largeSpacing
            text: i18n("Popup content")
        }

        PopupFormGroup {
            Controls.CheckBox {
                id: showPopupPaceCheck
                objectName: "showPopupPaceCheck"
                implicitWidth: 0
                Layout.fillWidth: true
                text: i18n("Show pace forecasts")
            }

            Controls.CheckBox {
                id: monthlyDailyAllowanceCheck
                objectName: "monthlyDailyAllowanceCheck"
                implicitWidth: 0
                Layout.fillWidth: true
                text: i18n("Show remaining monthly quota per day")
            }

            Controls.CheckBox {
                id: showPopupCreditsCheck
                objectName: "showPopupCreditsCheck"
                implicitWidth: 0
                Layout.fillWidth: true
                text: i18n("Show credits and reset credits")
            }

            Controls.CheckBox {
                id: showPopupProviderDetailsCheck
                objectName: "showPopupProviderDetailsCheck"
                implicitWidth: 0
                Layout.fillWidth: true
                text: i18n("Show provider details and charts")
            }

            Controls.CheckBox {
                id: showProviderChangelogsCheck
                implicitWidth: 0
                Layout.fillWidth: true
                text: i18n("Show provider changelog links")
            }
        }

        PopupSectionHeading {
            Layout.topMargin: Kirigami.Units.largeSpacing
            text: i18n("Providers")
        }

        Kirigami.FormLayout {
            id: providersForm

            Controls.CheckBox {
                id: showPopupTabLabelsCheck
                implicitWidth: 0
                Layout.fillWidth: true
                text: i18n("Show text labels in the tab bar")
            }

            ColumnLayout {
                id: providerOrderColumn
                Kirigami.FormData.label: i18n("Provider order:")
                Kirigami.FormData.labelAlignment: providerOrderRepeater.count > 0 ? 0 : Qt.AlignTop
                Kirigami.FormData.buddyFor: providerOrderRepeater.count > 0
                    ? providerOrderRepeater.itemAt(0) : providerOrderColumn
                Layout.fillWidth: true
                Layout.preferredWidth: page.formFieldWidth
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                spacing: Kirigami.Units.smallSpacing / 2

                Components.PlainControlsLabel {
                    Layout.fillWidth: true
                    visible: page.providerRosterLoading
                    text: i18n("Loading providers…")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                }

                Components.PlainControlsLabel {
                    Layout.fillWidth: true
                    visible: !page.providerRosterLoading
                        && page.orderedEnabledProviderRoster.length === 0
                        && page.providerRosterError.length === 0
                    text: i18n("No enabled providers available.")
                    font: Kirigami.Theme.smallFont
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
                        // Keep the move buttons near the name, on the restore rows' action edge.
                        Layout.maximumWidth: Kirigami.Units.gridUnit * 18
                        spacing: Kirigami.Units.smallSpacing

                        Components.PlainControlsLabel {
                            text: Number(index + 1).toLocaleString(Qt.locale(), 'f', 0)
                            font: Kirigami.Theme.smallFont
                            opacity: 0.7
                            Layout.preferredWidth: Kirigami.Units.gridUnit
                            Accessible.ignored: true
                        }

                        Kirigami.Icon {
                            source: page.providerIconSource(modelData.provider)
                            fallback: "view-statistics"
                            isMask: true
                            color: Kirigami.Theme.textColor
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
                                visible: providerMoveUp.hovered || providerMoveUp.visualFocus
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
                                visible: providerMoveDown.hovered || providerMoveDown.visualFocus
                                delay: Kirigami.Units.toolTipDelay
                            }

                            onClicked: page.moveProvider(index, 1, visualFocus)
                        }
                    }
                }

                Item {
                    implicitHeight: Kirigami.Units.smallSpacing
                }
            }

            ColumnLayout {
                id: overviewProviderSelection

                Kirigami.FormData.label: i18n("Overview providers:")
                // Center the label on the first option rather than the column top.
                Kirigami.FormData.buddyFor: overviewAutomaticRadio
                Layout.fillWidth: true
                Layout.preferredWidth: page.formFieldWidth
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                spacing: Kirigami.Units.smallSpacing

                Components.PlainControlsLabel {
                    Layout.fillWidth: true
                    visible: page.providerRosterLoading
                    text: i18n("Loading providers…")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                }

                Components.PlainControlsLabel {
                    Layout.fillWidth: true
                    visible: !page.providerRosterLoading && page.enabledProviderRoster.length === 0 && page.providerRosterError.length === 0
                    text: i18n("No enabled providers available for Overview.")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    wrapMode: Text.WordWrap
                }

                Controls.RadioButton {
                    id: overviewAutomaticRadio
                    objectName: "overviewAutomaticRadio"
                    implicitWidth: 0
                    Layout.fillWidth: true
                    text: i18n("Automatic: first %1 providers", OverviewProviders.automaticProviderCount)
                    checked: !OverviewProviders.selectionActive(page.cfg_overviewProviderIDs)
                    onClicked: page.resetOverviewProvidersToAutomatic()
                }

                Components.PlainControlsLabel {
                    objectName: "overviewAutomaticHint"
                    Layout.fillWidth: true
                    text: i18n("Follows the provider order above.")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    leftPadding: page.mirrored ? 0 : overviewAutomaticRadio.indicator.width + overviewAutomaticRadio.spacing
                    rightPadding: page.mirrored ? overviewAutomaticRadio.indicator.width + overviewAutomaticRadio.spacing : 0
                    // Sit closer to its own option than to the next one.
                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                    wrapMode: Text.WordWrap
                }

                Controls.RadioButton {
                    id: overviewCustomRadio
                    objectName: "overviewCustomRadio"
                    implicitWidth: 0
                    Layout.fillWidth: true
                    text: i18n("Choose providers")
                    checked: OverviewProviders.selectionActive(page.cfg_overviewProviderIDs)
                    onClicked: page.cfg_overviewProviderIDs = OverviewProviders.selectionText(page.resolvedOverviewProviderIDs)
                }

                Repeater {
                    model: page.orderedEnabledProviderRoster

                    delegate: Controls.CheckBox {
                        implicitWidth: 0
                        Layout.fillWidth: true
                        required property var modelData

                        visible: overviewCustomRadio.checked
                        readonly property bool selected: OverviewProviders.isSelected(
                            page.resolvedOverviewProviderIDs, modelData.provider)

                        text: SafeText.plainTextAsRichText(modelData.displayName)
                        Kirigami.MnemonicData.label: SafeText.plainTextAsMnemonicRichText(modelData.displayName)
                        Accessible.name: modelData.displayName
                        checked: selected
                        enabled: overviewCustomRadio.checked
                            && (selected || page.resolvedOverviewProviderIDs.length < ProviderOrder.maximumProviderItems)
                        Layout.leftMargin: overviewCustomRadio.indicator.width + overviewCustomRadio.spacing
                        onClicked: {
                            page.toggleOverviewProvider(modelData.provider, checked)
                            // Keep the checkbox bound to the stored selection after a click.
                            checked = Qt.binding(function() { return selected })
                        }
                    }
                }
            }
        }

        PopupSectionHeading {
            Layout.topMargin: Kirigami.Units.largeSpacing
            text: i18n("Hidden items")
        }

        PopupFormGroup {
            Components.DisclosureButton {
                id: hiddenItemsDisclosure
                alignWithForm: true
                objectName: "hiddenItemsDisclosure"
                Layout.alignment: page.mirrored ? Qt.AlignRight : Qt.AlignLeft
                plainText: i18n("%1, %2",
                    i18np("%1 section", "%1 sections", page.hiddenDetailSections.length),
                    i18np("%1 usage row", "%1 usage rows", page.hiddenUsageRows.length))
                Accessible.description: i18n("Hidden items")
                onClicked: {
                    forceActiveFocus(visualFocus ? Qt.TabFocusReason : Qt.MouseFocusReason)
                    expanded = !expanded
                }
            }

            Kirigami.FormLayout {
                visible: hiddenItemsDisclosure.expanded
                wideMode: false
                Layout.fillWidth: true
                Layout.maximumWidth: visible ? page.formFieldWidth : 0

                Item {
                    objectName: "hiddenDetailSectionsSettings"
                    Kirigami.FormData.label: i18n("Hidden detail sections:")
                    Kirigami.FormData.labelAlignment: Qt.AlignTop
                    Layout.fillWidth: true
                    Layout.preferredWidth: page.formFieldWidth
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                    // Isolate FormLayout's size queries while restore delegates rebuild.
                    implicitWidth: hiddenDetailSectionsLayout.implicitWidth
                    implicitHeight: hiddenDetailSectionsLayout.implicitHeight

                    ColumnLayout {
                        id: hiddenDetailSectionsLayout
                        width: parent.width
                        spacing: Kirigami.Units.smallSpacing

                        Components.PlainControlsLabel {
                            Layout.fillWidth: true
                            text: page.hiddenDetailProviders.length === 0
                                ? i18n("None. Use a section's hide button in the popup.")
                                : i18n("Restore individual sections in the popup, or all sections for a provider here.")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.7
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            model: page.hiddenDetailProviders
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.maximumWidth: Kirigami.Units.gridUnit * 18
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.Icon {
                                    source: page.providerIconSource(modelData)
                                    fallback: "view-statistics"
                                    isMask: true
                                    color: Kirigami.Theme.textColor
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                }

                                Components.PlainControlsLabel {
                                    text: page.hiddenRowProviderTitle(modelData)
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                HiddenItemRestoreButton {
                                    objectName: "restoreProviderDetailSectionsButton"
                                    plainText: i18n("Restore all")
                                    Accessible.name: i18n("Restore all sections for %1", page.hiddenRowProviderTitle(modelData))
                                    onRestoreRequested: page.restoreProviderDetailSections(modelData)
                                }
                            }
                        }
                    }
                }

                Item {
                    id: hiddenUsageRowsSection
                    objectName: "hiddenUsageRowsSection"

                    Kirigami.FormData.label: i18n("Hidden usage rows:")
                    Kirigami.FormData.labelAlignment: Qt.AlignTop
                    Layout.fillWidth: true
                    Layout.preferredWidth: page.formFieldWidth
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                    // Isolate FormLayout's size queries while restore delegates rebuild.
                    implicitWidth: hiddenUsageRowsLayout.implicitWidth
                    implicitHeight: hiddenUsageRowsLayout.implicitHeight

                    ColumnLayout {
                        id: hiddenUsageRowsLayout
                        width: parent.width
                        spacing: Kirigami.Units.smallSpacing

                        Components.PlainControlsLabel {
                            Layout.fillWidth: true
                            text: page.hiddenUsageRows.length === 0
                                ? i18n("None. Use a row's hide button in the popup.")
                                : i18n("Hidden rows stay out of the popup's provider tabs only.")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.7
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            model: page.hiddenUsageRows

                            delegate: RowLayout {
                                required property var modelData
                                readonly property string rowText: i18n("%1: %2",
                                    page.hiddenRowProviderTitle(modelData.provider), page.hiddenRowLabel(modelData))

                                Layout.fillWidth: true
                                Layout.maximumWidth: Kirigami.Units.gridUnit * 18
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.Icon {
                                    source: page.providerIconSource(modelData.provider)
                                    fallback: "view-statistics"
                                    isMask: true
                                    color: Kirigami.Theme.textColor
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                }

                                Components.PlainControlsLabel {
                                    text: rowText
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                HiddenItemRestoreButton {
                                    objectName: "restoreHiddenUsageRowButton"
                                    plainText: i18n("Restore")
                                    Accessible.name: i18n("Restore %1", rowText)
                                    onRestoreRequested: page.restoreHiddenUsageRow(modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
