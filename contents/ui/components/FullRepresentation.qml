import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "." as Components
import "../CostPresentation.js" as CostPresentation
import "../TabStripGeometry.js" as TabStripGeometry

Item {
    id: fullRoot

    required property var applet

    // A fixed popup height left the Overview half empty whenever few
    // providers were configured. The content drives the height instead,
    // clamped so a long provider list still scrolls rather than growing
    // without bound, and so a nearly empty popup keeps a usable shape.
    readonly property int maximumPopupHeight: Kirigami.Units.gridUnit * 38
    readonly property int minimumPopupHeight: Kirigami.Units.gridUnit * 20
    readonly property int popupContentHeight: Math.ceil(popupContent.implicitHeight)
        + Kirigami.Units.largeSpacing * 2

    implicitWidth: Kirigami.Units.gridUnit * 34
    implicitHeight: Math.max(minimumPopupHeight,
        Math.min(maximumPopupHeight, popupContentHeight))
    Layout.minimumWidth: Kirigami.Units.gridUnit * 30
    Layout.minimumHeight: Math.min(Kirigami.Units.gridUnit * 28, implicitHeight)
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight

    Rectangle {
        id: popupInnerSurface

        anchors.fill: parent
        radius: applet.roundedSurfaceRadius
        color: applet.withAlpha(Kirigami.Theme.alternateBackgroundColor, 0.18)
        border.width: 1
        border.color: applet.withAlpha(Kirigami.Theme.textColor, 0.09)

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, parent.radius - 1)
            color: "transparent"
            border.width: 1
            border.color: applet.withAlpha(Kirigami.Theme.backgroundColor, 0.28)
        }
    }

    ColumnLayout {
        id: popupContent

        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        Item {
            id: providerTabsBar

            visible: applet.providers.length > 0 || applet.spendAvailable || applet.sessionsAvailable
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2.35

            Rectangle {
                id: providerTabsSurface

                anchors.fill: parent
                radius: applet.roundedSurfaceRadius
                color: applet.withAlpha(Kirigami.Theme.textColor, 0.035)
                border.width: 1
                border.color: applet.withAlpha(Kirigami.Theme.textColor, 0.06)
            }

            Flickable {
                id: providerTabsFlickable

                // The selected provider tab, so geometry changes can bring it
                // back into view without every delegate registering itself.
                property Item selectedTab: null
                readonly property real tabPageStep: Math.max(Kirigami.Units.gridUnit * 4, width * 0.6)
                readonly property real tabWheelStep: Kirigami.Units.gridUnit * 5

                function scrollTo(position) {
                    var bounded = TabStripGeometry.boundedPosition(position, contentWidth, width)
                    providerTabsScroll.stop()
                    providerTabsScroll.to = bounded
                    providerTabsScroll.start()
                }

                function scrollBy(delta) {
                    scrollTo(contentX + delta)
                }

                // Tabs come from three different delegates, so walk the parent
                // chain instead of keeping a registry of them in sync.
                function containsTab(item) {
                    var node = item
                    while (node) {
                        if (node === providerTabs) {
                            return true
                        }
                        node = node.parent
                    }
                    return false
                }

                function ensureVisible(item) {
                    if (!interactive || !item || item.width <= 0 || !containsTab(item)) {
                        return
                    }
                    var target = TabStripGeometry.revealPosition(
                        item.mapToItem(providerTabs, 0, 0).x,
                        item.width,
                        contentX,
                        width,
                        Kirigami.Units.gridUnit)
                    // null means the tab is already on screen; scrolling anyway
                    // would restart the animation on every selection report.
                    if (target !== null) {
                        scrollTo(target)
                    }
                }

                // Every tab kind reports through here: tracking only provider
                // tabs would leave a stale one selected once a global view is
                // picked, and a later resize would scroll it back into view.
                function claimSelectedTab(item, isSelected) {
                    if (!isSelected) {
                        if (selectedTab === item) {
                            selectedTab = null
                        }
                        return
                    }
                    selectedTab = item
                    ensureVisible(item)
                }

                function revealSelectedTab() {
                    ensureVisible(selectedTab)
                }

                function focusAdjacentTab(item, forward) {
                    if (!item) {
                        return false
                    }
                    var candidate = item.nextItemInFocusChain(forward)
                    if (!candidate || !containsTab(candidate)) {
                        return false
                    }
                    candidate.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason)
                    return true
                }

                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing / 2
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: providerTabs.implicitWidth
                contentHeight: height
                interactive: contentWidth > width

                onWidthChanged: Qt.callLater(providerTabsFlickable.revealSelectedTab)
                onContentWidthChanged: Qt.callLater(providerTabsFlickable.revealSelectedTab)

                NumberAnimation {
                    id: providerTabsScroll

                    target: providerTabsFlickable
                    property: "contentX"
                    duration: Kirigami.Units.longDuration
                    easing.type: Easing.OutCubic
                }

                // Touchpads flick this strip horizontally, but a plain mouse
                // only sends a vertical wheel, which a horizontal-only
                // Flickable ignores; without this the overflowing tabs can
                // only be reached by dragging the strip.
                WheelHandler {
                    enabled: providerTabsFlickable.interactive
                    acceptedDevices: PointerDevice.Mouse

                    onWheel: function(event) {
                        var delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                        if (delta === 0) {
                            return
                        }
                        providerTabsFlickable.scrollBy(
                            -delta / 120 * providerTabsFlickable.tabWheelStep)
                    }
                }

                RowLayout {
                    id: providerTabs

                    height: providerTabsFlickable.height
                    spacing: Kirigami.Units.smallSpacing / 2

                    Rectangle {
                        id: overviewTab

                        readonly property bool selected: applet.overviewSelected
                        readonly property bool keyboardFocusVisible: overviewFocus.visualFocus
                        readonly property color brandAccent: Kirigami.Theme.highlightColor
                        readonly property color accent: applet.readableAccentColor(
                            brandAccent,
                            Kirigami.Theme.backgroundColor)
                        readonly property color foreground: selected
                            ? Kirigami.Theme.textColor
                            : applet.withAlpha(Kirigami.Theme.textColor, 0.72)

                        function activate() {
                            applet.selectGlobalView("overview")
                        }

                        function claimSelectedTab() {
                            providerTabsFlickable.claimSelectedTab(overviewTab, selected)
                        }

                        visible: applet.overviewAvailable
                        Layout.preferredWidth: applet.showPopupTabLabels
                            ? Math.max(
                                Kirigami.Units.gridUnit * 5.2,
                                overviewTabLabel.implicitWidth + Kirigami.Units.gridUnit * 2.2)
                            : providerTabsFlickable.height
                        Layout.preferredHeight: providerTabsFlickable.height
                        radius: applet.roundedSurfaceRadius
                        color: overviewTabMouse.pressed
                            ? applet.withAlpha(Kirigami.Theme.focusColor, 0.1)
                            : (selected
                            ? applet.withAlpha(Kirigami.Theme.textColor, 0.045)
                            : (keyboardFocusVisible
                            ? applet.withAlpha(Kirigami.Theme.focusColor, 0.06)
                            : (overviewTabMouse.containsMouse ? applet.withAlpha(Kirigami.Theme.textColor, 0.05) : "transparent")
                            ))
                        border.width: keyboardFocusVisible ? 1 : 0
                        border.color: Kirigami.Theme.focusColor
                        scale: overviewTabMouse.pressed ? 0.985 : 1
                        onSelectedChanged: overviewTab.claimSelectedTab()
                        Component.onCompleted: overviewTab.claimSelectedTab()

                        Behavior on color {
                            ColorAnimation {
                                duration: Kirigami.Units.shortDuration
                            }
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: Kirigami.Units.shortDuration
                                easing.type: Easing.OutCubic
                            }
                        }

                        Controls.Control {
                            id: overviewFocus

                            anchors.fill: parent
                            activeFocusOnTab: true
                            background: null

                            onActiveFocusChanged: {
                                if (activeFocus) {
                                    providerTabsFlickable.ensureVisible(overviewTab)
                                }
                            }

                            Accessible.role: Accessible.PageTab
                            Accessible.name: i18n("Overview")
                            Accessible.selectable: true
                            Accessible.selected: overviewTab.selected
                            Accessible.onPressAction: overviewTab.activate()

                            Keys.onPressed: function(event) {
                                switch (event.key) {
                                case Qt.Key_Space:
                                case Qt.Key_Enter:
                                case Qt.Key_Return:
                                case Qt.Key_Select:
                                    overviewTab.activate()
                                    event.accepted = true
                                    break
                                case Qt.Key_Left:
                                    event.accepted = providerTabsFlickable.focusAdjacentTab(overviewFocus, false)
                                    break
                                case Qt.Key_Right:
                                    event.accepted = providerTabsFlickable.focusAdjacentTab(overviewFocus, true)
                                    break
                                }
                            }
                        }

                        MouseArea {
                            id: overviewTabMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: overviewFocus.forceActiveFocus(Qt.MouseFocusReason)
                            onClicked: overviewTab.activate()
                        }

                        PlainToolTip {
                            visible: !applet.showPopupTabLabels && overviewTabMouse.containsMouse
                            plainText: i18n("Overview")
                        }

                        RowLayout {
                            id: overviewTabContent

                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            anchors.bottomMargin: Kirigami.Units.smallSpacing + 2
                            spacing: Kirigami.Units.smallSpacing

                            Item {
                                id: overviewTabLeadingSpacer

                                visible: !applet.showPopupTabLabels
                                Layout.fillWidth: !applet.showPopupTabLabels
                            }

                            Kirigami.Icon {
                                source: "view-grid-symbolic"
                                isMask: true
                                color: overviewTab.selected ? overviewTab.accent : overviewTab.foreground
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            }

                            Item {
                                id: overviewTabTrailingSpacer

                                visible: !applet.showPopupTabLabels
                                Layout.fillWidth: !applet.showPopupTabLabels
                            }

                            PlainPlasmaLabel {
                                id: overviewTabLabel

                                visible: applet.showPopupTabLabels
                                text: i18n("Overview")
                                font.weight: overviewTab.selected ? Font.DemiBold : Font.Normal
                                color: overviewTab.foreground
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
                            color: overviewTab.selected ? overviewTab.accent : "transparent"
                        }
                    }

                    Components.GlobalTab {
                        id: spendTab

                        visible: applet.spendAvailable
                        applet: fullRoot.applet
                        title: i18n("Usage & Spend")
                        showLabel: applet.showPopupTabLabels
                        tabStrip: providerTabsFlickable
                        iconName: "office-chart-bar"
                        tabHeight: providerTabsFlickable.height
                        selected: applet.spendSelected
                        onActivated: applet.selectGlobalView("spend")
                    }

                    Components.GlobalTab {
                        id: sessionsTab

                        visible: applet.sessionsAvailable
                        applet: fullRoot.applet
                        title: i18n("Sessions")
                        showLabel: applet.showPopupTabLabels
                        tabStrip: providerTabsFlickable
                        iconName: "system-run-symbolic"
                        tabHeight: providerTabsFlickable.height
                        selected: applet.sessionsSelected
                        onActivated: applet.selectGlobalView("sessions")
                    }

                    Rectangle {
                        visible: applet.providers.length > 0
                            && (applet.overviewAvailable || applet.spendAvailable || applet.sessionsAvailable)
                        Layout.preferredHeight: providerTabsFlickable.height - Kirigami.Units.smallSpacing * 2
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignVCenter
                        color: applet.withAlpha(Kirigami.Theme.textColor, 0.12)
                    }

                    Repeater {
                        model: applet.providers

                        delegate: Rectangle {
                            id: providerTab

                            required property int index
                            required property var modelData
                            readonly property bool selected: index === applet.selectedProviderIndex
                            readonly property bool keyboardFocusVisible: providerFocus.visualFocus
                            readonly property real meter: applet.switcherPercent(modelData)
                            readonly property color accent: applet.providerReadableColor(
                                modelData.provider,
                                Kirigami.Theme.backgroundColor)
                            readonly property color foreground: selected
                                ? Kirigami.Theme.textColor
                                : applet.withAlpha(Kirigami.Theme.textColor, 0.72)

                            function activate() {
                                applet.selectedProviderID = modelData.provider
                                applet.selectionInitialized = true
                            }

                            // An auto-selected provider can sit past the right
                            // edge; keep the active tab reachable and visible.
                            function claimSelectedTab() {
                                providerTabsFlickable.claimSelectedTab(providerTab, selected)
                            }

                            Layout.preferredWidth: applet.showPopupTabLabels
                                ? Math.min(
                                    Kirigami.Units.gridUnit * 7,
                                    Math.max(Kirigami.Units.gridUnit * 4.2,
                                        providerTabLabel.implicitWidth + Kirigami.Units.gridUnit * 2.2))
                                : providerTabsFlickable.height
                            Layout.preferredHeight: providerTabsFlickable.height
                            radius: applet.roundedSurfaceRadius
                            color: providerTabMouse.pressed
                                ? applet.withAlpha(Kirigami.Theme.focusColor, 0.1)
                                : (selected
                                ? applet.withAlpha(Kirigami.Theme.textColor, 0.045)
                                : (keyboardFocusVisible
                                ? applet.withAlpha(Kirigami.Theme.focusColor, 0.06)
                                : (providerTabMouse.containsMouse ? applet.withAlpha(Kirigami.Theme.textColor, 0.05) : "transparent")
                                ))
                            border.width: keyboardFocusVisible ? 1 : 0
                            border.color: Kirigami.Theme.focusColor
                            opacity: modelData.error.length > 0 ? 0.62 : 1
                            scale: providerTabMouse.pressed ? 0.985 : 1
                            onSelectedChanged: providerTab.claimSelectedTab()
                            Component.onCompleted: providerTab.claimSelectedTab()

                            Behavior on color {
                                ColorAnimation {
                                    duration: Kirigami.Units.shortDuration
                                }
                            }

                            Behavior on scale {
                                NumberAnimation {
                                    duration: Kirigami.Units.shortDuration
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Controls.Control {
                                id: providerFocus

                                anchors.fill: parent
                                activeFocusOnTab: true
                                background: null

                                onActiveFocusChanged: {
                                    if (activeFocus) {
                                        providerTabsFlickable.ensureVisible(providerTab)
                                    }
                                }

                                Accessible.role: Accessible.PageTab
                                Accessible.name: providerTab.modelData.title
                                Accessible.selectable: true
                                Accessible.selected: providerTab.selected
                                Accessible.onPressAction: providerTab.activate()

                                Keys.onPressed: function(event) {
                                    switch (event.key) {
                                    case Qt.Key_Space:
                                    case Qt.Key_Enter:
                                    case Qt.Key_Return:
                                    case Qt.Key_Select:
                                        providerTab.activate()
                                        event.accepted = true
                                        break
                                    case Qt.Key_Left:
                                        event.accepted = providerTabsFlickable.focusAdjacentTab(providerFocus, false)
                                        break
                                    case Qt.Key_Right:
                                        event.accepted = providerTabsFlickable.focusAdjacentTab(providerFocus, true)
                                        break
                                    }
                                }
                            }

                            MouseArea {
                                id: providerTabMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onPressed: providerFocus.forceActiveFocus(Qt.MouseFocusReason)
                                onClicked: providerTab.activate()
                            }

                            PlainToolTip {
                                visible: !applet.showPopupTabLabels && providerTabMouse.containsMouse
                                plainText: modelData.title
                            }

                            RowLayout {
                                id: providerTabContent

                                anchors.fill: parent
                                anchors.margins: Kirigami.Units.smallSpacing
                                anchors.bottomMargin: Kirigami.Units.smallSpacing + 2
                                spacing: Kirigami.Units.smallSpacing

                                Item {
                                    id: providerTabLeadingSpacer

                                    visible: !applet.showPopupTabLabels
                                    Layout.fillWidth: !applet.showPopupTabLabels
                                }

                                Kirigami.Icon {
                                    source: applet.providerIconSource(modelData.provider)
                                    fallback: "view-statistics"
                                    isMask: applet.providerIconIsMask(modelData.provider)
                                    color: providerTab.accent
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                }

                                Item {
                                    id: providerTabTrailingSpacer

                                    visible: !applet.showPopupTabLabels
                                    Layout.fillWidth: !applet.showPopupTabLabels
                                }

                                PlainPlasmaLabel {
                                    id: providerTabLabel

                                    visible: applet.showPopupTabLabels
                                    text: modelData.title
                                    font.weight: providerTab.selected ? Font.DemiBold : Font.Normal
                                    color: providerTab.foreground
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
                                color: providerTab.meter >= 0
                                    ? applet.withAlpha(Kirigami.Theme.textColor, 0.12)
                                    : (providerTab.selected ? providerTab.accent : "transparent")
                                clip: true

                                Rectangle {
                                    visible: providerTab.meter >= 0
                                    width: providerTab.meter <= 0
                                        ? 0
                                        : Math.max(parent.height, parent.width * Math.max(0, Math.min(100, providerTab.meter)) / 100)
                                    height: parent.height
                                    radius: parent.radius
                                    color: providerTab.accent

                                    Behavior on width {
                                        NumberAnimation {
                                            duration: Kirigami.Units.longDuration
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // The fades double as buttons: scrolling the strip otherwise
            // depends on gestures a plain mouse cannot produce, and nothing
            // on screen says the tabs continue past the edge.
            Rectangle {
                id: providerTabsLeftFade

                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Kirigami.Units.gridUnit * 1.5
                visible: opacity > 0
                opacity: providerTabsFlickable.interactive && providerTabsFlickable.contentX > 0 ? 1 : 0
                gradient: Gradient {
                    orientation: Gradient.Horizontal

                    GradientStop { position: 0; color: Kirigami.Theme.backgroundColor }
                    GradientStop { position: 1; color: applet.withAlpha(Kirigami.Theme.backgroundColor, 0) }
                }

                Accessible.role: Accessible.Button
                Accessible.name: i18n("Show previous tabs")
                Accessible.onPressAction: providerTabsFlickable.scrollBy(-providerTabsFlickable.tabPageStep)

                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: Kirigami.Units.iconSizes.small
                    height: width
                    source: "go-previous-symbolic"
                    isMask: true
                    color: providerTabsLeftFadeMouse.containsMouse
                        ? applet.readableAccentColor(Kirigami.Theme.highlightColor, Kirigami.Theme.backgroundColor)
                        : applet.withAlpha(Kirigami.Theme.textColor, 0.72)
                }

                MouseArea {
                    id: providerTabsLeftFadeMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: providerTabsFlickable.scrollBy(-providerTabsFlickable.tabPageStep)
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: Kirigami.Units.shortDuration
                    }
                }
            }

            Rectangle {
                id: providerTabsRightFade

                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Kirigami.Units.gridUnit * 1.5
                visible: opacity > 0
                opacity: providerTabsFlickable.interactive
                    && providerTabsFlickable.contentX < providerTabsFlickable.contentWidth - providerTabsFlickable.width - 1 ? 1 : 0
                gradient: Gradient {
                    orientation: Gradient.Horizontal

                    GradientStop { position: 0; color: applet.withAlpha(Kirigami.Theme.backgroundColor, 0) }
                    GradientStop { position: 1; color: Kirigami.Theme.backgroundColor }
                }

                Accessible.role: Accessible.Button
                Accessible.name: i18n("Show more tabs")
                Accessible.onPressAction: providerTabsFlickable.scrollBy(providerTabsFlickable.tabPageStep)

                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: Kirigami.Units.iconSizes.small
                    height: width
                    source: "go-next-symbolic"
                    isMask: true
                    color: providerTabsRightFadeMouse.containsMouse
                        ? applet.readableAccentColor(Kirigami.Theme.highlightColor, Kirigami.Theme.backgroundColor)
                        : applet.withAlpha(Kirigami.Theme.textColor, 0.72)
                }

                MouseArea {
                    id: providerTabsRightFadeMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: providerTabsFlickable.scrollBy(providerTabsFlickable.tabPageStep)
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: Kirigami.Units.shortDuration
                    }
                }
            }
        }

        Kirigami.Separator {
            visible: applet.providers.length > 0
            Layout.fillWidth: true
        }

        Components.PlainInlineMessage {
            id: globalErrorMessage

            visible: applet.providerUsageFeedbackVisible && applet.errorText.length > 0
            plainText: applet.errorText
            type: Kirigami.MessageType.Error
            Layout.fillWidth: true
        }

        // A plain Item absorbs the leftover popup height; a RowLayout here
        // inherits its children's maximum height, so the layout engine would
        // spread the slack across every row and push the tab bar downwards.
        Item {
            id: providerUsageLoadingRow

            visible: applet.providerUsageFeedbackVisible
                && applet.providers.length === 0
                && applet.errorText.length === 0
                && applet.loading
            Layout.fillWidth: true
            Layout.fillHeight: true

            RowLayout {
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width)
                spacing: Kirigami.Units.smallSpacing

                Controls.BusyIndicator {
                    running: providerUsageLoadingRow.visible
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }

                PlainPlasmaLabel {
                    text: i18n("Loading usage...")
                    opacity: applet.secondaryTextOpacity
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }
        }

        PlainPlaceholderMessage {
            id: emptyProvidersMessage

            visible: applet.providers.length === 0
                && !applet.globalViewSelected
                && applet.errorText.length === 0
                && !applet.loading
            plainText: i18n("No provider data.")
            icon.name: "view-statistics-symbolic"
            type: Kirigami.PlaceholderMessage.Type.Informational
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        Components.SpendView {
            visible: applet.spendSelected
            applet: fullRoot.applet
        }

        Components.SessionsView {
            visible: applet.sessionsSelected
            applet: fullRoot.applet
        }

        ColumnLayout {
            visible: applet.overviewSelected
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                id: overviewHeaderRow

                Layout.fillWidth: true
                Layout.rightMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing / 2

                    PlainHeading {
                        text: i18n("Overview")
                        level: 2
                        type: Kirigami.Heading.Type.Primary
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    PlainPlasmaLabel {
                        readonly property int providerCount: applet.overviewProviderItems.length

                        text: applet.lastUpdatedText.length > 0
                            ? i18n("%1 - %2", applet.lastUpdatedText, applet.providerCountText(providerCount))
                            : applet.providerCountText(providerCount)
                        opacity: applet.secondaryTextOpacity
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                Components.RefreshButton {
                    busy: applet.loading
                    label: i18n("Refresh")
                    onRequested: applet.refreshNow(true)
                }
            }

            PlasmaComponents.ScrollView {
                id: overviewScroll

                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true
                PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff

                ColumnLayout {
                    width: Math.max(
                        0,
                        overviewScroll.availableWidth - Kirigami.Units.smallSpacing)
                    spacing: Kirigami.Units.smallSpacing

                    PlainPlaceholderMessage {
                        id: overviewPlaceholderMessage

                        visible: applet.overviewProviderItems.length === 0
                        plainText: i18n("No overview data available.")
                        icon.name: "view-grid-symbolic"
                        type: Kirigami.PlaceholderMessage.Type.Informational
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 8
                    }

                    Repeater {
                        model: applet.overviewProviderItems

                        delegate: Components.OverviewProviderRow {
                            applet: fullRoot.applet
                            onSelected: function(providerData) {
                                var nextProviderIndex = applet.providerIndex(providerData)
                                if (nextProviderIndex >= 0) {
                                    applet.selectedProviderID = providerData.provider
                                    applet.selectionInitialized = true
                                }
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            visible: applet.selectedProviderData !== null
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Kirigami.Units.largeSpacing

            Components.ProviderHeader {
                applet: fullRoot.applet
                providerData: applet.selectedProviderData
            }

            Components.ProviderAccountsPanel {
                applet: fullRoot.applet
                providerData: applet.selectedProviderData
            }

            Components.PlainInlineMessage {
                id: providerStatusMessage

                visible: applet.selectedProviderData
                    && applet.selectedProviderData.hasIncident
                    && applet.selectedProviderData.status
                    && applet.selectedProviderData.status.length > 0
                plainText: applet.selectedProviderData ? applet.selectedProviderData.status : ""
                type: applet.selectedProviderData
                    ? applet.statusMessageType(applet.selectedProviderData.statusSeverity)
                    : Kirigami.MessageType.Information
                Layout.fillWidth: true
            }

            Components.PlainInlineMessage {
                id: providerErrorMessage

                visible: applet.selectedProviderData
                    && applet.selectedProviderData.error
                    && applet.selectedProviderData.error.length > 0
                plainText: applet.selectedProviderData ? applet.selectedProviderData.error : ""
                type: Kirigami.MessageType.Error
                Layout.fillWidth: true
            }

            PlasmaComponents.ScrollView {
                id: providerScroll

                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true
                PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff

                ColumnLayout {
                    width: Math.max(
                        0,
                        providerScroll.availableWidth - Kirigami.Units.smallSpacing)
                    spacing: Kirigami.Units.largeSpacing

                    PlainPlaceholderMessage {
                        id: providerPlaceholderMessage

                        visible: applet.providerPlaceholderText(applet.selectedProviderData).length > 0
                        plainText: applet.providerPlaceholderText(applet.selectedProviderData)
                        icon.name: "view-statistics-symbolic"
                        type: Kirigami.PlaceholderMessage.Type.Informational
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 8
                    }

                    Repeater {
                        model: applet.selectedProviderData ? applet.selectedProviderData.rows : []

                        delegate: Components.ProviderUsageRow {
                            applet: fullRoot.applet
                            providerData: applet.selectedProviderData
                        }
                    }

                    Kirigami.Separator {
                        visible: applet.hasAdditionalSections(applet.selectedProviderData)
                        Layout.fillWidth: true
                    }

                    ColumnLayout {
                        id: creditsSection

                        readonly property var creditLimit: applet.selectedProviderData
                            ? applet.selectedProviderData.codexCreditLimit
                            : null
                        readonly property var creditLimitRow: applet.codexCreditLimitUsageRow(
                            creditsSection.creditLimit)

                        visible: applet.selectedProviderData
                            && (applet.selectedProviderData.credits !== null
                                || creditsSection.creditLimit !== null)
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing / 1.5

                        PlainHeading {
                            text: i18n("Credits")
                            level: 4
                            type: Kirigami.Heading.Type.Primary
                            Layout.fillWidth: true
                        }

                        Repeater {
                            model: creditsSection.creditLimitRow ? [creditsSection.creditLimitRow] : []

                            delegate: Components.ProviderUsageRow {
                                applet: fullRoot.applet
                                providerData: applet.selectedProviderData
                            }
                        }

                        RowLayout {
                            visible: applet.selectedProviderData
                                && applet.selectedProviderData.credits !== null
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            PlainPlasmaLabel {
                                text: i18n("Remaining: %1", applet.selectedProviderData ? applet.formatNumber(applet.selectedProviderData.credits) : "")
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }
                    }

                    ColumnLayout {
                        id: resetCreditsSection

                        readonly property var resetCredits: applet.selectedProviderData ? applet.selectedProviderData.resetCredits : null

                        visible: resetCreditsSection.resetCredits ? true : false
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing / 1.5

                        Kirigami.Separator {
                            Layout.fillWidth: true
                        }

                        PlainHeading {
                            text: resetCreditsSection.resetCredits ? resetCreditsSection.resetCredits.title : ""
                            level: 4
                            type: Kirigami.Heading.Type.Primary
                            Layout.fillWidth: true
                        }

                        PlainPlasmaLabel {
                            text: resetCreditsSection.resetCredits ? resetCreditsSection.resetCredits.line : ""
                            opacity: applet.secondaryTextOpacity
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }

                    ColumnLayout {
                        id: providerCostSection

                        readonly property var providerCost: applet.selectedProviderData ? applet.selectedProviderData.providerCost : null
                        readonly property color accent: applet.providerReadableColor(applet.selectedProviderData ? applet.selectedProviderData.provider : "")

                        visible: providerCostSection.providerCost ? true : false
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing / 1.5

                        Kirigami.Separator {
                            Layout.fillWidth: true
                        }

                        PlainHeading {
                            text: providerCostSection.providerCost ? providerCostSection.providerCost.title : ""
                            level: 4
                            type: Kirigami.Heading.Type.Primary
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            visible: providerCostSection.providerCost && providerCostSection.providerCost.percentUsed >= 0 ? true : false
                            Layout.fillWidth: true
                            Layout.preferredHeight: applet.meterTrackHeight
                            radius: height / 2
                            color: applet.withAlpha(Kirigami.Theme.textColor, 0.1)
                            clip: true

                            Rectangle {
                                width: providerCostSection.providerCost && providerCostSection.providerCost.percentUsed > 0
                                    ? Math.max(parent.height, parent.width * providerCostSection.providerCost.percentUsed / 100)
                                    : 0
                                height: parent.height
                                radius: parent.radius
                                color: providerCostSection.accent

                                Behavior on width {
                                    NumberAnimation {
                                        duration: Kirigami.Units.longDuration
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            PlainPlasmaLabel {
                                text: providerCostSection.providerCost ? providerCostSection.providerCost.spendLine : ""
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            PlainPlasmaLabel {
                                visible: providerCostSection.providerCost && providerCostSection.providerCost.percentLine.length > 0 ? true : false
                                text: providerCostSection.providerCost ? providerCostSection.providerCost.percentLine : ""
                                opacity: applet.secondaryTextOpacity
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideRight
                            }
                        }

                        PlainPlasmaLabel {
                            visible: providerCostSection.providerCost && providerCostSection.providerCost.personalSpendLine.length > 0 ? true : false
                            text: providerCostSection.providerCost ? providerCostSection.providerCost.personalSpendLine : ""
                            opacity: applet.secondaryTextOpacity
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }

                    ColumnLayout {
                        id: providerDetailsSection

                        readonly property var details: applet.selectedProviderData
                            ? applet.selectedProviderData.providerDetails || []
                            : []

                        visible: details.length > 0
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Separator {
                            Layout.fillWidth: true
                        }

                        Repeater {
                            model: providerDetailsSection.details

                            delegate: Components.ProviderDetailSection {
                                applet: fullRoot.applet
                                providerData: applet.selectedProviderData
                            }
                        }
                    }

                    ColumnLayout {
                        id: usageDashboardSection

                        readonly property var dashboard: applet.selectedProviderData ? applet.selectedProviderData.usageDashboard : null
                        readonly property var kpis: dashboard ? dashboard.kpis : []
                        readonly property var rows: dashboard ? dashboard.rows : []

                        visible: kpis.length > 0 || rows.length > 0
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing / 1.5

                        Kirigami.Separator {
                            Layout.fillWidth: true
                        }

                        PlainPlasmaLabel {
                            text: i18n("Usage dashboard")
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        GridLayout {
                            visible: usageDashboardSection.kpis.length > 0
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: Kirigami.Units.smallSpacing
                            rowSpacing: Kirigami.Units.smallSpacing / 2

                            Repeater {
                                model: usageDashboardSection.kpis

                                delegate: ColumnLayout {
                                    required property var modelData

                                    Layout.fillWidth: true
                                    spacing: 0

                                    PlainPlasmaLabel {
                                        text: modelData.label
                                        opacity: applet.secondaryTextOpacity
                                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    PlainPlasmaLabel {
                                        text: modelData.value
                                        font.weight: Font.DemiBold
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            visible: usageDashboardSection.rows.length > 0
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing / 2

                            Repeater {
                                model: usageDashboardSection.rows

                                delegate: RowLayout {
                                    required property var modelData

                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing

                                    PlainPlasmaLabel {
                                        text: modelData.label
                                        opacity: applet.secondaryTextOpacity
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    PlainPlasmaLabel {
                                        text: modelData.value
                                        opacity: applet.valueTextOpacity
                                        horizontalAlignment: Text.AlignRight
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        id: tokenCostSection

                        readonly property var tokenCost: applet.selectedProviderData ? applet.selectedProviderData.tokenCost : null
                        readonly property var chartPoints: tokenCost
                            ? applet.costChartPoints(tokenCost.daily) : []
                        readonly property var costTrustSummary: CostPresentation.costTrustSummary(
                            tokenCost ? [tokenCost] : [])
                        readonly property string costErrorText: applet.costErrorText
                        readonly property bool supportsLocalCost: applet.selectedProviderData
                            && applet.tokenCostHint(applet.selectedProviderData.provider).length > 0

                        visible: tokenCostSection.tokenCost
                            ? true
                            : tokenCostSection.supportsLocalCost && tokenCostSection.costErrorText.length > 0
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing / 1.5

                        Kirigami.Separator {
                            Layout.fillWidth: true
                        }

                        PlainHeading {
                            text: i18n("Cost")
                            level: 4
                            type: Kirigami.Heading.Type.Primary
                            Layout.fillWidth: true
                        }

                        PlainPlasmaLabel {
                            visible: !tokenCostSection.tokenCost && tokenCostSection.costErrorText.length > 0
                            text: i18n("Cost unavailable: %1", tokenCostSection.costErrorText)
                            color: Kirigami.Theme.negativeTextColor
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }

                        PlainPlasmaLabel {
                            id: costSessionSummaryLabel

                            visible: tokenCostSection.tokenCost ? true : false
                            text: tokenCostSection.tokenCost ? tokenCostSection.tokenCost.sessionLine : ""
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        PlainPlasmaLabel {
                            id: costMonthSummaryLabel

                            visible: tokenCostSection.tokenCost ? true : false
                            text: tokenCostSection.tokenCost ? tokenCostSection.tokenCost.monthLine : ""
                            font: Kirigami.Theme.smallFont
                            opacity: applet.secondaryTextOpacity
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Components.CostTrustNotice {
                            noticeScope: "provider:" + (applet.selectedProviderData
                                ? applet.selectedProviderData.provider : "")
                            stateOwner: fullRoot.applet
                            presentationVisible: fullRoot.visible && !applet.globalViewSelected
                            summary: tokenCostSection.costTrustSummary
                        }

                        Components.InteractiveChart {
                            readonly property var tokenCost: tokenCostSection.tokenCost
                            readonly property var providerData: applet.selectedProviderData

                            visible: tokenCostSection.chartPoints.length > 1
                            applet: fullRoot.applet
                            points: tokenCostSection.chartPoints
                            accent: applet.providerReadableColor(providerData ? providerData.provider : "")
                            kind: "bar"
                            accessibleTitle: applet.costHistoryShowsTokens
                                ? i18n("Daily token history")
                                : i18n("Daily cost history")
                            Layout.topMargin: Kirigami.Units.smallSpacing / 2
                        }

                        RowLayout {
                            visible: tokenCostSection.chartPoints.length > 1
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            PlainPlasmaLabel {
                                id: costSparklineSummaryLabel

                                text: tokenCostSection.tokenCost ? applet.costSparklineSummary(tokenCostSection.tokenCost.daily) : ""
                                font: Kirigami.Theme.smallFont
                                opacity: applet.secondaryTextOpacity
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            PlainPlasmaLabel {
                                id: costSparklineRangeLabel

                                text: tokenCostSection.tokenCost
                                    ? i18np("%1 day", "%1 days", tokenCostSection.tokenCost.daily.length)
                                    : ""
                                font: Kirigami.Theme.smallFont
                                opacity: applet.secondaryTextOpacity
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideRight
                            }
                        }

                        ColumnLayout {
                            id: costHistoryChartSection

                            readonly property var rows: applet.costHistoryRows(tokenCostSection.tokenCost)
                            readonly property string peakLine: tokenCostSection.tokenCost ? applet.costPeakLine(tokenCostSection.tokenCost.daily) : ""
                            readonly property string averageLine: tokenCostSection.tokenCost ? applet.costAverageDailyLine(tokenCostSection.tokenCost.daily) : ""
                            readonly property color accent: applet.providerReadableColor(applet.selectedProviderData ? applet.selectedProviderData.provider : "")

                            visible: rows.length > 1
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing / 2

                            RowLayout {
                                id: costHistoryHeaderRow

                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                PlainPlasmaLabel {
                                    text: i18n("Cost history")
                                    font.weight: Font.DemiBold
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                PlainPlasmaLabel {
                                    visible: costHistoryChartSection.averageLine.length > 0
                                    text: costHistoryChartSection.averageLine
                                    font: Kirigami.Theme.smallFont
                                    opacity: applet.secondaryTextOpacity
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                }
                            }

                            PlainPlasmaLabel {
                                visible: costHistoryChartSection.peakLine.length > 0
                                text: costHistoryChartSection.peakLine
                                font: Kirigami.Theme.smallFont
                                opacity: applet.secondaryTextOpacity
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            Repeater {
                                model: costHistoryChartSection.rows

                                delegate: RowLayout {
                                    id: costHistoryMetricRow

                                    required property var modelData

                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing

                                    PlainPlasmaLabel {
                                        id: costHistoryDateLabel

                                        text: modelData.label
                                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                        opacity: applet.secondaryTextOpacity
                                        Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        id: costHistoryBarTrack

                                        Layout.fillWidth: true
                                        Layout.preferredHeight: applet.compactMeterTrackHeight
                                        radius: height / 2
                                        color: applet.withAlpha(Kirigami.Theme.textColor, 0.055)
                                        clip: true
                                        antialiasing: true

                                        Rectangle {
                                            width: parent.width * Math.max(0, Math.min(100, modelData.percent)) / 100
                                            height: parent.height
                                            radius: parent.radius
                                            antialiasing: true
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal

                                                GradientStop {
                                                    position: 0
                                                    color: applet.withAlpha(
                                                        costHistoryChartSection.accent,
                                                        modelData.isPeak ? 0.72 : 0.46)
                                                }

                                                GradientStop {
                                                    position: 1
                                                    color: applet.withAlpha(
                                                        costHistoryChartSection.accent,
                                                        modelData.isPeak ? 1 : 0.8)
                                                }
                                            }

                                            Behavior on width {
                                                NumberAnimation {
                                                    duration: Kirigami.Units.longDuration
                                                    easing.type: Easing.OutCubic
                                                }
                                            }
                                        }
                                    }

                                    PlainPlasmaLabel {
                                        id: costHistoryValueLabel

                                        text: modelData.value
                                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                        opacity: modelData.isPeak ? applet.valueTextOpacity : applet.secondaryTextOpacity
                                        font.weight: modelData.isPeak ? Font.DemiBold : Font.Normal
                                        horizontalAlignment: Text.AlignRight
                                        Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            id: costDrillDownSection

                            readonly property var breakdownRows: applet.costBreakdownRows(tokenCostSection.tokenCost)
                            readonly property var modelRows: applet.costModelRows(tokenCostSection.tokenCost)
                            readonly property real metricValueColumnWidth: Kirigami.Units.gridUnit * 9

                            visible: tokenCostSection.tokenCost
                                && (costDrillDownSection.breakdownRows.length > 0
                                    || costDrillDownSection.modelRows.length > 0)
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            PlainPlasmaLabel {
                                text: i18n("Cost details")
                                font.weight: Font.DemiBold
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            PlainPlasmaLabel {
                                visible: tokenCostSection.tokenCost && applet.costPerMillionLine(tokenCostSection.tokenCost).length > 0
                                text: tokenCostSection.tokenCost ? applet.costPerMillionLine(tokenCostSection.tokenCost) : ""
                                font: Kirigami.Theme.smallFont
                                opacity: applet.secondaryTextOpacity
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            ColumnLayout {
                                visible: costDrillDownSection.breakdownRows.length > 0
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing / 2

                                Repeater {
                                    model: costDrillDownSection.breakdownRows

                                    delegate: RowLayout {
                                        required property var modelData

                                        Layout.fillWidth: true
                                        spacing: Kirigami.Units.smallSpacing

                                        PlainPlasmaLabel {
                                            text: modelData.label
                                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                            opacity: applet.secondaryTextOpacity
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }

                                        PlainPlasmaLabel {
                                            id: costBreakdownValueLabel

                                            text: modelData.value
                                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                            opacity: applet.valueTextOpacity
                                            font.weight: Font.Medium
                                            horizontalAlignment: Text.AlignRight
                                            Layout.preferredWidth: costDrillDownSection.metricValueColumnWidth
                                            Layout.maximumWidth: costDrillDownSection.metricValueColumnWidth
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }

                            Kirigami.Separator {
                                visible: costDrillDownSection.modelRows.length > 0
                                Layout.fillWidth: true
                                opacity: 0.55
                            }

                            ColumnLayout {
                                visible: costDrillDownSection.modelRows.length > 0
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing / 2

                                PlainPlasmaLabel {
                                    id: costModelsHeading

                                    text: i18n("Models")
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    font.weight: Font.DemiBold
                                    opacity: applet.secondaryTextOpacity
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                Repeater {
                                    model: costDrillDownSection.modelRows

                                    delegate: RowLayout {
                                        required property var modelData

                                        Layout.fillWidth: true
                                        spacing: Kirigami.Units.smallSpacing

                                        PlainPlasmaLabel {
                                            text: modelData.label
                                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                            opacity: applet.secondaryTextOpacity
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }

                                        PlainPlasmaLabel {
                                            id: costModelValueLabel

                                            text: modelData.value
                                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                            opacity: applet.valueTextOpacity
                                            font.weight: Font.Medium
                                            horizontalAlignment: Text.AlignRight
                                            Layout.preferredWidth: costDrillDownSection.metricValueColumnWidth
                                            Layout.maximumWidth: costDrillDownSection.metricValueColumnWidth
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }

                        }

                        PlainPlasmaLabel {
                            visible: tokenCostSection.tokenCost && tokenCostSection.tokenCost.hintLine.length > 0 ? true : false
                            text: tokenCostSection.tokenCost ? tokenCostSection.tokenCost.hintLine : ""
                            opacity: applet.secondaryTextOpacity
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }

                    ColumnLayout {
                        visible: applet.selectedProviderData !== null
                        Layout.fillWidth: true
                        spacing: 0

                        Kirigami.Separator {
                            Layout.fillWidth: true
                        }

                        Repeater {
                            id: providerActionRows

                            model: applet.selectedProviderData ? applet.actionRows(applet.selectedProviderData) : []

                            delegate: ColumnLayout {
                                required property var modelData

                                Layout.fillWidth: true
                                spacing: 0

                                Kirigami.Separator {
                                    id: providerActionGroupSeparator

                                    visible: modelData.separatorBefore === true
                                    Layout.fillWidth: true
                                    Layout.topMargin: Kirigami.Units.smallSpacing / 2
                                    Layout.bottomMargin: Kirigami.Units.smallSpacing / 2
                                }

                                Controls.ItemDelegate {
                                    Layout.fillWidth: true
                                    text: modelData.title
                                    icon.name: modelData.icon
                                    enabled: modelData.enabled
                                    onClicked: applet.performAction(modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
