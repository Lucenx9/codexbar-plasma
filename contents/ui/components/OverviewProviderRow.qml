import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../OverviewProviders.js" as OverviewProviders

Rectangle {
    id: overviewRow

    required property var applet
    required property var modelData
    readonly property var providerData: modelData

    readonly property color accent: applet.providerReadableColor(
        providerData.provider,
        Kirigami.Theme.backgroundColor)
    // Each named quota window gets its own labelled meter, so a low session
    // value cannot hide an exhausted weekly window behind one bare percentage.
    readonly property var meterRows: applet.overviewMeterRows(providerData)
    readonly property string detail: {
        var primary = OverviewProviders.detailText(providerData)
        if (providerData.usageStale !== true) {
            return primary
        }
        var lastKnown = applet.lastGoodUsageText(providerData)
        // A stale row must keep its account/status context; the freshness
        // note augments the detail instead of replacing it.
        return [primary, lastKnown]
            .filter(function(part) { return part.length > 0 })
            .join(" \u00b7 ")
    }
    // Screen readers get what the row shows beside its title, in drawn order:
    // the account or status detail, then each named quota with its reset.
    readonly property string accessibleDescription: [detail]
        .concat(meterRows.map(function(row) { return overviewRow.applet.quotaDescription(row) }))
        .filter(function(part) { return part.length > 0 })
        .join(". ")
    readonly property bool keyboardFocusVisible: overviewRowFocus.visualFocus
    // A narrow popup elides long provider names, account details, and quota
    // captions.
    readonly property bool textTruncated: overviewRowTitle.truncated
        || (overviewRowDetail.visible && overviewRowDetail.truncated)
        || meterCaptionTruncated
    readonly property bool meterCaptionTruncated: anyCaptionTruncated(overviewMeters, overviewMeters.count)

    // Passing count re-evaluates the binding when meters are created or removed.
    function anyCaptionTruncated(meters, count) {
        for (var i = 0; i < count; i++) {
            var meter = meters.itemAt(i)
            if (meter && meter.captionTruncated) {
                return true
            }
        }
        return false
    }

    function meterCaption(row) {
        return [row.label || "", applet.resetTextForRow(row)]
            .filter(function(part) { return part.length > 0 })
            .join(" \u00b7 ")
    }

    signal selected(var providerData)

    function activate() {
        overviewRow.selected(overviewRow.providerData)
    }

    Layout.fillWidth: true
    implicitHeight: overviewRowContent.implicitHeight + Kirigami.Units.largeSpacing * 2
    Layout.preferredHeight: implicitHeight
    radius: applet.roundedSurfaceRadius
    color: overviewRowMouse.pressed
        ? applet.withAlpha(Kirigami.Theme.focusColor, 0.16)
        : (keyboardFocusVisible
        ? applet.withAlpha(Kirigami.Theme.focusColor, 0.1)
        : (overviewRowMouse.containsMouse
        ? applet.withAlpha(Kirigami.Theme.textColor, 0.075)
        : applet.withAlpha(Kirigami.Theme.textColor, 0.035)))
    scale: overviewRowMouse.pressed ? 0.99 : 1

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

    RowLayout {
        id: overviewRowContent

        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        anchors.leftMargin: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing

        Rectangle {
            id: overviewProviderIdentitySurface

            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                + Kirigami.Units.smallSpacing * 2
            Layout.preferredHeight: Layout.preferredWidth
            radius: overviewRow.applet.nestedSurfaceRadius
            color: overviewRow.applet.withAlpha(overviewRow.accent, 0.1)
            border.width: 1
            border.color: overviewRow.applet.withAlpha(Kirigami.Theme.textColor, 0.1)

            Kirigami.Icon {
                anchors.centerIn: parent
                source: overviewRow.applet.providerIconSource(overviewRow.providerData.provider)
                fallback: "view-statistics"
                isMask: overviewRow.applet.providerIconIsMask(overviewRow.providerData.provider)
                color: overviewRow.accent
                width: Kirigami.Units.iconSizes.medium
                height: Kirigami.Units.iconSizes.medium
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlainPlasmaLabel {
                id: overviewRowTitle

                text: overviewRow.providerData.title
                font.weight: Font.DemiBold
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            PlainPlasmaLabel {
                id: overviewRowDetail

                visible: overviewRow.detail.length > 0
                text: overviewRow.detail
                font: Kirigami.Theme.smallFont
                opacity: overviewRow.applet.secondaryTextOpacity
                Layout.fillWidth: true
                elide: Text.ElideMiddle
            }

            Repeater {
                id: overviewMeters

                model: overviewRow.meterRows

                delegate: ColumnLayout {
                    id: overviewMeter

                    required property var modelData
                    readonly property bool captionTruncated: overviewMeterCaption.truncated
                        || overviewMeterReset.truncated

                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing / 2
                    spacing: Kirigami.Units.smallSpacing / 2

                    Item {
                        id: overviewMeterHeader

                        Layout.fillWidth: true
                        implicitHeight: Math.max(overviewMeterCaption.implicitHeight,
                            overviewMeterReset.implicitHeight, overviewMeterPercent.implicitHeight)
                        implicitWidth: overviewMeterCaption.implicitWidth
                            + overviewMeterReset.implicitWidth + overviewMeterPercent.implicitWidth
                            + Kirigami.Units.smallSpacing * 2

                        PlainPlasmaLabel {
                            id: overviewMeterCaption

                            text: overviewMeter.modelData.label || ""
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            font.weight: Font.DemiBold
                            opacity: overviewRow.applet.valueTextOpacity
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, Math.max(0,
                                overviewMeterPercent.x - Kirigami.Units.smallSpacing))
                            elide: Text.ElideRight
                        }

                        PlainPlasmaLabel {
                            id: overviewMeterReset

                            text: overviewRow.applet.resetTextForRow(overviewMeter.modelData)
                            visible: text.length > 0
                            font: Kirigami.Theme.smallFont
                            opacity: overviewRow.applet.secondaryTextOpacity
                            anchors.verticalCenter: parent.verticalCenter
                            x: overviewMeterCaption.width + Kirigami.Units.smallSpacing
                            width: Math.max(0, overviewMeterPercent.x - x
                                - Kirigami.Units.smallSpacing)
                            elide: Text.ElideRight
                        }

                        PlainPlasmaLabel {
                            id: overviewMeterPercent

                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: overviewRow.applet.usagePercentText(overviewMeter.modelData)
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: overviewRow.applet.compactMeterTrackHeight
                        radius: height / 2
                        color: overviewRow.applet.withAlpha(Kirigami.Theme.textColor, 0.1)
                        clip: true

                        Rectangle {
                            readonly property real shownPercent: overviewRow.applet.displayPercent(overviewMeter.modelData)

                            width: shownPercent <= 0
                                ? 0
                                : Math.max(parent.height, parent.width * shownPercent / 100)
                            height: parent.height
                            radius: parent.radius
                            color: overviewRow.applet.quotaMeterColor(
                                overviewMeter.modelData, overviewRow.accent)

                            Behavior on color {
                                ColorAnimation {
                                    duration: Kirigami.Units.longDuration
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
                }
            }
        }

        Kirigami.Icon {
            source: "go-next-symbolic"
            isMask: true
            color: Kirigami.Theme.textColor
            opacity: overviewRow.applet.secondaryTextOpacity
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: Kirigami.Units.smallSpacing * 3
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            Accessible.role: Accessible.Graphic
            Accessible.ignored: true
        }
    }

    Controls.Control {
        id: overviewRowFocus

        anchors.fill: parent
        activeFocusOnTab: true
        background: Rectangle {
            radius: overviewRow.radius
            color: "transparent"
            border.width: overviewRow.keyboardFocusVisible ? 1 : 0
            border.color: Kirigami.Theme.focusColor
        }

        Accessible.role: Accessible.Button
        Accessible.name: overviewRow.providerData.title
        Accessible.description: overviewRow.accessibleDescription
        Accessible.onPressAction: overviewRow.activate()

        Keys.onPressed: function(event) {
            switch (event.key) {
            case Qt.Key_Space:
            case Qt.Key_Enter:
            case Qt.Key_Return:
            case Qt.Key_Select:
                overviewRow.activate()
                event.accepted = true
                break
            }
        }
    }

    MouseArea {
        id: overviewRowMouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: {
            // Re-enter focus so an already-focused row also gets a mouse reason.
            overviewRowFocus.focus = false
            overviewRowFocus.forceActiveFocus(Qt.MouseFocusReason)
        }
        onClicked: overviewRow.activate()
    }

    PlainToolTip {
        id: overviewRowToolTip

        parent: overviewRowMouse
        visible: overviewRow.textTruncated
            && (overviewRowMouse.containsMouse || overviewRow.keyboardFocusVisible)
        plainText: [overviewRow.providerData.title, overviewRow.detail]
            .concat(overviewRow.meterRows.map(function(row) { return overviewRow.meterCaption(row) }))
            .filter(function(part) { return part.length > 0 })
            .join("\n")
    }
}
