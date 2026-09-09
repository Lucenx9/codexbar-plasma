import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import "components" as Components

KCM.SimpleKCM {
    id: page

    property alias cfg_enableNotifications: enableNotificationsCheck.checked
    property bool cfg_enableNotificationsDefault: true
    property alias cfg_notifyStatusIncidents: notifyStatusIncidentsCheck.checked
    property bool cfg_notifyStatusIncidentsDefault: true
    property alias cfg_notifyQuotaWarnings: notifyQuotaWarningsCheck.checked
    property bool cfg_notifyQuotaWarningsDefault: true
    property alias cfg_notifyPredictivePaceWarnings: notifyPredictivePaceWarningsCheck.checked
    property bool cfg_notifyPredictivePaceWarningsDefault: false
    property alias cfg_notifyLimitResets: notifyLimitResetsCheck.checked
    property bool cfg_notifyLimitResetsDefault: false
    property alias cfg_quotaWarningPercent: quotaWarningPercentSpin.value
    property int cfg_quotaWarningPercentDefault: 80
    property alias cfg_quotaCriticalPercent: quotaCriticalPercentSpin.value
    property int cfg_quotaCriticalPercentDefault: 95
    readonly property bool includeStatus: Plasmoid.configuration ? Plasmoid.configuration.includeStatus === true : false

    Kirigami.FormLayout {
        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Quota warnings")
            Kirigami.FormData.isSection: true
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
            onValueChanged: if (quotaCriticalPercentSpin.value < value) {
                quotaCriticalPercentSpin.value = value
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

                Components.PlainToolTip {
                    parent: notifyPredictivePaceWarningsCheck
                    plainText: i18n("Uses the pace forecast reported by codexbar.")
                    visible: notifyPredictivePaceWarningsCheck.hovered
                    delay: Kirigami.Units.toolTipDelay
                }
            }

            Controls.CheckBox {
                id: notifyLimitResetsCheck
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit
                text: i18n("Notify limit resets")
                enabled: enableNotificationsCheck.checked
            }

            Controls.CheckBox {
                id: notifyStatusIncidentsCheck
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit
                text: i18n("Notify status incidents")
                enabled: enableNotificationsCheck.checked && page.includeStatus
            }
        }

        Components.PlainControlsLabel {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            text: i18n("Enable provider service status in General to receive incident notifications.")
            visible: !page.includeStatus
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WordWrap
        }
    }
}
