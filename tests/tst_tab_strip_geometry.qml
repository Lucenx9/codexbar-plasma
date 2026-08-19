import QtQuick
import QtTest
import "../contents/ui/TabStripGeometry.js" as TabStripGeometry

TestCase {
    name: "TabStripGeometry"

    // A 300px viewport over 800px of tabs, so the last valid position is 500.
    readonly property int viewport: 300
    readonly property int content: 800
    readonly property int margin: 18

    function test_boundedPositionKeepsAScrollInsideTheRange() {
        compare(TabStripGeometry.boundedPosition(0, content, viewport), 0)
        compare(TabStripGeometry.boundedPosition(250, content, viewport), 250)
        compare(TabStripGeometry.boundedPosition(500, content, viewport), 500)
    }

    function test_boundedPositionRefusesToOverscroll() {
        compare(TabStripGeometry.boundedPosition(-40, content, viewport), 0)
        compare(TabStripGeometry.boundedPosition(9999, content, viewport), 500)
    }

    // Content narrower than its viewport has one valid position. Clamping the
    // other way round would answer with a negative contentX and leave the strip
    // scrolled off its own start.
    function test_boundedPositionPinsAStripThatFitsItsViewport() {
        compare(TabStripGeometry.boundedPosition(0, 120, viewport), 0)
        compare(TabStripGeometry.boundedPosition(80, 120, viewport), 0)
        compare(TabStripGeometry.boundedPosition(-80, 120, viewport), 0)
    }

    function test_boundedPositionTreatsAnExactFitAsPinned() {
        compare(TabStripGeometry.boundedPosition(50, viewport, viewport), 0)
    }

    function test_boundedPositionFallsBackToTheStartOnUnusableInput() {
        compare(TabStripGeometry.boundedPosition("abc", content, viewport), 0)
        compare(TabStripGeometry.boundedPosition(undefined, content, viewport), 0)
    }

    // The whole point of returning null: a tab already on screen must not
    // restart the scroll animation every time the strip reports its selection.
    function test_revealPositionIsNullWhenTheTabIsAlreadyVisible() {
        compare(TabStripGeometry.revealPosition(100, 60, 0, viewport, margin), null)
        compare(TabStripGeometry.revealPosition(margin, 60, 0, viewport, margin), null)
    }

    function test_revealPositionScrollsBackForATabOffTheLeftEdge() {
        // Scrolled to 400, tab sits at 300: bring it in with its margin.
        compare(TabStripGeometry.revealPosition(300, 60, 400, viewport, margin), 300 - margin)
    }

    function test_revealPositionScrollsForwardForATabOffTheRightEdge() {
        // Scrolled to 0, tab spans 700..800: its right edge plus margin must
        // land on the viewport's right edge.
        compare(TabStripGeometry.revealPosition(700, 100, 0, viewport, margin),
                700 + 100 + margin - viewport)
    }

    // A tab touching the edge is not comfortably visible; the margin is what
    // decides, so the boundary has to be tested on both sides of it.
    function test_revealPositionTreatsTheMarginAsPartOfTheTab() {
        compare(TabStripGeometry.revealPosition(margin, 60, 0, viewport, margin), null)
        compare(TabStripGeometry.revealPosition(margin - 1, 60, 0, viewport, margin), -1)

        var lastFullyVisibleLeft = viewport - margin - 60
        compare(TabStripGeometry.revealPosition(lastFullyVisibleLeft, 60, 0, viewport, margin), null)
        compare(TabStripGeometry.revealPosition(lastFullyVisibleLeft + 1, 60, 0, viewport, margin), 1)
    }

    // The left edge wins, so a tab wider than the viewport shows its start
    // rather than its end.
    function test_revealPositionPrefersTheStartOfAnOversizedTab() {
        compare(TabStripGeometry.revealPosition(400, 900, 500, viewport, margin), 400 - margin)
    }

    function test_revealPositionCanAnswerBelowZeroForTheCallerToClamp() {
        // Reported without clamping; scrollTo bounds it, which is what keeps the
        // two decisions separable and testable.
        compare(TabStripGeometry.revealPosition(0, 60, 10, viewport, margin), -margin)
        compare(TabStripGeometry.boundedPosition(-margin, content, viewport), 0)
    }

    function test_revealPositionWithoutAMarginUsesTheBareEdges() {
        compare(TabStripGeometry.revealPosition(0, 60, 0, viewport, 0), null)
        compare(TabStripGeometry.revealPosition(viewport - 60, 60, 0, viewport, 0), null)
        compare(TabStripGeometry.revealPosition(viewport - 59, 60, 0, viewport, 0), 1)
    }

    function test_revealPositionRefusesUnusableGeometry() {
        compare(TabStripGeometry.revealPosition("abc", 60, 0, viewport, margin), null)
        compare(TabStripGeometry.revealPosition(100, undefined, 0, viewport, margin), null)
        compare(TabStripGeometry.revealPosition(100, 60, 0, NaN, margin), null)
    }
}
