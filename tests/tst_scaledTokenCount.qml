import QtQuick 2.0
import QtTest 1.0
import "../contents/ui/js/utils.js" as Utils

TestCase {
    name: "ScaledTokenCountTest"

    function test_scaledTokenCount() {
        // >= 10: rounded to whole number
        compare(Utils.scaledTokenCount(10.0), "10", "10.0 should be 10")
        compare(Utils.scaledTokenCount(10.5), "11", "10.5 should round to 11")
        compare(Utils.scaledTokenCount(15.2), "15", "15.2 should round to 15")
        compare(Utils.scaledTokenCount(99.9), "100", "99.9 should round to 100")

        // < 10, no decimal part: 1 decimal but ".0" removed
        compare(Utils.scaledTokenCount(5.0), "5", "5.0 should be 5")
        compare(Utils.scaledTokenCount(9.0), "9", "9.0 should be 9")
        compare(Utils.scaledTokenCount(0.0), "0", "0.0 should be 0")

        // < 10, with decimal part: 1 decimal
        compare(Utils.scaledTokenCount(5.5), "5.5", "5.5 should be 5.5")
        compare(Utils.scaledTokenCount(9.9), "9.9", "9.9 should be 9.9")
        compare(Utils.scaledTokenCount(0.5), "0.5", "0.5 should be 0.5")
        compare(Utils.scaledTokenCount(4.44), "4.4", "4.44 should round to 4.4")
        compare(Utils.scaledTokenCount(4.45), "4.5", "4.45 should round to 4.5")
        compare(Utils.scaledTokenCount(4.99), "5", "4.99 should round to 5")
    }
}
