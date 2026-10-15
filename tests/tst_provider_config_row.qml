import QtQuick
import QtQuick.Layouts
import QtTest
import "../contents/ui/components" as Components

Item {
    id: page
    width: 500
    height: 400
    property real secondaryTextOpacity: 0.7
    property var providerListFocus: null
    property string selectedProviderID: ""
    property var providers: [
        {
            provider: "a",
            displayName: "A",
            enabled: true
        },
        {
            provider: "b",
            displayName: "B",
            enabled: true
        },
        {
            provider: "c",
            displayName: "C",
            enabled: false
        }
    ]
    property var pending: ({})
    readonly property var enabledRows: providers.filter(function (p) {
        return p.enabled;
    })
    readonly property var disabledRows: providers.filter(function (p) {
        return !p.enabled;
    })
    function i18n(t, a) {
        return String(t).replace("%1", a);
    }
    function providerIconSource(id) {
        return "";
    }
    function providerReadableColor(id, bg) {
        return "black";
    }
    function isPending(id) {
        return pending[id] === true;
    }
    property var pendingDesired: ({})
    function visualEnabled(id, fallback) {
        return pendingDesired.hasOwnProperty(id) ? pendingDesired[id] : fallback === true;
    }
    function updateProviderEnabled(id, enabled) {
        providers = providers.map(function (p) {
            var c = Object.assign({}, p);
            if (c.provider === id)
                c.enabled = enabled;
            return c;
        });
    }
    property var queued: []
    function setEnabled(id, desired) {
        var n = Object.assign({}, pending);
        n[id] = true;
        pending = n;
        var d = Object.assign({}, pendingDesired);
        d[id] = desired;
        pendingDesired = d;
        queued.push({
            id: id,
            desired: desired
        });
    }
    function completeQueued() {
        var q = queued;
        queued = [];
        for (var i = 0; i < q.length; i++) {
            updateProviderEnabled(q[i].id, q[i].desired);
            var n = Object.assign({}, pending);
            delete n[q[i].id];
            pending = n;
            var d = Object.assign({}, pendingDesired);
            delete d[q[i].id];
            pendingDesired = d;
        }
    }
    ColumnLayout {
        id: list
        anchors.fill: parent
        Repeater {
            model: page.enabledRows
            delegate: Components.ProviderConfigRow {
                configPage: page
            }
        }
        Repeater {
            model: page.disabledRows
            delegate: Components.ProviderConfigRow {
                configPage: page
            }
        }
    }
    function rowFor(id) {
        for (var i = 0; i < list.children.length; i++) {
            var r = list.children[i];
            if (r.providerData && r.providerData.provider === id)
                return r;
        }
        return null;
    }
    function switchIn(row) {
        return row.contentItem.children[row.contentItem.children.length - 1];
    }
    Rectangle {
        id: outside
        activeFocusOnTab: true
        width: 10
        height: 10
        y: 390
    }
    TestCase {
        name: "ProviderConfigRow"
        when: windowShown
        function init() {
            page.providers = [
                {
                    provider: "a",
                    displayName: "A",
                    enabled: true
                },
                {
                    provider: "b",
                    displayName: "B",
                    enabled: true
                },
                {
                    provider: "c",
                    displayName: "C",
                    enabled: false
                }
            ];
            page.pending = ({});
            page.pendingDesired = ({});
            page.queued = [];
        }
        function test_toggleKeepsFocus() {
            var sw = page.switchIn(page.rowFor("a"));
            sw.forceActiveFocus(Qt.TabFocusReason);
            verify(sw.activeFocus);
            keyClick(Qt.Key_Space);
            compare(page.queued.length, 1);
            verify(sw.activeFocus, "pending switch lost focus");
            page.completeQueued();
            tryVerify(function () {
                return page.switchIn(page.rowFor("a")).activeFocus;
            }, 1000, "toggled switch lost focus");
        }
        function test_doesNotStealFocusFromElsewhere() {
            page.switchIn(page.rowFor("a")).forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
            outside.forceActiveFocus(Qt.TabFocusReason);
            page.completeQueued();
            wait(50);
            verify(outside.activeFocus, "focus stolen from outside control");
        }
        function test_pendingSwitchIgnoresSecondPress() {
            page.switchIn(page.rowFor("a")).forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
            keyClick(Qt.Key_Space);
            compare(page.queued.length, 1);
            verify(!page.switchIn(page.rowFor("a")).checked, "pending visual state must not flip back");
        }
        function test_otherRowFocusSurvivesUnrelatedResult() {
            page.switchIn(page.rowFor("a")).forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
            page.rowFor("b").forceActiveFocus(Qt.TabFocusReason);
            page.completeQueued();
            tryVerify(function () {
                return page.rowFor("b").activeFocus;
            }, 1000, "row b lost focus after result for a");
        }
    }
}
