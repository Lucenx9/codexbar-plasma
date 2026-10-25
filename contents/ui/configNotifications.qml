import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import "components" as Components

KCM.SimpleKCM {
    id: page

    readonly property Controls.ScrollView scrollView: contentItem as Controls.ScrollView

    // Reserve the themed scrollbar width even when initial overflow disappears.
    Binding {
        target: page.scrollView
        property: page.mirrored ? "leftPadding" : "rightPadding"
        value: page.scrollView.Controls.ScrollBar.vertical.implicitWidth
    }

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
            objectName: "quotaWarningPercentSpin"
            Kirigami.FormData.label: i18n("Quota warning (% used):")
            from: 1
            to: 99
            editable: true
            // Unparsable text keeps the current threshold. Substituting the
            // schema default here would move a configured threshold silently.
            valueFromText: function(text, locale) {
                try {
                    var localized = Number.fromLocaleString(locale, text)
                    if (isFinite(localized)) {
                        return localized
                    }
                } catch (error) {
                    // Invalid locale text still needs the compatibility fallback.
                }
                var match = text.match(/\d+/)
                return match ? parseInt(match[0], 10) : value
            }
            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
        }

        Controls.SpinBox {
            id: quotaCriticalPercentSpin
            objectName: "quotaCriticalPercentSpin"
            Kirigami.FormData.label: i18n("Quota critical (% used):")
            // Keeping the floor on the warning value makes the "critical is never
            // below warning" rule visible here instead of only correcting it at
            // runtime, where the widget would silently ignore the entered number.
            from: quotaWarningPercentSpin.value
            to: 100
            editable: true
            valueFromText: function(text, locale) {
                try {
                    var localized = Number.fromLocaleString(locale, text)
                    if (isFinite(localized)) {
                        return localized
                    }
                } catch (error) {
                    // Invalid locale text still needs the compatibility fallback.
                }
                var match = text.match(/\d+/)
                return match ? parseInt(match[0], 10) : value
            }
            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
        }

        Components.PlainControlsLabel {
            text: i18n("Thresholds also set warning colors and markers on usage meters.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
        }

        ColumnLayout {
            objectName: "quotaColorPreview"
            Kirigami.FormData.label: i18n("Color preview:")
            Kirigami.FormData.labelAlignment: Qt.AlignTop
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                id: colorScale
                objectName: "quotaColorScale"
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.smallSpacing * 2
                radius: height / 2
                Accessible.ignored: true
                readonly property real firstBoundary: page.mirrored
                    ? 1 - page.cfg_quotaCriticalPercent / 100 : page.cfg_quotaWarningPercent / 100
                readonly property real secondBoundary: page.mirrored
                    ? 1 - page.cfg_quotaWarningPercent / 100 : page.cfg_quotaCriticalPercent / 100
                readonly property color lowColor: page.mirrored
                    ? (page.cfg_quotaCriticalPercent === 100 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.negativeTextColor)
                    : Kirigami.Theme.highlightColor
                readonly property color highColor: page.mirrored
                    ? Kirigami.Theme.highlightColor
                    : (page.cfg_quotaCriticalPercent === 100 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.negativeTextColor)
                readonly property color middleColor: page.cfg_quotaWarningPercent === page.cfg_quotaCriticalPercent
                    ? highColor : Kirigami.Theme.neutralTextColor

                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    // Qt merges coincident stops; distinct positions keep the severity boundaries sharp.
                    GradientStop { position: 0; color: colorScale.lowColor }
                    GradientStop { position: Math.max(0, colorScale.firstBoundary - 0.000001); color: colorScale.lowColor }
                    GradientStop { position: colorScale.firstBoundary; color: colorScale.middleColor }
                    GradientStop { position: Math.max(colorScale.firstBoundary, colorScale.secondBoundary - 0.000001); color: colorScale.middleColor }
                    GradientStop { position: colorScale.secondBoundary; color: colorScale.highColor }
                    GradientStop { position: 1; color: colorScale.highColor }
                }
            }

            // Swatches tie each legend to its color; label position along the
            // scale would only line up with one threshold pair.
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing * 2

                FontMetrics {
                    id: legendMetrics
                    font: Kirigami.Theme.smallFont
                }

                Repeater {
                    // A constant model keeps the legend items alive while thresholds change.
                    model: ["quotaWarningLegend", "quotaCriticalLegend"]

                    delegate: RowLayout {
                        required property int index
                        required property var modelData
                        readonly property bool critical: index === 1
                        // Pack legends at the start, yet let them shrink and wrap when narrow.
                        Layout.fillWidth: true
                        Layout.maximumWidth: implicitWidth
                        spacing: Kirigami.Units.smallSpacing

                        Rectangle {
                            objectName: modelData + "Swatch"
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: Math.max(0, Math.round((legendMetrics.height - height) / 2))
                            implicitWidth: Kirigami.Units.smallSpacing * 2
                            implicitHeight: implicitWidth
                            radius: width / 2
                            color: critical && page.cfg_quotaCriticalPercent !== 100
                                ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.neutralTextColor
                            Accessible.ignored: true
                        }

                        Components.PlainControlsLabel {
                            objectName: modelData
                            Layout.fillWidth: true
                            text: !critical
                                ? i18n("Warning from %1%", page.cfg_quotaWarningPercent.toLocaleString(Qt.locale(), 'f', 0))
                                : i18n("Critical from %1%", page.cfg_quotaCriticalPercent.toLocaleString(Qt.locale(), 'f', 0))
                            font: Kirigami.Theme.smallFont
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Notifications")
            Kirigami.FormData.isSection: true
        }

        Controls.CheckBox {
            id: enableNotificationsCheck
            implicitWidth: 0
            Layout.fillWidth: true
            text: i18n("Enable Plasma notifications")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.CheckBox {
                id: notifyQuotaWarningsCheck
                implicitWidth: 0
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit
                text: i18n("Notify quota warnings")
                enabled: enableNotificationsCheck.checked
            }

            Controls.CheckBox {
                id: notifyPredictivePaceWarningsCheck
                implicitWidth: 0
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit
                text: i18n("Notify predicted quota exhaustion")
                enabled: enableNotificationsCheck.checked

                Components.PlainToolTip {
                    parent: notifyPredictivePaceWarningsCheck
                    plainText: i18n("Uses the pace forecast reported by codexbar.")
                    visible: notifyPredictivePaceWarningsCheck.hovered || notifyPredictivePaceWarningsCheck.visualFocus
                    delay: Kirigami.Units.toolTipDelay
                }
            }

            Controls.CheckBox {
                id: notifyLimitResetsCheck
                implicitWidth: 0
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit
                text: i18n("Notify limit resets")
                enabled: enableNotificationsCheck.checked
            }

            Controls.CheckBox {
                id: notifyStatusIncidentsCheck
                objectName: "notifyStatusIncidentsCheck"
                implicitWidth: 0
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit
                text: i18n("Notify status incidents")
                enabled: enableNotificationsCheck.checked && page.includeStatus
            }

            // Explains the unavailable option directly below its label text.
            Components.PlainControlsLabel {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit
                    + notifyStatusIncidentsCheck.indicator.width + notifyStatusIncidentsCheck.spacing
                Layout.preferredWidth: Kirigami.Units.gridUnit * 24
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                text: i18n("Enable provider service status in General to receive incident notifications.")
                visible: !page.includeStatus
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                wrapMode: Text.WordWrap
            }
        }
    }
}
