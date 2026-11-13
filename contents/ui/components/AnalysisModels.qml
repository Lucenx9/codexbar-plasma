import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../UsageAnalysis.js" as Analysis
import "../CostAmounts.mjs" as Amounts

ColumnLayout {
    id: section
    objectName: "analysisModels"
    required property var applet
    required property var costs
    property string selectedDay: ""
    property bool expanded: false
    readonly property var models: expanded ? Analysis.modelRows(costs, selectedDay, applet.costHistoryShowsTokens)
        : ({rows: [], truncated: false})
    Layout.fillWidth: true

    DisclosureButton {
        plainText: i18n("Models and token composition")
        expanded: section.expanded
        onClicked: section.expanded = !section.expanded
    }
    ColumnLayout {
        visible: section.expanded
        Layout.fillWidth: true
        PlainPlasmaLabel {
            text: i18n("Model breakdown is partial.")
            visible: section.models.truncated
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        PlainPlasmaLabel {
            text: section.selectedDay ? i18n("No model breakdown for this day.") : i18n("No model breakdown for this period.")
            visible: section.models.rows.length === 0
            opacity: applet.secondaryTextOpacity
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        Repeater {
            model: section.models.rows
            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                RowLayout {
                    Layout.fillWidth: true
                    PlainPlasmaLabel {
                        text: applet.providerDisplayTitle(modelData.provider) + " · " + modelData.label
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        wrapMode: Text.Wrap
                    }
                    PlainPlasmaLabel {
                        id: modelAmount
                        text: Amounts.hasMetricValue(modelData, applet.costHistoryShowsTokens)
                            ? applet.costHistoryShowsTokens ? applet.usageCountText(modelData.tokens, "tokens")
                                : applet.qualifiedCostValue(applet.amountString(modelData.cost, modelData.currency), modelData.valueMode)
                            : i18n("Unavailable")
                        font.features: { "tnum": 1 }
                        Layout.maximumWidth: section.width * 0.5
                        elide: Text.ElideRight
                        HoverHandler { id: amountHover }
                        PlainToolTip { visible: modelAmount.truncated && amountHover.hovered; plainText: modelAmount.text }
                    }
                }
                PlainPlasmaLabel {
                    visible: modelData.incompleteRequests > 0
                    text: i18np("%1 incomplete request excluded", "%1 incomplete requests excluded", modelData.incompleteRequests || 0)
                    font: Kirigami.Theme.smallFont
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
        }
        Repeater {
            model: section.expanded ? Analysis.dayCosts(section.costs, section.selectedDay) : []
            delegate: ColumnLayout {
                required property var modelData
                readonly property var parts: labels.costBreakdownRows(modelData)
                visible: parts.length > 1
                Layout.fillWidth: true
                CostLabels {
                    id: labels
                    numberFormat: applet.costNumberFormat
                    showsTokens: true
                    tokenCountText: applet.usageCountText
                }
                PlainPlasmaLabel {
                    text: applet.providerDisplayTitle(modelData.provider)
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
                Repeater {
                    model: parts
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        PlainPlasmaLabel {
                            text: modelData.label
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            wrapMode: Text.Wrap
                        }
                        PlainPlasmaLabel {
                            id: partAmount
                            text: modelData.value
                            font.features: { "tnum": 1 }
                            Layout.maximumWidth: section.width * 0.5
                            elide: Text.ElideRight
                            HoverHandler { id: partHover }
                            PlainToolTip { visible: partAmount.truncated && partHover.hovered; plainText: partAmount.text }
                        }
                    }
                }
            }
        }
    }
}
