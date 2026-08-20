import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../CostPresentation.js" as CostPresentation

Kirigami.InlineMessage {
    id: noticeRoot

    property var summary: null
    property var noticeState: ({ key: "", dismissed: false, shouldShow: false })

    visible: false
    text: summaryText()
    type: summary && summary.level === "warning"
        ? Kirigami.MessageType.Warning
        : Kirigami.MessageType.Information
    showCloseButton: true
    Layout.fillWidth: true

    onSummaryChanged: refreshNoticeState()
    onTextChanged: syncVisibility()
    onVisibleChanged: {
        // Kirigami's close button hides the message directly. Convert that
        // effect into semantic state before a refresh can show it again. An
        // invisible parent means ordinary tab navigation, not a close action.
        if (!visible
                && parent !== null
                && parent.visible
                && text.length > 0
                && noticeState.shouldShow === true) {
            dismissNotice()
        }
    }
    Component.onCompleted: refreshNoticeState()

    function refreshNoticeState() {
        updateNoticeState(false)
    }

    function dismissNotice() {
        updateNoticeState(true)
    }

    function updateNoticeState(shouldDismiss) {
        noticeState = CostPresentation.costTrustNoticeTransition(
            summary, noticeState, shouldDismiss)
        syncVisibility()
    }

    function syncVisibility() {
        visible = noticeState.shouldShow === true && text.length > 0
    }

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
