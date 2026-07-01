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
    readonly property color selectedForeground: contrastTextColor(Kirigami.Theme.highlightColor)
    readonly property color selectedSecondaryForeground: withAlpha(selectedForeground, 0.72)

    function withAlpha(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    function contrastTextColor(color) {
        var luminance = (0.2126 * color.r) + (0.7152 * color.g) + (0.0722 * color.b)
        return luminance > 0.62 ? Qt.rgba(0.08, 0.08, 0.1, 1) : Qt.rgba(1, 1, 1, 1)
    }

    contentItem: RowLayout {
        spacing: Kirigami.Units.gridUnit

        Kirigami.Icon {
            source: providerRow.configPage.providerIconSource(providerRow.providerData.provider)
            isMask: true
            color: providerRow.highlighted ? providerRow.selectedForeground : providerRow.configPage.providerColor(providerRow.providerData.provider)
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Controls.Label {
                text: providerRow.providerData.displayName
                elide: Text.ElideRight
                color: providerRow.highlighted ? providerRow.selectedForeground : Kirigami.Theme.textColor
                Layout.fillWidth: true
            }

            Controls.Label {
                text: providerRow.providerData.defaultEnabled
                    ? i18n("%1 - on by default", providerRow.providerData.provider)
                    : providerRow.providerData.provider
                elide: Text.ElideRight
                color: providerRow.highlighted ? providerRow.selectedSecondaryForeground : providerRow.withAlpha(Kirigami.Theme.textColor, 0.6)
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
