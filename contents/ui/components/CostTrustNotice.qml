import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.InlineMessage {
    id: noticeRoot

    required property var summary

    visible: summary !== null && text.length > 0
    text: summaryText()
    type: summary && summary.level === "warning"
        ? Kirigami.MessageType.Warning
        : Kirigami.MessageType.Information
    Layout.fillWidth: true

    function coverageText() {
        if (!summary) {
            return ""
        }
        if (summary.hasUnpriced && summary.hasUnmetered) {
            return i18n("Some usage in the selected range is unpriced or unmetered, so the displayed cost total is incomplete.")
        }
        if (summary.hasUnpriced) {
            return i18n("Some usage in the selected range is unpriced, so the displayed cost total is incomplete.")
        }
        if (summary.hasUnmetered) {
            return i18n("Some usage in the selected range is unmetered, so the displayed cost total is incomplete.")
        }
        if (summary.hasEstimated
                && summary.sourceKind !== "listPrice"
                && summary.sourceKind !== "mixed") {
            return i18n("Some usage costs in the selected range are estimated.")
        }
        return ""
    }

    function sourceText() {
        if (!summary) {
            return ""
        }
        switch (summary.sourceKind) {
        case "listPrice":
            return i18n("The displayed range total is estimated from public list prices.")
        case "vendor":
            return i18n("The displayed range total uses provider-metered cost data.")
        case "mixed":
            return i18n("The displayed range total combines provider-metered cost data and public list-price estimates.")
        case "unknown":
            return i18n("The source of the displayed range total could not be verified.")
        default:
            return ""
        }
    }

    function summaryText() {
        var coverage = coverageText()
        var source = sourceText()
        if (coverage.length > 0 && source.length > 0) {
            return i18n("%1 %2", coverage, source)
        }
        return coverage.length > 0 ? coverage : source
    }
}
