import QtQuick
import QtTest
import "../contents/ui/StatusComponents.js" as StatusComponents

TestCase {
    name: "StatusComponents"

    function record(components) {
        return JSON.stringify({status: "ok", components: components})
    }

    function test_feedsOnlyClaudeAndOpenAI() {
        compare(StatusComponents.feed("claude"), "claude")
        compare(StatusComponents.feed("claudeplatform"), "claude")
        compare(StatusComponents.feed("codex"), "openai")
        compare(StatusComponents.feed("openai"), "openai")
        compare(StatusComponents.feed("cursor"), "")
        compare(StatusComponents.feed("toString"), "")
        compare(StatusComponents.feed(undefined), "")
    }

    function test_commandQuotesScriptAndRejectsUnknownFeeds() {
        compare(StatusComponents.command("file:///opt/my%20widget/status-components.py", "openai"),
            "timeout --kill-after=2s 25s python3 '/opt/my widget/status-components.py' --provider openai")
        compare(StatusComponents.command("file:///s.py", "cursor"), "")
        compare(StatusComponents.command("file:///s.py", "openai; rm -rf ~"), "")
        compare(StatusComponents.command("https://example.test/s.py", "claude"), "")
        compare(StatusComponents.command("file:///bad%E0%A4%A", "claude"), "")
    }

    function test_acceptsGroupsAndFlattensNames() {
        var rows = StatusComponents.response(record([
            {name: "APIs", indicator: "major", children: [
                {name: " Chat\nCompletions ", indicator: "major", children: []},
                {name: "Batch", indicator: "none", children: [{name: "ignored", indicator: "none"}]}]},
            {name: "Claude Code", indicator: "maintenance", children: []}]))
        compare(rows.length, 2)
        compare(rows[0].children[0].name, "Chat Completions")
        compare(rows[0].children[1].children, [])
        compare(rows[1], {name: "Claude Code", indicator: "maintenance", children: []})
        compare(StatusComponents.response(record([{name: "x".repeat(500), indicator: "none", children: []}]))[0].name.length, 120)
    }

    function test_rejectsFailuresAndInvalidShapes() {
        var invalid = [
            undefined, "", "not json", "null", "[]", "x".repeat(262145),
            JSON.stringify({status: "error"}),
            record([]),
            record({}),
            record([{name: "APIs", indicator: "fine", children: []}]),
            record([{name: "   ", indicator: "none", children: []}]),
            record([{name: 7, indicator: "none", children: []}]),
            record([{name: "APIs", indicator: "none"}]),
            record([{name: "APIs", indicator: "none", children: [{name: "Bad", indicator: "toString"}]}]),
            record(new Array(65).fill({name: "A", indicator: "none", children: []}))
        ]
        for (var i = 0; i < invalid.length; i++)
            compare(StatusComponents.response(invalid[i]), null, "case " + i)
    }
}
