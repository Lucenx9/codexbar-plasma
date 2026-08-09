import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: compactRoot

    required property var applet

    readonly property bool verticalPanel: applet.verticalFormFactor
    readonly property bool hasProviderMeters: applet.compactProviders().length > 0
    readonly property var incidentProvider: applet.primaryIncidentProvider()
    readonly property string primaryText: applet.compactText()
    readonly property bool showPrimaryIdentity: verticalPanel || !hasProviderMeters || primaryText.length > 0
    readonly property int compactExtent: Kirigami.Units.iconSizes.smallMedium
        + Kirigami.Units.smallSpacing * 2
    readonly property int desiredWidth: verticalPanel
        ? compactExtent
        : Math.min(
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
        cursorShape: Qt.PointingHandCursor
        onClicked: compactRoot.applet.expanded = !compactRoot.applet.expanded
    }

    RowLayout {
        id: compactRow

        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            id: compactIdentityIcon

            readonly property string compactProvider: compactRoot.applet.selectedCompactProvider() ? compactRoot.applet.selectedCompactProvider().provider : "codex"

            visible: compactRoot.showPrimaryIdentity
            source: compactRoot.applet.loading ? "view-refresh" : compactRoot.applet.providerIconSource(compactProvider)
            isMask: !compactRoot.applet.loading && compactRoot.applet.providerIconIsMask(compactProvider)
            color: compactRoot.applet.loading
                ? Kirigami.Theme.textColor
                : compactRoot.applet.providerReadableColor(compactProvider, Kirigami.Theme.backgroundColor)
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            Layout.alignment: Qt.AlignCenter

            RotationAnimator {
                target: compactIdentityIcon
                running: compactRoot.applet.loading
                from: 0
                to: 360
                duration: 1250
                loops: Animation.Infinite
                onStopped: compactIdentityIcon.rotation = 0
            }

            // The inline badge below needs horizontal room the vertical strip does
            // not have, so overlay the incident marker on the identity icon instead
            // of dropping the only at-a-glance status signal. Hidden while the icon
            // spins so the marker does not orbit the refresh indicator.
            Rectangle {
                id: compactVerticalStatusBadge

                visible: compactRoot.verticalPanel
                    && !compactRoot.applet.loading
                    && compactRoot.incidentProvider !== null
                    && compactRoot.incidentProvider.hasIncident
                anchors.top: parent.top
                anchors.right: parent.right
                width: Math.round(Kirigami.Units.iconSizes.smallMedium / 3)
                height: width
                radius: width / 2
                color: compactRoot.incidentProvider
                    ? compactRoot.applet.statusBadgeColor(compactRoot.incidentProvider.statusSeverity)
                    : "transparent"
                border.width: 1
                border.color: Kirigami.Theme.backgroundColor
            }
        }

        Rectangle {
            id: compactStatusBadge

            visible: !compactRoot.verticalPanel
                && compactRoot.incidentProvider !== null
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
                acceptedButtons: Qt.NoButton
            }
        }

        PlasmaComponents.Label {
            visible: !compactRoot.verticalPanel && compactRoot.primaryText.length > 0
            text: compactRoot.primaryText
            elide: Text.ElideRight
            font.bold: true
            Layout.fillWidth: true
        }

        Repeater {
            model: compactRoot.verticalPanel ? [] : compactRoot.applet.compactProviders()

            delegate: Item {
                id: compactMeter

                readonly property real meter: compactRoot.applet.switcherPercent(modelData)
                readonly property color accent: compactRoot.applet.providerReadableColor(
                    modelData.provider,
                    Kirigami.Theme.backgroundColor)

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

                            Behavior on width {
                                NumberAnimation {
                                    duration: Kirigami.Units.longDuration
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
