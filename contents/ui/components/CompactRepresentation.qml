import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../PanelElements.js" as PanelElements

Item {
    id: compactRoot

    required property var applet
    property bool animationsEnabled: true
    property bool interactive: true

    readonly property bool verticalPanel: applet.verticalFormFactor
    readonly property bool minimalStyle: applet.minimalPanel === true
    readonly property var meterProviders: applet.compactProviders()
    readonly property bool hasProviderMeters: meterProviders.length > 0
    readonly property var incidentProvider: applet.providerPresentation(applet.primaryIncidentProvider())
    // The incident dot must sit on the incident provider's own icon. The
    // standalone status element stays only when no rendered meter, and no
    // vertical identity icon, can carry the badge.
    readonly property bool incidentProviderHasMeterBadge: incidentProvider !== null
        && meterProviders.some(function(provider) {
            return provider.provider === incidentProvider.provider
                && provider.hasIncident === true
                && provider.statusKnown !== false
        })
    readonly property string primaryText: applet.compactText()
    readonly property var selectedProvider: applet.selectedCompactProvider()
    readonly property bool selectedProviderHasMeter: selectedProvider !== null && selectedProvider !== undefined
        && meterProviders.some(function(provider) { return provider.provider === selectedProvider.provider })
    // Without rendered meters in a vertical panel the identity icon is the only
    // anchor, so it carries the badge only when the primary incident belongs to
    // the selected provider. Any other incident keeps the standalone status
    // element available so the outage never loses its marker.
    readonly property bool identityCarriesIncidentBadge: verticalPanel
        && !hasProviderMeters
        && incidentProvider !== null
        && selectedProvider !== null && selectedProvider !== undefined
        && incidentProvider.provider === selectedProvider.provider
    // Independent text still needs its identity when several meters are shown.
    readonly property bool inlinePrimaryText: !verticalPanel && primaryText.length > 0
        && inlineTextWidth > 0
        && applet.panelElementOrder().join(",") === PanelElements.defaultOrder.join(",")
        && selectedProviderHasMeter
    readonly property bool showPrimaryIdentity: !hasProviderMeters
        || (!verticalPanel && primaryText.length > 0 && !inlinePrimaryText
            && (meterProviders.length > 1 || !selectedProviderHasMeter))
    readonly property int compactExtent: Kirigami.Units.iconSizes.smallMedium
        + Kirigami.Units.smallSpacing * 2
    readonly property int meterContentHeight: Math.max(0, height - Kirigami.Units.smallSpacing * 2)
    readonly property int meterIconSize: Math.min(Kirigami.Units.iconSizes.small,
        Math.max(12, verticalPanel ? width / 3 : meterContentHeight))
    readonly property int meterSpacing: Kirigami.Units.smallSpacing
    readonly property int meterBarHeight: Math.max(3, Math.min(6,
        Math.round((verticalPanel ? compactExtent : meterContentHeight) / 4)))
    readonly property int meterBarWidth: verticalPanel
        ? Math.max(8, Math.min(Kirigami.Units.iconSizes.smallMedium + meterSpacing,
            width - meterIconSize - meterSpacing * 3))
        : Kirigami.Units.iconSizes.smallMedium + meterSpacing
    readonly property int meterWidth: meterIconSize + meterSpacing + meterBarWidth
        + (verticalPanel ? 0 : meterSpacing)
    readonly property int meterHeight: Math.max(compactExtent, meterBarHeight * 2 + meterSpacing * 3)
    readonly property int metersExtent: meterProviders.length * meterHeight
        + Math.max(0, meterProviders.length - 1) * meterSpacing
    readonly property int maximumCompactWidth: Kirigami.Units.gridUnit * 18
    readonly property int inlineTextWidth: Math.min(Math.ceil(compactTextMeasurer.implicitWidth), Math.max(0,
            maximumCompactWidth - meterProviders.length * (meterWidth + meterSpacing)
                - Kirigami.Units.smallSpacing * 5))
    readonly property int desiredWidth: verticalPanel
        ? Kirigami.Units.iconSizes.small + Kirigami.Units.iconSizes.smallMedium + meterSpacing * 4
        : Math.min(maximumCompactWidth, Math.max(Kirigami.Units.gridUnit * 4.8,
            compactRow.implicitWidth + Kirigami.Units.smallSpacing * 2))
    readonly property int desiredHeight: verticalPanel
        ? Math.ceil(compactRow.implicitHeight + Kirigami.Units.smallSpacing * 2)
        : compactExtent

    Layout.minimumWidth: verticalPanel
        ? (hasProviderMeters ? Kirigami.Units.iconSizes.small * 2 : compactExtent) : desiredWidth
    Layout.preferredWidth: desiredWidth
    Layout.maximumWidth: verticalPanel ? Infinity : desiredWidth
    Layout.fillWidth: verticalPanel
    Layout.minimumHeight: verticalPanel ? desiredHeight : 0
    Layout.preferredHeight: desiredHeight
    Layout.maximumHeight: verticalPanel ? desiredHeight : Infinity

    implicitWidth: desiredWidth
    implicitHeight: desiredHeight
    clip: true

    MouseArea {
        id: compactBackgroundMouse
        anchors.fill: parent
        enabled: compactRoot.interactive
        cursorShape: Qt.PointingHandCursor
        onClicked: compactRoot.applet.expanded = !compactRoot.applet.expanded
    }

    // Measure outside the Loader so its layout-assigned width cannot feed back
    // into the label's preferred width and collapse the compact representation.
    PlainPlasmaLabel {
        id: compactTextMeasurer

        visible: false
        text: compactRoot.primaryText
        font.bold: !compactRoot.minimalStyle
    }

    GridLayout {
        id: compactRow

        columns: compactRoot.verticalPanel ? 1 : -1
        rows: compactRoot.verticalPanel ? -1 : 1

        // The applet keeps a minimum panel width, so a short content set (meters
        // without panel text) leaves spare room. Centre the row instead of
        // letting all of it pile up on the right of the content.
        anchors.centerIn: parent
        width: Math.max(0, Math.min(compactRoot.width - Kirigami.Units.smallSpacing * 2,
            implicitWidth))
        height: compactRoot.verticalPanel ? implicitHeight
            : Math.max(0, compactRoot.height - Kirigami.Units.smallSpacing * 2)
        rowSpacing: Kirigami.Units.smallSpacing
        columnSpacing: Kirigami.Units.smallSpacing

        Repeater {
            model: compactRoot.applet.panelElementOrder()

            delegate: Loader {
                id: elementLoader

                required property var modelData

                readonly property bool isTextElement: modelData === "text"
                readonly property bool elementVisible: modelData === "identity"
                    ? compactRoot.showPrimaryIdentity
                    : (modelData === "status"
                    ? ((!compactRoot.verticalPanel || compactRoot.hasProviderMeters
                            || !compactRoot.identityCarriesIncidentBadge)
                        && compactRoot.incidentProvider !== null
                        && compactRoot.incidentProvider.hasIncident
                        && !compactRoot.incidentProviderHasMeterBadge)
                    : (modelData === "text"
                    ? (!compactRoot.verticalPanel && compactRoot.primaryText.length > 0 && !compactRoot.inlinePrimaryText)
                    : compactRoot.hasProviderMeters))

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
                    ? (compactRoot.verticalPanel ? compactRoot.meterWidth
                        : compactRoot.meterProviders.length * compactRoot.meterWidth
                            + (compactRoot.inlinePrimaryText ? compactRoot.inlineTextWidth + compactRoot.meterSpacing : 0)
                            + Math.max(0, compactRoot.meterProviders.length - 1) * Kirigami.Units.smallSpacing)
                    : Math.max(Kirigami.Units.gridUnit * 2,
                        Math.ceil(compactTextMeasurer.implicitWidth)))))
                Layout.preferredHeight: compactRoot.verticalPanel
                    ? (modelData === "meters" ? compactRoot.metersExtent
                        : (modelData === "status" ? Kirigami.Units.smallSpacing * 1.5 : compactRoot.compactExtent))
                    : compactRow.height
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
                objectName: "panelIdentityIcon"

                anchors.fill: parent
                source: compactRoot.applet.loading ? "view-refresh" : compactRoot.applet.providerIconSource(parent.compactProvider)
                fallback: "view-statistics"
                isMask: !compactRoot.applet.loading && (compactRoot.minimalStyle || compactRoot.applet.providerIconIsMask(parent.compactProvider))
                color: compactRoot.applet.loading || compactRoot.minimalStyle
                    ? Kirigami.Theme.textColor
                    : compactRoot.applet.providerReadableColor(parent.compactProvider, Kirigami.Theme.backgroundColor)

                RotationAnimator {
                    target: compactIdentityIcon
                    running: compactRoot.animationsEnabled && compactRoot.applet.loading && Kirigami.Units.longDuration > 0
                    from: 0
                    to: 360
                    duration: 1250
                    loops: Animation.Infinite
                    onStopped: compactIdentityIcon.rotation = 0
                }

                Rectangle {
                    id: compactVerticalStatusBadge
                    objectName: "panelIdentityBadge"

                    // Without meters this icon is the only anchor, so it may
                    // carry the badge only for its own provider's incident.
                    // Loading replaces the icon with a refresh spinner, so the
                    // badge waits for the provider icon to come back.
                    visible: compactRoot.identityCarriesIncidentBadge
                        && !compactRoot.applet.loading
                    anchors.top: parent.top
                    anchors.right: parent.right
                    width: Math.round(Kirigami.Units.iconSizes.smallMedium / 3)
                    height: width
                    radius: width / 2
                    color: compactRoot.selectedProvider
                        ? compactRoot.applet.statusBadgeColor(compactRoot.selectedProvider.statusSeverity)
                        : "transparent"
                    border.width: 1
                    border.color: Kirigami.Theme.backgroundColor
                }
            }
        }
    }

    Component {
        id: statusElement

        Item {
            id: compactStatusBadge

            visible: (!compactRoot.verticalPanel || compactRoot.hasProviderMeters
                    || !compactRoot.identityCarriesIncidentBadge)
                && compactRoot.incidentProvider !== null
                && compactRoot.incidentProvider.hasIncident
                && !compactRoot.incidentProviderHasMeterBadge
            implicitWidth: Kirigami.Units.smallSpacing * 1.5
            implicitHeight: implicitWidth

            // The Loader gives this item the full panel row height. Keep the
            // status dot square inside it instead of stretching into a pill.
            Rectangle {
                id: panelStatusDot
                objectName: "panelStatusDot"

                anchors.centerIn: parent
                width: parent.implicitWidth
                height: width
                radius: width / 2
                color: compactRoot.incidentProvider
                    ? compactRoot.applet.statusBadgeColor(compactRoot.incidentProvider.statusSeverity)
                    : "transparent"
                border.width: 1
                border.color: Kirigami.Theme.backgroundColor

                PlainToolTip {
                    visible: compactStatusMouse.containsMouse
                    plainText: compactRoot.incidentProvider
                        ? i18n("%1: %2", compactRoot.incidentProvider.title, compactRoot.incidentProvider.status)
                        : ""
                }

                MouseArea {
                    id: compactStatusMouse

                    anchors.fill: parent
                    enabled: compactRoot.interactive
                    hoverEnabled: true
                    // A binding avoids Qt rejecting a bare zero enum literal.
                    acceptedButtons: (0)
                }
            }
        }
    }

    Component {
        id: textElement

        PlainPlasmaLabel {
            objectName: "panelStandaloneText"
            visible: !compactRoot.verticalPanel && compactRoot.primaryText.length > 0
            text: compactRoot.primaryText
            elide: Text.ElideRight
            font.bold: !compactRoot.minimalStyle
            // The loader stretches this label to the full row height, so the
            // default top alignment would sit the text above the centred
            // provider icon beside it.
            verticalAlignment: Text.AlignVCenter
        }
    }

    Component {
        id: metersElement

        GridLayout {
            columns: compactRoot.verticalPanel ? 1 : -1
            rows: compactRoot.verticalPanel ? -1 : 1
            rowSpacing: compactRoot.meterSpacing
            columnSpacing: compactRoot.meterSpacing

            Repeater {
                model: compactRoot.meterProviders

                delegate: Item {
                    id: compactMeter

                    required property var modelData
                    readonly property bool showsPrimaryText: compactRoot.inlinePrimaryText
                        && modelData.provider === compactRoot.selectedProvider.provider
                    readonly property var quotaRows: compactRoot.applet.panelMeterRows(modelData)
                    readonly property string incidentText: modelData.hasIncident === true
                        && modelData.statusKnown !== false
                        && modelData.status
                        ? modelData.status : ""
                    readonly property color accent: compactRoot.minimalStyle ? Kirigami.Theme.textColor
                        : compactRoot.applet.providerReadableColor(modelData.provider, Kirigami.Theme.backgroundColor)

                    function activate() {
                        if (!compactRoot.interactive) {
                            return
                        }
                        compactRoot.applet.openProviderFromPanel(compactMeter.modelData.provider)
                    }

                    Layout.preferredWidth: compactRoot.meterWidth
                        + (showsPrimaryText ? compactRoot.inlineTextWidth + compactRoot.meterSpacing : 0)
                    Layout.preferredHeight: compactRoot.verticalPanel ? compactRoot.meterHeight : compactRow.height
                    activeFocusOnTab: compactRoot.interactive

                    Accessible.role: compactRoot.interactive ? Accessible.Button : Accessible.Graphic
                    Accessible.name: compactRoot.interactive ? i18n("Open %1", modelData.title) : modelData.title
                    Accessible.description: compactRoot.applet.panelMeterDescription(modelData)
                        + (compactMeter.incidentText.length > 0 ? ". " + compactMeter.incidentText : "")
                        + (showsPrimaryText ? ". " + compactRoot.primaryText : "")
                    Accessible.ignored: !compactRoot.interactive
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
                        radius: Kirigami.Units.smallSpacing
                        color: compactRoot.applet.withAlpha(Kirigami.Theme.textColor,
                            compactMeterMouse.pressed ? 0.14 : (compactMeterMouse.containsMouse ? 0.07 : 0))

                        Behavior on color {
                            ColorAnimation {
                                duration: Kirigami.Units.shortDuration
                            }
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

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: compactRoot.meterSpacing
                        opacity: compactMeter.modelData.usageStale === true ? 0.55 : 1

                        Kirigami.Icon {
                            objectName: "panelProviderIcon"
                            source: compactRoot.applet.providerIconSource(compactMeter.modelData.provider)
                            fallback: "view-statistics"
                            isMask: compactRoot.minimalStyle || compactRoot.applet.providerIconIsMask(compactMeter.modelData.provider)
                            color: compactMeter.accent
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: compactRoot.meterIconSize
                            Layout.preferredHeight: compactRoot.meterIconSize

                            Rectangle {
                                id: meterIncidentBadge
                                objectName: "panelIncidentBadge"

                                // Refreshes keep the rendered providers, so the
                                // badge must not flicker away with loading.
                                visible: compactMeter.modelData.hasIncident === true
                                    && compactMeter.modelData.statusKnown !== false
                                anchors.top: parent.top
                                anchors.right: parent.right
                                width: Math.max(4, Math.round(compactRoot.meterIconSize / 3))
                                height: width
                                radius: width / 2
                                color: compactRoot.applet.statusBadgeColor(compactMeter.modelData.statusSeverity)
                                border.width: 1
                                border.color: Kirigami.Theme.backgroundColor
                            }
                        }

                        ColumnLayout {
                            spacing: compactRoot.meterSpacing
                            Layout.alignment: Qt.AlignVCenter

                            Repeater {
                                model: compactMeter.quotaRows

                                delegate: Rectangle {
                                    id: quotaCapsule
                                    required property var modelData
                                    readonly property real meter: compactRoot.applet.displayPercent(modelData)
                                    readonly property color meterColor: compactRoot.applet.quotaMeterColor(modelData, compactMeter.accent)
                                    readonly property bool warning: compactRoot.applet.quotaSeverity(modelData).length > 0

                                    objectName: "panelMeterTrack"
                                    Layout.preferredWidth: compactRoot.meterBarWidth
                                    Layout.preferredHeight: compactRoot.meterBarHeight
                                    radius: height / 2
                                    // The track remains identifiable at zero, including an
                                    // exhausted quota when displaying the remaining amount.
                                    color: compactRoot.applet.withAlpha(meterColor, warning ? 0.32 : 0.18)
                                    border.width: warning || meter === 0 ? 1 : 0
                                    border.color: compactRoot.applet.withAlpha(meterColor, warning ? 0.9 : 0.45)
                                    clip: true

                                    Rectangle {
                                        objectName: "panelMeterFill"
                                        width: parent.width * Math.max(0, Math.min(100, quotaCapsule.meter)) / 100
                                        height: parent.height
                                        radius: Math.min(height / 2, width / 2)
                                        color: quotaCapsule.meterColor

                                        // Every popup meter grows into a new
                                        // reading; this capsule jumped to it.
                                        // The settings preview renders static
                                        // frames, so it opts out.
                                        Behavior on width {
                                            enabled: compactRoot.animationsEnabled

                                            NumberAnimation {
                                                duration: Kirigami.Units.longDuration
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        PlainPlasmaLabel {
                            objectName: "panelProviderText"
                            visible: compactMeter.showsPrimaryText
                            text: visible ? compactRoot.primaryText : ""
                            Layout.preferredWidth: compactRoot.inlineTextWidth
                            Layout.maximumWidth: compactRoot.inlineTextWidth
                            Layout.alignment: Qt.AlignVCenter
                            elide: Text.ElideRight
                            font.bold: !compactRoot.minimalStyle
                        }
                    }

                    MouseArea {
                        id: compactMeterMouse

                        anchors.fill: parent
                        enabled: compactRoot.interactive
                        z: 1
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: compactMeter.activate()
                        // The plasmoid tooltip narrows to the hovered meter, so
                        // each panel icon reports only its own provider. Clearing
                        // only the matching id keeps a fast move between two
                        // meters from ending on an empty tooltip.
                        onContainsMouseChanged: {
                            if (!compactRoot.interactive) {
                                return
                            }
                            if (containsMouse) {
                                compactRoot.applet.setHoveredPanelProvider(compactMeter.modelData.provider)
                            } else {
                                compactRoot.applet.clearHoveredPanelProvider(compactMeter.modelData.provider)
                            }
                        }
                    }
                }
            }
        }
    }
}
