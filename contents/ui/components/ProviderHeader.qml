import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

RowLayout {
    id: providerHeaderRow

    required property var applet
    required property var providerData

    Layout.fillWidth: true
    Layout.rightMargin: Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.smallSpacing

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing / 2

        RowLayout {
            id: providerTitleRow

            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading {
                text: providerHeaderRow.providerData ? providerHeaderRow.providerData.title : ""
                level: 2
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

                PlasmaComponents.Label {
                    id: providerStatusBadgeLabel

                    anchors.centerIn: parent
                    text: providerHeaderRow.providerData
                        ? providerHeaderRow.applet.statusBadgeText(providerHeaderRow.providerData.statusSeverity)
                        : ""
                    color: providerHeaderRow.applet.contrastTextColor(providerStatusBadge.color)
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }

            PlasmaComponents.ToolButton {
                id: providerRefreshButton

                icon.name: "view-refresh"
                enabled: !providerHeaderRow.applet.loading
                Accessible.name: i18n("Refresh")
                onClicked: providerHeaderRow.applet.refreshNow()
            }
        }

        RowLayout {
            id: providerMetaRow

            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                id: providerUpdatedLabel

                text: providerHeaderRow.applet.lastUpdatedText.length > 0
                    ? providerHeaderRow.applet.lastUpdatedText
                    : i18n("Updated just now")
                opacity: 0.62
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            PlasmaComponents.Label {
                id: providerAccountLabel

                visible: providerHeaderRow.providerData
                    && providerHeaderRow.providerData.account
                    && providerHeaderRow.providerData.account.length > 0
                text: providerHeaderRow.providerData ? providerHeaderRow.providerData.account : ""
                opacity: 0.62
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideMiddle
                Layout.maximumWidth: Kirigami.Units.gridUnit * 16
            }

            PlasmaComponents.Label {
                id: providerPlanLabel

                visible: providerHeaderRow.providerData
                    && providerHeaderRow.providerData.planText
                    && providerHeaderRow.providerData.planText.length > 0
                text: providerHeaderRow.providerData ? providerHeaderRow.providerData.planText : ""
                opacity: 0.66
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                Layout.maximumWidth: Kirigami.Units.gridUnit * 5
            }
        }
    }
}
