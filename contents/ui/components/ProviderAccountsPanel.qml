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
            || applet.accountErrorForProvider(providerID).length > 0
            || applet.selectedAccountForProvider(providerID).length > 0)
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlainPlasmaLabel {
            text: i18n("Accounts")
            font.weight: Font.DemiBold
            Layout.fillWidth: true
        }

        PlasmaComponents.ToolButton {
            id: clearAccountOverrideButton

            visible: accountsPanel.applet.selectedAccountForProvider(accountsPanel.providerID).length > 0
            enabled: !accountsPanel.applet.accountLoadingForProvider(accountsPanel.providerID)
            icon.name: "edit-clear"
            Accessible.name: i18n("Use default account")
            onClicked: accountsPanel.applet.selectAccount(accountsPanel.providerID, "")
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

            delegate: PlainButton {
                required property var modelData
                readonly property string label: accountsPanel.applet.accountLabel(modelData)
                readonly property string subtitle: accountsPanel.applet.accountSubtitle(modelData)
                readonly property bool accountSelected: accountsPanel.applet.accountIsSelected(modelData, accountsPanel.providerData)

                checkable: true
                checked: accountSelected
                plainText: subtitle.length > 0 ? label + " · " + subtitle : label
                icon.name: "user-identity"
                onClicked: {
                    accountsPanel.applet.selectAccount(modelData.provider, label)
                    checked = Qt.binding(function() { return accountSelected })
                }
            }
        }
    }

    PlainPlasmaLabel {
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
