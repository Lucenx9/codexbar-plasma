import QtQuick
import QtTest
import "../contents/ui/ResetPresentation.js" as ResetPresentation

TestCase {
    name: "ResetPresentation"
    readonly property double nowMs: Date.UTC(2026, 8, 13, 12)

    function test_countdown_data() {
        return [
            {
                tag: "past",
                offset: -1,
                expected: {
                    kind: "now"
                }
            },
            {
                tag: "due",
                offset: 0,
                expected: {
                    kind: "now"
                }
            },
            {
                tag: "future-millisecond",
                offset: 1,
                expected: {
                    kind: "minutes",
                    minutes: 1
                }
            },
            {
                tag: "below-half-minute",
                offset: 29999,
                expected: {
                    kind: "minutes",
                    minutes: 1
                }
            },
            {
                tag: "half-minute",
                offset: 30000,
                expected: {
                    kind: "minutes",
                    minutes: 1
                }
            },
            {
                tag: "minute",
                offset: 60000,
                expected: {
                    kind: "minutes",
                    minutes: 1
                }
            },
            {
                tag: "below-two-minutes",
                offset: 89999,
                expected: {
                    kind: "minutes",
                    minutes: 1
                }
            },
            {
                tag: "round-two-minutes",
                offset: 90000,
                expected: {
                    kind: "minutes",
                    minutes: 2
                }
            },
            {
                tag: "below-hour",
                offset: 3569999,
                expected: {
                    kind: "minutes",
                    minutes: 59
                }
            },
            {
                tag: "round-hour",
                offset: 3570000,
                expected: {
                    kind: "hours",
                    hours: 1,
                    minutes: 0
                }
            },
            {
                tag: "hour",
                offset: 3600000,
                expected: {
                    kind: "hours",
                    hours: 1,
                    minutes: 0
                }
            },
            {
                tag: "hour-minute",
                offset: 3630000,
                expected: {
                    kind: "hours",
                    hours: 1,
                    minutes: 1
                }
            },
            {
                tag: "hours-minutes",
                offset: 9000000,
                expected: {
                    kind: "hours",
                    hours: 2,
                    minutes: 30
                }
            },
            {
                tag: "below-day",
                offset: 86369999,
                expected: {
                    kind: "hours",
                    hours: 23,
                    minutes: 59
                }
            },
            {
                tag: "round-day",
                offset: 86370000,
                expected: {
                    kind: "days",
                    days: 1,
                    hours: 0
                }
            },
            {
                tag: "day",
                offset: 86400000,
                expected: {
                    kind: "days",
                    days: 1,
                    hours: 0
                }
            },
            {
                tag: "day-truncates-minutes",
                offset: 89969999,
                expected: {
                    kind: "days",
                    days: 1,
                    hours: 0
                }
            },
            {
                tag: "day-round-hour",
                offset: 89970000,
                expected: {
                    kind: "days",
                    days: 1,
                    hours: 1
                }
            },
            {
                tag: "round-two-days",
                offset: 172770000,
                expected: {
                    kind: "days",
                    days: 2,
                    hours: 0
                }
            },
            {
                tag: "days-hours",
                offset: 176400000,
                expected: {
                    kind: "days",
                    days: 2,
                    hours: 1
                }
            }
        ];
    }

    function test_countdown(data) {
        var timestamp = nowMs + data.offset;
        var window = Object.freeze({
            resetsAt: timestamp,
            resetDescription: "stale description"
        });
        compare(ResetPresentation.parts(window, nowMs, false), data.expected);
        compare(ResetPresentation.parts({
            resetsAt: new Date(timestamp).toISOString()
        }, nowMs, false), data.expected);
        compare(window.resetsAt, timestamp);
        compare(ResetPresentation.parts(window, nowMs, true), {
            kind: "absolute",
            timestampMs: timestamp
        });
    }

    function test_calendarBoundaries_data() {
        return [
            {
                tag: "offset-equivalence",
                from: "2026-09-13T12:00:00Z",
                to: "2026-09-13T15:00:00+02:00",
                expected: {
                    kind: "hours",
                    hours: 1,
                    minutes: 0
                }
            },
            {
                tag: "spring-forward",
                from: "2026-03-08T01:30:00-08:00",
                to: "2026-03-08T03:30:00-07:00",
                expected: {
                    kind: "hours",
                    hours: 1,
                    minutes: 0
                }
            },
            {
                tag: "fall-back",
                from: "2026-11-01T01:30:00-07:00",
                to: "2026-11-01T01:30:00-08:00",
                expected: {
                    kind: "hours",
                    hours: 1,
                    minutes: 0
                }
            },
            {
                tag: "year-boundary",
                from: "2026-12-31T23:59:00Z",
                to: "2027-01-01T00:01:00Z",
                expected: {
                    kind: "minutes",
                    minutes: 2
                }
            },
            {
                tag: "leap-day",
                from: "2028-02-28T12:00:00Z",
                to: "2028-03-01T12:00:00Z",
                expected: {
                    kind: "days",
                    days: 2,
                    hours: 0
                }
            }
        ];
    }

    function test_calendarBoundaries(data) {
        compare(ResetPresentation.parts({
            resetsAt: data.to
        }, Date.parse(data.from), false), data.expected);
    }

    function test_missingAndMalformedMetadata() {
        for (var value of [null, undefined, false, 12, "text", [],
            {
                toString: null
            }
        ])
            compare(ResetPresentation.parts(value, nowMs, false), {
                kind: "text",
                text: ""
            });
        for (var timestamp of [null, undefined, false, true, 0, NaN, [],
            {},
            {
                toString: null
            }
        ]) {
            compare(ResetPresentation.parts({
                resetsAt: timestamp,
                resetDescription: "fallback"
            }, nowMs, false), {
                kind: "text",
                text: "fallback"
            });
        }
        for (var timestamp of ["not a date", Infinity, -Infinity, 8640000000000001]) {
            compare(ResetPresentation.parts({
                resetsAt: timestamp,
                resetDescription: "ignored"
            }, nowMs, false), {
                kind: "text",
                text: String(timestamp)
            });
        }
        for (var description of [null, undefined, [],
            {
                toString: null
            }
        ])
            compare(ResetPresentation.parts({
                resetDescription: description
            }, nowMs, false), {
                kind: "text",
                text: ""
            });
        compare(ResetPresentation.parts({
            resetsAt: -1
        }, nowMs, true), {
            kind: "absolute",
            timestampMs: -1
        });
    }

    function test_clockIsExplicit() {
        var window = {
            resetsAt: "2026-09-13T13:00:00Z",
            resetDescription: "ignored"
        };
        compare(ResetPresentation.parts(window, nowMs, false), {
            kind: "hours",
            hours: 1,
            minutes: 0
        });
        compare(ResetPresentation.parts(window, nowMs + 60000, false), {
            kind: "minutes",
            minutes: 59
        });
        compare(ResetPresentation.parts(window, nowMs + 3600000, false), {
            kind: "now"
        });
        for (var clock of [null, undefined, false, "0",
            {},
            [], NaN, Infinity, Number.MAX_VALUE]) {
            compare(ResetPresentation.parts(window, clock, false), {
                kind: "text",
                text: window.resetsAt
            });
            compare(ResetPresentation.parts(window, clock, true), {
                kind: "absolute",
                timestampMs: nowMs + 3600000
            });
        }
        compare(ResetPresentation.parts(window, nowMs, "true"), {
            kind: "hours",
            hours: 1,
            minutes: 0
        });
        compare(ResetPresentation.parts({
            resetsAt: 8640000000000000
        }, -8640000000000000, false), {
            kind: "days",
            days: 200000000,
            hours: 0
        });
    }

    // The suite runs with TZ=America/Los_Angeles; DST ends there on 2026-11-01.
    function test_absoluteShowsDateBeyondTheNextSixDays() {
        function local(month, day, hour, minute) {
            return new Date(2026, month - 1, day, hour, minute || 0).getTime();
        }
        var now = local(10, 25, 23, 30);
        verify(!ResetPresentation.absoluteShowsDate(local(10, 25, 23, 45), now));
        verify(!ResetPresentation.absoluteShowsDate(local(10, 26, 0, 5), now));
        // Six local days ahead across the DST change is still a unique weekday.
        verify(!ResetPresentation.absoluteShowsDate(local(10, 31, 23, 59), now));
        // A week later falls on today's weekday again; a month later repeats it.
        verify(ResetPresentation.absoluteShowsDate(local(11, 1, 0, 30), now));
        verify(ResetPresentation.absoluteShowsDate(local(11, 20, 9), now));
        // A reset already behind the clock would otherwise read as upcoming.
        verify(ResetPresentation.absoluteShowsDate(local(10, 24, 23, 30), now));
        // No usable clock or timestamp leaves the date as the only safe choice.
        for (var clock of [null, undefined, NaN, Infinity, "0", {}, [], Number.MAX_VALUE])
            verify(ResetPresentation.absoluteShowsDate(local(10, 26, 9), clock), String(clock));
        for (var timestamp of [null, undefined, NaN, "2026-10-26T09:00:00Z", {}, Number.MAX_VALUE])
            verify(ResetPresentation.absoluteShowsDate(timestamp, now), String(timestamp));
    }

    function test_labels_data() {
        return [
            {
                tag: "empty",
                input: "",
                text: "",
                isTime: false
            },
            {
                tag: "joined-duration",
                input: "Resets5h30m",
                text: "5h 30m",
                isTime: true
            },
            {
                tag: "compact-duration",
                input: "2h 30m",
                text: "2h 30m",
                isTime: true
            },
            {
                tag: "spaced-duration",
                input: " 2 h   30 m ",
                text: "2 h 30 m",
                isTime: true
            },
            {
                tag: "case-prefix",
                input: "RESETS 2h",
                text: "2h",
                isTime: true
            },
            {
                tag: "prefix-only",
                input: "Resets",
                text: "",
                isTime: false
            },
            {
                tag: "now",
                input: "now",
                text: "now",
                isTime: true
            },
            {
                tag: "future-prose",
                input: "Resets tomorrow at midnight",
                text: "tomorrow at midnight",
                isTime: true
            },
            {
                tag: "unknown-prose",
                input: "Resets after a successful request",
                text: "after a successful request",
                isTime: false
            },
            {
                tag: "literal",
                input: "Monthly window",
                text: "Monthly window",
                isTime: false
            },
            {
                tag: "localized-literal",
                input: "ora",
                text: "ora",
                isTime: false
            },
            {
                tag: "bare-count",
                input: "30",
                text: "30",
                isTime: false
            },
            {
                tag: "clock",
                input: "14:30",
                text: "14:30",
                isTime: true
            },
            {
                tag: "clock-zone",
                input: "2pm(UTC)",
                text: "2pm (UTC)",
                isTime: true
            },
            {
                tag: "weekday",
                input: "Mon 14:30",
                text: "Mon 14:30",
                isTime: true
            },
            {
                tag: "localized-weekday",
                input: "lunedì 14:30",
                text: "lunedì 14:30",
                isTime: true
            },
            {
                tag: "days",
                input: "2d 3h",
                text: "2d 3h",
                isTime: true
            },
            {
                tag: "word-units",
                input: "1 day 2 hours",
                text: "1 day 2 hours",
                isTime: true
            }
        ];
    }

    function test_labels(data) {
        compare(ResetPresentation.labelParts(data.input), {
            text: data.text,
            isTime: data.isTime
        });
    }

    function test_textBoundsAndRedaction() {
        for (var input of [null, undefined, false, 0,
            {},
            [],
            {
                toString: null
            }
        ])
            compare(ResetPresentation.labelParts(input), {
                text: "",
                isTime: false
            });
        for (var field of ["resetsAt", "resetDescription"]) {
            var window = {};
            window[field] = "x".repeat(10000);
            var parts = ResetPresentation.parts(window, nowMs, false);
            compare(parts.kind, "text");
            compare(parts.text.length, 500);
            window[field] = "Authorization: Bearer synthetic-reset-token";
            verify(ResetPresentation.parts(window, nowMs, false).text.indexOf("synthetic-reset-token") < 0);
        }
        var label = ResetPresentation.labelParts("a1".repeat(10000));
        verify(label.text.length <= 1000, "unit separation must have bounded output");
        verify(!label.isTime);
        verify(ResetPresentation.labelParts("Authorization: Bearer synthetic-reset-token").text.indexOf("synthetic-reset-token") < 0);
    }
}
