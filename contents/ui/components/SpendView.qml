import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "." as Components
import "../CostAmounts.js" as CostAmounts
import "../CostChart.js" as CostChart
import "../CostCurrency.js" as CostCurrency
import "../CostTrust.js" as CostTrust
import "../HeatmapNavigation.js" as HeatmapNavigation

ColumnLayout {
    id: view

    required property var applet
    readonly property var dailyPoints: applet.spendDailyPoints()
    property var daySelectionMemo: ({ points: [], index: -1 })
    readonly property string selectionScope: JSON.stringify([
        applet.costHistoryDays, applet.costHistoryPeriod, applet.costHistoryMetric])
    readonly property var providerCosts: applet.spendProviderCosts()
    readonly property var presentedProviderCosts: applet.presentedSpendProviderCosts(providerCosts)
    readonly property var costTrustSummary: CostTrust.costTrustSummary(providerCosts)
    readonly property string spendCurrency: applet.spendCurrency(providerCosts)
    readonly property bool hasMixedCostCurrencies: CostCurrency.spendHasMixedCostCurrencies(providerCosts)
    readonly property real heatmapMaximum: chartMaximum(dailyPoints)
    readonly property var heatmapDays: CostChart.spendHeatmapDays(dailyPoints, providerCosts)
    readonly property int heatmapFirstWeekday: Qt.locale().firstDayOfWeek
    readonly property var heatmapRowWeekdays: CostChart.spendHeatmapRowWeekdays(
        heatmapDays, heatmapFirstWeekday)
    readonly property int heatmapTrailingSlots: CostChart.spendHeatmapTrailingSlots(
        heatmapDays, heatmapFirstWeekday)

    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Kirigami.Units.largeSpacing

    onSelectionScopeChanged: {
        if (!historyChart)
            return
        heatmapFocus.selectedDay = ""
        heatmapFocus.hoveredDay = ""
        daySelectionMemo = { points: historyChart.points, index: -1 }
        historyChart.selectedIndex = -1
        historyChart.hoveredIndex = -1
    }

    function chartMaximum(points) {
        var maximum = 0
        for (var i = 0; i < points.length; i++) {
            maximum = Math.max(maximum, Number(points[i].value) || 0)
        }
        return maximum
    }

    // Shared by the grid and its legend, so the key matches the cells exactly.
    function heatmapTint(fraction) {
        return applet.withAlpha(Kirigami.Theme.highlightColor, 0.1 + fraction * 0.8)
    }

    // Day counts are numbers; the calendar periods are the CLI's names.
    function rangeOptions(days) {
        var values = [7, 30, 90]
        var options = [
            { text: i18n("7 days"), value: 7 },
            { text: i18n("30 days"), value: 30 },
            { text: i18n("90 days"), value: 90 },
            { text: i18n("Month to date"), value: "month-to-date" },
            { text: i18n("All history"), value: "all" }
        ]
        var currentDays = Number(days)
        if (values.indexOf(currentDays) === -1) {
            options.unshift({
                text: i18np("%1 day", "%1 days", currentDays),
                value: currentDays
            })
        }
        return options
    }

    function rangeIndex(options, days, period) {
        for (var i = 0; i < options.length; i++) {
            if (period ? options[i].value === period : options[i].value === Number(days)) {
                return i
            }
        }
        return 0
    }

    RowLayout {
        id: spendHeaderRow

        Layout.fillWidth: true
        Layout.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing / 2

            PlainHeading {
                text: i18n("Usage & Spend")
                level: 2
                type: Kirigami.Heading.Type.Primary
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            PlainPlasmaLabel {
                id: spendMetaLabel

                visible: view.applet.costUsageEnabled !== false
                text: view.applet.spendTotalLine()
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
                font.features: { "tnum": 1 }
                font.weight: Font.DemiBold
                Layout.fillWidth: true
                elide: Text.ElideRight

                HoverHandler {
                    id: spendMetaLabelHover
                }

                PlainToolTip {
                    parent: spendMetaLabel
                    visible: spendMetaLabel.truncated && spendMetaLabelHover.hovered
                    plainText: spendMetaLabel.text
                }
            }
        }

        PlasmaComponents.ToolButton {
            id: shareButton
            visible: view.applet.costUsageEnabled !== false
            objectName: "shareUsageButton"
            Layout.alignment: Qt.AlignTop
            icon.name: "document-share"
            Accessible.name: i18n("Share AI usage")
            enabled: view.providerCosts.length > 0 && !view.applet.costLoading
            onClicked: view.applet.openShareUsage()
            PlainToolTip {
                parent: shareButton
                visible: shareButton.hovered || shareButton.visualFocus
                plainText: i18n("Share AI usage")
            }
        }

        Components.RefreshButton {
            visible: view.applet.costUsageEnabled !== false
            Layout.alignment: Qt.AlignTop
            busy: view.applet.costLoading
            label: i18n("Refresh local history")
            onRequested: view.applet.refreshCost(true)
        }
    }

    RowLayout {
        id: historyControlsRow
        visible: view.applet.costUsageEnabled !== false

        Layout.fillWidth: true
        Layout.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        PlainPlasmaLabel {
            text: i18n("History")
            font.weight: Font.DemiBold
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        Components.CostMetricToggle {
            id: metricToggle

            applet: view.applet
        }

        Components.PlainComboBox {
            id: rangeCombo

            Layout.minimumHeight: metricToggle.implicitHeight
            textRole: "text"
            valueRole: "value"
            model: view.rangeOptions(view.applet.costHistoryDays)
            currentIndex: view.rangeIndex(model, view.applet.costHistoryDays, view.applet.costHistoryPeriod)
            Accessible.name: i18n("%1: %2", i18n("History range"), displayText)
            onActivated: function(index) {
                var value = rangeCombo.valueAt(index)
                if (typeof value === "string") {
                    view.applet.setCostHistoryPeriod(value)
                } else {
                    view.applet.setCostHistoryDays(value)
                }
                // The pick severs currentIndex; restore the binding so the
                // combo keeps tracking settings changes made outside this view.
                rangeCombo.currentIndex = Qt.binding(function() {
                    return view.rangeIndex(rangeCombo.model, view.applet.costHistoryDays,
                        view.applet.costHistoryPeriod)
                })
            }
        }
    }

    PlasmaComponents.ScrollView {
        id: spendHistoryScroll
        objectName: "spendHistoryScroll"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        contentWidth: availableWidth
        clip: true
        PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff

        ColumnLayout {
            width: Math.max(0, parent.width - Kirigami.Units.smallSpacing)
            height: view.providerCosts.length > 0 || view.applet.identifiedTokensEnabled === true
                ? implicitHeight : Math.max(implicitHeight, spendHistoryScroll.availableHeight)
            spacing: Kirigami.Units.largeSpacing

            Loader {
                Layout.fillWidth: true
                active: view.applet.identifiedTokensEnabled === true
                visible: active
                sourceComponent: Components.IdentifiedTokensSection { applet: view.applet }
            }

            Components.PlainNote {
                visible: view.applet.costErrorText.length > 0
                plainText: view.providerCosts.length > 0
                    ? i18n("Some local history is unavailable: %1", view.applet.privateErrorText(view.applet.costErrorText))
                    : i18n("Local history is unavailable: %1", view.applet.privateErrorText(view.applet.costErrorText))
                type: Kirigami.MessageType.Warning
                Layout.fillWidth: true
            }

            Components.PlainNote {
                visible: view.hasMixedCostCurrencies
                plainText: i18n("The cost subtotal and charts use %1. Providers reporting another currency remain separate below. Token figures include every provider.", view.spendCurrency)
                type: Kirigami.MessageType.Information
                Layout.fillWidth: true
            }

            Components.PlainNote {
                // Distinguishes "you spent little" from "the local scan has not reached
                // that far back yet", which otherwise look identical on the chart.
                visible: view.providerCosts.length > 0 && view.applet.spendHistoryStillBuilding()
                plainText: i18n("Local history is still being collected, so early days may be incomplete.")
                type: Kirigami.MessageType.Information
                Layout.fillWidth: true
            }

            Components.CostTrustNotice {
                noticeScope: "spend"
                stateOwner: view.applet
                presentationVisible: view.visible
                summary: view.costTrustSummary
            }

            Components.PlainNote {
                visible: view.providerCosts.length > 0 && view.dailyPoints.length === 0
                plainText: view.applet.costHistoryShowsTokens
                    ? i18n("No daily token history is available for this range.")
                    : i18n("No daily cost history is available for this range. Try Tokens to check for token-only history.")
                type: Kirigami.MessageType.Information
                Layout.fillWidth: true
            }

            Item {
                visible: view.applet.costUsageEnabled !== false && !view.applet.costLoading
                    && view.providerCosts.length === 0
                    && view.applet.costErrorText.length === 0
                implicitHeight: emptySpendPlaceholder.implicitHeight
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Keep the native placeholder together while this item fills the view.
                PlainPlaceholderMessage {
                    id: emptySpendPlaceholder

                    anchors.centerIn: parent
                    width: parent.width
                    plainText: i18n("No local token or cost history")
                    plainExplanation: i18n("History appears for providers supported by the codexbar cost command.")
                    icon.name: "view-statistics-symbolic"
                    type: Kirigami.PlaceholderMessage.Type.Informational
                }
            }

            Item {
                visible: view.applet.costLoading && view.providerCosts.length === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: spendBusyIndicator.implicitHeight

                Controls.BusyIndicator {
                    id: spendBusyIndicator
                    anchors.centerIn: parent
                    running: parent.visible
                }
            }

            Item {
                visible: !view.applet.costLoading
                    && view.providerCosts.length === 0
                    && view.applet.costErrorText.length > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
            }

            InteractiveChart {
                id: historyChart

                onPointsChanged: {
                    var index = CostChart.costDayIndexAfterRefresh(
                        view.daySelectionMemo.points, view.daySelectionMemo.index, points)
                    view.daySelectionMemo = { points: points, index: index }
                    selectedIndex = index
                    hoveredIndex = -1
                }
                onSelectedIndexChanged: {
                    // Ignore the chart's index clamp until new points are reconciled.
                    if (view.daySelectionMemo.points === points)
                        view.daySelectionMemo = { points: points, index: selectedIndex }
                }
                visible: view.dailyPoints.length > 0
                applet: view.applet
                points: view.dailyPoints
                accent: view.applet.readableAccentColor(
                    Kirigami.Theme.highlightColor,
                    Kirigami.Theme.backgroundColor)
                kind: "bar"
                showPeak: true
                // This chart plots the whole selected range, up to 90 bars, and
                // is the primary view here: it outranks the heatmap below it.
                plotHeight: Kirigami.Units.gridUnit * 6
                accessibleTitle: view.applet.costHistoryShowsTokens
                    ? i18n("Daily token history")
                    : i18n("Daily cost history")
            }

            Components.ProjectCostSection {
                applet: view.applet
                providerCosts: view.presentedProviderCosts
            }

            GridLayout {
                id: activitySummary
                objectName: "spendActivitySummary"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 1
                // The viewport stays stable when the grid's implicit size or
                // scrollbar visibility changes at the layout breakpoint.
                columns: view.width >= Kirigami.Units.gridUnit * 28
                    && view.heatmapDays.length > 7 && view.heatmapDays.length <= 35 ? 2 : 1
                columnSpacing: Kirigami.Units.largeSpacing * 2
                rowSpacing: Kirigami.Units.largeSpacing

                ColumnLayout {
                    // One week column carries a single day per row, which repeats
                    // the chart above instead of showing a weekday pattern.
                    visible: view.heatmapDays.length > 7
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignTop
                    spacing: Kirigami.Units.smallSpacing / 2

                    PlainPlasmaLabel {
                        text: i18n("Activity heatmap")
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    // The grid follows the selected range instead of a fixed
                    // 42-day window, and derives the cell size from the available
                    // width so the cells stay large enough to hover.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        // Without weekday names the rows are an unlabelled stripe
                        // pattern; the labels are what make it a weekday read.
                        Column {
                            id: heatmapWeekdayLabels

                            visible: view.heatmapRowWeekdays.length === 7
                            spacing: heatmapGrid.rowSpacing
                            Layout.alignment: Qt.AlignTop
                            Accessible.ignored: true

                            Repeater {
                                model: view.heatmapRowWeekdays

                                delegate: PlainPlasmaLabel {
                                    required property var modelData

                                    height: heatmapGrid.cellHeight
                                    text: Qt.locale().dayName(modelData, Locale.ShortFormat)
                                    font: Kirigami.Theme.smallFont
                                    opacity: view.applet.secondaryTextOpacity
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }

                        Controls.Control {
                            id: heatmapFocus
                            objectName: "spendHeatmap"

                            property string selectedDay: ""
                            property string hoveredDay: ""
                            readonly property var cells: heatmapGrid.cells
                            readonly property int inspectedIndex: HeatmapNavigation.indexForDay(cells,
                                hoveredDay.length > 0 ? hoveredDay : (activeFocus ? selectedDay : ""))
                            readonly property var inspectedCell: inspectedIndex >= 0 ? cells[inspectedIndex] : null
                            readonly property string readout: inspectedCell
                                ? i18n("%1: %2", historyChart.pointLabel(inspectedCell), inspectedCell.displayValue) : ""

                            activeFocusOnTab: HeatmapNavigation.nextDay(cells, "", "first", false).length > 0
                            background: null
                            Accessible.role: Accessible.Graphic
                            Accessible.name: readout.length > 0
                                ? i18n("%1: %2", i18n("Activity heatmap"), readout) : i18n("Activity heatmap")
                            Accessible.description: i18n("Use the arrow keys to inspect chart points")

                            function revealInHistoryScroll() {
                                var flick = spendHistoryScroll.contentItem as Flickable
                                if (!flick)
                                    return
                                var top = mapToItem(flick.contentItem, 0, 0).y
                                var bottom = heatmapReadout.mapToItem(flick.contentItem, 0, heatmapReadout.height).y
                                var target = flick.contentY
                                if (top < target)
                                    target = top
                                else if (bottom > target + flick.height)
                                    target = Math.min(top, bottom - flick.height)
                                flick.contentY = Math.max(0, Math.min(target,
                                    Math.max(0, flick.contentHeight - flick.height)))
                            }

                            onActiveFocusChanged: {
                                if (activeFocus) {
                                    hoveredDay = ""
                                    revealInHistoryScroll()
                                }
                                if (activeFocus && HeatmapNavigation.indexForDay(cells, selectedDay) < 0)
                                    selectedDay = HeatmapNavigation.nextDay(cells, "", "last", false)
                            }
                            onCellsChanged: {
                                hoveredDay = ""
                                if (HeatmapNavigation.indexForDay(cells, selectedDay) < 0)
                                    selectedDay = ""
                            }
                            Keys.onPressed: function(event) {
                                var direction = ""
                                switch (event.key) {
                                case Qt.Key_Left: direction = "left"; break
                                case Qt.Key_Right: direction = "right"; break
                                case Qt.Key_Up: direction = "up"; break
                                case Qt.Key_Down: direction = "down"; break
                                case Qt.Key_Home: direction = "first"; break
                                case Qt.Key_End: direction = "last"; break
                                default: event.accepted = false; return
                                }
                                selectedDay = HeatmapNavigation.nextDay(cells, selectedDay,
                                    direction, LayoutMirroring.enabled)
                                hoveredDay = ""
                                event.accepted = true
                            }

                            Layout.fillWidth: true
                            Layout.preferredHeight: 7 * heatmapGrid.cellHeight
                                + 6 * heatmapGrid.rowSpacing
                            clip: true

                            Grid {
                                id: heatmapGrid

                                readonly property real cellSpacing: Math.max(1, Math.round(Kirigami.Units.smallSpacing / 2))
                                readonly property real minimumCellSize: Kirigami.Units.gridUnit * 0.6
                                // Kept below the chart's weight: this is the secondary
                                // read, a weekday pattern, not the magnitude over time.
                                readonly property real maximumCellSize: Kirigami.Units.gridUnit * 1.15
                                readonly property int fittingColumns: Math.max(1, Math.floor(
                                    (width + cellSpacing) / (minimumCellSize + cellSpacing)))
                                readonly property int columnCount: Math.max(1, Math.min(
                                    fittingColumns, Math.ceil(
                                        (view.heatmapDays.length + view.heatmapTrailingSlots) / 7)))
                                readonly property real availableCellWidth: Math.max(minimumCellSize,
                                    (width - cellSpacing * (columnCount - 1)) / columnCount)
                                readonly property real cellHeight: Math.max(minimumCellSize, Math.min(
                                    maximumCellSize, availableCellWidth))
                                readonly property real cellWidth: cellHeight
                                readonly property var cells: CostChart.spendHeatmapCells(
                                    view.heatmapDays, columnCount * 7, view.heatmapTrailingSlots)

                                width: parent.width
                                rows: 7
                                flow: Grid.TopToBottom
                                columnSpacing: cellSpacing
                                rowSpacing: cellSpacing

                                Repeater {
                                    model: heatmapGrid.cells

                                    delegate: Rectangle {
                                        id: heatmapCell

                                        required property var modelData
                                        required property int index

                                        // Padding slots carry no day: they fill the
                                        // oldest corner of the block and stay out of
                                        // hover, the readout, and the reading order.
                                        readonly property bool measured: !!heatmapCell.modelData
                                        readonly property real fraction: heatmapCell.measured && view.heatmapMaximum > 0
                                            ? Math.max(0, Math.min(1,
                                                Number(heatmapCell.modelData.value) / view.heatmapMaximum))
                                            : 0

                                        Accessible.role: Accessible.Graphic
                                        Accessible.ignored: !heatmapCell.measured
                                        // Days read like the chart's, in the locale's date format.
                                        readonly property string dayLabel: heatmapCell.measured
                                            ? historyChart.pointLabel(heatmapCell.modelData) : ""

                                        Accessible.name: heatmapCell.dayLabel
                                        Accessible.description: heatmapCell.measured ? heatmapCell.modelData.displayValue : ""

                                        width: heatmapGrid.cellWidth
                                        height: heatmapGrid.cellHeight
                                        radius: Kirigami.Units.cornerRadius / 2
                                        // Padding has no measurement and must stay distinct
                                        // from a measured zero. Its outline never receives tint.
                                        color: heatmapCell.measured
                                            ? view.applet.withAlpha(Kirigami.Theme.textColor, 0.05) : "transparent"
                                        border.width: heatmapCell.measured ? 0 : 1
                                        border.color: view.applet.withAlpha(Kirigami.Theme.textColor, 0.12)

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: parent.radius
                                            visible: heatmapCell.measured
                                            color: view.heatmapTint(heatmapCell.fraction)
                                        }

                                        // The cell carries no border of its own and the
                                        // hover outline is a separate overlay. Fading a
                                        // border's own alpha does not work: Qt treats a
                                        // zero-alpha pen as invalid and paints the
                                        // rectangle with a zero-width border, so the fill
                                        // snaps out to the cell edge the moment the
                                        // highlight leaves. Grabbing the rendered pixels
                                        // confirmed it: between alpha 0 and 0.01 an edge
                                        // pixel jumped straight from the fill colour to
                                        // the background. Fading this overlay's opacity
                                        // blends that pixel instead, leaving the cell's
                                        // painted geometry untouched.
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: parent.radius
                                            color: "transparent"
                                            border.width: 1
                                            border.color: heatmapFocus.activeFocus && heatmapFocus.hoveredDay.length === 0
                                                ? Kirigami.Theme.focusColor
                                                : view.applet.withAlpha(Kirigami.Theme.textColor, 0.4)
                                            visible: heatmapCell.measured
                                            opacity: heatmapCell.index === heatmapFocus.inspectedIndex ? 1 : 0

                                            Behavior on opacity {
                                                enabled: !heatmapFocus.activeFocus
                                                NumberAnimation {
                                                    duration: Kirigami.Units.shortDuration
                                                }
                                            }
                                        }

                                        Components.PlainToolTip {
                                            // A readout for the cell under the pointer,
                                            // not a label for a control: scanning the
                                            // grid must not wait out a hover delay.
                                            delay: 0
                                            visible: heatmapMouse.containsMouse && heatmapCell.measured
                                                && heatmapFocus.hoveredDay === heatmapCell.modelData.label
                                            plainText: heatmapCell.measured
                                                ? i18n("%1: %2", heatmapCell.dayLabel,
                                                    heatmapCell.modelData.displayValue)
                                                : ""
                                        }

                                        MouseArea {
                                            id: heatmapMouse

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            // A binding avoids Qt rejecting a bare zero enum literal.
                                            acceptedButtons: (0)
                                            onEntered: if (heatmapCell.measured)
                                                heatmapFocus.hoveredDay = heatmapCell.modelData.label
                                            onPositionChanged: if (heatmapCell.measured)
                                                heatmapFocus.hoveredDay = heatmapCell.modelData.label
                                            onExited: if (heatmapCell.measured
                                                && heatmapFocus.hoveredDay === heatmapCell.modelData.label)
                                                heatmapFocus.hoveredDay = ""
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // The tint is the only magnitude cue: without a key the
                    // shades read as decoration. Each cell keeps its own
                    // accessible value, so the key stays out of the tree.
                    RowLayout {
                        objectName: "heatmapLegend"

                        spacing: heatmapGrid.cellSpacing
                        Accessible.ignored: true

                        PlainPlasmaLabel {
                            text: i18nc("Activity heatmap legend, shade of the lowest daily value", "Less")
                            font: Kirigami.Theme.smallFont
                            opacity: view.applet.secondaryTextOpacity
                            Accessible.ignored: true
                            Layout.rightMargin: Kirigami.Units.smallSpacing - heatmapGrid.cellSpacing
                        }

                        Repeater {
                            model: [0, 0.25, 0.5, 0.75, 1]

                            delegate: Rectangle {
                                required property var modelData

                                implicitWidth: Math.round(Kirigami.Units.gridUnit * 0.6)
                                implicitHeight: implicitWidth
                                radius: Kirigami.Units.cornerRadius / 2
                                color: view.applet.withAlpha(Kirigami.Theme.textColor, 0.05)
                                Accessible.ignored: true

                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: view.heatmapTint(parent.modelData)
                                }
                            }
                        }

                        PlainPlasmaLabel {
                            text: i18nc("Activity heatmap legend, shade of the highest daily value", "More")
                            font: Kirigami.Theme.smallFont
                            opacity: view.applet.secondaryTextOpacity
                            Accessible.ignored: true
                            Layout.leftMargin: Kirigami.Units.smallSpacing - heatmapGrid.cellSpacing
                        }
                    }

                    PlainPlasmaLabel {
                        id: heatmapReadout
                        objectName: "heatmapReadout"
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        text: heatmapFocus.readout.length > 0 ? heatmapFocus.readout : " "
                        opacity: heatmapFocus.readout.length > 0 ? view.applet.secondaryTextOpacity : 0
                        font: Qt.font(Object.assign({}, Kirigami.Theme.smallFont, { features: { "tnum": 1 } }))
                        elide: Text.ElideRight
                        Accessible.ignored: true

                        HoverHandler { id: heatmapReadoutHover }
                        PlainToolTip {
                            visible: heatmapReadout.truncated && heatmapFocus.readout.length > 0
                                && (heatmapReadoutHover.hovered || heatmapFocus.activeFocus)
                            plainText: heatmapFocus.readout
                        }
                    }
                }

                ColumnLayout {
                    visible: view.providerCosts.length > 0
                    Layout.fillWidth: true
                    Layout.preferredWidth: 2
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignTop
                    spacing: Kirigami.Units.smallSpacing

                    PlainPlasmaLabel {
                        text: i18n("Providers")
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Repeater {
                        id: spendProviderRepeater

                        model: view.presentedProviderCosts

                        delegate: Rectangle {
                            id: spendProviderCard

                            required property var modelData
                            readonly property var totals: modelData.totals
                            readonly property string costText: CostAmounts.hasMetricValue(totals, false)
                                ? view.applet.qualifiedCostValue(view.applet.amountString(totals.cost,
                                    totals.currency), modelData.valueMode)
                                : i18n("Cost unavailable")
                            readonly property string tokensText: CostAmounts.hasMetricValue(totals, true)
                                ? view.applet.usageCountText(totals.tokens, "tokens")
                                : i18n("Tokens unavailable")

                            Layout.fillWidth: true
                            implicitHeight: spendProviderRow.implicitHeight + Kirigami.Units.largeSpacing * 2
                            radius: view.applet.nestedSurfaceRadius
                            // A passive display row: no hover state, because every
                            // other highlighted surface in the popup acts on click
                            // or reveals actions, and this one does neither.
                            color: view.applet.withAlpha(Kirigami.Theme.textColor, 0.035)

                            Accessible.role: Accessible.ListItem
                            Accessible.name: view.applet.providerDisplayTitle(spendProviderCard.modelData.provider)
                            Accessible.description: spendProviderPrimary.text + ". " + spendProviderSecondary.text

                            HoverHandler { id: spendProviderHover }

                            PlainToolTip {
                                visible: spendProviderHover.hovered
                                    && (spendProviderTitle.truncated || spendProviderPrimary.truncated
                                        || spendProviderSecondary.truncated)
                                plainText: spendProviderTitle.text + "\n" + spendProviderPrimary.text
                                    + "\n" + spendProviderSecondary.text
                            }

                            RowLayout {
                                id: spendProviderRow

                                anchors.fill: parent
                                anchors.margins: Kirigami.Units.largeSpacing
                                spacing: Kirigami.Units.largeSpacing

                                Rectangle {
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                        + Kirigami.Units.smallSpacing * 2
                                    Layout.preferredHeight: Layout.preferredWidth
                                    // Same identity-tile treatment as the overview
                                    // and header tiles, scaled down for this row.
                                    radius: view.applet.nestedSurfaceRadius
                                    color: view.applet.withAlpha(view.applet.providerReadableColor(
                                        spendProviderCard.modelData.provider,
                                        Kirigami.Theme.backgroundColor), 0.12)
                                    border.width: 1
                                    border.color: view.applet.withAlpha(Kirigami.Theme.textColor, 0.1)

                                    Kirigami.Icon {
                                        anchors.centerIn: parent
                                        source: view.applet.providerIconSource(spendProviderCard.modelData.provider)
                                        fallback: "view-statistics"
                                        isMask: view.applet.providerIconIsMask(spendProviderCard.modelData.provider)
                                        color: view.applet.providerReadableColor(
                                            spendProviderCard.modelData.provider,
                                            Kirigami.Theme.backgroundColor)
                                        width: Kirigami.Units.iconSizes.smallMedium
                                        height: Kirigami.Units.iconSizes.smallMedium
                                    }
                                }

                                PlainPlasmaLabel {
                                    id: spendProviderTitle
                                    objectName: "spendProviderTitle"

                                    text: view.applet.providerDisplayTitle(spendProviderCard.modelData.provider)
                                    font.weight: Font.DemiBold
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    Layout.preferredWidth: 1
                                    elide: Text.ElideRight
                                }

                                ColumnLayout {
                                    // Equal flexible columns keep long amounts from
                                    // pushing the provider identity out of the row.
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    Layout.preferredWidth: 1
                                    spacing: Kirigami.Units.smallSpacing / 2

                                    PlainPlasmaLabel {
                                        id: spendProviderPrimary
                                        objectName: "spendProviderPrimary"
                                        font.features: { "tnum": 1 }

                                        text: view.applet.costHistoryShowsTokens
                                            ? spendProviderCard.tokensText : spendProviderCard.costText
                                        font.weight: Font.DemiBold
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        horizontalAlignment: Text.AlignRight
                                        elide: Text.ElideRight
                                    }

                                    PlainPlasmaLabel {
                                        id: spendProviderSecondary
                                        objectName: "spendProviderSecondary"

                                        text: view.applet.costHistoryShowsTokens
                                            ? spendProviderCard.costText : spendProviderCard.tokensText
                                        font: Qt.font(Object.assign({}, Kirigami.Theme.smallFont, { features: { "tnum": 1 } }))
                                        opacity: view.applet.secondaryTextOpacity
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        horizontalAlignment: Text.AlignRight
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
