import QtQuick
import QtTest
import "../contents/ui/NotificationCommand.js" as NotificationCommand

TestCase {
    name: "NotificationCommand"

    function test_invalidText_data() {
        return [
            {
                tag: "null-title",
                title: null,
                body: "body"
            },
            {
                tag: "missing-title",
                title: undefined,
                body: "body"
            },
            {
                tag: "number-title",
                title: 42,
                body: "body"
            },
            {
                tag: "object-title",
                title: {
                    toString: null
                },
                body: "body"
            },
            {
                tag: "array-title",
                title: ["title"],
                body: "body"
            },
            {
                tag: "null-body",
                title: "title",
                body: null
            },
            {
                tag: "object-body",
                title: "title",
                body: {
                    toString: null
                }
            },
            {
                tag: "array-body",
                title: "title",
                body: ["body"]
            }
        ];
    }

    function test_invalidText(data) {
        compare(NotificationCommand.command(data.title, data.body, "normal"), "");
    }

    function test_urgency_data() {
        return [
            {
                tag: "low",
                input: "low",
                expected: "low"
            },
            {
                tag: "normal",
                input: "normal",
                expected: "normal"
            },
            {
                tag: "critical",
                input: " critical ",
                expected: "critical"
            },
            {
                tag: "unknown",
                input: "urgent",
                expected: "normal"
            },
            {
                tag: "shell",
                input: "critical; touch /synthetic-marker",
                expected: "normal"
            },
            {
                tag: "null",
                input: null,
                expected: "normal"
            },
            {
                tag: "object",
                input: {
                    toString: null
                },
                expected: "normal"
            }
        ];
    }

    function test_urgency(data) {
        var command = NotificationCommand.command("title", "body", data.input);
        verify(command.indexOf("--urgency='" + data.expected + "' -- ") >= 0);
        verify(command.indexOf("/synthetic-marker") < 0);
    }

    function test_emptyTitleAndBody() {
        verify(NotificationCommand.command(" \n", " \t", "normal").endsWith(" -- 'CodexBar' ''; fi"));
    }
}
