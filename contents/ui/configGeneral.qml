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
    property alias cfg_enableNotifications: enableNotificationsCheck.checked
    property bool cfg_enableNotificationsDefault
    property alias cfg_notifyStatusIncidents: notifyStatusIncidentsCheck.checked
    property bool cfg_notifyStatusIncidentsDefault
    property alias cfg_notifyQuotaWarnings: notifyQuotaWarningsCheck.checked
    property bool cfg_notifyQuotaWarningsDefault
    property alias cfg_notifyLimitResets: notifyLimitResetsCheck.checked
    property bool cfg_notifyLimitResetsDefault
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
    }
}
