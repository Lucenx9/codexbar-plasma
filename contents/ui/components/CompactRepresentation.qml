import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: compactRoot

    required property var applet

    readonly property bool hasProviderMeters: applet.compactProviders().length > 0
    readonly property var incidentProvider: applet.primaryIncidentProvider()
    readonly property string primaryText: applet.compactText()
    readonly property bool showPrimaryIdentity: !hasProviderMeters || primaryText.length > 0
    readonly property int desiredWidth: Math.min(
        Kirigami.Units.gridUnit * 8.5,
        Math.max(Kirigami.Units.gridUnit * 4.8,
            compactRow.implicitWidth + Kirigami.Units.smallSpacing * 2))

    Layout.minimumWidth: desiredWidth
    Layout.preferredWidth: desiredWidth
    Layout.maximumWidth: desiredWidth
    Layout.maximumHeight: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing * 2

    implicitWidth: desiredWidth
    implicitHeight: Layout.maximumHeight
    clip: true

    MouseArea {
        anchors.fill: parent
        onClicked: compactRoot.applet.expanded = !compactRoot.applet.expanded
    }

    RowLayout {
        id: compactRow

        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            readonly property string compactProvider: compactRoot.applet.selectedCompactProvider() ? compactRoot.applet.selectedCompactProvider().provider : "codex"

            visible: compactRoot.showPrimaryIdentity
            source: compactRoot.applet.loading ? "view-refresh" : compactRoot.applet.providerIconSource(compactProvider)
            isMask: !compactRoot.applet.loading && compactRoot.applet.providerIconIsMask(compactProvider)
            color: compactRoot.applet.loading ? Kirigami.Theme.textColor : compactRoot.applet.providerColor(compactProvider)
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
        }

        Rectangle {
            id: compactStatusBadge

            visible: compactRoot.incidentProvider !== null
                && compactRoot.incidentProvider.hasIncident
            Layout.preferredWidth: Kirigami.Units.smallSpacing * 1.5
            Layout.preferredHeight: Kirigami.Units.smallSpacing * 1.5
            radius: width / 2
            color: compactRoot.incidentProvider
                ? compactRoot.applet.statusBadgeColor(compactRoot.incidentProvider.statusSeverity)
                : "transparent"

            Controls.ToolTip.visible: compactStatusMouse.containsMouse
            Controls.ToolTip.text: compactRoot.incidentProvider
                ? i18n("%1: %2", compactRoot.incidentProvider.title, compactRoot.incidentProvider.status)
                : ""

            MouseArea {
                id: compactStatusMouse

                anchors.fill: parent
                hoverEnabled: true
            }
        }

        PlasmaComponents.Label {
            visible: compactRoot.primaryText.length > 0
            text: compactRoot.primaryText
            elide: Text.ElideRight
            font.bold: true
            Layout.fillWidth: true
        }

        Repeater {
            model: compactRoot.applet.compactProviders()

            delegate: Item {
                id: compactMeter

                readonly property real meter: compactRoot.applet.switcherPercent(modelData)
                readonly property color accent: compactRoot.applet.providerColor(modelData.provider)

                Layout.preferredWidth: Kirigami.Units.gridUnit * 1.15
                Layout.preferredHeight: compactRow.height

                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: 0

                    Kirigami.Icon {
                        source: compactRoot.applet.providerIconSource(modelData.provider)
                        isMask: compactRoot.applet.providerIconIsMask(modelData.provider)
                        color: compactMeter.accent
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 9
                        Layout.preferredHeight: 9
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 3
                        radius: height / 2
                        color: compactRoot.applet.withAlpha(compactMeter.accent, 0.28)
                        clip: true

                        Rectangle {
                            visible: compactMeter.meter >= 0
                            width: compactMeter.meter <= 0
                                ? 0
                                : Math.max(parent.height, parent.width * Math.max(0, Math.min(100, compactMeter.meter)) / 100)
                            height: parent.height
                            radius: parent.radius
                            color: compactMeter.accent
                        }
                    }
                }
            }
        }
    }
}
