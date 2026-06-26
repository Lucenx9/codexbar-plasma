import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: page

    property alias cfg_commandPath: commandPathField.text
    property string cfg_commandPathDefault
    property alias cfg_provider: providerField.text
    property string cfg_providerDefault
    property alias cfg_source: sourceField.text
    property string cfg_sourceDefault
    property alias cfg_refreshInterval: refreshIntervalSpin.value
    property int cfg_refreshIntervalDefault
    property alias cfg_includeStatus: includeStatusCheck.checked
    property bool cfg_includeStatusDefault
    property alias cfg_usageBarsShowUsed: usageBarsShowUsedCheck.checked
    property bool cfg_usageBarsShowUsedDefault
    property alias cfg_showQuotaWarningMarkers: showQuotaWarningMarkersCheck.checked
    property bool cfg_showQuotaWarningMarkersDefault
    property alias cfg_enableNotifications: enableNotificationsCheck.checked
    property bool cfg_enableNotificationsDefault
    property alias cfg_notifyStatusIncidents: notifyStatusIncidentsCheck.checked
    property bool cfg_notifyStatusIncidentsDefault
    property alias cfg_notifyQuotaWarnings: notifyQuotaWarningsCheck.checked
    property bool cfg_notifyQuotaWarningsDefault
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
    property alias cfg_showCreditsInPanel: showCreditsCheck.checked
    property bool cfg_showCreditsInPanelDefault
    property int cfg_providerConfigRevision
    property int cfg_providerConfigRevisionDefault

    function displayModeIndex(value) {
        for (var i = 0; i < displayModeCombo.model.length; i++) {
            if (displayModeCombo.model[i].value === value) {
                return i
            }
        }
        return 0
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

    onCfg_refreshIntervalChanged: {
        var nextIndex = refreshPresetIndex(cfg_refreshInterval)
        if (refreshPresetCombo.currentIndex !== nextIndex) {
            refreshPresetCombo.currentIndex = nextIndex
        }
    }

    onCfg_menuBarDisplayModeChanged: {
        var nextIndex = displayModeIndex(cfg_menuBarDisplayMode)
        if (displayModeCombo.currentIndex !== nextIndex) {
            displayModeCombo.currentIndex = nextIndex
        }
    }

    Kirigami.FormLayout {
        Controls.TextField {
            id: commandPathField
            Kirigami.FormData.label: i18n("Command path:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 18
            placeholderText: "codexbar"
        }

        Controls.TextField {
            id: providerField
            Kirigami.FormData.label: i18n("Provider:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 18
            placeholderText: i18n("Provider id (blank = all enabled)")
        }

        Controls.Label {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 18
            Layout.maximumWidth: Kirigami.Units.gridUnit * 18
            text: i18n("Advanced override: pin the panel to a single provider id. Leave blank to show every provider enabled on the Providers page.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.WordWrap
        }

        Controls.TextField {
            id: sourceField
            Kirigami.FormData.label: i18n("Source:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 18
            placeholderText: i18n("Provider default (blank)")
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
            id: usageBarsShowUsedCheck
            text: i18n("Show usage as percent used")
        }

        Controls.CheckBox {
            id: showQuotaWarningMarkersCheck
            text: i18n("Show quota warning markers")
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

        Controls.CheckBox {
            id: showCreditsCheck
            text: i18n("Show credits in panel")
        }
    }
}
