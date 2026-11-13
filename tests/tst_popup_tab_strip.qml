import QtQuick
import QtQuick.Controls as Controls
import QtTest
import "../contents/ui/components" as Components

TestCase {
    id: testCase
    name: "PopupTabStrip"
    when: windowShown
    visible: true
    width: 620
    height: 130

    QtObject {
        id: appearance
        readonly property real roundedSurfaceRadius: 8
        function withAlpha(color, alpha) {
            return Qt.rgba(color.r, color.g, color.b, alpha);
        }
        function readableAccentColor(accent) {
            return accent;
        }
    }

    Component {
        id: stripFactory
        Components.PopupTabStrip {
            id: host
            width: 280
            surfaceRadius: appearance.roundedSurfaceRadius
            function i18n(text) {
                return text;
            }
            property int selectedIndex: 0
            property bool showLabels: true
            property string firstTitle: "First tab"
            property string lastTitle: "Synthetic tab 7"
            property bool mirrored: false
            LayoutMirroring.enabled: mirrored
            LayoutMirroring.childrenInherit: true

            Repeater {
                model: 8
                Components.GlobalTab {
                    required property int index
                    objectName: "tab" + index
                    applet: appearance
                    title: index === 0 ? host.firstTitle
                        : (index === 7 ? host.lastTitle : "Synthetic tab " + index)
                    iconName: "view-grid-symbolic"
                    tabHeight: host.tabHeight
                    tabStrip: host
                    showLabel: host.showLabels
                    selected: index === host.selectedIndex
                    onActivated: host.selectedIndex = index
                }
            }
        }
    }

    Component {
        id: outsideButtonFactory
        Controls.Button {
            y: 80
            text: "Outside navigation"
        }
    }

    function createStrip() {
        failOnWarning(/ReferenceError|TypeError|SyntaxError|Detected recursive rearrange/);
        var host = createTemporaryObject(stripFactory, testCase);
        verify(host !== null);
        tryVerify(function () {
            return findChild(host, "tab7").width > 0;
        });
        wait(0);
        return host;
    }

    function focusFor(host, index) {
        return findChild(host, "tab" + index).nextItemInFocusChain(true);
    }

    function verifyRevealed(host, index) {
        var viewport = findChild(host, "providerTabsFlickable");
        var tab = findChild(host, "tab" + index);
        var x = tab.mapToItem(viewport, 0, 0).x;
        verify(x >= -1, "tab starts before viewport: " + x);
        verify(tab.width > viewport.width || x + tab.width <= viewport.width + 1, "tab ends after viewport: " + x + " + " + tab.width + " > " + viewport.width);
    }

    function test_keyboardWrapsAndJumpsWithoutSelectingUntilActivation() {
        var host = createStrip();
        var first = focusFor(host, 0);
        var last = focusFor(host, 7);
        first.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Left);
        verify(last.activeFocus);
        verifyRevealed(host, 7);
        compare(host.selectedIndex, 0);
        keyClick(Qt.Key_Right);
        verify(first.activeFocus);
        keyClick(Qt.Key_End);
        verify(last.activeFocus);
        keyClick(Qt.Key_Return);
        compare(host.selectedIndex, 7);
        keyClick(Qt.Key_Home);
        verify(first.activeFocus);
        verifyRevealed(host, 0);
        keyClick(Qt.Key_Up);
        verify(first.activeFocus);
        keyClick(Qt.Key_Space);
        compare(host.selectedIndex, 0);
    }

    function test_overflowControlsAndWheelKeepScrollBounded() {
        var host = createStrip();
        var viewport = findChild(host, "providerTabsFlickable");
        var previous = findChild(host, "previousTabsButton");
        var next = findChild(host, "nextTabsButton");
        verify(host.tabsOverflow);
        verify(previous.visible && next.visible);
        verify(previous.x + previous.width <= viewport.x);
        verify(next.x >= viewport.x + viewport.width);
        verify(!previous.enabled && next.enabled);
        mouseClick(next);
        tryVerify(function () {
            return viewport.contentX > 0;
        });
        host.scrollTo(0, true);
        mouseWheel(viewport, viewport.width / 2, viewport.height / 2, 0, -120);
        tryVerify(function () {
            return viewport.contentX > 0;
        });
        host.scrollBy(100000, true);
        compare(viewport.contentX, viewport.contentWidth - viewport.width);
        verify(previous.enabled && !next.enabled);
        host.scrollBy(-100000, true);
        compare(viewport.contentX, 0);
        verify(!previous.enabled && next.enabled);
    }

    function test_selectionAndResizeRevealTheCurrentTab() {
        var host = createStrip();
        host.selectedIndex = 7;
        verifyRevealed(host, 7);
        host.width = 240;
        wait(0);
        verifyRevealed(host, 7);
        host.selectedIndex = 0;
        verifyRevealed(host, 0);
        var first = focusFor(host, 0);
        first.forceActiveFocus(Qt.TabFocusReason);
        host.firstTitle = "Updated synthetic title";
        wait(0);
        compare(focusFor(host, 0), first);
        verify(first.activeFocus);
        verifyRevealed(host, 0);
    }

    function test_aFittingIconStripHidesControlsAndRejectsForeignFocus() {
        var host = createStrip();
        host.width = 600;
        host.showLabels = false;
        wait(0);
        tryCompare(host, "tabsOverflow", false);
        verify(!findChild(host, "previousTabsButton").visible);
        verify(!findChild(host, "nextTabsButton").visible);
        verify(!host.navigateFromTab(testCase, Qt.Key_Right));
        host.ensureVisible(testCase);
        compare(findChild(host, "providerTabsFlickable").contentX, 0);
    }

    function test_navigationSkipsHiddenAndDisabledTabs() {
        var host = createStrip();
        var first = focusFor(host, 0);
        var third = focusFor(host, 3);
        findChild(host, "tab1").visible = false;
        findChild(host, "tab2").enabled = false;
        wait(0);
        first.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Right);
        verify(third.activeFocus, "Right must skip unavailable tabs");
        keyClick(Qt.Key_Left);
        verify(first.activeFocus, "Left must skip unavailable tabs");
    }

    function test_layoutKeepsTheFocusedUnselectedTabVisible_data() {
        return [
            { tag: "resize", rename: false },
            { tag: "label-growth", rename: true }
        ];
    }

    function test_layoutKeepsTheFocusedUnselectedTabVisible(data) {
        var host = createStrip();
        var last = focusFor(host, 7);
        last.forceActiveFocus(Qt.TabFocusReason);
        verifyRevealed(host, 7);
        if (data.rename) {
            host.firstTitle = "A much longer synthetic tab title after a refresh";
        } else {
            host.width = 240;
        }
        waitForPolish(findChild(host, "tab0").parent);
        wait(0);
        verify(last.activeFocus);
        compare(host.selectedIndex, 0);
        verifyRevealed(host, 7);
    }

    function test_resizeRevealsSelectionWithoutTakingOutsideFocus() {
        var host = createStrip();
        var outside = createTemporaryObject(outsideButtonFactory, testCase);
        verify(outside !== null);
        focusFor(host, 7).forceActiveFocus(Qt.TabFocusReason);
        outside.forceActiveFocus(Qt.TabFocusReason);
        host.width = 240;
        waitForPolish(findChild(host, "tab0").parent);
        wait(0);
        verify(outside.activeFocus);
        compare(host.selectedIndex, 0);
        verifyRevealed(host, 0);
    }

    function test_labelChangesRevealFocusWhenTotalWidthStaysTheSame() {
        var host = createStrip();
        host.lastTitle = "A much longer synthetic tab title after a refresh";
        waitForPolish(findChild(host, "tab0").parent);
        wait(0);
        var focused = focusFor(host, 6);
        focused.forceActiveFocus(Qt.TabFocusReason);
        verifyRevealed(host, 6);
        var viewport = findChild(host, "providerTabsFlickable");
        var width = viewport.contentWidth;
        var firstTitle = host.firstTitle;
        host.firstTitle = host.lastTitle;
        host.lastTitle = firstTitle;
        waitForPolish(findChild(host, "tab0").parent);
        wait(0);
        verify(Math.abs(viewport.contentWidth - width) < 1);
        verify(focused.activeFocus);
        compare(host.selectedIndex, 0);
        verifyRevealed(host, 6);
    }

    function test_arrowsFollowMirroredTabPositions() {
        var host = createStrip();
        host.mirrored = true;
        wait(0);
        var first = focusFor(host, 0);
        var second = focusFor(host, 1);
        tryVerify(function () {
            return findChild(host, "tab0").x > findChild(host, "tab1").x;
        });
        first.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Left);
        verify(second.activeFocus, "Left must move to the visually adjacent RTL tab");
        compare(host.selectedIndex, 0);
        verifyRevealed(host, 1);
        keyClick(Qt.Key_Right);
        verify(first.activeFocus);
        keyClick(Qt.Key_Right);
        verify(focusFor(host, 7).activeFocus, "Right wraps at the RTL start");
        verifyRevealed(host, 7);
        keyClick(Qt.Key_Left);
        verify(first.activeFocus, "Left wraps at the RTL end");
        keyClick(Qt.Key_End);
        verify(focusFor(host, 7).activeFocus);
        keyClick(Qt.Key_Return);
        compare(host.selectedIndex, 7);
        keyClick(Qt.Key_Home);
        verify(first.activeFocus);
        compare(host.selectedIndex, 7);
        keyClick(Qt.Key_Space);
        compare(host.selectedIndex, 0);
    }
}
