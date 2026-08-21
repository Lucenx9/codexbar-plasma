import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Rectangle {
    id: tab

    required property var applet
    required property string title
    required property string iconName
    required property real tabHeight
    property bool selected: false
    // Scrolling tab strip hosting this tab, so keyboard focus can pull an
    // overflowing tab back into view. Null when the host cannot overflow.
    property var tabStrip: null
    readonly property bool keyboardFocusVisible: tabFocus.visualFocus
    readonly property color accent: applet.readableAccentColor(
        Kirigami.Theme.highlightColor,
        Kirigami.Theme.backgroundColor)
    readonly property color foreground: selected
        ? Kirigami.Theme.textColor
        : applet.withAlpha(Kirigami.Theme.textColor, 0.72)

    signal activated()

    Layout.preferredWidth: Math.max(
        Kirigami.Units.gridUnit * 5.2,
        tabLabel.implicitWidth + Kirigami.Units.gridUnit * 2.2)
    Layout.preferredHeight: tabHeight
    radius: applet.roundedSurfaceRadius
    color: tabMouse.pressed
        ? applet.withAlpha(Kirigami.Theme.focusColor, 0.1)
        : (selected
        ? applet.withAlpha(Kirigami.Theme.textColor, 0.045)
        : (keyboardFocusVisible
        ? applet.withAlpha(Kirigami.Theme.focusColor, 0.06)
        : (tabMouse.containsMouse ? applet.withAlpha(Kirigami.Theme.textColor, 0.05) : "transparent")))
    border.width: keyboardFocusVisible ? 1 : 0
    border.color: Kirigami.Theme.focusColor
    scale: tabMouse.pressed ? 0.985 : 1

    function claimSelectedTab() {
        if (tab.tabStrip) {
            tab.tabStrip.claimSelectedTab(tab, tab.selected)
        }
    }

    onSelectedChanged: tab.claimSelectedTab()
    Component.onCompleted: tab.claimSelectedTab()

    Behavior on color {
        ColorAnimation { duration: Kirigami.Units.shortDuration }
    }

    Behavior on scale {
        NumberAnimation {
            duration: Kirigami.Units.shortDuration
            easing.type: Easing.OutCubic
        }
    }

    // Controls.Control exposes Qt's visualFocus contract: mouse focus follows
    // the clicked tab without drawing or later restoring a keyboard-only ring.
    Controls.Control {
        id: tabFocus

        anchors.fill: parent
        activeFocusOnTab: true
        background: null

        onActiveFocusChanged: {
            if (activeFocus && tab.tabStrip) {
                tab.tabStrip.ensureVisible(tab)
            }
        }

        Accessible.role: Accessible.PageTab
        Accessible.name: tab.title
        Accessible.selectable: true
        Accessible.selected: tab.selected
        Accessible.onPressAction: tab.activated()

        Keys.onPressed: function(event) {
            switch (event.key) {
            case Qt.Key_Space:
            case Qt.Key_Enter:
            case Qt.Key_Return:
            case Qt.Key_Select:
                tab.activated()
                event.accepted = true
                break
            case Qt.Key_Left:
                event.accepted = tab.tabStrip
                    ? tab.tabStrip.focusAdjacentTab(tabFocus, false)
                    : false
                break
            case Qt.Key_Right:
                event.accepted = tab.tabStrip
                    ? tab.tabStrip.focusAdjacentTab(tabFocus, true)
                    : false
                break
            }
        }
    }

    MouseArea {
        id: tabMouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: tabFocus.forceActiveFocus(Qt.MouseFocusReason)
        onClicked: tab.activated()
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        anchors.bottomMargin: Kirigami.Units.smallSpacing + 2
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            source: tab.iconName
            isMask: true
            color: tab.selected ? tab.accent : tab.foreground
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }

        PlasmaComponents.Label {
            id: tabLabel

            text: tab.title
            font.weight: tab.selected ? Font.DemiBold : Font.Normal
            color: tab.foreground
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        anchors.bottomMargin: 2
        height: 2
        radius: height / 2
        color: tab.selected ? tab.accent : "transparent"
    }
}
