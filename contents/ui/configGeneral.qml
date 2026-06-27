import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: page

    property alias cfg_commandPath: commandPathField.text
    property string cfg_commandPathDefault
    property alias cfg_refreshInterval: refreshIntervalSpin.value
    property int cfg_refreshIntervalDefault
    property alias cfg_includeStatus: includeStatusCheck.checked
    property bool cfg_includeStatusDefault
    property alias cfg_costUsageEnabled: costUsageEnabledCheck.checked
    property bool cfg_costUsageEnabledDefault
    property alias cfg_costHistoryDays: costHistoryDaysSpin.value
    property int cfg_costHistoryDaysDefault
    property alias cfg_enableNotifications: enableNotificationsCheck.checked
    property bool cfg_enableNotificationsDefault
    property alias cfg_notifyStatusIncidents: notifyStatusIncidentsCheck.checked
    property bool cfg_notifyStatusIncidentsDefault
    property alias cfg_notifyQuotaWarnings: notifyQuotaWarningsCheck.checked
    property bool cfg_notifyQuotaWarningsDefault
    property alias cfg_notifyLimitResets: notifyLimitResetsCheck.checked
    property bool cfg_notifyLimitResetsDefault
    property alias cfg_updateChecksEnabled: updateChecksEnabledCheck.checked
    property bool cfg_updateChecksEnabledDefault
    property alias cfg_updateNotificationsEnabled: updateNotificationsEnabledCheck.checked
    property bool cfg_updateNotificationsEnabledDefault
    property alias cfg_autoUpdateEnabled: autoUpdateEnabledCheck.checked
    property bool cfg_autoUpdateEnabledDefault
    property alias cfg_autoUpdateIntervalHours: autoUpdateIntervalHoursSpin.value
    property int cfg_autoUpdateIntervalHoursDefault
    property string cfg_autoUpdateLastCheck
    property string cfg_autoUpdateLastCheckDefault
    property string cfg_widgetUpdateLastStatus
    property string cfg_widgetUpdateLastStatusDefault
    property string cfg_widgetUpdateLastError
    property string cfg_widgetUpdateLastErrorDefault
    property int cfg_providerConfigRevision
    property int cfg_providerConfigRevisionDefault

    function refreshPresetIndex(value) {
        var numeric = Number(value)
        for (var i = 0; i < refreshPresetCombo.model.length; i++) {
            if (refreshPresetCombo.model[i].value === numeric) {
                return i
            }
        }
        return refreshPresetCombo.model.length - 1
    }

    onCfg_refreshIntervalChanged: {
        var nextIndex = refreshPresetIndex(cfg_refreshInterval)
        if (refreshPresetCombo.currentIndex !== nextIndex) {
            refreshPresetCombo.currentIndex = nextIndex
        }
    }

    Kirigami.FormLayout {
        Controls.TextField {
            id: commandPathField
            Kirigami.FormData.label: i18n("Command path:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 18
            placeholderText: "codexbar"
        }

        Controls.ComboBox {
            id: refreshPresetCombo
            Kirigami.FormData.label: i18n("Refresh preset:")
            textRole: "text"
            valueRole: "value"
            model: [
                { text: i18n("Manual"), value: 0 },
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
            Kirigami.FormData.label: i18n("Custom refresh:")
            from: 0
            to: 3600
            stepSize: 10
            editable: true
            visible: refreshPresetCombo.currentValue < 0
            textFromValue: function(value, locale) {
                return value <= 0 ? i18n("Manual") : i18n("%1 s", value)
            }
            valueFromText: function(text, locale) {
                var match = text.match(/\d+/)
                return match ? parseInt(match[0], 10) : 300
            }
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
        }

        Controls.CheckBox {
            id: includeStatusCheck
            text: i18n("Fetch provider status")
        }

        Controls.CheckBox {
            id: costUsageEnabledCheck
            text: i18n("Show local cost usage")
        }

        Controls.SpinBox {
            id: costHistoryDaysSpin
            Kirigami.FormData.label: i18n("Cost history days:")
            from: 1
            to: 365
            editable: true
            enabled: costUsageEnabledCheck.checked
            Layout.preferredWidth: Kirigami.Units.gridUnit * 8
        }

        Controls.CheckBox {
            id: enableNotificationsCheck
            text: i18n("Enable Plasma notifications")
        }

        Controls.CheckBox {
            id: notifyStatusIncidentsCheck
            text: i18n("Notify status incidents")
            enabled: enableNotificationsCheck.checked
        }

        Controls.CheckBox {
            id: notifyQuotaWarningsCheck
            text: i18n("Notify quota warnings")
            enabled: enableNotificationsCheck.checked
        }

        Controls.CheckBox {
            id: notifyLimitResetsCheck
            text: i18n("Notify limit resets")
            enabled: enableNotificationsCheck.checked
        }

        Controls.CheckBox {
            id: updateChecksEnabledCheck
            text: i18n("Check for widget updates")
        }

        Controls.CheckBox {
            id: updateNotificationsEnabledCheck
            text: i18n("Notify when a widget update is available")
            enabled: updateChecksEnabledCheck.checked && enableNotificationsCheck.checked
        }

        Controls.CheckBox {
            id: autoUpdateEnabledCheck
            text: i18n("Install widget updates automatically")
            enabled: updateChecksEnabledCheck.checked
        }

        Controls.SpinBox {
            id: autoUpdateIntervalHoursSpin
            Kirigami.FormData.label: i18n("Update check interval:")
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

        Controls.Label {
            id: lastUpdateCheckLabel

            text: cfg_autoUpdateLastCheck.length > 0
                ? i18n("Last update check: %1", cfg_autoUpdateLastCheck)
                : i18n("Last update check: never")
            visible: updateChecksEnabledCheck.checked
            opacity: 0.7
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Controls.Label {
            id: lastUpdateStatusLabel

            text: i18n("Last update status: %1", cfg_widgetUpdateLastStatus)
            visible: updateChecksEnabledCheck.checked && cfg_widgetUpdateLastStatus.length > 0
            opacity: 0.7
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Error
            text: String(cfg_widgetUpdateLastError || "").slice(0, 500)
            visible: updateChecksEnabledCheck.checked && cfg_widgetUpdateLastError.length > 0
        }
    }
}
