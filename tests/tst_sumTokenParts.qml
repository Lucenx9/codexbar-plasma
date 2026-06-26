import QtQuick 2.0
import QtTest 1.0
import "../contents/ui/TokenUtils.js" as TokenUtils

TestCase {
    name: "SumTokenPartsTests"

    function test_all_positive() {
        compare(TokenUtils.sumTokenParts(10, 20, 30, 40), 100)
    }

    function test_some_null_undefined() {
        compare(TokenUtils.sumTokenParts(10, undefined, null, 40), 50)
    }

    function test_all_zero() {
        verify(isNaN(TokenUtils.sumTokenParts(0, 0, 0, 0)))
    }

    function test_negative_numbers_ignored() {
        compare(TokenUtils.sumTokenParts(10, -5, 20, -10), 30)
    }

    function test_nan_ignored() {
        compare(TokenUtils.sumTokenParts(10, NaN, 20, 0), 30)
    }

    function test_all_invalid() {
        verify(isNaN(TokenUtils.sumTokenParts(0, -1, NaN, undefined)))
    }

    function test_strings_parsed_as_numbers() {
        compare(TokenUtils.sumTokenParts("10", "20", "30", "40"), 100)
    }
}
