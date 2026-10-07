import QtQuick
import QtTest
import "../contents/ui/components" as Components

TestCase {
    name: "ProviderNotificationText"
    Components.ProviderNotificationText { id: subject }
    function i18n(text) {
        for (var i = 1; i < arguments.length; i++) text = text.replace("%" + i, arguments[i])
        return text
    }
    function test_messages_data() {
        return [
            {tag: "status", kind: "status", severity: "major", title: "Codex status issue", body: "Service <unavailable>", urgency: "critical"},
            {tag: "status-unknown", kind: "status", severity: "unknown", title: "Codex status issue", body: "Service <unavailable>", urgency: "low"},
            {tag: "quota-critical", kind: "quota", severity: "major", title: "Codex quota critical", body: "Weekly is 96% used. Resets 2h", urgency: "critical"},
            {tag: "quota-warning", kind: "quota", severity: "minor", title: "Codex quota warning", body: "Weekly is 96% used. Resets 2h", urgency: "normal"},
            {tag: "pace", kind: "pace", severity: "", title: "Codex pace warning", body: "Weekly may run out in 1 hour", urgency: "normal"},
            {tag: "reset", kind: "reset", severity: "", title: "Codex limit reset", body: "Weekly is back to 96% used", urgency: "low"}
        ]
    }
    function test_messages(data) {
        var intent = {kind: data.kind, severity: data.severity}
        var item = {title: "Codex", status: "Service <unavailable>"}
        var row = {label: "Weekly", usedPercent: 95.6}
        var before = JSON.stringify([intent, item, row])
        compare(subject.message(intent, item, row, "Resets 2h", "1 hour"), {
            title: data.title, body: data.body, urgency: data.urgency
        })
        compare(JSON.stringify([intent, item, row]), before)
    }
    function test_absentRowsAndUnknownIntents() {
        var item = {title: "Codex", status: "Incident"}
        var row = {label: "Session", usedPercent: 0}
        compare(subject.message(null, item, row, "", ""), null)
        compare(subject.message({kind: "status"}, null, row, "", ""), null)
        for (var kind of ["quota", "pace", "reset", "future"]) {
            compare(subject.message({kind: kind}, item, null, "", ""), null)
        }
        compare(subject.message({kind: "future"}, item, row, "", ""), null)
        compare(subject.message({kind: "status", severity: "minor"}, item, null, "", ""), {
            title: "Codex status issue", body: "Incident", urgency: "normal"
        })
    }
    function test_emptyResetAndZeroArePreserved() {
        var item = {title: "Future provider"}
        var row = {label: "Unknown lane", usedPercent: 0}
        compare(subject.message({kind: "quota", severity: "critical"}, item, row, "", ""), {
            title: "Future provider quota warning", body: "Unknown lane is 0% used", urgency: "critical"
        })
        compare(subject.message({kind: "reset"}, item, row, "", "").body, "Unknown lane is back to 0% used")
    }
    function test_urgency_data() {
        return [
            {tag: "critical", input: "critical", expected: "critical"},
            {tag: "major", input: "major", expected: "critical"},
            {tag: "minor", input: "minor", expected: "normal"},
            {tag: "unknown", input: "unknown", expected: "low"},
            {tag: "future", input: "future", expected: "normal"},
            {tag: "null", input: null, expected: "normal"},
            {tag: "empty", input: "", expected: "normal"}
        ]
    }
    function test_urgency(data) { compare(subject.urgency(data.input), data.expected) }
}
