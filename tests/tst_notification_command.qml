import QtQuick
import QtTest
import "../contents/ui/NotificationCommand.js" as NotificationCommand
import "../contents/ui/Guards.js" as Guards

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

    function test_textBounds() {
        var title = "t".repeat(NotificationCommand.maximumTitleLength)
        var body = "b".repeat(NotificationCommand.maximumBodyLength)
        var expected = NotificationCommand.command(title, body, "normal")

        compare(NotificationCommand.command(title + "extra", body + "extra", "normal"), expected)
    }

    function test_actionlessSendsStayOnThePlainCommand() {
        var plain = NotificationCommand.command("title", "body", "normal")

        compare(NotificationCommand.command("title", "body", "normal", undefined), plain)
        compare(NotificationCommand.command("title", "body", "normal", ""), plain)
        compare(NotificationCommand.command("title", "body", "normal", "   "), plain)
        compare(NotificationCommand.command("title", "body", "normal", 42), plain)
        compare(NotificationCommand.command("title", "body", "normal", ["label"]), plain)
        compare(NotificationCommand.command("title", "body", "normal", { toString: null }), plain)
    }

    function test_actionSendRegistersTheDefaultActionAndFallsBack() {
        var command = NotificationCommand.command("title", "body", "normal", "Open release page")

        verify(command.indexOf("notify-send --help 2>&1 | grep -q -- '--action'") >= 0)
        verify(command.indexOf("--urgency='normal' --action=" + Guards.shellQuote("default=Open release page") + " -- 'title' 'body'") >= 0)
        // The pre-0.8 fallback keeps the exact plain send.
        verify(command.indexOf("else notify-send --app-name=CodexBar --icon=view-statistics --urgency='normal' -- 'title' 'body'; fi; fi") >= 0)
    }

    function test_actionLabelBounds() {
        var label = "l".repeat(NotificationCommand.maximumActionLabelLength)
        var command = NotificationCommand.command("title", "body", "low", label + "extra")

        verify(command.indexOf("--action=" + Guards.shellQuote("default=" + label) + " ") >= 0)
        verify(command.indexOf("extra") < 0)
    }

    // The dispatcher appends this command after a nonce assignment, so it must
    // start detached and never run notify-send unguarded.
    function test_commandStartsDetachedAndGuardsNotifySend() {
        var plain = NotificationCommand.command("title", "body", "normal")
        var withAction = NotificationCommand.command("title", "body", "normal", "Open")

        verify(plain.indexOf(":; if command -v notify-send") === 0)
        verify(withAction.indexOf(":; if command -v notify-send") === 0)
    }

    function test_actionLabelCannotInjectShellSyntax() {
        var marker = "/synthetic-marker"
        var command = NotificationCommand.command("title", "body", "normal", "' ; touch " + marker + "; #")

        verify(command.indexOf("--action=" + Guards.shellQuote("default=' ; touch " + marker + "; #") + " ") >= 0)
        // The marker stays inside the quoted action label: exactly one
        // occurrence, never as a standalone command.
        compare(command.split(marker).length, 2)
    }
}
