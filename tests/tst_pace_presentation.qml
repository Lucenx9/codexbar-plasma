import QtQuick
import QtTest
import "../contents/ui/PacePresentation.js" as PacePresentation

TestCase {
    name: "PacePresentation"

    function test_structuredFieldsReplaceEnglishSummary() {
        compare(PacePresentation.summaryParts({
            stage: "ahead",
            deltaPercent: 12,
            expectedUsedPercent: 30,
            willLastToReset: false,
            etaSeconds: 3600,
            summary: "12% in deficit | Expected 30% used | Runs out in 1h"
        }), [
            {
                kind: "deficit",
                percent: 12
            },
            {
                kind: "expected",
                percent: 30
            },
            {
                kind: "runsOut",
                seconds: 3600
            }
        ]);
    }

    function test_stageDirectionComesFromTheCli() {
        for (var stage of ["slightlyAhead", "ahead", "farAhead"])
            compare(PacePresentation.summaryParts({
                stage: stage,
                deltaPercent: -7
            }), [
                {
                    kind: "deficit",
                    percent: 7
                }
            ]);
        for (var stage of ["slightlyBehind", "behind", "farBehind"])
            compare(PacePresentation.summaryParts({
                stage: stage,
                deltaPercent: 7
            }), [
                {
                    kind: "reserve",
                    percent: 7
                }
            ]);
        compare(PacePresentation.summaryParts({
            stage: "onTrack",
            willLastToReset: true
        }), [
            {
                kind: "onTrack"
            },
            {
                kind: "lasts"
            }
        ]);
    }

    function test_unknownOrMalformedFieldsPreserveHealthyParts() {
        compare(PacePresentation.summaryParts({
            stage: "future",
            expectedUsedPercent: 0,
            willLastToReset: "false"
        }), [
            {
                kind: "expected",
                percent: 0
            }
        ]);
        compare(PacePresentation.summaryParts({
            stage: "ahead",
            deltaPercent: null,
            expectedUsedPercent: false,
            willLastToReset: false,
            etaSeconds: null
        }), []);
        compare(PacePresentation.summaryParts({
            willLastToReset: false,
            etaSeconds: 0
        }), [
            {
                kind: "runsOut",
                seconds: 0
            }
        ]);
        for (var value of [null, [], true, "English", 7])
            compare(PacePresentation.summaryParts(value), []);
        for (var invalid of [null, true, false, "", " ", "NaN", [],
            {},
            NaN, Infinity, -Infinity])
            compare(PacePresentation.summaryParts({
                expectedUsedPercent: invalid,
                deltaPercent: invalid,
                stage: "ahead",
                willLastToReset: false,
                etaSeconds: invalid
            }), []);
        compare(PacePresentation.summaryParts({
            willLastToReset: false,
            etaSeconds: -1
        }), []);
    }

    function test_boundsNumbersAndIgnoresInheritedFields() {
        compare(PacePresentation.summaryParts({
            stage: "behind",
            deltaPercent: -999,
            expectedUsedPercent: "999"
        }), [
            {
                kind: "reserve",
                percent: 100
            },
            {
                kind: "expected",
                percent: 100
            }
        ]);
        compare(PacePresentation.summaryParts({
            expectedUsedPercent: -1
        }), [
            {
                kind: "expected",
                percent: 0
            }
        ]);
        compare(PacePresentation.summaryParts(Object.create({
            stage: "onTrack",
            expectedUsedPercent: 50,
            willLastToReset: true,
            summary: "inherited"
        })), []);
        var parts = PacePresentation.summaryParts({
            willLastToReset: false,
            etaSeconds: 1e100
        });
        verify(parts[0].seconds > 0 && parts[0].seconds <= 366 * 86400);
    }

    function test_legacySummaryRemainsBoundedAndRedacted() {
        compare(PacePresentation.summaryParts({
            summary: "Legacy forecast"
        }), [
            {
                kind: "fallback",
                text: "Legacy forecast"
            }
        ]);
        compare(PacePresentation.summaryParts({
            summary: {
                text: "wrong shape"
            }
        }), []);
        var parts = PacePresentation.summaryParts({
            summary: "x".repeat(2000)
        });
        verify(parts[0].text.length <= 500);
        parts = PacePresentation.summaryParts({
            summary: "Authorization: Bearer synthetic-test-value"
        });
        verify(parts[0].text.indexOf("synthetic-test-value") === -1);
    }
}
