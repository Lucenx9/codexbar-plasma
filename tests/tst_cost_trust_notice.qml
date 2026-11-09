import QtQuick
import QtTest
import "../contents/ui/components" as Components
import "../contents/ui/CostTrust.js" as CostTrust

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

        notice.presentationVisible = false
        notice.visible = false

        compare(owner.dismissals, [])
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
