import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Rectangle {
    id: overviewRow

    required property var applet
    required property var modelData
    readonly property var providerData: modelData

    readonly property color accent: applet.providerColor(providerData.provider)
    readonly property var usageRow: applet.switcherMetricRow(providerData)
    readonly property bool hasUsage: usageRow && usageRow.hasPercent
    readonly property real shownPercent: hasUsage ? applet.displayPercent(usageRow) : -1
    readonly property string resetText: usageRow ? applet.resetLabel(usageRow.reset) : ""
    readonly property string detail: applet.overviewDetailText(providerData)

    signal selected(var providerData)

    Layout.fillWidth: true
    Layout.preferredHeight: Kirigami.Units.gridUnit * (detail.length > 0 ? 4.45 : 4.05)
    radius: Kirigami.Units.smallSpacing
    color: overviewRowMouse.containsMouse
        ? applet.withAlpha(Kirigami.Theme.textColor, 0.06)
        : "transparent"
    border.width: 1
    border.color: applet.withAlpha(accent, 0.22)

    RowLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Rectangle {
            Layout.preferredWidth: 3
            Layout.fillHeight: true
            radius: width / 2
            color: overviewRow.accent
        }

        Kirigami.Icon {
            source: overviewRow.applet.providerIconSource(overviewRow.providerData.provider)
            isMask: overviewRow.applet.providerIconIsMask(overviewRow.providerData.provider)
            color: overviewRow.accent
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

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
                    opacity: 0.72
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                }
            }

            PlasmaComponents.Label {
                visible: overviewRow.detail.length > 0
                text: overviewRow.detail
                opacity: 0.62
                Layout.fillWidth: true
                elide: Text.ElideMiddle
            }

            Rectangle {
                visible: overviewRow.hasUsage
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                radius: height / 2
                color: overviewRow.applet.withAlpha(Kirigami.Theme.textColor, 0.14)
                clip: true

                Rectangle {
                    width: overviewRow.shownPercent <= 0
                        ? 0
                        : Math.max(parent.height, parent.width * overviewRow.shownPercent / 100)
                    height: parent.height
                    radius: parent.radius
                    color: overviewRow.accent
                }
            }

            PlasmaComponents.Label {
                visible: overviewRow.resetText.length > 0
                text: overviewRow.resetText
                opacity: 0.56
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        id: overviewRowMouse

        anchors.fill: parent
        hoverEnabled: true
        onClicked: overviewRow.selected(overviewRow.providerData)
    }
}
