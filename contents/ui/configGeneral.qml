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

    property string cfg_commandPath
    // cfg_*Default mirrors the schema default in contents/config/main.xml.
    // Plasma's configuration map also exposes a <key>Default entry, so the
    // config dialog injects cfg_<key>Default over these initializers
    // (plasma-workspace 6.7.4); they stay the portable fallback for loaders that
    // do not, and the restore-defaults action reads them either way.
    // scripts/test_ui_regressions.sh checks them against main.xml for drift.
    property string cfg_commandPathDefault: "codexbar"
    property alias cfg_refreshOnOpen: refreshOnOpenCheck.checked
    property bool cfg_refreshOnOpenDefault: true
    property alias cfg_privacyMode: privacyModeCheck.checked
    property bool cfg_privacyModeDefault: false
    property bool cfg_showPopupPace
    property bool cfg_showPopupPaceDefault: true
    property bool cfg_showPopupCredits
    property bool cfg_showPopupCreditsDefault: true
    property bool cfg_showPopupProviderDetails
    property bool cfg_showPopupProviderDetailsDefault: true
    property alias cfg_refreshInterval: refreshIntervalSpin.value
    property int cfg_refreshIntervalDefault: 300
    property alias cfg_includeStatus: includeStatusCheck.checked
    property bool cfg_includeStatusDefault: false
    property alias cfg_costUsageEnabled: costUsageEnabledCheck.checked
    property bool cfg_costUsageEnabledDefault: true
    property int cfg_costHistoryDays: 30
    property int cfg_costHistoryDaysDefault: 30
    property bool cfg_enableNotifications
    property bool cfg_enableNotificationsDefault: true
    property bool cfg_notifyStatusIncidents
    property bool cfg_notifyStatusIncidentsDefault: true
    property bool cfg_notifyQuotaWarnings
    property bool cfg_notifyQuotaWarningsDefault: true
    property bool cfg_notifyPredictivePaceWarnings
    property bool cfg_notifyPredictivePaceWarningsDefault: false
    property bool cfg_notifyLimitResets
    property bool cfg_notifyLimitResetsDefault: false
    property int cfg_quotaWarningPercent
    property int cfg_quotaWarningPercentDefault: 80
    property int cfg_quotaCriticalPercent
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
    // user-facing values from every page here as well so one global reset
    // remains pending until Apply/OK instead of writing configuration directly.
    property string cfg_provider
    property string cfg_providerDefault: ""
    property string cfg_source
    property string cfg_sourceDefault: ""
    property bool cfg_usageBarsShowUsed
    property bool cfg_usageBarsShowUsedDefault: true
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
    property bool cfg_showProviderInPanelDefault: false
    property string cfg_panelStyle
    property string cfg_panelStyleDefault: "standard"
    property bool cfg_showPercentInPanel
    property bool cfg_showPercentInPanelDefault: false
    property bool cfg_showMultiProviderInPanel
    property bool cfg_showMultiProviderInPanelDefault: true
    property string cfg_panelElementOrder
    property string cfg_panelElementOrderDefault: "identity,status,text,meters"
    property string cfg_panelQuotaLane
    property string cfg_panelQuotaLaneDefault: "auto"
    property string cfg_panelVisibilityRules
    property string cfg_panelVisibilityRulesDefault: "{}"
    property bool cfg_autoSelectProvider
    property bool cfg_autoSelectProviderDefault: false
    property string cfg_overviewProviderIDs
    property string cfg_overviewProviderIDsDefault: ""
    property string cfg_panelProviderIDs
    property string cfg_panelProviderIDsDefault: ""
    property bool cfg_showCreditsInPanel
    property bool cfg_showCreditsInPanelDefault: false

    property bool defaultsActionRequested: false
    // Plasma supplies cfg_* values as creation-time properties, which replaces
    // bindings declared on them. Track runtime-owned values separately and
    // copy them into the pending KCM state only while the user has no edit.
    // Each read stays guarded like the one on Notifications, so building the
    // page without a plasmoid resolves to the schema default instead of raising
    // a TypeError for every runtime-owned binding.
    readonly property int persistedCostHistoryDays: Plasmoid.configuration
        ? Plasmoid.configuration.costHistoryDays : cfg_costHistoryDaysDefault
    readonly property string persistedCostHistoryMetric: Plasmoid.configuration
        ? Plasmoid.configuration.costHistoryMetric : cfg_costHistoryMetricDefault
    property bool costHistoryDaysEditPending: false
    property bool costHistoryMetricEditPending: false
    readonly property bool defaultValuesPrepared: defaultsActionRequested
        && userSettingsAreDefault()
    readonly property string autoUpdateLastCheck: Plasmoid.configuration
        ? Plasmoid.configuration.autoUpdateLastCheck || "" : ""
    readonly property string widgetUpdateLastStatus: Plasmoid.configuration
        ? Plasmoid.configuration.widgetUpdateLastStatus || "" : ""
    readonly property string widgetUpdateLastError: Plasmoid.configuration
        ? Plasmoid.configuration.widgetUpdateLastError || "" : ""

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
            [cfg_refreshOnOpen, cfg_refreshOnOpenDefault],
            [cfg_privacyMode, cfg_privacyModeDefault],
            [cfg_showPopupPace, cfg_showPopupPaceDefault],
            [cfg_showPopupCredits, cfg_showPopupCreditsDefault],
            [cfg_showPopupProviderDetails, cfg_showPopupProviderDetailsDefault],
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
            [cfg_panelStyle, cfg_panelStyleDefault],
            [cfg_showPercentInPanel, cfg_showPercentInPanelDefault],
            [cfg_showMultiProviderInPanel, cfg_showMultiProviderInPanelDefault],
            [cfg_panelElementOrder, cfg_panelElementOrderDefault],
            [cfg_panelQuotaLane, cfg_panelQuotaLaneDefault],
            [cfg_panelVisibilityRules, cfg_panelVisibilityRulesDefault],
            [cfg_autoSelectProvider, cfg_autoSelectProviderDefault],
            [cfg_overviewProviderIDs, cfg_overviewProviderIDsDefault],
            [cfg_panelProviderIDs, cfg_panelProviderIDsDefault],
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
        cfg_refreshOnOpen = cfg_refreshOnOpenDefault
        cfg_privacyMode = cfg_privacyModeDefault
        cfg_showPopupPace = cfg_showPopupPaceDefault
        cfg_showPopupCredits = cfg_showPopupCreditsDefault
        cfg_showPopupProviderDetails = cfg_showPopupProviderDetailsDefault
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
        cfg_panelStyle = cfg_panelStyleDefault
        cfg_showPercentInPanel = cfg_showPercentInPanelDefault
        cfg_showMultiProviderInPanel = cfg_showMultiProviderInPanelDefault
        cfg_panelElementOrder = cfg_panelElementOrderDefault
        cfg_panelQuotaLane = cfg_panelQuotaLaneDefault
        cfg_panelVisibilityRules = cfg_panelVisibilityRulesDefault
        cfg_autoSelectProvider = cfg_autoSelectProviderDefault
        cfg_overviewProviderIDs = cfg_overviewProviderIDsDefault
        cfg_panelProviderIDs = cfg_panelProviderIDsDefault
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
            Kirigami.FormData.label: i18n("Refresh")
            Kirigami.FormData.isSection: true
        }

        Controls.ComboBox {
            id: refreshPresetCombo
            objectName: "refreshPresetCombo"
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
            objectName: "refreshIntervalSpin"
            Kirigami.FormData.label: i18n("Custom interval:")
            from: 0
            to: 3600
            stepSize: 10
            editable: true
            visible: refreshPresetCombo.currentValue < 0
            textFromValue: function(value, locale) {
                return value <= 0 ? i18n("No periodic refresh") : i18n("%1 s", value)
            }
            // "No periodic refresh" and cleared text carry no digits. Keeping the
            // current value leaves the stored interval alone instead of writing
            // an unrelated preset over it.
            valueFromText: function(text, locale) {
                var match = text.match(/\d+/)
                return match ? parseInt(match[0], 10) : value
            }
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
        }

        Controls.CheckBox {
            id: refreshOnOpenCheck
            objectName: "refreshOnOpenCheck"
            implicitWidth: 0
            Layout.fillWidth: true
            text: i18n("Refresh when opening the popup")
        }

        Components.PlainControlsLabel {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            text: i18n("Refreshes quota data when needed, including when periodic refresh is disabled.")
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WordWrap
        }

        Controls.CheckBox {
            id: includeStatusCheck
            implicitWidth: 0
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
            Kirigami.FormData.label: i18n("Privacy")
            Kirigami.FormData.isSection: true
        }

        Controls.CheckBox {
            id: privacyModeCheck
            objectName: "privacyModeCheck"
            implicitWidth: 0
            Layout.fillWidth: true
            text: i18n("Hide personal information")
        }

        Components.PlainControlsLabel {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            text: i18n("Hides account identities and project or session names in the panel, popup and tooltips. Saved data is unchanged.")
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WordWrap
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Usage history")
            Kirigami.FormData.isSection: true
        }

        Controls.CheckBox {
            id: costUsageEnabledCheck
            implicitWidth: 0
            Layout.fillWidth: true
            text: i18n("Load local usage and spend history")
        }

        Controls.SpinBox {
            id: costHistoryDaysSpin
            objectName: "costHistoryDaysSpin"
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
            Kirigami.FormData.label: i18n("Updates")
            Kirigami.FormData.isSection: true
        }

        Controls.CheckBox {
            id: updateChecksEnabledCheck
            implicitWidth: 0
            Layout.fillWidth: true
            text: i18n("Check for widget updates")
        }

        Controls.SpinBox {
            id: autoUpdateIntervalHoursSpin
            objectName: "autoUpdateIntervalHoursSpin"
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
                return match ? parseInt(match[0], 10) : value
            }
            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.CheckBox {
                id: updateNotificationsEnabledCheck
                implicitWidth: 0
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit
                text: i18n("Notify when a widget update is available")
                enabled: updateChecksEnabledCheck.checked && page.cfg_enableNotifications
            }

            Controls.CheckBox {
                id: autoUpdateEnabledCheck
                implicitWidth: 0
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit
                text: i18n("Install widget updates automatically")
                enabled: updateChecksEnabledCheck.checked
            }
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
            text: i18n("Restore every widget setting. Provider accounts and CodexBar CLI configuration are not changed.")
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
