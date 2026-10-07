import QtQuick
import QtTest
import "../contents/ui/components" as Components

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

    // Records dismissals and keeps showing the notice until one arrives.
    QtObject {
        id: owner

        property var dismissals: []

        function updateCostTrustNoticeState(scope, summary, shouldDismiss) {
            if (shouldDismiss) {
                dismissals = dismissals.concat([scope])
            }
            return { key: scope, dismissed: dismissals.length > 0, shouldShow: dismissals.length === 0 }
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
    }

    function test_closeButtonDismissesTheScope() {
        var notice = createTemporaryObject(noticeComponent, this)
        tryVerify(function() { return notice.visible })

        findChild(notice, "plainNoteCloseButton").clicked()

        verify(!notice.visible)
        compare(owner.dismissals, ["spend"])
    }

    function test_hiddenPresentationDoesNotDismiss() {
        var notice = createTemporaryObject(noticeComponent, this)
        tryVerify(function() { return notice.visible })

        notice.presentationVisible = false
        notice.visible = false

        compare(owner.dismissals, [])
    }
}
