import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Rectangle {
    id: overviewRow

    required property var applet
    required property var modelData
    readonly property var providerData: modelData

    readonly property color accent: applet.providerReadableColor(
        providerData.provider,
        Kirigami.Theme.backgroundColor)
    readonly property var usageRow: applet.switcherMetricRow(providerData)
    readonly property bool hasUsage: usageRow && usageRow.hasPercent
    readonly property real shownPercent: hasUsage ? applet.displayPercent(usageRow) : -1
    readonly property string resetText: usageRow ? applet.resetLabel(applet.usageResetText(usageRow)) : ""
    readonly property string detail: applet.overviewDetailText(providerData)

    signal selected(var providerData)

    function activate() {
        overviewRow.selected(overviewRow.providerData)
    }

    Layout.fillWidth: true
    Layout.preferredHeight: Kirigami.Units.gridUnit * (detail.length > 0 ? 4.35 : 3.95)
    radius: applet.roundedSurfaceRadius
    color: overviewRowMouse.pressed
        ? applet.withAlpha(Kirigami.Theme.focusColor, 0.16)
        : (activeFocus
        ? applet.withAlpha(Kirigami.Theme.focusColor, 0.1)
        : (overviewRowMouse.containsMouse
        ? applet.withAlpha(Kirigami.Theme.textColor, 0.075)
        : applet.withAlpha(Kirigami.Theme.textColor, 0.035)))
    scale: overviewRowMouse.pressed ? 0.99 : 1
    activeFocusOnTab: true

    Accessible.role: Accessible.Button
    Accessible.name: providerData.title
    Accessible.description: detail
    Accessible.onPressAction: overviewRow.activate()

    Keys.onPressed: function(event) {
        switch (event.key) {
        case Qt.Key_Space:
        case Qt.Key_Enter:
        case Qt.Key_Return:
        case Qt.Key_Select:
            overviewRow.activate()
            event.accepted = true
            break
        }
    }

    Behavior on color {
        ColorAnimation {
            duration: Kirigami.Units.shortDuration
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: Kirigami.Units.shortDuration
            easing.type: Easing.OutCubic
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Rectangle {
            id: overviewProviderIdentitySurface

            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                + Kirigami.Units.smallSpacing * 2
            Layout.preferredHeight: Layout.preferredWidth
            radius: overviewRow.applet.nestedSurfaceRadius
            color: overviewRow.applet.withAlpha(overviewRow.accent, 0.1)
            border.width: 1
            border.color: overviewRow.applet.withAlpha(Kirigami.Theme.textColor, 0.1)

            Kirigami.Icon {
                anchors.centerIn: parent
                source: overviewRow.applet.providerIconSource(overviewRow.providerData.provider)
                fallback: "view-statistics"
                isMask: overviewRow.applet.providerIconIsMask(overviewRow.providerData.provider)
                color: overviewRow.accent
                width: Kirigami.Units.iconSizes.medium
                height: Kirigami.Units.iconSizes.medium
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing / 2

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: overviewRow.providerData.title
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                PlasmaComponents.Label {
                    visible: overviewRow.hasUsage
                    text: i18n("%1% %2", Math.round(overviewRow.shownPercent), overviewRow.applet.percentSuffix())
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                }
            }

            PlasmaComponents.Label {
                visible: overviewRow.detail.length > 0
                text: overviewRow.detail
                opacity: overviewRow.applet.secondaryTextOpacity
                Layout.fillWidth: true
                elide: Text.ElideMiddle
            }

            Rectangle {
                visible: overviewRow.hasUsage
                Layout.fillWidth: true
                Layout.preferredHeight: overviewRow.applet.compactMeterTrackHeight
                radius: height / 2
                color: overviewRow.applet.withAlpha(Kirigami.Theme.textColor, 0.1)
                clip: true

                Rectangle {
                    width: overviewRow.shownPercent <= 0
                        ? 0
                        : Math.max(parent.height, parent.width * overviewRow.shownPercent / 100)
                    height: parent.height
                    radius: parent.radius
                    color: overviewRow.accent

                    Behavior on width {
                        NumberAnimation {
                            duration: Kirigami.Units.longDuration
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }

            PlasmaComponents.Label {
                visible: overviewRow.resetText.length > 0
                text: overviewRow.resetText
                opacity: overviewRow.applet.secondaryTextOpacity
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        id: overviewRowMouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: overviewRow.forceActiveFocus(Qt.MouseFocusReason)
        onClicked: overviewRow.activate()
    }
}
