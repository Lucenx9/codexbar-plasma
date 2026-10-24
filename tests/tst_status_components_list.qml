import QtQuick
import QtTest
import "../contents/ui/components" as Components

TestCase {
    id: testCase

    name: "StatusComponentsList"
    when: windowShown
    width: 360
    height: 600

    function i18n(text) {
        return text
    }

    QtObject {
        id: fakeApplet

        property real secondaryTextOpacity: 0.7

        function statusBadgeColor(indicator) {
            return "red"
        }
    }

    Component {
        id: listComponent

        Components.StatusComponentsList {
            width: testCase.width
            applet: fakeApplet
            statusState: ({ loading: false, failed: false, rows: [
                { name: "G".repeat(120), indicator: "major", children: [
                    { name: "Chat Completions", indicator: "major", children: [] }] },
                { name: "Claude Code", indicator: "none", children: [] }] })
        }
    }

    function labelsWithText(item, text, found) {
        for (var i = 0; i < item.children.length; i++) {
            var child = item.children[i]
            if (child.text === text && child.truncated !== undefined)
                found.push(child)
            labelsWithText(child, text, found)
        }
        return found
    }

    // A long remote group name elides inside the popup width and keeps its
    // status text visible instead of widening the row.
    function test_longNamesElideWithinTheList() {
        var list = createTemporaryObject(listComponent, testCase)
        waitForRendering(list)
        var name = labelsWithText(list, "G".repeat(120), [])[0]
        verify(name.truncated)
        var status = labelsWithText(list, "Partial outage", [])[0]
        var right = status.mapToItem(list, status.width, 0).x
        verify(right <= list.width, "status ends at " + right + " in " + list.width)
    }

    // The arrow toggles its group from the keyboard, keeps focus, and names
    // the group for assistive technology.
    function test_groupTogglesFromKeyboard() {
        var list = createTemporaryObject(listComponent, testCase)
        var toggle = findChild(list, "statusGroupToggle")
        compare(toggle.Accessible.name, "G".repeat(120))
        compare(labelsWithText(list, "Chat Completions", []).length, 0)
        toggle.forceActiveFocus()
        keyClick(Qt.Key_Space)
        verify(toggle.expanded)
        verify(toggle.activeFocus)
        compare(labelsWithText(list, "Chat Completions", []).length, 1)
        keyClick(Qt.Key_Space)
        verify(!toggle.expanded)
        compare(labelsWithText(list, "Chat Completions", []).length, 0)
    }
}
