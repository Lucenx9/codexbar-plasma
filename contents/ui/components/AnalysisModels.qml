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
    property bool showAll: false
    readonly property var models: expanded ? Analysis.modelRows(costs, selectedDay, applet.costHistoryShowsTokens)
        : ({rows: [], truncated: false})
    readonly property bool hasMore: models.rows.length > 3
    readonly property bool actionFocused: showMore.activeFocus
    signal restoreFocusRequested()
    signal showAllRequested(bool value)
    onHasMoreChanged: if (!hasMore && showMore.activeFocus) restoreFocusRequested()
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    spacing: Kirigami.Units.smallSpacing

    function restoreActionFocus() {
        if (expanded && hasMore) showMore.forceActiveFocus(Qt.OtherFocusReason)
        else restoreFocusRequested()
    }

    RowLayout {
        Layout.fillWidth: true
        PlainPlasmaLabel {
            text: i18n("Models")
            opacity: section.applet.secondaryTextOpacity
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            wrapMode: Text.Wrap
        }
        PlainButton {
            id: showMore
            objectName: "analysisModelsShowMore"
            visible: section.hasMore
            flat: true
            plainText: section.showAll ? i18n("Show fewer models") : i18n("Show more models")
            onClicked: section.showAllRequested(!section.showAll)
        }
    }
    PlainPlasmaLabel {
        text: i18n("Some models are not shown.")
        visible: section.models.truncated
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }
    PlainPlasmaLabel {
        text: section.selectedDay ? i18n("No model data for this day.") : i18n("No model data for this period.")
        visible: section.models.rows.length === 0
        opacity: applet.secondaryTextOpacity
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }
    Repeater {
        model: section.showAll ? section.models.rows : section.models.rows.slice(0, 3)
        delegate: ColumnLayout {
            id: modelRow
            required property var modelData
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: Kirigami.Units.smallSpacing / 2
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                PlainPlasmaLabel {
                    text: modelRow.modelData.label
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 3
                    Layout.alignment: Qt.AlignTop
                    wrapMode: Text.Wrap
                }
                PlainPlasmaLabel {
                    id: modelAmount
                    text: Amounts.hasMetricValue(modelRow.modelData, section.applet.costHistoryShowsTokens)
                        ? section.applet.costHistoryShowsTokens ? section.applet.usageCountText(modelRow.modelData.tokens, "tokens")
                            : section.applet.qualifiedCostValue(section.applet.amountString(modelRow.modelData.cost, modelRow.modelData.currency), modelRow.modelData.valueMode)
                        : i18n("Unavailable")
                    font.features: { "tnum": 1 }
                    Layout.alignment: Qt.AlignTop
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 2
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    Accessible.name: i18n("%1: %2", modelRow.modelData.label, text)
                    HoverHandler { id: amountHover }
                    PlainToolTip { visible: modelAmount.truncated && amountHover.hovered; plainText: modelAmount.text }
                }
            }
            PlainPlasmaLabel {
                visible: modelRow.modelData.incompleteRequests > 0
                text: i18np("%1 incomplete request excluded", "%1 incomplete requests excluded", modelRow.modelData.incompleteRequests || 0)
                font: Kirigami.Theme.smallFont
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }
    }
}
