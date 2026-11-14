import QtQuick
import QtTest
import "../contents/ui/components" as Components
import "../contents/ui/CostTrust.mjs" as CostTrust

TestCase {
    name: "CostTrustNotice"
    when: windowShown

    width: 400
    height: 200
    visible: true

    function i18n(text) {
        for (var i = 1; i < arguments.length; ++i) {
            text = text.replace("%" + i, arguments[i]);
        }
        return text;
    }
    function i18np(singular, plural, count) {
        return i18n(count === 1 ? singular : plural, count);
    }

    // Like the applet owner, keep semantic dismissal state across popup instances.
    QtObject {
        id: owner

        property var dismissals: []
        property var noticeStates: ({})

        function updateCostTrustNoticeState(scope, summary, shouldDismiss) {
            if (shouldDismiss) {
                dismissals = dismissals.concat([scope])
            }
            var result = CostTrust.costTrustNoticeStoreTransition(summary, noticeStates, scope, shouldDismiss)
            noticeStates = result.states
            return result.state
        }
    }

    Component {
        id: popupComponent
        Item {
            id: popup
            width: 400
            height: 200
            property alias view: view
            property alias notice: notice

            Item {
                id: view
                anchors.fill: parent

                Components.CostTrustNotice {
                    id: notice
                    width: parent.width
                    noticeScope: "spend"
                    stateOwner: owner
                    presentationVisible: view.visible
                    summary: ({ sourceKind: "listPrice" })
                }
            }
        }
    }

    Component {
        id: noticeComponent
        Components.CostTrustNotice {
            width: 400
            noticeScope: "spend"
            stateOwner: owner
            presentationVisible: true
            summary: ({ sourceKind: "listPrice" })
        }
    }

    function init() {
        owner.dismissals = []
        owner.noticeStates = ({})
    }

    function test_closeButtonDismissesTheScope_data() {
        return [{ tag: "pointer", keyboard: false }, { tag: "keyboard", keyboard: true }]
    }

    function test_closeButtonDismissesTheScope(data) {
        var notice = createTemporaryObject(noticeComponent, this)
        tryVerify(function() { return notice.visible })
        verify(waitForPolish(notice))

        var details = findChild(notice, "plainNoteDetailsButton")
        mouseClick(details)
        verify(notice.expanded)

        var close = findChild(notice, "plainNoteCloseButton")
        if (data.keyboard) {
            close.forceActiveFocus(Qt.TabFocusReason)
            keyClick(Qt.Key_Space)
        } else {
            mouseClick(close)
        }

        verify(!notice.visible)
        compare(owner.dismissals, ["spend"])

        var recreated = createTemporaryObject(noticeComponent, this)
        wait(0)
        verify(!recreated.visible)
        // A different meaning still revives the notice after an explicit dismissal.
        recreated.summary = { sourceKind: "unknown" }
        tryVerify(function() { return recreated.visible })
    }

    function test_hiddenPresentationDoesNotDismiss() {
        var notice = createTemporaryObject(noticeComponent, this)
        tryVerify(function() { return notice.visible })
        verify(waitForPolish(notice))

        notice.presentationVisible = false
        notice.visible = false

        compare(owner.dismissals, [])
    }

    function test_explanationStartsCollapsedAndCanBeOpened_data() {
        return [{ tag: "pointer", keyboard: false }, { tag: "keyboard", keyboard: true }]
    }

    function test_explanationStartsCollapsedAndCanBeOpened(data) {
        var notice = createTemporaryObject(noticeComponent, this)
        tryVerify(function() { return notice.visible })
        verify(waitForPolish(notice))
        var label = findChild(notice, "plainNoteLabel")
        var details = findChild(notice, "plainNoteDetailsButton")
        verify(!label.visible)
        if (data.keyboard) {
            details.forceActiveFocus(Qt.TabFocusReason)
            keyClick(Qt.Key_Space)
        } else {
            mouseClick(details)
        }
        verify(label.visible)
        compare(label.text, "The total is estimated from public list prices.")

        notice.summary = { sourceKind: "listPrice" }
        wait(0)
        verify(label.visible)
        notice.summary = { sourceKind: "unknown" }
        tryVerify(function() { return !label.visible })
        compare(owner.dismissals, [])
    }

    function test_scopeChangeCollapsesExplanationAndRestoresFocus() {
        var notice = createTemporaryObject(noticeComponent, this)
        tryVerify(function() { return notice.visible })
        verify(waitForPolish(notice))
        var details = findChild(notice, "plainNoteDetailsButton")
        mouseClick(details)
        findChild(notice, "plainNoteCloseButton").forceActiveFocus(Qt.TabFocusReason)
        notice.noticeScope = "provider:codex"
        tryVerify(function() { return !notice.expanded })
        verify(details.activeFocus)
        compare(owner.dismissals, [])
    }

    function test_partialTokensKeepAVisibleQualifierWithoutCost() {
        var notice = createTemporaryObject(noticeComponent, this, {
            summary: CostTrust.costTrustSummary([{totals: {cost: null, tokens: 20},
                trust: {incompleteRequests: 2}}])
        })
        tryVerify(function() { return notice.visible })
        verify(waitForPolish(notice))
        compare(findChild(notice, "plainNoteDetailsButton").plainText, "Partial data")
        verify(!findChild(notice, "plainNoteLabel").visible)
    }

    function test_enlargedTranslatedDisclosureFitsNarrowWidth() {
        var notice = createTemporaryObject(noticeComponent, this, {
            width: 240, heading: "Informationen zu diesen Kosten"
        })
        tryVerify(function() { return notice.visible })
        verify(waitForPolish(notice))
        var details = findChild(notice, "plainNoteDetailsButton")
        details.font.pointSize = 24
        verify(waitForPolish(notice))
        verify(details.width > 0)
        verify(details.mapToItem(notice, 0, 0).x >= 0)
        verify(details.mapToItem(notice, details.width, 0).x <= notice.width)
        details.forceActiveFocus(Qt.TabFocusReason)
        keyClick(Qt.Key_Space)
        verify(waitForPolish(notice))
        verify(findChild(notice, "plainNoteLabel").visible)
        verify(details.mapToItem(notice, details.width, 0).x <= notice.width)
        compare(details.Accessible.name, "Informationen zu diesen Kosten")
    }

    function test_hidingAncestorsPreservesTheNotice_data() {
        return [{ tag: "switch-tab", hideView: true }, { tag: "close-popup", hideView: false }]
    }

    function test_hidingAncestorsPreservesTheNotice(data) {
        var popup = createTemporaryObject(popupComponent, this)
        tryVerify(function() { return popup.notice.visible })

        var ancestor = data.hideView ? popup.view : popup
        ancestor.visible = false
        verify(!popup.notice.visible)
        compare(owner.dismissals, [])

        ancestor.visible = true
        tryVerify(function() { return popup.notice.visible })
        popup.destroy()
        wait(0)
        var recreated = createTemporaryObject(popupComponent, this)
        tryVerify(function() { return recreated.notice.visible })
        compare(owner.dismissals, [])
    }
}
