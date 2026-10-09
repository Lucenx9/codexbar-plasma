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
    readonly property var accountOptions: providerID.length > 0
        ? applet.accountOptionsForProvider(providerID) : []
    readonly property bool largeAccountList: accountOptions.length > 3
    property bool accountsExpanded: false

    onProviderIDChanged: accountsExpanded = false
    onLargeAccountListChanged: {
        if (!largeAccountList)
            accountsExpanded = false
    }

    visible: providerID.length > 0
        && (applet.accountLoadingForProvider(providerID)
            || accountOptions.length > 0
            || applet.accountErrorForProvider(providerID).length > 0
            || applet.selectedAccountForProvider(providerID).length > 0)
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlainPlasmaLabel {
            visible: !accountsPanel.largeAccountList
            text: i18n("Accounts")
            font.weight: Font.DemiBold
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        DisclosureButton {
            id: accountsDisclosure
            objectName: "accountsDisclosureButton"
            visible: accountsPanel.largeAccountList
            plainText: i18n("Accounts")
            expanded: accountsPanel.accountsExpanded
            Layout.alignment: Qt.AlignVCenter
            onClicked: accountsPanel.accountsExpanded = !accountsPanel.accountsExpanded
        }

        Item {
            visible: accountsPanel.largeAccountList
            Layout.fillWidth: true
        }

        PlasmaComponents.ToolButton {
            id: clearAccountOverrideButton
            objectName: "clearAccountOverrideButton"

            visible: accountsPanel.applet.selectedAccountForProvider(accountsPanel.providerID).length > 0
            enabled: !accountsPanel.applet.accountLoadingForProvider(accountsPanel.providerID)
            icon.name: "edit-clear"
            Accessible.name: i18n("Use default account")
            onClicked: {
                if (accountsPanel.largeAccountList && activeFocus)
                    accountsDisclosure.forceActiveFocus(visualFocus ? Qt.TabFocusReason : Qt.OtherFocusReason)
                accountsPanel.applet.selectAccount(accountsPanel.providerID, "")
                accountsPanel.accountsExpanded = false
            }

            PlainToolTip {
                visible: clearAccountOverrideButton.hovered || clearAccountOverrideButton.visualFocus
                delay: Kirigami.Units.toolTipDelay
                plainText: clearAccountOverrideButton.Accessible.name
            }
        }

        // Always visible so the reload action keeps its place while accounts
        // load; an idle indicator renders nothing but holds its size.
        Controls.BusyIndicator {
            id: accountsBusyIndicator
            objectName: "accountsBusyIndicator"

            running: accountsPanel.providerID.length > 0
                && accountsPanel.applet.accountLoadingForProvider(accountsPanel.providerID)
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }

        PlasmaComponents.ToolButton {
            id: reloadAccountsButton
            objectName: "reloadAccountsButton"

            icon.name: "view-refresh"
            enabled: accountsPanel.providerID.length > 0
                && !accountsPanel.applet.accountLoadingForProvider(accountsPanel.providerID)
            Accessible.name: i18n("Reload accounts")
            onClicked: {
                if (accountsPanel.providerID.length > 0) {
                    accountsPanel.applet.loadAccounts(accountsPanel.providerID)
                }
            }

            PlainToolTip {
                visible: reloadAccountsButton.hovered || reloadAccountsButton.visualFocus
                delay: Kirigami.Units.toolTipDelay
                plainText: reloadAccountsButton.Accessible.name
            }
        }
    }

    Flow {
        objectName: "accountChoices"
        visible: !accountsPanel.largeAccountList || accountsPanel.accountsExpanded
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Repeater {
            model: accountsPanel.accountOptions

            delegate: PlainButton {
                id: accountButton

                required property var modelData
                required property int index
                readonly property string label: accountsPanel.applet.accountDisplayLabel(modelData, index)
                readonly property string subtitle: accountsPanel.applet.accountSubtitle(modelData)
                readonly property bool accountSelected: accountsPanel.applet.accountIsSelected(modelData, accountsPanel.providerData)
                readonly property string fullLabel: subtitle.length > 0 ? label + " · " + subtitle : label
                readonly property real labelPadding: icon.width + Kirigami.Units.largeSpacing * 2
                readonly property bool textTruncated: accountFontMetrics.advanceWidth(fullLabel)
                    > Math.max(0, width - labelPadding)

                // Measure the full label independently: measuring elided text
                // through implicitWidth would feed the truncation back into sizing.
                width: Math.min(accountFontMetrics.advanceWidth(fullLabel) + labelPadding, parent.width)
                hoverEnabled: true
                checkable: true
                checked: accountSelected
                plainText: accountFontMetrics.elidedText(fullLabel, Qt.ElideRight,
                    Math.max(0, width - labelPadding))
                Accessible.name: fullLabel
                icon.name: "user-identity"
                icon.width: Kirigami.Units.iconSizes.small
                icon.height: Kirigami.Units.iconSizes.small

                FontMetrics {
                    id: accountFontMetrics

                    font: accountButton.font
                }

                PlainToolTip {
                    visible: accountButton.textTruncated
                        && (accountButton.hovered || accountButton.visualFocus)
                    plainText: accountButton.fullLabel
                }

                onClicked: {
                    accountsPanel.applet.selectAccount(modelData.provider, accountsPanel.applet.accountKey(modelData))
                    checked = Qt.binding(function() { return accountSelected })
                    if (accountsPanel.largeAccountList && activeFocus)
                        accountsDisclosure.forceActiveFocus(visualFocus ? Qt.TabFocusReason : Qt.OtherFocusReason)
                    accountsPanel.accountsExpanded = false
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
