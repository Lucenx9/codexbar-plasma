import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

PlainInlineMessage {
    id: noticeRoot

    property var stateOwner: null
    property string noticeScope: ""
    property bool presentationVisible: false
    property var summary: null
    property var noticeState: ({ key: "", dismissed: false, shouldShow: false })

    visible: false
    plainText: summaryText()
    type: summary && summary.level === "warning"
        ? Kirigami.MessageType.Warning
        : Kirigami.MessageType.Information
    showCloseButton: true
    Layout.fillWidth: true

    onSummaryChanged: scheduleRefreshNoticeState()
    onNoticeScopeChanged: scheduleRefreshNoticeState()
    onStateOwnerChanged: scheduleRefreshNoticeState()
    onTextChanged: syncVisibility()
    onVisibleChanged: {
        // Kirigami's close button hides the message directly. Convert that
        // effect into semantic state before a refresh can show it again. An
        // invisible presentation means ordinary tab navigation, not a close
        // action.
        if (!visible
                && presentationVisible
                && text.length > 0
                && noticeState.shouldShow === true) {
            dismissNotice()
        }
    }
    Component.onCompleted: scheduleRefreshNoticeState()

    Timer {
        id: noticeRefresh

        interval: 0
        repeat: false
        onTriggered: noticeRoot.refreshNoticeState()
    }

    function scheduleRefreshNoticeState() {
        // Provider selection updates the scope and bound summary separately.
        // Coalesce both bindings before touching the shared dismissal store so
        // one provider's warning cannot overwrite another provider's state.
        noticeRefresh.restart()
    }

    function refreshNoticeState() {
        updateNoticeState(false)
    }

    function dismissNotice() {
        updateNoticeState(true)
    }

    function updateNoticeState(shouldDismiss) {
        // Property bindings are installed one at a time while QML constructs
        // the component. A summary can therefore arrive before its owner during
        // that brief initialization window.
        if (!stateOwner
                || typeof stateOwner.updateCostTrustNoticeState !== "function") {
            noticeState = ({ key: "", dismissed: false, shouldShow: false })
            syncVisibility()
            return
        }
        noticeState = stateOwner.updateCostTrustNoticeState(
            noticeScope, summary, shouldDismiss)
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

    // The CLI reports how many requests it excluded from the displayed amounts.
    // Keep it a separate sentence so the coverage and source wording that
    // translators already have stays untouched.
    function incompleteText() {
        var count = summary && typeof summary.incompleteRequests === "number"
            && isFinite(summary.incompleteRequests)
            ? Math.floor(summary.incompleteRequests)
            : 0
        if (count <= 0) {
            return ""
        }
        return i18np(
            "%1 request in the selected range lacked final usage, so it is excluded from the displayed totals.",
            "%1 requests in the selected range lacked final usage, so they are excluded from the displayed totals.",
            count)
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
        var sentences = []
        var coverage = coverageText()
        if (coverage.length > 0) {
            sentences.push(coverage)
        }
        var incomplete = incompleteText()
        if (incomplete.length > 0) {
            sentences.push(incomplete)
        }
        var source = sourceText()
        if (source.length > 0) {
            sentences.push(source)
        }
        // Join with the sentence separator translators already have instead of
        // adding a placeholder-only message per sentence count.
        var text = sentences.length > 0 ? sentences[0] : ""
        for (var i = 1; i < sentences.length; i++) {
            text = i18n("%1 %2", text, sentences[i])
        }
        return text
    }
}
