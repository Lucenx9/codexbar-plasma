import QtQuick
import QtTest
import "../contents/ui/PanelTextFit.js" as PanelTextFit

TestCase {
    name: "PanelTextFit"

    function segments(ids) {
        var texts = {name: "Codex", usage: "43% used", credits: "125cr"}
        return ids.map(function(id) { return {id: id, text: texts[id]} })
    }

    function test_fullCompositionComesFirstInSettingsOrder() {
        compare(PanelTextFit.segmentTexts(segments(["name", "usage", "credits"]))[0],
            "Codex 43% used 125cr")
        compare(PanelTextFit.segmentTexts(segments(["credits", "name"]))[0], "125cr Codex")
    }

    // The provider icon beside the label already names the provider and the
    // usage figure is the reading the panel exists for, so the name is
    // surrendered first and the usage figure last.
    function test_segmentsAreSurrenderedByPriority() {
        compare(PanelTextFit.segmentTexts(segments(["name", "usage", "credits"])),
            ["Codex 43% used 125cr", "43% used 125cr", "43% used"])
        compare(PanelTextFit.segmentTexts(segments(["name", "credits"])),
            ["Codex 125cr", "125cr"])
        compare(PanelTextFit.segmentTexts(segments(["name", "usage"])),
            ["Codex 43% used", "43% used"])
        compare(PanelTextFit.segmentTexts(segments(["usage", "credits"])),
            ["43% used 125cr", "43% used"])
    }

    // A single enabled segment has nothing to surrender: the caller elides it
    // rather than letting an enabled segment vanish without a trace.
    function test_theLastSegmentIsNeverSurrendered() {
        compare(PanelTextFit.segmentTexts(segments(["name"])), ["Codex"])
        compare(PanelTextFit.segmentTexts(segments(["credits"])), ["125cr"])
        var compositions = PanelTextFit.compositions(segments(["name", "usage", "credits"]))
        compare(compositions[compositions.length - 1].length, 1)
    }

    function test_emptyAndMalformedInputProduceNoComposition() {
        compare(PanelTextFit.compositions([]).length, 0)
        compare(PanelTextFit.compositions(null).length, 0)
        compare(PanelTextFit.compositions("name").length, 0)
        compare(PanelTextFit.compositions([null, 42, [], {}]).length, 0)
        compare(PanelTextFit.compositions([{id: "unknown", text: "Codex"}]).length, 0)
        compare(PanelTextFit.compositions([{id: "name", text: "   "}]).length, 0)
        compare(PanelTextFit.compositions([{id: "name"}]).length, 0)
    }

    function test_duplicateAndOversizedSegmentsAreBounded() {
        compare(PanelTextFit.segmentTexts([
            {id: "name", text: "Codex"}, {id: "name", text: "Claude"},
            {id: "usage", text: "43% used"}]), ["Codex 43% used", "43% used"])
        var oversized = PanelTextFit.compositions([{id: "name", text: "x".repeat(5000)}])
        compare(oversized.length, 1)
        verify(oversized[0][0].text.length <= PanelTextFit.maximumSegmentLength)
        // A long list cannot grow the composition set beyond one drop per segment.
        var repeated = []
        for (var i = 0; i < 500; i++) {
            repeated.push({id: "name", text: "Codex"})
        }
        compare(PanelTextFit.compositions(repeated).length, 1)
    }

    function test_widestFittingCompositionWins() {
        compare(PanelTextFit.fittedIndex([200, 120, 60], 300), 0)
        compare(PanelTextFit.fittedIndex([200, 120, 60], 200), 0)
        compare(PanelTextFit.fittedIndex([200, 120, 60], 199), 1)
        compare(PanelTextFit.fittedIndex([200, 120, 60], 60), 2)
    }

    // Below the narrowest composition the caller still renders something, so it
    // receives the last index rather than "nothing fits".
    function test_theNarrowestCompositionIsTheLastResort() {
        compare(PanelTextFit.fittedIndex([200, 120, 60], 59), 2)
        compare(PanelTextFit.fittedIndex([200, 120, 60], 0), 2)
        compare(PanelTextFit.fittedIndex([200], -50), 0)
        compare(PanelTextFit.fittedIndex([200], NaN), 0)
        compare(PanelTextFit.fittedIndex([], 500), -1)
        compare(PanelTextFit.fittedIndex(null, 500), -1)
    }

    function test_unusableWidthsAreSkippedRatherThanChosen() {
        compare(PanelTextFit.fittedIndex([NaN, 120, 60], 300), 1)
        compare(PanelTextFit.fittedIndex(["120", 60], 300), 1)
        compare(PanelTextFit.fittedIndex([-5, 60], 300), 1)
        compare(PanelTextFit.fittedIndex([Infinity, 60], 300), 1)
    }

    function test_fullTextIsTheWholeLabel() {
        compare(PanelTextFit.fullText(segments(["name", "usage", "credits"])),
            "Codex 43% used 125cr")
        compare(PanelTextFit.fullText([]), "")
        compare(PanelTextFit.fullText(null), "")
    }

    function test_textsIgnoresMalformedCompositionLists() {
        compare(PanelTextFit.texts(null).length, 0)
        compare(PanelTextFit.texts([[], null]), ["", ""])
    }
}
