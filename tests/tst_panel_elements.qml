import QtQuick
import QtTest
import "../contents/ui/PanelElements.js" as PanelElements

TestCase {
    name: "PanelElements"

    function test_defaultOrderFillsEmptyConfiguration() {
        compare(PanelElements.serializedOrder(""), "identity,status,text,meters")
    }

    function test_normalizationDropsUnknownAndDuplicateTokens() {
        compare(
            PanelElements.serializedOrder("text,unknown,text,identity"),
            "text,identity,status,meters")
    }

    function test_moveKeepsEveryKnownElementExactlyOnce() {
        compare(
            PanelElements.movedOrder("identity,status,text,meters", 2, -1).join(","),
            "identity,text,status,meters")
        compare(
            PanelElements.movedOrder("identity,status,text,meters", 0, -1).join(","),
            "identity,status,text,meters")
    }

    function test_largeInputIsBoundedAndFallsBackSafely() {
        var oversized = "unknown,".repeat(1000) + "text"
        compare(PanelElements.serializedOrder(oversized), "identity,status,text,meters")
    }
}
