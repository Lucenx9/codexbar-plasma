import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../ThemeContrast.js" as ThemeContrast

RowLayout {
    id: providerHeaderRow

    required property var applet
    required property var providerData
    readonly property bool hasAccount: providerData
        && providerData.account && providerData.account.length > 0
    readonly property bool hasPlan: providerData
        && providerData.planText && providerData.planText.length > 0
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
                Layout.preferredWidth: providerStatusBadgeLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
                Layout.preferredHeight: Math.max(Kirigami.Units.gridUnit * 1.25,
                    providerStatusBadgeLabel.implicitHeight + Kirigami.Units.smallSpacing)
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
                    color: ThemeContrast.readableTextColor(Kirigami.Theme.textColor, providerStatusBadge.color)
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    font.weight: Font.DemiBold
                }
            }

        }

        RowLayout {
            id: providerMetaRow

            visible: providerHeaderRow.hasAccount || providerHeaderRow.hasPlan
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlainPlasmaLabel {
                id: providerAccountLabel

                Layout.alignment: Qt.AlignBaseline
                visible: providerHeaderRow.hasAccount
                text: providerHeaderRow.providerData ? providerHeaderRow.providerData.account : ""
                opacity: providerHeaderRow.applet.secondaryTextOpacity
                Layout.fillWidth: true
                elide: Text.ElideMiddle
                Layout.maximumWidth: Kirigami.Units.gridUnit * 16
            }

            PlainPlasmaLabel {
                id: providerPlanLabel

                Layout.alignment: Qt.AlignBaseline
                visible: providerHeaderRow.hasPlan
                text: providerHeaderRow.providerData ? providerHeaderRow.providerData.planText : ""
                font: Kirigami.Theme.smallFont
                opacity: providerHeaderRow.applet.secondaryTextOpacity
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                Layout.maximumWidth: Kirigami.Units.gridUnit * 5
            }
        }

        PlainPlasmaLabel {
            id: providerUpdatedLabel

            visible: text.length > 0
            text: providerHeaderRow.providerData && providerHeaderRow.providerData.lastGoodAtMs > 0
                ? providerHeaderRow.applet.providerUsageTimestamp(providerHeaderRow.providerData)
                : providerHeaderRow.applet.lastUpdatedText
            font: Kirigami.Theme.smallFont
            opacity: providerHeaderRow.applet.secondaryTextOpacity
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
    }

    RefreshButton {
        id: providerRefreshButton

        Layout.alignment: Qt.AlignTop
        busy: providerHeaderRow.applet.loading
        label: i18n("Refresh")
        onRequested: providerHeaderRow.applet.refreshNow(true)
    }
}
