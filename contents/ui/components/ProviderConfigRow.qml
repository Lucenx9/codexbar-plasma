import QtQuick
import QtQuick.Window
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../ThemeContrast.js" as ThemeContrast

Controls.ItemDelegate {
    id: providerRow

    required property var configPage
    required property var modelData
    readonly property var providerData: modelData

    Layout.fillWidth: true
    focusPolicy: Qt.StrongFocus
    Accessible.name: providerData.displayName
    hoverEnabled: true
    down: false
    highlighted: providerData.provider === configPage.selectedProviderID
    onClicked: configPage.selectedProviderID = providerData.provider
    onActiveFocusChanged: if (activeFocus) configPage.providerListFocus = ({
        provider: providerData.provider, control: "row"
    })
    // Array models recreate every row. Restore focus only when the old control
    // was destroyed and no other control has claimed focus in the meantime.
    Component.onCompleted: Qt.callLater(function() {
        var remembered = configPage.providerListFocus
        var window = providerRow.Window.window
        if (!remembered || remembered.provider !== providerData.provider || !window
                || (window.activeFocusItem && window.activeFocusItem !== window.contentItem)) {
            return
        }
        if (remembered.control === "switch") {
            enabledSwitch.forceActiveFocus(Qt.TabFocusReason)
        } else if (remembered.control === "row") {
            providerRow.forceActiveFocus(Qt.TabFocusReason)
        }
    })
    readonly property color selectedForeground: ThemeContrast.readableTextColor(
        Kirigami.Theme.highlightedTextColor, Kirigami.Theme.highlightColor)
    readonly property color selectedSecondaryForeground: ThemeContrast.readableTextColor(
        ThemeContrast.interpolateColor(Kirigami.Theme.highlightColor, selectedForeground,
            configPage.secondaryTextOpacity), Kirigami.Theme.highlightColor)

    function withAlpha(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    PlainToolTip {
        parent: providerRow
        visible: (providerRow.hovered || providerRow.visualFocus)
            && (providerTitle.truncated || providerSubtitle.truncated)
        plainText: providerTitle.text + "\n" + providerSubtitle.text
    }

    contentItem: RowLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Icon {
            source: providerRow.configPage.providerIconSource(providerRow.providerData.provider)
            fallback: "view-statistics"
            isMask: true
            color: providerRow.highlighted
                ? providerRow.selectedForeground
                : providerRow.configPage.providerReadableColor(
                    providerRow.providerData.provider,
                    Kirigami.Theme.backgroundColor)
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing / 2

            PlainControlsLabel {
                id: providerTitle

                text: providerRow.providerData.displayName
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                color: providerRow.highlighted ? providerRow.selectedForeground : Kirigami.Theme.textColor
                Layout.fillWidth: true
            }

            PlainControlsLabel {
                id: providerSubtitle

                text: providerRow.providerData.defaultEnabled
                    ? i18n("%1 - CodexBar default", providerRow.providerData.provider)
                    : providerRow.providerData.provider
                elide: Text.ElideRight
                color: providerRow.highlighted ? providerRow.selectedSecondaryForeground
                    : providerRow.withAlpha(Kirigami.Theme.textColor, providerRow.configPage.secondaryTextOpacity)
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
            id: enabledSwitch

            onActiveFocusChanged: if (activeFocus) providerRow.configPage.providerListFocus = ({
                provider: providerRow.providerData.provider, control: "switch"
            })
            Accessible.name: i18n("Enable %1", providerRow.providerData.displayName)
            checked: providerRow.configPage.visualEnabled(providerRow.providerData.provider, providerRow.providerData.enabled)
            onClicked: {
                if (!providerRow.configPage.isPending(providerRow.providerData.provider)) {
                    providerRow.configPage.setEnabled(providerRow.providerData.provider, !providerRow.providerData.enabled)
                }
                // Clicking severs the declarative binding on `checked`; restore it so the
                // switch reverts when a toggle fails or its pending state clears.
                checked = Qt.binding(function() {
                    return providerRow.configPage.visualEnabled(providerRow.providerData.provider, providerRow.providerData.enabled)
                })
            }
        }
    }
}
