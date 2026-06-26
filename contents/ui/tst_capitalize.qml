import QtQuick 2.15
import QtTest 1.15
import "utils.js" as Utils

TestCase {
    name: "CapitalizeTests"

    function test_capitalize_standard() {
        compare(Utils.capitalize("hello"), "Hello")
    }

    function test_capitalize_alreadyCapitalized() {
        compare(Utils.capitalize("Hello"), "Hello")
    }

    function test_capitalize_emptyString() {
        compare(Utils.capitalize(""), "")
    }

    function test_capitalize_null() {
        compare(Utils.capitalize(null), "")
    }

    function test_capitalize_undefined() {
        compare(Utils.capitalize(undefined), "")
    }

    function test_capitalize_singleCharacter() {
        compare(Utils.capitalize("h"), "H")
    }

    function test_capitalize_numbers() {
        compare(Utils.capitalize("123"), "123")
    }

    function test_capitalize_startingWithSpace() {
        compare(Utils.capitalize(" hello"), " hello")
    }
}
