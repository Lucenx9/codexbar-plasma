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

    property bool advancedExpanded: false
    readonly property string advancedSummary: {
        var parts = []
        if (PanelDisplay.safeLane(cfg_panelQuotaLane) !== "auto") {
            parts.push(i18n("Quota: %1", panelQuotaCombo.currentText))
        }
        if (PanelElements.normalizedOrder(cfg_panelElementOrder).join(",") !== PanelElements.defaultOrder.join(",")) {
            parts.push(i18n("Custom element order"))
        }
        var ruleCount = (panelVisibilityRules.text.condition !== "always" ? 1 : 0)
            + (panelVisibilityRules.meters.condition !== "always" ? 1 : 0)
        if (ruleCount > 0) {
            parts.push(i18np("%1 visibility rule", "%1 visibility rules", ruleCount))
        }
        if (cfg_autoSelectProvider) {
            parts.push(i18n("Highest-usage provider selected automatically"))
        }
        return parts.length > 0 ? parts.join(" · ")
            : i18n("Automatic quotas, default order, no conditions")
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
            Kirigami.FormData.label: i18n("Appearance")
            Kirigami.FormData.isSection: true
        }

        Controls.ButtonGroup {
            buttons: [standardStyleButton, minimalStyleButton]
        }

        GridLayout {
            Kirigami.FormData.label: i18n("Panel style:")
            Kirigami.FormData.labelAlignment: Qt.AlignTop
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            columns: width >= Kirigami.Units.gridUnit * 20 ? 2 : 1
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.smallSpacing

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Controls.RadioButton {
                    id: standardStyleButton
                    objectName: "panelStandardStyle"
                    text: i18n("Standard")
                    checked: page.cfg_panelStyle !== "minimal"
                    Accessible.description: i18n("Colored provider icons")
                    onClicked: page.cfg_panelStyle = "standard"
                    Keys.onRightPressed: {
                        page.cfg_panelStyle = "minimal"
                        minimalStyleButton.forceActiveFocus(Qt.TabFocusReason)
                    }
                    Keys.onDownPressed: {
                        page.cfg_panelStyle = "minimal"
                        minimalStyleButton.forceActiveFocus(Qt.TabFocusReason)
                    }
                }
                Components.PlainControlsLabel {
                    Layout.fillWidth: true
                    text: i18n("Colored provider icons")
                    font: Kirigami.Theme.smallFont
                    wrapMode: Text.WordWrap
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Controls.RadioButton {
                    id: minimalStyleButton
                    objectName: "panelMinimalStyle"
                    text: i18n("Minimal")
                    checked: page.cfg_panelStyle === "minimal"
                    Accessible.description: i18n("Monochrome provider icons")
                    onClicked: page.cfg_panelStyle = "minimal"
                    Keys.onLeftPressed: {
                        page.cfg_panelStyle = "standard"
                        standardStyleButton.forceActiveFocus(Qt.TabFocusReason)
                    }
                    Keys.onUpPressed: {
                        page.cfg_panelStyle = "standard"
                        standardStyleButton.forceActiveFocus(Qt.TabFocusReason)
                    }
                }
                Components.PlainControlsLabel {
                    Layout.fillWidth: true
                    text: i18n("Monochrome provider icons")
                    font: Kirigami.Theme.smallFont
                    wrapMode: Text.WordWrap
                }
            }
        }

        Components.PlainControlsLabel {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            text: i18n("Quota capsules keep their warning colors in both styles.")
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WordWrap
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Contents")
            Kirigami.FormData.isSection: true
        }

        Controls.CheckBox {
            id: showProviderCheck
            Layout.fillWidth: true
            text: i18n("Show provider name in panel")
        }

        Controls.CheckBox {
            id: showPercentCheck
            objectName: "panelUsageTextCheck"
            Layout.fillWidth: true
            text: i18n("Show usage text in panel")
        }

        Controls.ComboBox {
            id: displayModeCombo
            objectName: "panelTextMode"
            visible: showPercentCheck.checked
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

        Components.PlainControlsLabel {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            text: i18n("Usage text is available only in horizontal panels. Provider meters also work in vertical panels.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.WordWrap
        }

        Components.PlainButton {
            objectName: "minimalPanelPresetButton"
            plainText: i18n("Use monochrome icons and meters only")
            onClicked: page.applyMinimalPanelPreset()
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
        }

        Components.PlainButton {
            id: advancedButton
            objectName: "panelAdvancedButton"
            plainText: i18n("Quota, order and visibility")
            icon.name: page.advancedExpanded ? "arrow-down" : (LayoutMirroring.enabled ? "arrow-left" : "arrow-right")
            checkable: true
            checked: page.advancedExpanded
            onToggled: page.advancedExpanded = checked
            Accessible.description: page.advancedExpanded
                ? i18n("Collapse options. %1", page.advancedSummary)
                : i18n("Expand options. %1", page.advancedSummary)
        }

        Components.PlainControlsLabel {
            objectName: "panelAdvancedSummary"
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            text: page.advancedSummary
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WordWrap
        }

        Kirigami.FormLayout {
            objectName: "panelAdvancedOptions"
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
            visible: page.advancedExpanded

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

            Controls.CheckBox {
                id: autoSelectProviderCheck
                Layout.fillWidth: true
                text: i18n("Auto-select highest-usage provider")
            }
        }
    }
}
