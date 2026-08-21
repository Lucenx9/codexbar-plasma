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
    // Panel meters scale with the panel thickness instead of using fixed pixel
    // sizes, which rendered them nearly unreadable on normal panels.
    readonly property int meterContentHeight: Math.max(0, height - Kirigami.Units.smallSpacing * 2)
    readonly property int meterSpacing: Math.max(1, Math.round(Kirigami.Units.smallSpacing / 2))
    readonly property int meterBarHeight: Math.max(3, Math.round(meterContentHeight * 0.2))
    readonly property int meterIconSize: Math.max(9, meterContentHeight - meterBarHeight - meterSpacing)
    readonly property int meterWidth: Math.max(Kirigami.Units.gridUnit * 1.6,
        meterIconSize + Kirigami.Units.smallSpacing)
    readonly property int maximumCompactWidth: Kirigami.Units.gridUnit * 18
    readonly property int desiredWidth: verticalPanel
        ? compactExtent
        : Math.min(
            maximumCompactWidth,
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

    // Measure outside the Loader so its layout-assigned width cannot feed back
    // into the label's preferred width and collapse the compact representation.
    PlasmaComponents.Label {
        id: compactTextMeasurer

        visible: false
        text: compactRoot.primaryText
        font.bold: true
    }

    RowLayout {
        id: compactRow

        // The applet keeps a minimum panel width, so a short content set (meters
        // without panel text) leaves spare room. Centre the row instead of
        // letting all of it pile up on the right of the content.
        anchors.centerIn: parent
        width: Math.max(0, Math.min(compactRoot.width - Kirigami.Units.smallSpacing * 2,
            implicitWidth))
        height: Math.max(0, compactRoot.height - Kirigami.Units.smallSpacing * 2)
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
                    ? compactRoot.applet.compactProviders().length * compactRoot.meterWidth
                        + Math.max(0, compactRoot.applet.compactProviders().length - 1) * Kirigami.Units.smallSpacing
                    : Math.max(Kirigami.Units.gridUnit * 2,
                        Math.ceil(compactTextMeasurer.implicitWidth)))))
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
            border.width: 1
            border.color: Kirigami.Theme.backgroundColor

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
            // The loader stretches this label to the full row height, so the
            // default top alignment would sit the text above the centred
            // provider icon beside it.
            verticalAlignment: Text.AlignVCenter
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
                    // The panel is the surface a user reads without opening
                    // anything, so it carries the same quota level as the popup
                    // meters instead of staying provider-coloured at 99% used.
                    readonly property color meterColor: compactRoot.applet.quotaMeterColor(
                        compactRoot.applet.switcherMetricRow(modelData),
                        accent)

                    function activate() {
                        compactRoot.applet.openProviderFromPanel(compactMeter.modelData.provider)
                    }

                    Layout.preferredWidth: compactRoot.meterWidth
                    Layout.preferredHeight: compactRow.height
                    activeFocusOnTab: true

                    Accessible.role: Accessible.Button
                    Accessible.name: i18n("Open %1", modelData.title)
                    Accessible.onPressAction: compactMeter.activate()

                    Keys.onPressed: function(event) {
                        switch (event.key) {
                        case Qt.Key_Space:
                        case Qt.Key_Enter:
                        case Qt.Key_Return:
                        case Qt.Key_Select:
                            compactMeter.activate()
                            event.accepted = true
                            break
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: compactMeter.activeFocus
                        radius: Kirigami.Units.smallSpacing
                        color: "transparent"
                        border.width: 1
                        border.color: Kirigami.Theme.focusColor
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: compactRoot.meterSpacing

                        Kirigami.Icon {
                            source: compactRoot.applet.providerIconSource(compactMeter.modelData.provider)
                            fallback: "view-statistics"
                            isMask: compactRoot.applet.providerIconIsMask(compactMeter.modelData.provider)
                            color: compactMeter.accent
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: compactRoot.meterIconSize
                            Layout.preferredHeight: compactRoot.meterIconSize
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: compactRoot.meterBarHeight
                            radius: height / 2
                            color: compactRoot.applet.withAlpha(compactMeter.meterColor, 0.28)
                            clip: true

                            Rectangle {
                                visible: compactMeter.meter >= 0
                                width: compactMeter.meter <= 0
                                    ? 0
                                    : Math.max(parent.height, parent.width * Math.max(0, Math.min(100, compactMeter.meter)) / 100)
                                height: parent.height
                                radius: parent.radius
                                color: compactMeter.meterColor

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Kirigami.Units.longDuration
                                    }
                                }

                                Behavior on width {
                                    NumberAnimation {
                                        duration: Kirigami.Units.longDuration
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: compactMeterMouse

                        anchors.fill: parent
                        z: 1
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: compactMeter.activate()
                    }
                }
            }
        }
    }
}
