import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

ColumnLayout {
    id: accountsPanel

    required property var applet
    required property var providerData

    readonly property string providerID: providerData ? providerData.provider : ""

    visible: providerID.length > 0
        && (applet.accountLoadingForProvider(providerID)
            || applet.accountOptionsForProvider(providerID).length > 0
            || applet.accountErrorForProvider(providerID).length > 0)
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            text: i18n("Accounts")
            font.weight: Font.DemiBold
            Layout.fillWidth: true
        }

        Controls.BusyIndicator {
            running: accountsPanel.providerID.length > 0
                && accountsPanel.applet.accountLoadingForProvider(accountsPanel.providerID)
            visible: running
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }

        PlasmaComponents.ToolButton {
            icon.name: "view-refresh"
            enabled: accountsPanel.providerID.length > 0
                && !accountsPanel.applet.accountLoadingForProvider(accountsPanel.providerID)
            Accessible.name: i18n("Reload accounts")
            onClicked: {
                if (accountsPanel.providerID.length > 0) {
                    accountsPanel.applet.loadAccounts(accountsPanel.providerID)
                }
            }
        }
    }

    Flow {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Repeater {
            model: accountsPanel.providerID.length > 0
                ? accountsPanel.applet.accountOptionsForProvider(accountsPanel.providerID)
                : []

            delegate: Controls.Button {
                readonly property string label: accountsPanel.applet.accountLabel(modelData)
                readonly property string subtitle: accountsPanel.applet.accountSubtitle(modelData)

                checkable: true
                checked: accountsPanel.applet.accountIsSelected(modelData, accountsPanel.providerData)
                text: subtitle.length > 0 ? label + " · " + subtitle : label
                icon.name: "user-identity"
                onClicked: accountsPanel.applet.selectAccount(modelData.provider, label)
            }
        }
    }

    PlasmaComponents.Label {
        visible: accountsPanel.providerID.length > 0
            && accountsPanel.applet.accountErrorForProvider(accountsPanel.providerID).length > 0
        text: accountsPanel.providerID.length > 0
            ? accountsPanel.applet.accountErrorForProvider(accountsPanel.providerID)
            : ""
        color: Kirigami.Theme.negativeTextColor
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }
}
