import QtQuick
import QtTest
import "../contents/ui/PopupHiddenRows.js" as PopupHiddenRows

// Hidden popup rows are a stored display choice: the stored text is untrusted,
// rows are matched by lane or CLI window ID, and filtering never drops a row
// that cannot be hidden.
TestCase {
    name: "PopupHiddenRows"

    function test_rowKeysCoverLanesAndIdentifiedExtraWindows() {
        compare(PopupHiddenRows.rowKey({lane: "primary"}), "primary");
        compare(PopupHiddenRows.rowKey({lane: "tertiary"}), "tertiary");
        compare(PopupHiddenRows.rowKey({lane: "extra", windowId: "opus-weekly"}), "extra:opus-weekly");
        compare(PopupHiddenRows.rowKey({lane: "extra", windowId: ""}), "");
        compare(PopupHiddenRows.rowKey({lane: "extra", windowId: "bad id"}), "");
        compare(PopupHiddenRows.rowKey({lane: "extra", windowId: "x".repeat(65)}), "");
        compare(PopupHiddenRows.rowKey({lane: "monthlyCredits"}), "");
        compare(PopupHiddenRows.rowKey(null), "");
        compare(PopupHiddenRows.rowKey([]), "");
    }

    function test_parseKeepsOnlyWellFormedUniqueEntries_data() {
        return [
            {tag: "empty", raw: "", count: 0},
            {tag: "not-json", raw: "{", count: 0},
            {tag: "object", raw: "{\"provider\":\"codex\",\"row\":\"primary\"}", count: 0},
            {tag: "oversized", raw: "[" + " ".repeat(16400) + "]", count: 0},
            {tag: "non-string", raw: 42, count: 0}
        ];
    }

    function test_parseKeepsOnlyWellFormedUniqueEntries(data) {
        compare(PopupHiddenRows.parse(data.raw).length, data.count);
    }

    function test_parseValidatesEachEntry() {
        var entries = PopupHiddenRows.parse(JSON.stringify([
            {provider: "codex", row: "secondary"},
            {provider: "codex", row: "secondary"},
            {provider: "claude", row: "extra:opus"},
            {provider: "claude", row: "extra:"},
            {provider: "claude", row: "extra:has space"},
            {provider: "claude", row: "quaternary"},
            {provider: "__proto__", row: "primary"},
            {provider: "", row: "primary"},
            {provider: 5, row: "primary"},
            {row: "primary"},
            null, "codex", ["codex", "primary"]
        ]));
        compare(entries, [
            {provider: "codex", row: "secondary"},
            {provider: "claude", row: "extra:opus"}
        ]);
    }

    function test_parseStopsAtTheEntryLimit() {
        var stored = [];
        for (var i = 0; i < PopupHiddenRows.maximumEntries + 5; i++)
            stored.push({provider: "provider" + i, row: "primary"});
        compare(PopupHiddenRows.parse(JSON.stringify(stored)).length, PopupHiddenRows.maximumEntries);
    }

    function test_hideRestoreAndSerializeRoundTrip() {
        var entries = PopupHiddenRows.hidden([], "codex", "secondary");
        entries = PopupHiddenRows.hidden(entries, "codex", "secondary");
        entries = PopupHiddenRows.hidden(entries, "claude", "extra:opus");
        entries = PopupHiddenRows.hidden(entries, "claude", "not-a-row");
        entries = PopupHiddenRows.hidden(entries, "", "primary");
        compare(entries.length, 2);
        var restoredEntries = PopupHiddenRows.parse(PopupHiddenRows.serialize(entries));
        compare(restoredEntries, entries);
        verify(PopupHiddenRows.isHidden(restoredEntries, "codex", "secondary"));
        verify(!PopupHiddenRows.isHidden(restoredEntries, "codex", "primary"));
        entries = PopupHiddenRows.restored(entries, "codex", "secondary");
        compare(entries, [{provider: "claude", row: "extra:opus"}]);
        compare(PopupHiddenRows.serialize(PopupHiddenRows.restored(entries, "claude", "extra:opus")), "");
    }

    // A full list refuses a new entry rather than silently forgetting an
    // older choice the user made.
    function test_fullListRefusesNewEntries() {
        var entries = [];
        for (var i = 0; i < PopupHiddenRows.maximumEntries; i++)
            entries = PopupHiddenRows.hidden(entries, "provider" + i, "primary");
        var next = PopupHiddenRows.hidden(entries, "codex", "primary");
        compare(next.length, PopupHiddenRows.maximumEntries);
        verify(!PopupHiddenRows.isHidden(next, "codex", "primary"));
        verify(PopupHiddenRows.isHidden(next, "provider0", "primary"));
    }

    function test_visibleRowsFilterOnlyTheNamedProvider() {
        var rows = [
            {lane: "primary", label: "Session"},
            {lane: "secondary", label: "Weekly"},
            {lane: "extra", windowId: "opus", label: "Opus"},
            {lane: "extra", windowId: "", label: "Unidentified"},
            {lane: "monthlyCredits", label: "Credits"}
        ];
        var entries = [
            {provider: "codex", row: "secondary"},
            {provider: "codex", row: "extra:opus"},
            {provider: "claude", row: "primary"}
        ];
        compare(PopupHiddenRows.visibleRows(rows, entries, "codex").map(function(row) { return row.label; }),
            ["Session", "Unidentified", "Credits"]);
        compare(PopupHiddenRows.visibleRows(rows, entries, "gemini").length, rows.length);
        compare(PopupHiddenRows.visibleRows(null, entries, "codex"), []);
        compare(PopupHiddenRows.visibleRows(rows, null, "codex").length, rows.length);
    }
}
