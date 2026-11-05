import QtQuick
import QtTest
import "../contents/ui/UsageRowLayout.js" as UsageRowLayout

TestCase {
    name: "UsageRowLayout"

    function test_countdownDoesNotRepeatedlyMoveReset() {
        var inline = UsageRowLayout.nextInlineReset(false, true, 18, 18);
        verify(inline);
        for (var spare of [17, 1, 0, 2, 17]) {
            inline = UsageRowLayout.nextInlineReset(inline, true, spare, 18);
            verify(inline, "A fitting reset must stay inline inside the safety band");
        }
        inline = UsageRowLayout.nextInlineReset(inline, true, -1, 18);
        verify(!inline, "Overflow must restore the expanded layout");
        for (var room of [0, 1, 17]) {
            inline = UsageRowLayout.nextInlineReset(inline, true, room, 18);
            verify(!inline, "The reset needs the full safety band before returning");
        }
        verify(UsageRowLayout.nextInlineReset(inline, true, 18, 18));
    }

    function test_paceOrMissingResetImmediatelyRestoresMetadata() {
        verify(!UsageRowLayout.nextInlineReset(true, false, 1000, 18));
        verify(UsageRowLayout.nextInlineReset(false, true, 1000, 18));
    }

    function test_invalidGeometryFallsBack() {
        for (var value of [undefined, null, "100", true, {}, NaN, Infinity, -Infinity]) {
            verify(!UsageRowLayout.nextInlineReset(true, true, value, 18));
            verify(!UsageRowLayout.nextInlineReset(true, true, 100, value));
        }
        verify(!UsageRowLayout.nextInlineReset(true, true, 100, -1));
        verify(!UsageRowLayout.nextInlineReset(true, "true", 100, 18));
    }
}
