import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../CostPresentation.js" as CostPresentation

ColumnLayout {
    id: section
    objectName: "projectCostSection"

    required property var applet
    required property var providerCosts
    readonly property var projectData: CostPresentation.projectRows(providerCosts, applet.costHistoryShowsTokens)

    visible: projectData.rows.length > 0 || projectData.truncated
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    function valueText(row) {
        if (!CostPresentation.hasMetricValue(row, applet.costHistoryShowsTokens)) {
            return applet.costHistoryShowsTokens ? i18n("Tokens unavailable") : i18n("Cost unavailable");
        }
        return applet.costHistoryShowsTokens ? i18n("%1 tokens", applet.tokenCountString(row.tokens)) : applet.qualifiedCostValue(applet.amountString(row.cost, row.currency), row.valueMode);
    }

    PlainPlasmaLabel {
        text: i18n("Projects")
        font.weight: Font.DemiBold
        Layout.fillWidth: true
    }

    PlainPlasmaLabel {
        text: section.applet.costHistoryShowsTokens ? i18n("Local token usage for the selected range.") : i18n("API-rate estimates for the selected range, not billed amounts.")
        opacity: section.applet.secondaryTextOpacity
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }

    Repeater {
        model: section.projectData.rows

        delegate: ColumnLayout {
            required property var modelData

            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing / 2

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                PlainPlasmaLabel {
                    text: modelData.label
                    Layout.fillWidth: true
                    Layout.preferredWidth: section.width * 0.55
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignTop
                    wrapMode: Text.Wrap
                }

                PlainPlasmaLabel {
                    text: section.valueText(modelData)
                    opacity: section.applet.valueTextOpacity
                    Layout.fillWidth: true
                    Layout.preferredWidth: section.width * 0.45
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignTop
                    horizontalAlignment: Text.AlignRight
                    wrapMode: Text.Wrap
                }
            }

            PlainPlasmaLabel {
                text: section.applet.providerTitle(modelData.provider)
                opacity: section.applet.secondaryTextOpacity
                font: Kirigami.Theme.smallFont
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
        }
    }

    PlainPlasmaLabel {
        visible: section.projectData.truncated
        text: i18n("Some projects are omitted from this list. Provider totals include the full reported range.")
        opacity: section.applet.secondaryTextOpacity
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }
}
