import QtQuick
import QtTest
import "../contents/ui/SessionResponse.js" as SessionResponse
import "../contents/ui/SafeText.js" as SafeText

TestCase {
    name: "SessionResponse"

    function test_confirmedEmptySnapshot_data() {
        return [
            {
                tag: "array",
                text: "[]"
            },
            {
                tag: "envelope",
                text: '{"sessions":[]}'
            }
        ];
    }

    function test_confirmedEmptySnapshot(data) {
        var result = SessionResponse.response(data.text, "ignored diagnostic");
        compare(result.outcome, "success");
        compare(result.sessions, []);
        compare(result.message, "");
    }

    function test_failureHasNoReplacementSnapshot_data() {
        return [
            {
                tag: "missing",
                text: undefined,
                outcome: "empty"
            },
            {
                tag: "empty",
                text: "  ",
                outcome: "empty"
            },
            {
                tag: "broken",
                text: "{",
                outcome: "invalidJson"
            },
            {
                tag: "null",
                text: "null",
                outcome: "unsupported"
            },
            {
                tag: "object",
                text: "{}",
                outcome: "unsupported"
            },
            {
                tag: "wrong-sessions-type",
                text: '{"sessions":{}}',
                outcome: "unsupported"
            },
            {
                tag: "too-large",
                text: " ".repeat(SafeText.maximumCliJsonLength + 1),
                outcome: "tooLarge"
            }
        ];
    }

    function test_failureHasNoReplacementSnapshot(data) {
        var result = SessionResponse.response(data.text, "scan failed");
        compare(result.outcome, data.outcome);
        verify(result.sessions === undefined);
        verify(result.message.length <= SafeText.maximumCliMessageLength);
    }

    function test_diagnosticsAreBoundedAndRedacted() {
        var result = SessionResponse.response("", "Authorization: Bearer synthetic-session-secret\n" + "x".repeat(800));
        compare(result.outcome, "empty");
        verify(result.message.length > 0);
        verify(result.message.length <= SafeText.maximumCliMessageLength);
        verify(result.message.indexOf("synthetic-session-secret") === -1);
        var malformed = SessionResponse.response('Bearer synthetic-session-secret {', "");
        compare(malformed.outcome, "invalidJson");
        verify(malformed.message.indexOf("synthetic-session-secret") === -1);
    }

    function test_snapshotUsesTheBoundedDisplayContract() {
        var items = [];
        for (var i = 0; i < 150; i++) {
            items.push({
                provider: "codex",
                projectName: "Project " + i,
                state: "active",
                source: "cli",
                cwd: "/private/work",
                transcriptPath: "/private/transcript",
                token: "synthetic-secret"
            });
        }
        var result = SessionResponse.response(JSON.stringify({
            sessions: items
        }), "");
        compare(result.outcome, "success");
        compare(result.sessions.length, 128);
        var serialized = JSON.stringify(result.sessions);
        verify(serialized.indexOf("/private/") === -1);
        verify(serialized.indexOf("synthetic-secret") === -1);
        compare(result.sessions[0].provider, "codex");
    }
}
