import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Controls.ItemDelegate {
    id: providerRow

    required property var configPage
    required property var modelData
    readonly property var providerData: modelData

    Layout.fillWidth: true
    hoverEnabled: true
    down: false
    highlighted: providerData.provider === configPage.selectedProviderID
    onClicked: configPage.selectedProviderID = providerData.provider

    contentItem: RowLayout {
        spacing: Kirigami.Units.gridUnit

        Kirigami.Icon {
            source: providerRow.configPage.providerIconSource(providerRow.providerData.provider)
            isMask: true
            color: providerRow.configPage.providerColor(providerRow.providerData.provider)
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Controls.Label {
                text: providerRow.providerData.displayName
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Controls.Label {
                text: providerRow.providerData.defaultEnabled
                    ? i18n("%1 - on by default", providerRow.providerData.provider)
                    : providerRow.providerData.provider
                elide: Text.ElideRight
                opacity: 0.6
                font: Kirigami.Theme.smallFont
                Layout.fillWidth: true
            }
        }

        Controls.BusyIndicator {
            running: providerRow.configPage.isPending(providerRow.providerData.provider)
            visible: running
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }

        Controls.Switch {
            checked: providerRow.configPage.visualEnabled(providerRow.providerData.provider, providerRow.providerData.enabled)
            enabled: !providerRow.configPage.isPending(providerRow.providerData.provider)
            onClicked: {
                providerRow.configPage.setEnabled(providerRow.providerData.provider, !providerRow.providerData.enabled)
                // Clicking severs the declarative binding on `checked`; restore it so the
                // switch reverts when a toggle fails or its pending state clears.
                checked = Qt.binding(function() {
                    return providerRow.configPage.visualEnabled(providerRow.providerData.provider, providerRow.providerData.enabled)
                })
            }
        }
    }
}
