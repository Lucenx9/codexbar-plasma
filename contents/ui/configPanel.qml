import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import "components" as Components
import "PanelDisplay.js" as PanelDisplay
import "PanelElements.js" as PanelElements
import "PanelRules.js" as PanelRules
import "QuotaThresholds.js" as QuotaThresholds

KCM.SimpleKCM {
    id: page

    property string cfg_menuBarDisplayMode: "percent"
    property string cfg_menuBarDisplayModeDefault: "percent"
    property alias cfg_showProviderInPanel: showProviderCheck.checked
    property bool cfg_showProviderInPanelDefault: false
    property string cfg_panelStyle: "standard"
    property string cfg_panelStyleDefault: "standard"
    property alias cfg_showPercentInPanel: showPercentCheck.checked
    property bool cfg_showPercentInPanelDefault: false
    property alias cfg_showMultiProviderInPanel: showMultiProviderCheck.checked
    property bool cfg_showMultiProviderInPanelDefault: true
    property string cfg_panelElementOrder: "identity,status,text,meters"
    property string cfg_panelElementOrderDefault: "identity,status,text,meters"
    property string cfg_panelQuotaLane: "auto"
    property string cfg_panelQuotaLaneDefault: "auto"
    property string cfg_panelVisibilityRules: "{}"
    property string cfg_panelVisibilityRulesDefault: "{}"
    property alias cfg_autoSelectProvider: autoSelectProviderCheck.checked
    property bool cfg_autoSelectProviderDefault: false
    property alias cfg_showCreditsInPanel: showCreditsCheck.checked
    property bool cfg_showCreditsInPanelDefault: false
    readonly property var panelVisibilityRules: PanelRules.normalizedRules(cfg_panelVisibilityRules)
    readonly property var presentationConfig: Plasmoid.configuration || ({})
    readonly property bool usageBarsShowUsed: presentationConfig.usageBarsShowUsed !== false

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

    function setPanelVisibilityRule(elementID, patch) {
        cfg_panelVisibilityRules = PanelRules.updatedRules(cfg_panelVisibilityRules, elementID, patch)
    }

    function applyMinimalPanelPreset() {
        cfg_panelStyle = "minimal"
        cfg_showProviderInPanel = false
        cfg_showPercentInPanel = false
        cfg_showCreditsInPanel = false
        cfg_showMultiProviderInPanel = true
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

    onCfg_menuBarDisplayModeChanged: {
        var nextIndex = displayModeIndex(cfg_menuBarDisplayMode)
        if (displayModeCombo.currentIndex !== nextIndex) {
            displayModeCombo.currentIndex = nextIndex
        }
    }

    Kirigami.FormLayout {
        Components.PanelSettingsPreview {
            objectName: "panelSettingsPreview"
            configPage: page
            usageBarsShowUsed: page.usageBarsShowUsed
            resetTimesShowAbsolute: page.presentationConfig.resetTimesShowAbsolute === true
            showQuotaWarningMarkers: page.presentationConfig.showQuotaWarningMarkers !== false
            quotaWarningPercent: QuotaThresholds.warningPercent(page.presentationConfig.quotaWarningPercent)
            quotaCriticalPercent: QuotaThresholds.criticalPercent(quotaWarningPercent, page.presentationConfig.quotaCriticalPercent)
            providerOrder: page.presentationConfig.providerOrder || ""
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Panel")
            Kirigami.FormData.isSection: true
        }

        Controls.ComboBox {
            id: panelStyleCombo
            objectName: "panelStyleCombo"
            Kirigami.FormData.label: i18n("Panel style:")
            textRole: "text"
            valueRole: "value"
            model: [
                {text: i18n("Standard"), value: "standard"},
                {text: i18n("Minimal"), value: "minimal"}
            ]
            currentIndex: page.cfg_panelStyle === "minimal" ? 1 : 0
            onActivated: function(index) { page.cfg_panelStyle = valueAt(index) }
        }

        Components.PlainControlsLabel {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            text: i18n("Minimal uses monochrome icons and capsule meters. Quota warnings keep their warning colors.")
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WordWrap
        }

        Components.PlainButton {
            objectName: "minimalPanelPresetButton"
            plainText: i18n("Use minimal preset")
            onClicked: page.applyMinimalPanelPreset()
        }

        Components.PlainControlsLabel {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            text: i18n("The preset enables provider meters and hides provider names, usage text and credits in the panel.")
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WordWrap
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
            id: showCreditsCheck
            Layout.fillWidth: true
            text: i18n("Show credits in panel")
        }

        Controls.CheckBox {
            id: showMultiProviderCheck
            Layout.fillWidth: true
            text: i18n("Show provider meters in panel")
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
            text: i18n("Usage text is available only in horizontal panels. Provider meters also work in vertical panels.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.WordWrap
        }

        Controls.ComboBox {
            id: panelQuotaCombo
            objectName: "panelQuotaCombo"
            Kirigami.FormData.label: i18n("Panel quota:")
            textRole: "text"
            valueRole: "value"
            model: [
                {text: i18n("Automatic"), value: "auto"},
                {text: i18n("Primary"), value: "primary"},
                {text: i18n("Secondary"), value: "secondary"},
                {text: i18n("Tertiary"), value: "tertiary"}
            ]
            currentIndex: ["auto", "primary", "secondary", "tertiary"].indexOf(PanelDisplay.safeLane(page.cfg_panelQuotaLane))
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
            enabled: showProviderCheck.checked || showPercentCheck.checked
                || showCreditsCheck.checked || showMultiProviderCheck.checked
            onActivated: function(index) { page.cfg_panelQuotaLane = valueAt(index) }
        }

        Components.PlainControlsLabel {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            text: i18n("Automatic meters show primary and secondary quotas. Choose a quota to show one capsule. Unavailable quotas are omitted.")
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
                    text: page.usageBarsShowUsed
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
                        Layout.minimumWidth: Math.max(implicitWidth, Kirigami.Units.iconSizes.small)
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

                        Components.PlainToolTip {
                            parent: panelMoveUp
                            plainText: panelMoveUp.Accessible.name
                            visible: panelMoveUp.hovered
                            delay: Kirigami.Units.toolTipDelay
                        }

                        onClicked: page.movePanelElement(index, -1, visualFocus)
                    }

                    Controls.ToolButton {
                        id: panelMoveDown

                        icon.name: "go-down"
                        enabled: index < PanelElements.defaultOrder.length - 1
                        Accessible.name: i18n("Move %1 down", page.panelElementTitle(modelData))

                        Components.PlainToolTip {
                            parent: panelMoveDown
                            plainText: panelMoveDown.Accessible.name
                            visible: panelMoveDown.hovered
                            delay: Kirigami.Units.toolTipDelay
                        }

                        onClicked: page.movePanelElement(index, 1, visualFocus)
                    }
                }
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Panel visibility")
            Kirigami.FormData.isSection: true
        }

        Components.PanelRuleEditor {
            configPage: page
            elementID: "text"
            Kirigami.FormData.label: i18n("Show panel text:")
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            enabled: showProviderCheck.checked || showPercentCheck.checked || showCreditsCheck.checked
        }

        Components.PanelRuleEditor {
            configPage: page
            elementID: "meters"
            Kirigami.FormData.label: i18n("Show each meter:")
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            enabled: showMultiProviderCheck.checked
        }

        Components.PlainControlsLabel {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            text: i18n("A provider meter appears when either displayed quota matches its condition. The text condition also applies to the provider name and credits. Missing data does not satisfy a condition.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.WordWrap
        }

    }
}
