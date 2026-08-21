import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

RowLayout {
    id: providerHeaderRow

    required property var applet
    required property var providerData
    readonly property color brandAccent: applet.providerColor(providerData ? providerData.provider : "")
    readonly property color accent: applet.providerReadableColor(
        providerData ? providerData.provider : "",
        Kirigami.Theme.backgroundColor)

    Layout.fillWidth: true
    Layout.rightMargin: Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.largeSpacing

    Rectangle {
        id: providerIdentitySurface

        Layout.preferredWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.smallSpacing * 2
        Layout.preferredHeight: Layout.preferredWidth
        radius: providerHeaderRow.applet.nestedSurfaceRadius
        color: providerHeaderRow.applet.withAlpha(providerHeaderRow.brandAccent, 0.12)
        border.width: 1
        border.color: providerHeaderRow.applet.withAlpha(Kirigami.Theme.textColor, 0.1)

        Kirigami.Icon {
            id: providerHeaderIcon

            anchors.centerIn: parent
            source: providerHeaderRow.providerData
                ? providerHeaderRow.applet.providerIconSource(providerHeaderRow.providerData.provider)
                : "view-statistics-symbolic"
            fallback: "view-statistics"
            isMask: providerHeaderRow.providerData
                ? providerHeaderRow.applet.providerIconIsMask(providerHeaderRow.providerData.provider)
                : true
            color: providerHeaderRow.accent
            width: Kirigami.Units.iconSizes.medium
            height: Kirigami.Units.iconSizes.medium
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing / 2

        RowLayout {
            id: providerTitleRow

            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlainHeading {
                text: providerHeaderRow.providerData ? providerHeaderRow.providerData.title : ""
                level: 2
                type: Kirigami.Heading.Type.Primary
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Rectangle {
                id: providerStatusBadge

                visible: providerHeaderRow.providerData
                    && providerHeaderRow.providerData.hasIncident
                Layout.preferredWidth: providerStatusBadgeLabel.implicitWidth + Kirigami.Units.smallSpacing * 1.5
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.25
                radius: height / 2
                color: providerHeaderRow.providerData
                    ? providerHeaderRow.applet.statusBadgeColor(providerHeaderRow.providerData.statusSeverity)
                    : "transparent"

                PlainPlasmaLabel {
                    id: providerStatusBadgeLabel

                    anchors.centerIn: parent
                    text: providerHeaderRow.providerData
                        ? providerHeaderRow.applet.statusBadgeText(providerHeaderRow.providerData.statusSeverity)
                        : ""
                    color: providerHeaderRow.applet.contrastTextColor(providerStatusBadge.color)
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    font.weight: Font.DemiBold
                }
            }

        }

        RowLayout {
            id: providerMetaRow

            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlainPlasmaLabel {
                id: providerUpdatedLabel

                text: providerHeaderRow.applet.lastUpdatedText.length > 0
                    ? providerHeaderRow.applet.lastUpdatedText
                    : i18n("Updated just now")
                opacity: providerHeaderRow.applet.secondaryTextOpacity
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            PlainPlasmaLabel {
                id: providerAccountLabel

                visible: providerHeaderRow.providerData
                    && providerHeaderRow.providerData.account
                    && providerHeaderRow.providerData.account.length > 0
                text: providerHeaderRow.providerData ? providerHeaderRow.providerData.account : ""
                opacity: providerHeaderRow.applet.secondaryTextOpacity
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideMiddle
                Layout.maximumWidth: Kirigami.Units.gridUnit * 16
            }

            PlainPlasmaLabel {
                id: providerPlanLabel

                visible: providerHeaderRow.providerData
                    && providerHeaderRow.providerData.planText
                    && providerHeaderRow.providerData.planText.length > 0
                text: providerHeaderRow.providerData ? providerHeaderRow.providerData.planText : ""
                opacity: providerHeaderRow.applet.secondaryTextOpacity
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                Layout.maximumWidth: Kirigami.Units.gridUnit * 5
            }
        }
    }

    // A refresh over data that is already on screen used to leave nothing here
    // but a greyed button, so the only sign of work was the panel icon spinning
    // behind the popup.
    Controls.BusyIndicator {
        id: providerRefreshIndicator

        visible: providerHeaderRow.applet.loading
        running: visible
        Layout.alignment: Qt.AlignTop
        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
    }

    PlasmaComponents.ToolButton {
        id: providerRefreshButton

        visible: !providerHeaderRow.applet.loading
        Layout.alignment: Qt.AlignTop
        icon.name: "view-refresh"
        Accessible.name: i18n("Refresh")
        onClicked: providerHeaderRow.applet.refreshNow()
    }
}
