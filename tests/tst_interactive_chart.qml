import QtQuick
import QtQuick.Window
import QtTest

TestCase {
    name: "InteractiveChart"
    when: windowShown
    width: 340
    height: 240
    visible: true
    property var componentHolders: []

    Component {
        id: paintSpyComponent
        SignalSpy { signalName: "painted" }
    }

    function cleanupTestCase() {
        for (var i = 0; i < componentHolders.length; i++) {
            componentHolders[i].destroy()
        }
    }

    function createChart(properties) {
        var component
        try {
            var holder = Qt.createQmlObject('import QtQuick; import org.kde.kirigami as Kirigami; '
                + 'import "../contents/ui/components" as Components; '
                + 'QtObject { property Component chartComponent: Component {'
                + ' Components.InteractiveChart { function i18n(text) { for (var i = 1; i < arguments.length; i++) text = text.replace("%" + i, String(arguments[i])); return text } '
                + 'function setThemeTextColor(value) { Kirigami.Theme.inherit = false; Kirigami.Theme.textColor = value } '
                + '} } }', this, Qt.resolvedUrl("InteractiveChartTest.qml"))
            component = holder.chartComponent
            componentHolders.push(holder)
        } catch (error) {
            if (/module "org\.kde\.(kirigami|plasma\.components)" is not installed/.test(String(error))) {
                skip("InteractiveChart needs the optional KDE QML modules")
                return null
            }
            throw error
        }
        var chart = createTemporaryObject(component, this, properties)
        verify(chart !== null)
        return chart
    }

    function test_providerLinesInspectValuesAndGapsWithoutChangingGeometry() {
        function points(values) {
            return values.map(function(value, index) {
                return {label: "2026-11-" + (10 + index), value: value,
                    displayValue: value === null ? null : String(value)}
            })
        }
        var chart = createChart({
            applet: {secondaryTextOpacity: 0.7, canvasColor: function(color, alpha) {
                return Qt.rgba(color.r, color.g, color.b, alpha).toString()
            }},
            width: 300, kind: "line", showPeak: true, accent: "blue",
            points: points([20, 10, 3, 21]), axisLabels: ["25", "12.5", "0"],
            lineSeries: [{provider: "a", label: "Codex", points: points([0, 10, null, 20])},
                {provider: "b", label: "Claude", points: points([20, 0, 3, 1])},
                {provider: "c", label: "Gemini", points: points([0, 0, 0, 0])}],
            seriesColors: {a: Qt.rgba(0, 0.6, 0.8, 1), b: Qt.rgba(0.8, 0.4, 0.2, 1), c: Qt.rgba(0.6, 0.2, 0.7, 1)}
        })
        if (!chart) return
        failOnWarning(/.*/)
        var focusTarget = chart.nextItemInFocusChain(true)
        var plot = focusTarget.parent
        var paints = createTemporaryObject(paintSpyComponent, this, {target: plot})
        tryCompare(plot, "available", true)
        tryVerify(function() { return paints.count > 0 })
        var originalHeight = chart.height
        var originalWidth = plot.width
        mouseMove(plot, chart.lineMarkerInset, plot.height / 2)
        tryCompare(chart, "hoveredIndex", 0)
        compare(chart.selectedIndex, -1)
        compare(focusTarget.Accessible.description, new Date(2026, 10, 10).toLocaleDateString(Qt.locale(), Locale.ShortFormat) + ": 20\nCodex: 0\nClaude: 20\nGemini: 0")
        focusTarget.forceActiveFocus(Qt.TabFocusReason)
        keyClick(Qt.Key_End)
        compare(chart.selectedIndex, 3)
        compare(chart.hoveredIndex, -1)
        compare(focusTarget.Accessible.description, new Date(2026, 10, 13).toLocaleDateString(Qt.locale(), Locale.ShortFormat) + ": 21\nCodex: 20\nClaude: 1\nGemini: 0")
        keyClick(Qt.Key_Left)
        compare(focusTarget.Accessible.description, new Date(2026, 10, 12).toLocaleDateString(Qt.locale(), Locale.ShortFormat) + ": 3\nCodex: Unavailable\nClaude: 3\nGemini: 0")
        compare(chart.height, originalHeight)
        compare(plot.width, originalWidth)
        verify(waitForRendering(chart))
    }

    function test_linePreviewStaysInsidePlotAndClosesAfterPointerExit() {
        var chart = createChart({applet: {secondaryTextOpacity: 0.7, canvasColor: function() { return "#000000" }},
            width: 300, kind: "line", accent: "blue", points: [{label: "2026-11-13", value: 1}],
            lineSeries: [{provider: "codex", points: [{label: "2026-11-13", value: 1}]}]});
        if (!chart) return;
        failOnWarning(/.*/);
        var focus = chart.nextItemInFocusChain(true);
        var plot = focus.parent;
        var preview = findChild(chart, "chartLinePreview");
        mouseMove(plot, plot.width / 2, plot.height / 2);
        tryCompare(preview, "visible", true);
        verify(preview.x >= 0 && preview.x + preview.width <= plot.width);
        verify(preview.y >= 0 && preview.y + preview.height <= plot.height);
        mouseClick(plot, plot.width / 2, plot.height / 2);
        mouseMove(this, 330, 230);
        tryCompare(preview, "visible", false);
        compare(chart.selectedIndex, 0);
        keyClick(Qt.Key_Escape);
        compare(chart.selectedIndex, -1);
    }

    function test_axisLabelsStayInsideMirroredChart() {
        var chart = createChart({applet: {secondaryTextOpacity: 0.7, canvasColor: function() { return "#000000" }},
            width: 300, kind: "line", accent: "blue", points: [{label: "2026-11-13", value: 1}],
            axisLabels: ["$2", "$1", "$0"], lineSeries: []});
        if (!chart) return;
        chart.LayoutMirroring.enabled = true;
        chart.LayoutMirroring.childrenInherit = true;
        verify(waitForRendering(chart));
        var plot = chart.nextItemInFocusChain(true).parent;
        var labels = plot.children.filter(function(item) { return item.text === "$2"; });
        compare(labels.length, 1);
        var x = labels[0].mapToItem(chart, 0, 0).x;
        verify(x >= 0 && x + labels[0].width <= chart.width + 1);
    }

    function test_firstInspectionKeepsPlotGeometry_data() {
        return [{tag: "hover", keyboard: false}, {tag: "keyboard", keyboard: true}]
    }

    function test_inspectionGuideMarksTheActivePosition_data() {
        return [
            {tag: "zero-bars-hover", kind: "bar", values: [0, 0, 0], keyboard: false, x: 150},
            {tag: "zero-bars-keyboard", kind: "bars", values: [0, 0, 0], keyboard: true, x: 250},
            {tag: "signed-bars", kind: "bar", values: [-3, 0, 9], keyboard: false, x: 150},
            {tag: "zero-line", kind: "line", values: [0, 0, 0], keyboard: true, x: 297},
            {tag: "signed-line", kind: "line", values: [-3, 0, 9], keyboard: false, x: 150},
            {tag: "single-point", kind: "line", values: [0], keyboard: true, x: 150}
        ]
    }

    function test_inspectionGuideMarksTheActivePosition(data) {
        var chart = createChart({
            applet: {secondaryTextOpacity: 0.7, canvasColor: function(color, alpha) {
                return Qt.rgba(0, 0, 0, alpha).toString()
            }},
            width: 300,
            points: data.values.map(function(value, index) { return {label: String(index), value: value} }),
            accent: "blue",
            kind: data.kind
        })
        if (!chart)
            return
        failOnWarning(/.*/)
        var focusTarget = chart.nextItemInFocusChain(true)
        var plot = focusTarget.parent
        var paints = createTemporaryObject(paintSpyComponent, this, {target: plot})
        tryCompare(plot, "available", true)
        tryVerify(function() { return paints.count > 0 })
        compare(plot.getContext("2d").getImageData(data.x, 0, 1, 1).data[3], 0)
        paints.clear()
        if (data.keyboard) {
            focusTarget.forceActiveFocus(Qt.TabFocusReason)
            keyClick(Qt.Key_End)
        } else {
            mouseMove(plot, data.x, plot.height / 2)
        }
        tryVerify(function() { return paints.count > 0 })
        verify(plot.getContext("2d").getImageData(data.x, 0, 1, 1).data[3] > 0,
            "The inspected point needs a visible guide, including zero values")
        paints.clear()
        mouseMove(this, 330, 230)
        chart.selectedIndex = -1
        tryVerify(function() { return paints.count > 0 })
        compare(plot.getContext("2d").getImageData(data.x, 0, 1, 1).data[3], 0)
    }

    function test_detailBarsKeepPeakGuideline_data() {
        return [{tag: "cost-bars", kind: "bar", guide: true},
            {tag: "detail-bars", kind: "bars", guide: true},
            {tag: "detail-line", kind: "line", guide: false}]
    }

    function test_detailBarsKeepPeakGuideline(data) {
        var chart = createChart({
            applet: {secondaryTextOpacity: 0.7, canvasColor: function() { return "#000000" }},
            width: 300,
            points: [{label: "First", value: 1}, {label: "Peak", value: 10}],
            accent: "blue",
            kind: data.kind
        })
        if (!chart)
            return
        var focusTarget = chart.nextItemInFocusChain(true)
        var plot = focusTarget.parent
        verify(waitForRendering(chart))
        // The peak is at y=2; x=0 is outside both bars and line markers.
        // Read the actual canvas so a missing guide cannot pass on geometry alone.
        tryCompare(plot, "available", true)
        plot.requestPaint()
        verify(waitForRendering(plot))
        var alpha = plot.getContext("2d").getImageData(0, 2, 1, 1).data[3]
        compare(alpha > 0, data.guide)
    }

    function test_themeChangeRepaintsGuidesWithAFixedAccent() {
        var chart = createChart({
            applet: {secondaryTextOpacity: 0.7, canvasColor: function(color) { return color.toString() }},
            width: 300,
            points: [{label: "First", value: 1}, {label: "Peak", value: 10}],
            accent: "blue"
        })
        if (!chart)
            return
        chart.setThemeTextColor("#ff0000")
        var focusTarget = chart.nextItemInFocusChain(true)
        var plot = focusTarget.parent
        var paints = createTemporaryObject(paintSpyComponent, this, {target: plot})
        tryCompare(plot, "available", true)
        tryVerify(function() { return paints.count > 0 })
        var before = plot.getContext("2d").getImageData(0, 2, 1, 1).data
        compare(before[0], 255)
        compare(before[1], 0)
        paints.clear()

        chart.setThemeTextColor("#00ff00")
        tryVerify(function() { return paints.count > 0 })
        compare(chart.accent.toString(), "#0000ff")
        var after = plot.getContext("2d").getImageData(0, 2, 1, 1).data
        compare(after[0], 0)
        compare(after[1], 255)
    }

    function test_firstInspectionKeepsPlotGeometry(data) {
        var chart = createChart({
            applet: {secondaryTextOpacity: 0.7, canvasColor: function() { return "#000000" }},
            width: 300,
            points: [{label: "First", value: 0}],
            accent: "blue"
        })
        if (!chart)
            return
        failOnWarning(/.*/)
        var focusTarget = chart.nextItemInFocusChain(true)
        var plot = focusTarget.parent
        verify(typeof plot.requestPaint === "function")
        verify(waitForRendering(chart))
        var initialY = plot.y
        var initialHeight = chart.implicitHeight
        compare(chart.readoutIndex, -1)
        if (data.keyboard) {
            focusTarget.forceActiveFocus(Qt.TabFocusReason)
            keyClick(Qt.Key_Home)
        } else {
            mouseMove(plot, plot.width / 2, plot.height / 2)
        }
        compare(chart.readoutIndex, 0)
        verify(waitForRendering(chart))
        compare(plot.y, initialY)
        compare(chart.implicitHeight, initialHeight)
        mouseMove(this, 330, 230)
        chart.selectedIndex = -1
        verify(waitForRendering(chart))
        compare(plot.y, initialY)
        chart.points = []
        verify(waitForRendering(chart))
        compare(plot.y, initialY)
    }

    // CLI calendar keys read as local dates in the system locale. The key is a
    // calendar day, not an instant, so a zone west of UTC must not show the
    // previous day. Other labels stay as the CLI wrote them.
    function test_calendarKeysUseTheLocaleShortDate() {
        var chart = createChart({
            applet: {secondaryTextOpacity: 0.7, canvasColor: function() { return "#000000" }},
            width: 300,
            points: [{label: "2026-08-25", value: 1}],
            accent: "blue"
        })
        if (!chart)
            return
        var expected = new Date(2026, 7, 25).toLocaleDateString(Qt.locale(), Locale.ShortFormat)
        compare(chart.pointLabel({label: "2026-08-25"}), expected)
        verify(expected.indexOf("25") >= 0)
        compare(chart.pointLabel({label: "Week 34"}), "Week 34")
        compare(chart.pointLabel({label: "2026-02-30"}), "2026-02-30")
        compare(chart.pointLabel({label: "2026-08-25T10:00:00Z"}), "2026-08-25T10:00:00Z")
        compare(chart.pointLabel(null), "")
    }

    function test_peakReadoutYieldsToInspectionAndUpdatesWithTheMetric() {
        var chart = createChart({
            applet: {secondaryTextOpacity: 0.7, canvasColor: function() { return "#000000" }},
            width: 300, showPeak: true, accent: "blue",
            points: [{label: "First", value: 2, displayValue: "$2"},
                {label: "Second", value: 9, displayValue: "$9"}]
        })
        if (!chart)
            return
        var label = findChild(chart, "chartPointLabel")
        var value = findChild(chart, "chartPointValue")
        compare(label.text, "Peak daily usage")
        compare(value.text, "$9")
        var focusTarget = chart.nextItemInFocusChain(true)
        focusTarget.forceActiveFocus(Qt.TabFocusReason)
        keyClick(Qt.Key_Home)
        compare(label.text, "First")
        compare(value.text, "$2")
        chart.selectedIndex = -1
        compare(label.text, "Peak daily usage")
        compare(value.text, "$9")
        chart.points = [{label: "Zero", value: 0, displayValue: "0 tokens"}]
        compare(value.text, "0 tokens")
        chart.points = []
        compare(chart.peakIndex, -1)
        compare(value.text, "")
    }

    function test_readoutPreservesNegativeDetailValues() {
        var chart = createChart({
            applet: {
                secondaryTextOpacity: 0.7
            },
            points: [
                {
                    label: "Adjustment",
                    value: -3
                }
            ],
            accent: "blue",
            valueSuffix: "credits"
        })
        if (!chart)
            return
        verify(chart !== null)
        compare(chart.pointDisplayValue(chart.points[0]), "-3 credits")
    }

    function test_signedPointsHaveSeparatePositionsAroundZero() {
        var chart = createChart({
            applet: {
                secondaryTextOpacity: 0.7
            },
            points: [
                {
                    value: -3
                },
                {
                    value: 0
                },
                {
                    value: 9
                }
            ],
            accent: "blue"
        })
        if (!chart)
            return
        compare(chart.chartFraction(-3), 0)
        compare(chart.chartFraction(0), 0.25)
        compare(chart.chartFraction(9), 1)
    }

    function test_missingPointsClearSelectionAndRecover_data() {
        return [{ tag: "null", value: null }, { tag: "undefined", value: undefined }]
    }

    function test_missingPointsClearSelectionAndRecover(data) {
        var chart = createChart({
            applet: { secondaryTextOpacity: 0.7, canvasColor: function() { return "#000000" } },
            width: 300,
            points: [{ label: "Before", value: 0 }],
            accent: "blue"
        })
        if (!chart)
            return
        failOnWarning(/.*/)
        compare(chart.pointCount, 1)
        chart.selectedIndex = 0
        chart.hoveredIndex = 0
        var focusTarget = chart.nextItemInFocusChain(true)
        var plot = focusTarget.parent
        verify(typeof plot.requestPaint === "function")
        focusTarget.forceActiveFocus(Qt.TabFocusReason)
        chart.points = data.value
        compare(chart.selectedIndex, -1)
        compare(chart.hoveredIndex, -1)
        compare(chart.hasActivePoint, false)
        compare(chart.indexAt(10), -1)
        for (var key of [Qt.Key_Left, Qt.Key_Right, Qt.Key_Home, Qt.Key_End]) {
            keyClick(key)
            compare(chart.selectedIndex, -1)
        }
        waitForRendering(plot)
        chart.points = [{ label: "After", value: 0 }]
        keyClick(Qt.Key_Home)
        compare(chart.selectedIndex, 0)
        compare(chart.hasActivePoint, true)
        compare(chart.pointLabel(chart.points[chart.activeIndex]), "After")
        waitForRendering(plot)
    }

    // A line chart strokes a line instead of filling bar gradients: usage
    // detail sections feed kind "line" from the CLI payload.
    function test_lineKindPlotsThroughLineGeometry() {
        var opacities = [];
        var chart = createChart({
            applet: {
                secondaryTextOpacity: 0.7,
                canvasColor: function(color, alpha) { opacities.push(alpha); return "#000000"; }
            },
            width: 300,
            points: [{ label: "First", value: 1 }, { label: "Last", value: 2 }],
            accent: "blue",
            kind: "line"
        })
        if (!chart)
            return
        failOnWarning(/.*/)
        verify(waitForRendering(chart))
        // One render pass is not guaranteed to have painted the canvas when the
        // runner shares a process with the rest of the suite, so wait for the
        // line stroke to actually be asked for rather than assuming it was.
        tryVerify(function() { return opacities.indexOf(0.9) >= 0 })
        compare(opacities.indexOf(0.78), -1)
    }

    function test_mouseFocusDoesNotDrawKeyboardOutline() {
        var chart = createChart({
            applet: { secondaryTextOpacity: 0.7, canvasColor: function() { return "#000000" } },
            x: 10, y: 10, width: 300,
            points: [{ label: "First", value: 1 }, { label: "Last", value: 2 }],
            accessibleTitle: "Daily history",
            accent: "blue"
        })
        if (!chart)
            return
        failOnWarning(/.*/)
        var focusTarget = chart.nextItemInFocusChain(true)
        compare(focusTarget.Accessible.role, Accessible.Graphic)
        compare(focusTarget.Accessible.name, "Daily history")
        verify(waitForRendering(chart))
        var edgeX = chart.x - 1
        var edgeY = Math.round(focusTarget.mapToItem(this, 0, focusTarget.height / 2).y)
        var frame = grabImage(this)
        var pixelX = Math.floor((edgeX + 0.5) * Screen.devicePixelRatio)
        var pixelY = Math.floor((edgeY + 0.5) * Screen.devicePixelRatio)
        var restingEdge = frame.pixel(pixelX, pixelY)

        mouseClick(focusTarget, focusTarget.width / 4, focusTarget.height / 2)
        verify(focusTarget.activeFocus)
        compare(chart.selectedIndex, 0)
        verify(waitForRendering(chart))
        compare(grabImage(this).pixel(pixelX, pixelY), restingEdge,
            "Mouse selection must not draw the keyboard focus outline")
        keyClick(Qt.Key_Right)
        compare(chart.selectedIndex, 1)

        chart.forceActiveFocus()
        keyClick(Qt.Key_Tab)
        verify(focusTarget.activeFocus)
        verify(waitForRendering(chart))
        verify(grabImage(this).pixel(pixelX, pixelY) !== restingEdge,
            "Tab focus must keep a visible outline")

        mouseClick(focusTarget, focusTarget.width / 4, focusTarget.height / 2)
        verify(focusTarget.activeFocus)
        verify(waitForRendering(chart))
        compare(grabImage(this).pixel(pixelX, pixelY), restingEdge,
            "Clicking a keyboard-focused chart must hide its outline")
        chart.forceActiveFocus()
        focusTarget.forceActiveFocus(Qt.ActiveWindowFocusReason)
        compare(grabImage(this).pixel(pixelX, pixelY), restingEdge,
            "Window reactivation must not turn mouse focus into keyboard focus")
    }

    // The plot stays in the tab chain so keyboard inspection needs no mouse.
    function test_plotIsReachableByTab() {
        var chart = createChart({
            applet: { secondaryTextOpacity: 0.7, canvasColor: function() { return "#000000" } },
            width: 300,
            points: [{ label: "First", value: 0 }],
            accent: "blue"
        })
        if (!chart)
            return
        failOnWarning(/.*/)
        var focusTarget = chart.nextItemInFocusChain(true)
        var plot = focusTarget.parent
        verify(typeof plot.requestPaint === "function")
        verify(waitForRendering(chart))
        verify(!focusTarget.activeFocus)
        chart.forceActiveFocus()
        verify(chart.activeFocus)
        keyClick(Qt.Key_Tab)
        verify(focusTarget.activeFocus)
    }

    function test_keyboardSelectionOverridesStationaryPointer_data() {
        return [
            { tag: "left", key: Qt.Key_Left, hovered: 2, selected: 0 },
            { tag: "right", key: Qt.Key_Right, hovered: 0, selected: 2 },
            { tag: "home", key: Qt.Key_Home, hovered: 2, selected: 0 },
            { tag: "end", key: Qt.Key_End, hovered: 0, selected: 2 }
        ]
    }

    function test_keyboardSelectionOverridesStationaryPointer(data) {
        var chart = createChart({
            applet: {
                secondaryTextOpacity: 0.7,
                canvasColor: function() { return "#000000" }
            },
            width: 300,
            points: [
                { label: "First", value: 0 },
                { label: "Middle", value: 0 },
                { label: "Last", value: 0 }
            ],
            accent: "blue",
            selectedIndex: 1
        })
        if (!chart)
            return
        var focusTarget = chart.nextItemInFocusChain(true)
        var plot = focusTarget.parent
        verify(typeof plot.requestPaint === "function")
        mouseMove(plot, (data.hovered + 0.5) * plot.width / 3, plot.height / 2)
        compare(chart.activeIndex, data.hovered)
        focusTarget.forceActiveFocus(Qt.TabFocusReason)
        keyClick(data.key)
        compare(chart.selectedIndex, data.selected)
        compare(chart.activeIndex, data.selected)
        mouseMove(plot, plot.width / 2, plot.height / 2)
        compare(chart.activeIndex, 1)
        mouseMove(this, 330, 230)
        tryCompare(chart, "hoveredIndex", -1)
        compare(chart.activeIndex, data.selected)
    }
}
