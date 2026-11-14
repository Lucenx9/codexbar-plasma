import QtQuick
import QtTest
import "../contents/ui/PanelRingGeometry.js" as Rings

TestCase {
    name: "PanelRingGeometry"

    function test_nestedRingsLeaveSpaceForTheLogo() {
        for (var diameter of [16, 22, 30, 46, 48]) {
            for (var count of [0, 1, 2]) {
                var geometry = Rings.layout(diameter, count);
                compare(geometry.radii.length, count);
                verify(geometry.logoSize > 0 && geometry.logoSize < diameter);
                if (count === 0) continue;
                verify(geometry.radii[0] + geometry.strokeWidth / 2 < diameter / 2);
                verify(geometry.logoSize / 2 < geometry.radii[count - 1] - geometry.strokeWidth / 2);
                if (count === 2)
                    verify(geometry.radii[0] - geometry.radii[1] > geometry.strokeWidth);
            }
        }
    }

    function test_invalidInputsStayBounded() {
        for (var diameter of [undefined, null, "32", NaN, Infinity, -5, 100000]) {
            var geometry = Rings.layout(diameter, 999);
            verify(geometry.diameter >= 16 && geometry.diameter <= 48);
            compare(geometry.radii.length, 0);
        }
        for (var percent of [undefined, null, "50", NaN, Infinity, -1]) {
            compare(Rings.arc(percent, 14, 2).sweepAngle, 0);
        }
        compare(Rings.arc(999, 14, 2).sweepAngle, 360);
    }

    function test_zeroTinyAndFullRemainDistinct() {
        var radius = 14;
        var stroke = 2;
        compare(Rings.arc(0, radius, stroke).sweepAngle, 0);
        var tiny = Rings.arc(0.001, radius, stroke);
        verify(tiny.sweepAngle > 0 && tiny.sweepAngle < 5);
        verify(!tiny.rounded);
        verify(Rings.arc(50, radius, stroke).rounded);
        var full = Rings.arc(100, radius, stroke);
        compare(full.sweepAngle, 360);
        verify(!full.rounded);
        var previous = 0;
        for (var percent = 0; percent <= 100; percent++) {
            var arc = Rings.arc(percent, radius, stroke);
            var paintedLength = arc.sweepAngle / 360 * 2 * Math.PI * radius + (arc.rounded ? stroke : 0);
            verify(paintedLength >= previous);
            previous = paintedLength;
        }
    }
}
