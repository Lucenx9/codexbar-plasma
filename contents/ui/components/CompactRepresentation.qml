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

        Repeater {
            model: compactRoot.applet.panelElementOrder()

            delegate: Loader {
                id: elementLoader

                required property var modelData

                readonly property bool isTextElement: modelData === "text"
                readonly property bool elementVisible: modelData === "identity"
                    ? compactRoot.showPrimaryIdentity
                    : (modelData === "status"
                    ? (!compactRoot.verticalPanel
                        && compactRoot.incidentProvider !== null
                        && compactRoot.incidentProvider.hasIncident)
                    : (modelData === "text"
                    ? (!compactRoot.verticalPanel && compactRoot.primaryText.length > 0)
                    : (!compactRoot.verticalPanel && compactRoot.applet.compactProviders().length > 0)))

                sourceComponent: modelData === "identity"
                    ? identityElement
                    : (modelData === "status"
                    ? statusElement
                    : (modelData === "text" ? textElement : metersElement))
                visible: elementVisible
                Layout.fillWidth: isTextElement && elementVisible
                Layout.preferredWidth: !elementVisible
                    ? 0
                    : (modelData === "identity"
                    ? Kirigami.Units.iconSizes.smallMedium
                    : (modelData === "status"
                    ? Kirigami.Units.smallSpacing * 1.5
                    : (modelData === "meters"
                    ? compactRoot.applet.compactProviders().length * Kirigami.Units.gridUnit * 1.15
                        + Math.max(0, compactRoot.applet.compactProviders().length - 1) * Kirigami.Units.smallSpacing
                    : Math.max(Kirigami.Units.gridUnit * 2,
                        elementLoader.implicitWidth))))
                Layout.preferredHeight: compactRow.height
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    Component {
        id: identityElement

        Item {
            readonly property string compactProvider: compactRoot.applet.selectedCompactProvider()
                ? compactRoot.applet.selectedCompactProvider().provider
                : "codex"

            visible: compactRoot.showPrimaryIdentity
            implicitWidth: Kirigami.Units.iconSizes.smallMedium
            implicitHeight: Kirigami.Units.iconSizes.smallMedium

            Kirigami.Icon {
                id: compactIdentityIcon

                anchors.fill: parent
                source: compactRoot.applet.loading ? "view-refresh" : compactRoot.applet.providerIconSource(parent.compactProvider)
                fallback: "view-statistics"
                isMask: !compactRoot.applet.loading && compactRoot.applet.providerIconIsMask(parent.compactProvider)
                color: compactRoot.applet.loading
                    ? Kirigami.Theme.textColor
                    : compactRoot.applet.providerReadableColor(parent.compactProvider, Kirigami.Theme.backgroundColor)

                RotationAnimator {
                    target: compactIdentityIcon
                    running: compactRoot.applet.loading
                    from: 0
                    to: 360
                    duration: 1250
                    loops: Animation.Infinite
                    onStopped: compactIdentityIcon.rotation = 0
                }

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
        }
    }

    Component {
        id: statusElement

        Rectangle {
            id: compactStatusBadge

            visible: !compactRoot.verticalPanel
                && compactRoot.incidentProvider !== null
                && compactRoot.incidentProvider.hasIncident
            implicitWidth: Kirigami.Units.smallSpacing * 1.5
            implicitHeight: implicitWidth
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
    }

    Component {
        id: textElement

        PlasmaComponents.Label {
            visible: !compactRoot.verticalPanel && compactRoot.primaryText.length > 0
            text: compactRoot.primaryText
            elide: Text.ElideRight
            font.bold: true
        }
    }

    Component {
        id: metersElement

        RowLayout {
            visible: !compactRoot.verticalPanel && compactRoot.applet.compactProviders().length > 0
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: compactRoot.applet.compactProviders()

                delegate: Item {
                    id: compactMeter

                    required property var modelData
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
                            source: compactRoot.applet.providerIconSource(compactMeter.modelData.provider)
                            fallback: "view-statistics"
                            isMask: compactRoot.applet.providerIconIsMask(compactMeter.modelData.provider)
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
}
