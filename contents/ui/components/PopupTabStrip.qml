import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "../TabStripGeometry.js" as TabStripGeometry

// Tab contents and activation belong to the caller. This module owns the
// viewport, overflow controls, selection reveal and keyboard focus navigation.
Item {
    id: strip
    objectName: "popupTabStrip"

    default property alias tabs: providerTabs.data
    required property real surfaceRadius
    readonly property real tabHeight: providerTabsFlickable.height
    readonly property real tabPageStep: Math.max(Kirigami.Units.gridUnit * 4, providerTabsFlickable.width * 0.6)
    readonly property real tabWheelStep: Kirigami.Units.gridUnit * 5
    property Item selectedTab: null
    // Reserve button space only after comparing the full strip width.
    readonly property bool tabsOverflow: width > 0 && providerTabs.implicitWidth > width - Kirigami.Units.smallSpacing

    implicitHeight: Kirigami.Units.gridUnit * 2.35

    function withAlpha(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha);
    }

    function scrollTo(position, immediate) {
        var bounded = TabStripGeometry.boundedPosition(position, providerTabsFlickable.contentWidth, providerTabsFlickable.width);
        providerTabsScroll.stop();
        if (immediate || Kirigami.Units.shortDuration <= 0) {
            providerTabsFlickable.contentX = bounded;
            return;
        }
        providerTabsScroll.to = bounded;
        providerTabsScroll.start();
    }

    function scrollBy(delta, immediate) {
        scrollTo(providerTabsFlickable.contentX + delta, immediate);
    }

    // Tabs come from three different delegates, so walk the parent
    // chain instead of keeping a registry of them in sync.
    function containsTab(item) {
        var node = item;
        while (node) {
            if (node === providerTabs) {
                return true;
            }
            node = node.parent;
        }
        return false;
    }

    function ensureVisible(item) {
        providerTabsScroll.stop();
        if (!providerTabsFlickable.interactive || !item || item.width <= 0 || !containsTab(item)) {
            return;
        }
        var target = TabStripGeometry.revealPosition(item.mapToItem(providerTabs, 0, 0).x, item.width, providerTabsFlickable.contentX, providerTabsFlickable.width, Kirigami.Units.gridUnit);
        // Keep an already-visible tab in place instead of aligning
        // it again on every focus or selection report.
        if (target !== null) {
            // Focus, selection and resize are direct navigation.
            // A focused tab must be visible before its next keypress.
            scrollTo(target, true);
        }
    }

    // Every tab kind reports through here: tracking only provider
    // tabs would leave a stale one selected once a global view is
    // picked, and a later resize would scroll it back into view.
    function claimSelectedTab(item, isSelected) {
        if (!isSelected) {
            if (selectedTab === item) {
                selectedTab = null;
            }
            return;
        }
        selectedTab = item;
        ensureVisible(item);
    }

    function revealSelectedTab() {
        ensureVisible(selectedTab);
    }

    // The focusable tabs in strip order, read off the focus chain
    // around the given tab. Both walks stop at the first item
    // outside the strip, and at a tab already collected in case
    // the chain wraps back without leaving the strip.
    function focusableTabs(item) {
        var tabs = [item];
        var candidate = item.nextItemInFocusChain(false);
        while (candidate && containsTab(candidate) && tabs.indexOf(candidate) < 0) {
            tabs.unshift(candidate);
            candidate = candidate.nextItemInFocusChain(false);
        }
        candidate = item.nextItemInFocusChain(true);
        while (candidate && containsTab(candidate) && tabs.indexOf(candidate) < 0) {
            tabs.push(candidate);
            candidate = candidate.nextItemInFocusChain(true);
        }
        return tabs;
    }

    // Arrow keys wrap around the strip and Home/End jump to its
    // ends, as in the WAI-ARIA tabs pattern. Focus moves without
    // selecting, so browsing tabs never switches the view.
    function navigateFromTab(item, key) {
        var action = "";
        switch (key) {
        case Qt.Key_Left:
            action = "previous";
            break;
        case Qt.Key_Right:
            action = "next";
            break;
        case Qt.Key_Home:
            action = "first";
            break;
        case Qt.Key_End:
            action = "last";
            break;
        default:
            return false;
        }
        if (!item || !containsTab(item)) {
            return false;
        }
        var tabs = focusableTabs(item);
        var target = TabStripGeometry.keyboardTargetIndex(action, tabs.indexOf(item), tabs.length);
        if (target < 0) {
            return false;
        }
        tabs[target].forceActiveFocus(action === "next" || action === "last" ? Qt.TabFocusReason : Qt.BacktabFocusReason);
        return true;
    }

    Rectangle {
        id: providerTabsSurface

        anchors.fill: parent
        radius: strip.surfaceRadius
        color: strip.withAlpha(Kirigami.Theme.textColor, 0.035)
        border.width: 1
        border.color: strip.withAlpha(Kirigami.Theme.textColor, 0.06)
    }

    Flickable {
        id: providerTabsFlickable
        objectName: "providerTabsFlickable"

        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing / 2
        anchors.leftMargin: strip.tabsOverflow ? previousTabsButton.width + Kirigami.Units.smallSpacing : Kirigami.Units.smallSpacing / 2
        anchors.rightMargin: strip.tabsOverflow ? nextTabsButton.width + Kirigami.Units.smallSpacing : Kirigami.Units.smallSpacing / 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: providerTabs.implicitWidth
        contentHeight: height
        interactive: contentWidth > width

        onMovementStarted: providerTabsScroll.stop()
        onWidthChanged: Qt.callLater(strip.revealSelectedTab)
        onContentWidthChanged: Qt.callLater(strip.revealSelectedTab)

        NumberAnimation {
            id: providerTabsScroll

            target: providerTabsFlickable
            property: "contentX"
            duration: Kirigami.Units.shortDuration
            easing.type: Easing.OutCubic
        }

        // Touchpads flick this strip horizontally, but a plain mouse
        // only sends a vertical wheel, which a horizontal-only
        // Flickable ignores; without this the overflowing tabs can
        // only be reached by dragging the strip.
        WheelHandler {
            enabled: providerTabsFlickable.interactive
            acceptedDevices: PointerDevice.Mouse

            onWheel: function (event) {
                var delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                if (delta === 0) {
                    return;
                }
                strip.scrollBy(-delta / 120 * strip.tabWheelStep);
            }
        }

        RowLayout {
            id: providerTabs

            height: providerTabsFlickable.height
            spacing: Kirigami.Units.smallSpacing / 2
        }
    }

    PlasmaComponents.ToolButton {
        id: previousTabsButton
        objectName: "previousTabsButton"

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Kirigami.Units.smallSpacing / 2
        width: height
        height: parent.height - Kirigami.Units.smallSpacing
        visible: strip.tabsOverflow
        enabled: providerTabsFlickable.contentX > 0
        icon.name: "go-previous-symbolic"
        text: i18n("Show previous tabs")
        display: PlasmaComponents.AbstractButton.IconOnly
        Accessible.name: text
        onClicked: strip.scrollBy(-strip.tabPageStep, visualFocus)

        PlainToolTip {
            plainText: previousTabsButton.text
            visible: previousTabsButton.hovered || previousTabsButton.visualFocus
            delay: Kirigami.Units.toolTipDelay
        }
    }

    PlasmaComponents.ToolButton {
        id: nextTabsButton
        objectName: "nextTabsButton"

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: Kirigami.Units.smallSpacing / 2
        width: height
        height: parent.height - Kirigami.Units.smallSpacing
        visible: strip.tabsOverflow
        enabled: providerTabsFlickable.contentX < providerTabsFlickable.contentWidth - providerTabsFlickable.width - 1
        icon.name: "go-next-symbolic"
        text: i18n("Show more tabs")
        display: PlasmaComponents.AbstractButton.IconOnly
        Accessible.name: text
        onClicked: strip.scrollBy(strip.tabPageStep, visualFocus)

        PlainToolTip {
            plainText: nextTabsButton.text
            visible: nextTabsButton.hovered || nextTabsButton.visualFocus
            delay: Kirigami.Units.toolTipDelay
        }
    }
}
