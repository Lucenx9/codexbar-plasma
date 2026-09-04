import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import "components" as Components
import "UpdateLogic.js" as UpdateLogic
import "general/ConfigValueSync.js" as ConfigValueSync

KCM.SimpleKCM {
    id: page

    property alias cfg_commandPath: commandPathField.text
    // cfg_*Default mirrors the schema default in contents/config/main.xml. The
    // Plasma config dialog injects only cfg_<key>, never defaults, so these
    // initializers are the only source for the restore-defaults action;
    // scripts/test_ui_regressions.sh checks them against main.xml for drift.
    property string cfg_commandPathDefault: "codexbar"
    property alias cfg_refreshInterval: refreshIntervalSpin.value
    property int cfg_refreshIntervalDefault: 300
    property alias cfg_includeStatus: includeStatusCheck.checked
    property bool cfg_includeStatusDefault: false
    property alias cfg_costUsageEnabled: costUsageEnabledCheck.checked
    property bool cfg_costUsageEnabledDefault: true
    property int cfg_costHistoryDays: 30
    property int cfg_costHistoryDaysDefault: 30
    property alias cfg_enableNotifications: enableNotificationsCheck.checked
    property bool cfg_enableNotificationsDefault: true
    property alias cfg_notifyStatusIncidents: notifyStatusIncidentsCheck.checked
    property bool cfg_notifyStatusIncidentsDefault: true
    property alias cfg_notifyQuotaWarnings: notifyQuotaWarningsCheck.checked
    property bool cfg_notifyQuotaWarningsDefault: true
    property alias cfg_notifyPredictivePaceWarnings: notifyPredictivePaceWarningsCheck.checked
    property bool cfg_notifyPredictivePaceWarningsDefault: false
    property alias cfg_notifyLimitResets: notifyLimitResetsCheck.checked
    property bool cfg_notifyLimitResetsDefault: true
    property alias cfg_quotaWarningPercent: quotaWarningPercentSpin.value
    property int cfg_quotaWarningPercentDefault: 80
    property alias cfg_quotaCriticalPercent: quotaCriticalPercentSpin.value
    property int cfg_quotaCriticalPercentDefault: 95
    property alias cfg_updateChecksEnabled: updateChecksEnabledCheck.checked
    property bool cfg_updateChecksEnabledDefault: true
    property alias cfg_updateNotificationsEnabled: updateNotificationsEnabledCheck.checked
    property bool cfg_updateNotificationsEnabledDefault: true
    property alias cfg_autoUpdateEnabled: autoUpdateEnabledCheck.checked
    property bool cfg_autoUpdateEnabledDefault: false
    property alias cfg_autoUpdateIntervalHours: autoUpdateIntervalHoursSpin.value
    property int cfg_autoUpdateIntervalHoursDefault: 24

    // Plasma saves the cfg_* properties declared by the current page. Keep the
    // user-facing Display and Advanced values here as well so one global reset
    // remains pending until Apply/OK instead of writing configuration directly.
    property string cfg_provider
    property string cfg_providerDefault: ""
    property string cfg_source
    property string cfg_sourceDefault: ""
    property bool cfg_usageBarsShowUsed
    property bool cfg_usageBarsShowUsedDefault: false
    property bool cfg_showQuotaWarningMarkers
    property bool cfg_showQuotaWarningMarkersDefault: true
    property string cfg_menuBarDisplayMode
    property string cfg_menuBarDisplayModeDefault: "percent"
    property bool cfg_showPopupTabLabels
    property bool cfg_showPopupTabLabelsDefault: true
    property string cfg_providerOrder
    property string cfg_providerOrderDefault: ""
    // Chosen from the Usage & Spend tab, reset from here like the other
    // popup-owned values.
    property string cfg_costHistoryMetric: "cost"
    property string cfg_costHistoryMetricDefault: "cost"
    property bool cfg_resetTimesShowAbsolute
    property bool cfg_resetTimesShowAbsoluteDefault: false
    property bool cfg_showProviderChangelogs
    property bool cfg_showProviderChangelogsDefault: false
    property bool cfg_showProviderInPanel
    property bool cfg_showProviderInPanelDefault: true
    property bool cfg_showPercentInPanel
    property bool cfg_showPercentInPanelDefault: true
    property bool cfg_showMultiProviderInPanel
    property bool cfg_showMultiProviderInPanelDefault: false
    property string cfg_panelElementOrder
    property string cfg_panelElementOrderDefault: "identity,status,text,meters"
    property bool cfg_autoSelectProvider
    property bool cfg_autoSelectProviderDefault: false
    property string cfg_overviewProviderIDs
    property string cfg_overviewProviderIDsDefault: ""
    property bool cfg_showCreditsInPanel
    property bool cfg_showCreditsInPanelDefault: false

    property bool defaultsActionRequested: false
    // Plasma supplies cfg_* values as creation-time properties, which replaces
    // bindings declared on them. Track runtime-owned values separately and
    // copy them into the pending KCM state only while the user has no edit.
    readonly property int persistedCostHistoryDays: Plasmoid.configuration.costHistoryDays
    readonly property string persistedCostHistoryMetric: Plasmoid.configuration.costHistoryMetric
    property bool costHistoryDaysEditPending: false
    property bool costHistoryMetricEditPending: false
    readonly property bool defaultValuesPrepared: defaultsActionRequested
        && userSettingsAreDefault()
    readonly property string autoUpdateLastCheck: Plasmoid.configuration.autoUpdateLastCheck || ""
    readonly property string widgetUpdateLastStatus: Plasmoid.configuration.widgetUpdateLastStatus || ""
    readonly property string widgetUpdateLastError: Plasmoid.configuration.widgetUpdateLastError || ""

    Component.onCompleted: {
        syncCostHistoryDaysFromPersisted()
        syncCostHistoryMetricFromPersisted()
    }
    onPersistedCostHistoryDaysChanged: syncCostHistoryDaysFromPersisted()
    onPersistedCostHistoryMetricChanged: syncCostHistoryMetricFromPersisted()

    function applyCostHistoryDaysTransition(transition) {
        costHistoryDaysEditPending = transition.hasPendingEdit
        cfg_costHistoryDays = transition.pendingValue
    }

    function applyCostHistoryMetricTransition(transition) {
        costHistoryMetricEditPending = transition.hasPendingEdit
        cfg_costHistoryMetric = transition.pendingValue
    }

    function editCostHistoryDays(value) {
        applyCostHistoryDaysTransition(ConfigValueSync.afterUserEdit(
            value, persistedCostHistoryDays))
    }

    function editCostHistoryMetric(value) {
        applyCostHistoryMetricTransition(ConfigValueSync.afterUserEdit(
            value, persistedCostHistoryMetric))
    }

    function syncCostHistoryDaysFromPersisted() {
        applyCostHistoryDaysTransition(ConfigValueSync.afterPersistedChange(
            cfg_costHistoryDays, costHistoryDaysEditPending, persistedCostHistoryDays))
    }

    function syncCostHistoryMetricFromPersisted() {
        applyCostHistoryMetricTransition(ConfigValueSync.afterPersistedChange(
            cfg_costHistoryMetric, costHistoryMetricEditPending, persistedCostHistoryMetric))
    }

    function refreshPresetIndex(value) {
        var numeric = Number(value)
        for (var i = 0; i < refreshPresetCombo.model.length; i++) {
            if (refreshPresetCombo.model[i].value === numeric) {
                return i
            }
        }
        return refreshPresetCombo.model.length - 1
    }

    function lastUpdateCheckText(value) {
        var checkedAtMs = UpdateLogic.lastCheckMs(value)
        if (!isFinite(checkedAtMs)) {
            return i18n("Last checked: never")
        }
        var checkedAt = new Date(checkedAtMs)
        return i18n("Last checked: %1",
            Qt.locale().toString(checkedAt, Locale.ShortFormat))
    }

    onCfg_refreshIntervalChanged: {
        var nextIndex = refreshPresetIndex(cfg_refreshInterval)
        if (refreshPresetCombo.currentIndex !== nextIndex) {
            refreshPresetCombo.currentIndex = nextIndex
        }
    }

    function settingsMatch(value, defaultValue) {
        return String(value) === String(defaultValue)
    }

    function userSettingsAreDefault() {
        var pairs = [
            [cfg_commandPath, cfg_commandPathDefault],
            [cfg_provider, cfg_providerDefault],
            [cfg_source, cfg_sourceDefault],
            [cfg_refreshInterval, cfg_refreshIntervalDefault],
            [cfg_includeStatus, cfg_includeStatusDefault],
            [cfg_costUsageEnabled, cfg_costUsageEnabledDefault],
            [cfg_costHistoryDays, cfg_costHistoryDaysDefault],
            [cfg_costHistoryMetric, cfg_costHistoryMetricDefault],
            [cfg_usageBarsShowUsed, cfg_usageBarsShowUsedDefault],
            [cfg_showQuotaWarningMarkers, cfg_showQuotaWarningMarkersDefault],
            [cfg_quotaWarningPercent, cfg_quotaWarningPercentDefault],
            [cfg_quotaCriticalPercent, cfg_quotaCriticalPercentDefault],
            [cfg_enableNotifications, cfg_enableNotificationsDefault],
            [cfg_notifyStatusIncidents, cfg_notifyStatusIncidentsDefault],
            [cfg_notifyQuotaWarnings, cfg_notifyQuotaWarningsDefault],
            [cfg_notifyPredictivePaceWarnings, cfg_notifyPredictivePaceWarningsDefault],
            [cfg_notifyLimitResets, cfg_notifyLimitResetsDefault],
            [cfg_updateChecksEnabled, cfg_updateChecksEnabledDefault],
            [cfg_updateNotificationsEnabled, cfg_updateNotificationsEnabledDefault],
            [cfg_autoUpdateEnabled, cfg_autoUpdateEnabledDefault],
            [cfg_autoUpdateIntervalHours, cfg_autoUpdateIntervalHoursDefault],
            [cfg_menuBarDisplayMode, cfg_menuBarDisplayModeDefault],
            [cfg_showPopupTabLabels, cfg_showPopupTabLabelsDefault],
            [cfg_providerOrder, cfg_providerOrderDefault],
            [cfg_resetTimesShowAbsolute, cfg_resetTimesShowAbsoluteDefault],
            [cfg_showProviderChangelogs, cfg_showProviderChangelogsDefault],
            [cfg_showProviderInPanel, cfg_showProviderInPanelDefault],
            [cfg_showPercentInPanel, cfg_showPercentInPanelDefault],
            [cfg_showMultiProviderInPanel, cfg_showMultiProviderInPanelDefault],
            [cfg_panelElementOrder, cfg_panelElementOrderDefault],
            [cfg_autoSelectProvider, cfg_autoSelectProviderDefault],
            [cfg_overviewProviderIDs, cfg_overviewProviderIDsDefault],
            [cfg_showCreditsInPanel, cfg_showCreditsInPanelDefault]
        ]
        for (var i = 0; i < pairs.length; i++) {
            if (!settingsMatch(pairs[i][0], pairs[i][1])) {
                return false
            }
        }
        return true
    }

    function restoreUserDefaults() {
        cfg_commandPath = cfg_commandPathDefault
        cfg_provider = cfg_providerDefault
        cfg_source = cfg_sourceDefault
        cfg_refreshInterval = cfg_refreshIntervalDefault
        cfg_includeStatus = cfg_includeStatusDefault
        cfg_costUsageEnabled = cfg_costUsageEnabledDefault
        editCostHistoryDays(cfg_costHistoryDaysDefault)
        editCostHistoryMetric(cfg_costHistoryMetricDefault)
        cfg_usageBarsShowUsed = cfg_usageBarsShowUsedDefault
        cfg_showQuotaWarningMarkers = cfg_showQuotaWarningMarkersDefault
        cfg_quotaWarningPercent = cfg_quotaWarningPercentDefault
        cfg_quotaCriticalPercent = cfg_quotaCriticalPercentDefault
        cfg_enableNotifications = cfg_enableNotificationsDefault
        cfg_notifyStatusIncidents = cfg_notifyStatusIncidentsDefault
        cfg_notifyQuotaWarnings = cfg_notifyQuotaWarningsDefault
        cfg_notifyPredictivePaceWarnings = cfg_notifyPredictivePaceWarningsDefault
        cfg_notifyLimitResets = cfg_notifyLimitResetsDefault
        cfg_updateChecksEnabled = cfg_updateChecksEnabledDefault
        cfg_updateNotificationsEnabled = cfg_updateNotificationsEnabledDefault
        cfg_autoUpdateEnabled = cfg_autoUpdateEnabledDefault
        cfg_autoUpdateIntervalHours = cfg_autoUpdateIntervalHoursDefault
        cfg_menuBarDisplayMode = cfg_menuBarDisplayModeDefault
        cfg_showPopupTabLabels = cfg_showPopupTabLabelsDefault
        cfg_providerOrder = cfg_providerOrderDefault
        cfg_resetTimesShowAbsolute = cfg_resetTimesShowAbsoluteDefault
        cfg_showProviderChangelogs = cfg_showProviderChangelogsDefault
        cfg_showProviderInPanel = cfg_showProviderInPanelDefault
        cfg_showPercentInPanel = cfg_showPercentInPanelDefault
        cfg_showMultiProviderInPanel = cfg_showMultiProviderInPanelDefault
        cfg_panelElementOrder = cfg_panelElementOrderDefault
        cfg_autoSelectProvider = cfg_autoSelectProviderDefault
        cfg_overviewProviderIDs = cfg_overviewProviderIDsDefault
        cfg_showCreditsInPanel = cfg_showCreditsInPanelDefault
        defaultsActionRequested = true
    }

    function saveConfig() {
        applyCostHistoryDaysTransition(ConfigValueSync.afterSave(cfg_costHistoryDays))
        applyCostHistoryMetricTransition(ConfigValueSync.afterSave(cfg_costHistoryMetric))
        defaultsActionRequested = false
    }

    Kirigami.FormLayout {
        // Bound supporting text below so its implicit width cannot force the
        // whole form into narrow mode or push content past the viewport.
        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Command")
            Kirigami.FormData.isSection: true
        }

        RowLayout {
            id: commandPathRow

            Kirigami.FormData.label: i18n("Command path:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            // FormLayout can stretch nested layouts as the KCM grows, so cap
            // this row to keep its trailing action inside the viewport.
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24

            Controls.TextField {
                id: commandPathField
                Layout.fillWidth: true
                placeholderText: "codexbar"
            }

            Controls.Button {
                id: usePathCommandButton
                text: i18n("Use PATH")
                enabled: page.cfg_commandPath.trim() !== (page.cfg_commandPathDefault || "codexbar")
                onClicked: page.cfg_commandPath = page.cfg_commandPathDefault || "codexbar"
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Refresh")
            Kirigami.FormData.isSection: true
        }

        Controls.ComboBox {
            id: refreshPresetCombo
            Kirigami.FormData.label: i18n("Usage refresh:")
            textRole: "text"
            valueRole: "value"
            model: [
                { text: i18n("No periodic refresh"), value: 0 },
                { text: i18n("1 min"), value: 60 },
                { text: i18n("2 min"), value: 120 },
                { text: i18n("5 min"), value: 300 },
                { text: i18n("15 min"), value: 900 },
                { text: i18n("Custom"), value: -1 }
            ]
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
            Component.onCompleted: currentIndex = page.refreshPresetIndex(page.cfg_refreshInterval)
            onActivated: {
                if (currentValue >= 0) {
                    page.cfg_refreshInterval = currentValue
                }
            }
        }

        Controls.SpinBox {
            id: refreshIntervalSpin
            Kirigami.FormData.label: i18n("Custom interval:")
            from: 0
            to: 3600
            stepSize: 10
            editable: true
            visible: refreshPresetCombo.currentValue < 0
            textFromValue: function(value, locale) {
                return value <= 0 ? i18n("No periodic refresh") : i18n("%1 s", value)
            }
            valueFromText: function(text, locale) {
                var match = text.match(/\d+/)
                return match ? parseInt(match[0], 10) : 300
            }
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
        }

        Controls.CheckBox {
            id: includeStatusCheck
            Layout.fillWidth: true
            text: i18n("Fetch provider service status")
        }

        Components.PlainControlsLabel {
            text: i18n("Required for status incident notifications.")
            opacity: 0.7
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Usage")
            Kirigami.FormData.isSection: true
        }

        Controls.CheckBox {
            id: costUsageEnabledCheck
            Layout.fillWidth: true
            text: i18n("Load local usage and spend history")
        }

        Controls.SpinBox {
            id: costHistoryDaysSpin
            Kirigami.FormData.label: i18n("History window:")
            from: 1
            to: 365
            editable: true
            textFromValue: function(value, locale) {
                return i18np("%1 day", "%1 days", value)
            }
            valueFromText: function(text, locale) {
                var match = text.match(/\d+/)
                return match ? parseInt(match[0], 10) : page.cfg_costHistoryDays
            }
            enabled: costUsageEnabledCheck.checked
            Layout.preferredWidth: Kirigami.Units.gridUnit * 8
            // valueModified fires on user edits only, so config-driven value
            // changes do not become pending edits and echo back on Apply. The
            // user edit severs the value binding, so re-install it here; other
            // pages follow the same pattern after interactive writes.
            value: page.cfg_costHistoryDays
            onValueModified: {
                page.editCostHistoryDays(value)
                value = Qt.binding(function() { return page.cfg_costHistoryDays })
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Notifications")
            Kirigami.FormData.isSection: true
        }

        Controls.CheckBox {
            id: enableNotificationsCheck
            Layout.fillWidth: true
            text: i18n("Enable Plasma notifications")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.CheckBox {
                id: notifyStatusIncidentsCheck
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit
                text: i18n("Notify status incidents")
                enabled: enableNotificationsCheck.checked && includeStatusCheck.checked
            }

            Controls.CheckBox {
                id: notifyQuotaWarningsCheck
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit
                text: i18n("Notify quota warnings")
                enabled: enableNotificationsCheck.checked
            }

            Controls.CheckBox {
                id: notifyPredictivePaceWarningsCheck
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit
                text: i18n("Notify predicted quota exhaustion")
                enabled: enableNotificationsCheck.checked
                Controls.ToolTip.text: i18n("Uses the pace forecast reported by codexbar.")
                Controls.ToolTip.visible: hovered
            }

            Controls.CheckBox {
                id: notifyLimitResetsCheck
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit
                text: i18n("Notify limit resets")
                enabled: enableNotificationsCheck.checked
            }
        }

        Controls.SpinBox {
            id: quotaWarningPercentSpin
            Kirigami.FormData.label: i18n("Quota warning at:")
            from: 1
            to: 99
            editable: true
            textFromValue: function(value, locale) {
                return i18n("%1% used", value)
            }
            valueFromText: function(text, locale) {
                var match = text.match(/\d+/)
                return match ? parseInt(match[0], 10) : 80
            }
            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
        }

        Controls.SpinBox {
            id: quotaCriticalPercentSpin
            Kirigami.FormData.label: i18n("Quota critical at:")
            // Keeping the floor on the warning value makes the "critical is never
            // below warning" rule visible here instead of only correcting it at
            // runtime, where the widget would silently ignore the entered number.
            from: quotaWarningPercentSpin.value
            to: 100
            editable: true
            textFromValue: function(value, locale) {
                return i18n("%1% used", value)
            }
            valueFromText: function(text, locale) {
                var match = text.match(/\d+/)
                return match ? parseInt(match[0], 10) : 95
            }
            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
        }

        Components.PlainControlsLabel {
            text: i18n("Thresholds also set warning colors and markers on usage meters.")
            opacity: 0.7
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Updates")
            Kirigami.FormData.isSection: true
        }

        Controls.CheckBox {
            id: updateChecksEnabledCheck
            Layout.fillWidth: true
            text: i18n("Check for widget updates")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.CheckBox {
                id: updateNotificationsEnabledCheck
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit
                text: i18n("Notify when a widget update is available")
                enabled: updateChecksEnabledCheck.checked && enableNotificationsCheck.checked
            }

            Controls.CheckBox {
                id: autoUpdateEnabledCheck
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit
                text: i18n("Install widget updates automatically")
                enabled: updateChecksEnabledCheck.checked
            }
        }

        Controls.SpinBox {
            id: autoUpdateIntervalHoursSpin
            Kirigami.FormData.label: i18n("Check every:")
            from: 1
            to: 168
            editable: true
            enabled: updateChecksEnabledCheck.checked
            textFromValue: function(value, locale) {
                return i18np("%1 hour", "%1 hours", value)
            }
            valueFromText: function(text, locale) {
                var match = text.match(/\d+/)
                return match ? parseInt(match[0], 10) : 24
            }
            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
        }

        Components.PlainControlsLabel {
            id: lastUpdateCheckLabel

            text: page.lastUpdateCheckText(autoUpdateLastCheck)
            visible: updateChecksEnabledCheck.checked
            opacity: 0.7
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
        }

        Components.PlainControlsLabel {
            id: lastUpdateStatusLabel

            text: i18n("Last update status: %1", widgetUpdateLastStatus)
            visible: updateChecksEnabledCheck.checked && widgetUpdateLastStatus.length > 0
            opacity: 0.7
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
        }

        Components.PlainInlineMessage {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            type: Kirigami.MessageType.Error
            plainText: widgetUpdateLastError.slice(0, 500)
            visible: updateChecksEnabledCheck.checked && widgetUpdateLastError.length > 0
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Defaults")
            Kirigami.FormData.isSection: true
        }

        Components.PlainControlsLabel {
            text: i18n("Restore every user-facing setting from General, Display, and Advanced. Provider accounts and CodexBar CLI configuration are not changed.")
            opacity: 0.7
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
        }

        Controls.Button {
            id: restoreAllDefaultsButton

            text: i18n("Restore all defaults")
            icon.name: "edit-undo"
            enabled: !page.userSettingsAreDefault()
            onClicked: page.restoreUserDefaults()
        }

        Components.PlainInlineMessage {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            type: Kirigami.MessageType.Information
            visible: page.defaultValuesPrepared
            plainText: i18n("Default values are ready. Select Apply or OK to save them, or Cancel to keep the current settings.")
        }
    }
}
