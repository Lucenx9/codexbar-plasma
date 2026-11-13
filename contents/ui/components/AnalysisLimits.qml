import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

PlasmaComponents.ScrollView {
    id: limits
    objectName: "analysisLimits"
    required property var applet
    Layout.fillWidth: true
    Layout.fillHeight: true
    contentWidth: availableWidth
    clip: true
    PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff

    ColumnLayout {
        width: Math.max(0, limits.availableWidth - Kirigami.Units.smallSpacing)
        spacing: Kirigami.Units.largeSpacing
        PlainPlasmaLabel {
            text: i18n("Current limits have different capacities and reset windows. Their percentages are not additive.")
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: applet.secondaryTextOpacity
        }
        Controls.BusyIndicator {
            visible: applet.loading === true && applet.presentedProviders.length === 0
            running: visible
            Layout.alignment: Qt.AlignHCenter
        }
        PlainPlasmaLabel {
            visible: applet.loading !== true && applet.presentedProviders.length === 0
            text: i18n("No provider data")
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }
        Repeater {
            model: applet.presentedProviders
            delegate: ColumnLayout {
                id: provider
                required property var modelData
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                PlasmaComponents.AbstractButton {
                    id: providerButton
                    Layout.fillWidth: true
                    implicitHeight: providerIdentity.implicitHeight + padding * 2
                    padding: Kirigami.Units.smallSpacing
                    Accessible.role: Accessible.Button
                    Accessible.name: applet.providerDisplayTitle(provider.modelData.provider)
                    background: Rectangle {
                        radius: applet.roundedSurfaceRadius
                        color: providerButton.hovered || providerButton.down
                            ? applet.withAlpha(Kirigami.Theme.highlightColor, 0.12) : "transparent"
                        border.width: providerButton.visualFocus ? 2 : 0
                        border.color: Kirigami.Theme.focusColor
                    }
                    contentItem: RowLayout {
                        id: providerIdentity
                        spacing: Kirigami.Units.largeSpacing
                        Rectangle {
                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                + Kirigami.Units.smallSpacing * 2
                            Layout.preferredHeight: Layout.preferredWidth
                            radius: applet.nestedSurfaceRadius
                            color: applet.withAlpha(applet.providerReadableColor(
                                provider.modelData.provider, Kirigami.Theme.backgroundColor), 0.12)
                            border.width: 1
                            border.color: applet.withAlpha(Kirigami.Theme.textColor, 0.1)
                            Kirigami.Icon {
                                anchors.centerIn: parent
                                source: applet.providerIconSource(provider.modelData.provider)
                                fallback: "view-statistics"
                                isMask: applet.providerIconIsMask(provider.modelData.provider)
                                color: applet.providerReadableColor(provider.modelData.provider,
                                    Kirigami.Theme.backgroundColor)
                                width: Kirigami.Units.iconSizes.smallMedium
                                height: Kirigami.Units.iconSizes.smallMedium
                            }
                        }
                        PlainPlasmaLabel {
                            id: providerTitle
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: providerButton.Accessible.name
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                    }
                    PlainToolTip {
                        visible: providerTitle.truncated && (providerButton.hovered || providerButton.visualFocus)
                        plainText: providerButton.Accessible.name
                    }
                    onClicked: {
                        applet.selectedProviderID = provider.modelData.provider
                        applet.selectionInitialized = true
                    }
                }
                PlainPlasmaLabel {
                    visible: provider.modelData.usageStale === true
                    text: applet.lastGoodUsageText(provider.modelData)
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
                PlainPlasmaLabel {
                    visible: provider.modelData.rows.length === 0
                    text: i18n("Limits not available")
                    opacity: applet.secondaryTextOpacity
                }
                Repeater {
                    model: provider.modelData.rows
                    delegate: ProviderUsageRow {
                        required property var modelData
                        rowData: modelData
                        showPace: applet.showPopupPace && provider.modelData.usageStale !== true
                        hideable: false
                        percentText: applet.usagePercentText(rowData)
                        paceText: provider.modelData.usageStale === true ? "" : applet.usagePaceText(rowData)
                        resetText: applet.resetLabel(applet.usageResetText(rowData))
                        confidenceText: applet.usageConfidenceText(rowData)
                        shownPercent: applet.displayPercent(rowData)
                        markerPercent: provider.modelData.usageStale === true ? -1 : applet.paceMarkerPercent(rowData)
                        meterColor: applet.quotaMeterColor(rowData, applet.providerReadableColor(
                            provider.modelData.provider, Kirigami.Theme.backgroundColor))
                        warningMarkers: []
                        meterTrackHeight: applet.meterTrackHeight
                        secondaryTextOpacity: applet.secondaryTextOpacity
                    }
                }
                Kirigami.Separator { Layout.fillWidth: true }
            }
        }
    }
}
