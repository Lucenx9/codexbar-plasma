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
        var result = SessionResponse.response(data.text, "ignored diagnostic", 0);
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
        var result = SessionResponse.response(data.text, "scan failed", 0);
        compare(result.outcome, data.outcome);
        verify(result.sessions === undefined);
        verify(result.message.length <= SafeText.maximumCliMessageLength);
    }

    function test_unreadableRecordsAreNotAnEmptyScan_data() {
        return [
            {tag: "null-record", payload: [null]},
            {tag: "empty-record", payload: [{}]},
            {tag: "envelope", payload: {sessions: [null, {}, false, "session"]}},
            {tag: "unusable-identity", payload: [{provider: {}, projectName: [], sessionName: null}]}
        ];
    }

    function test_unreadableRecordsAreNotAnEmptyScan(data) {
        var result = SessionResponse.response(JSON.stringify(data.payload), "", 0);
        compare(result.outcome, "unsupported");
        verify(result.sessions === undefined);
    }

    function test_unreadableRecordDoesNotDiscardHealthySession_data() {
        return [{tag: "array", wrapped: false}, {tag: "envelope", wrapped: true}];
    }

    function test_unreadableRecordDoesNotDiscardHealthySession(data) {
        var items = [null, {}, {provider: "codex", projectName: "Synthetic project"}, false];
        var payload = data.wrapped ? {sessions: items} : items;
        var result = SessionResponse.response(JSON.stringify(payload), "", 0);
        compare(result.outcome, "success");
        compare(result.sessions.length, 1);
        compare(result.sessions[0].projectName, "Synthetic project");
    }

    function test_diagnosticsAreBoundedAndRedacted() {
        var result = SessionResponse.response("", "Authorization: Bearer synthetic-session-secret\n" + "x".repeat(800), 0);
        compare(result.outcome, "empty");
        verify(result.message.length > 0);
        verify(result.message.length <= SafeText.maximumCliMessageLength);
        verify(result.message.indexOf("synthetic-session-secret") === -1);
        var malformed = SessionResponse.response('Bearer synthetic-session-secret {', "", 0);
        compare(malformed.outcome, "invalidJson");
        verify(malformed.message.indexOf("synthetic-session-secret") === -1);
    }

    function test_invalidActivityFallsBackToStart_data() {
        return [
            {tag: "impossible-day", value: "2026-02-30T12:00:00Z"},
            {tag: "non-leap-day", value: "2026-02-29T12:00:00Z"},
            {tag: "overflowing-hour", value: "2026-03-01T24:00:00Z"},
            {tag: "missing-zone", value: "2026-03-01T12:00:00"},
            {tag: "date-only", value: "2026-03-01"},
            {tag: "invalid-offset", value: "2026-03-01T12:00:00+14:30"},
            {tag: "control-character", value: "2026-03-01T12:00:00\u200bZ"},
            {tag: "trailing-space", value: "2026-03-01T12:00:00Z "},
            {tag: "empty", value: ""},
            {tag: "null", value: null},
            {tag: "wrong-type", value: ["2026-03-01T12:00:00Z"]}
        ];
    }

    function test_invalidActivityFallsBackToStart(data) {
        var result = SessionResponse.response(JSON.stringify([{
            provider: "codex", projectName: "Synthetic project",
            lastActivityAt: data.value,
            startedAt: "2026-02-27T12:00:00Z"
        }]), "", 0);
        compare(result.outcome, "success");
        compare(result.sessions[0].activityAt, "2026-02-27T12:00:00Z");
        compare(result.sessions[0].activityMs, Date.UTC(2026, 1, 27, 12));
    }

    function test_invalidStartPreservesUndatedSession_data() {
        return test_invalidActivityFallsBackToStart_data();
    }

    function test_invalidStartPreservesUndatedSession(data) {
        var result = SessionResponse.response(JSON.stringify({sessions: [{
            provider: "codex", projectName: "Synthetic project", startedAt: data.value
        }]}), "", 0);
        compare(result.outcome, "success");
        compare(result.sessions.length, 1);
        compare(result.sessions[0].projectName, "Synthetic project");
        compare(result.sessions[0].activityAt, "");
        compare(result.sessions[0].activityMs, 0);
    }

    function test_validActivity_data() {
        return [
            {tag: "utc", value: "2024-02-29T12:00:00Z", ms: Date.UTC(2024, 1, 29, 12)},
            {tag: "fractional", value: "2024-02-29T12:00:00.123Z", ms: Date.UTC(2024, 1, 29, 12, 0, 0, 123)},
            {tag: "positive-offset", value: "2024-02-29T14:00:00+02:00", ms: Date.UTC(2024, 1, 29, 12)},
            {tag: "negative-offset", value: "2024-02-29T07:00:00-05:00", ms: Date.UTC(2024, 1, 29, 12)}
        ];
    }

    function test_validActivity(data) {
        for (var field of ["lastActivityAt", "startedAt"]) {
            var item = {provider: "codex", projectName: "Synthetic project"};
            item[field] = data.value;
            var result = SessionResponse.response(JSON.stringify([item]), "", 0);
            compare(result.outcome, "success");
            compare(result.sessions[0].activityAt, data.value);
            compare(result.sessions[0].activityMs, data.ms);
        }
    }

    function test_invalidActivityDoesNotReorderSessions() {
        var result = SessionResponse.response(JSON.stringify([
            {provider: "codex", projectName: "Fallback", lastActivityAt: "2026-02-30T12:00:00Z", startedAt: "2026-02-27T12:00:00Z"},
            {provider: "codex", projectName: "Undated", startedAt: "2026-02-30T12:00:00Z"},
            {provider: "codex", projectName: "Recent", lastActivityAt: "2026-03-01T12:00:00Z"}
        ]), "", 0);
        compare(result.outcome, "success");
        compare(result.sessions.map(function(item) { return item.projectName; }), ["Recent", "Fallback", "Undated"]);
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
        }), "", 0);
        compare(result.outcome, "success");
        compare(result.sessions.length, 128);
        var serialized = JSON.stringify(result.sessions);
        verify(serialized.indexOf("/private/") === -1);
        verify(serialized.indexOf("synthetic-secret") === -1);
        compare(result.sessions[0].provider, "codex");
    }
}
