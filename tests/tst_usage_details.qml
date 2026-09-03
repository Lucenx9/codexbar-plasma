import QtQuick
import QtTest
import "../contents/ui/UsageDetails.js" as UsageDetails

TestCase {
    name: "UsageDetails"

    function test_normalizesOfficialRowAndBarChartContract() {
        var sections = UsageDetails.normalizeSections([
            {
                title: "API usage",
                rows: [
                    { label: "Requests", value: "1,240", secondaryValue: "+12%" }
                ],
                chart: {
                    kind: "bars",
                    title: "Daily requests",
                    unit: "requests",
                    points: [
                        { label: "Mon", value: 10 },
                        { label: "Tue", value: 25 }
                    ]
                }
            }
        ])

        compare(sections.length, 1)
        compare(sections[0].title, "API usage")
        compare(sections[0].rows.length, 1)
        compare(sections[0].rows[0].label, "Requests")
        compare(sections[0].rows[0].value, "1,240")
        compare(sections[0].rows[0].secondaryValue, "+12%")
        compare(sections[0].chart.kind, "bars")
        compare(sections[0].chart.points.length, 2)
        compare(sections[0].chart.points[1].value, 25)
    }

    function test_appliesOfficialContractBounds() {
        var rawRows = []
        for (var rowIndex = 0; rowIndex < 30; rowIndex++) {
            rawRows.push({ label: "Metric " + rowIndex, value: String(rowIndex) })
        }
        var rawPoints = []
        for (var pointIndex = 0; pointIndex < 130; pointIndex++) {
            rawPoints.push({ label: "Day " + pointIndex, value: pointIndex })
        }
        var rawSections = []
        for (var sectionIndex = 0; sectionIndex < 10; sectionIndex++) {
            rawSections.push({
                title: "x".repeat(140),
                rows: rawRows,
                chart: { kind: "line", points: rawPoints }
            })
        }

        var sections = UsageDetails.normalizeSections(rawSections)

        compare(sections.length, 8)
        compare(sections[0].title.length, 120)
        compare(sections[0].rows.length, 24)
        compare(sections[0].chart.points.length, 120)
    }

    function test_boundsWorkEvenWhenEntriesAreMalformed() {
        var rawSections = []
        for (var sectionIndex = 0; sectionIndex < 8; sectionIndex++) {
            rawSections.push(null)
        }
        rawSections.push({ title: "Outside inspection budget", rows: [] })
        compare(UsageDetails.normalizeSections(rawSections).length, 0)

        var rawRows = []
        for (var rowIndex = 0; rowIndex < 24; rowIndex++) {
            rawRows.push({ label: "", value: "ignored" })
        }
        rawRows.push({ label: "Outside inspection budget", value: "ignored" })
        var rowSections = UsageDetails.normalizeSections([{ title: "Rows", rows: rawRows }])
        compare(rowSections[0].rows.length, 0)

        var rawPoints = []
        for (var pointIndex = 0; pointIndex < 120; pointIndex++) {
            rawPoints.push({ label: "", value: 1 })
        }
        rawPoints.push({ label: "Outside inspection budget", value: 1 })
        var chartSections = UsageDetails.normalizeSections([
            { chart: { kind: "bars", title: "Empty chart", unit: "requests", points: rawPoints } }
        ])
        compare(chartSections.length, 1)
        compare(chartSections[0].chart.points.length, 0)
    }

    function test_preservesValidEmptyChart() {
        var sections = UsageDetails.normalizeSections([
            { chart: { kind: "line", title: "No activity", unit: "requests", points: [] } }
        ])

        compare(sections.length, 1)
        compare(sections[0].chart.kind, "line")
        compare(sections[0].chart.title, "No activity")
        compare(sections[0].chart.unit, "requests")
        compare(sections[0].chart.points.length, 0)
    }

    function test_preservesUnicodeStringsWithoutSplittingGraphemes() {
        var emoji = "😀"
        var validEmojiTitle = emoji.repeat(120)
        var validCombiningTitle = "e\u0301".repeat(120)
        var sections = UsageDetails.normalizeSections([
            { title: validEmojiTitle, rows: [] },
            { title: validCombiningTitle, rows: [] }
        ])

        compare(sections.length, 2)
        compare(sections[0].title, validEmojiTitle)
        compare(sections[1].title, validCombiningTitle)

        var unsafeTitle = emoji.repeat(UsageDetails.maximumStringCodeUnitsForSafety)
        compare(UsageDetails.normalizeSections([{ title: unsafeTitle, rows: [] }]).length, 0)
    }

    function test_redactsCredentialsFromEveryDisplayField() {
        var secrets = [
            "sk-sectionsecret",
            "label-secret",
            "value-secret",
            "secondary-secret",
            "sk-chartsecret",
            "unit-secret",
            "point-secret"
        ]
        var sections = UsageDetails.normalizeSections([
            {
                title: "API key: " + secrets[0],
                rows: [
                    {
                        label: "Authorization: Bearer " + secrets[1],
                        value: "Bearer " + secrets[2],
                        secondaryValue: "token=" + secrets[3]
                    }
                ],
                chart: {
                    kind: "bars",
                    title: secrets[4],
                    unit: "access_token=" + secrets[5],
                    points: [
                        { label: "Cookie: session=" + secrets[6], value: 1 }
                    ]
                }
            }
        ])

        compare(sections.length, 1)
        var normalized = JSON.stringify(sections)
        for (var i = 0; i < secrets.length; i++) {
            verify(normalized.indexOf(secrets[i]) === -1)
        }
        verify(normalized.indexOf("[redacted]") !== -1)

        var escapedQuote = UsageDetails.normalizeSections([
            { title: "token=\"prefix\\\"LEAK\"", rows: [] }
        ])
        verify(JSON.stringify(escapedQuote).indexOf("LEAK") === -1)
    }

    function test_redactionPreservesUnicodeAndTheStorageBound() {
        var secret = "sk-latesecret"
        var unicodePrefix = "é".repeat(3000)
        var sections = UsageDetails.normalizeSections([
            { title: unicodePrefix + " " + secret, rows: [] }
        ])

        compare(sections.length, 1)
        verify(sections[0].title.indexOf(secret) === -1)
        verify(sections[0].title.indexOf("[redacted]") !== -1)
        verify(sections[0].title.indexOf(unicodePrefix) === 0)

        var expandingCredentials = "é " + "token=a ".repeat(400)
        verify(expandingCredentials.length < UsageDetails.maximumStringCodeUnitsForSafety)
        compare(UsageDetails.normalizeSections([
            { title: expandingCredentials, rows: [] }
        ]).length, 0)

        var postBoundaryMarker = "POST_BOUNDARY_TEXT"
        var longAsciiCredential = "token=" + "a".repeat(200) + " " + postBoundaryMarker
        verify(longAsciiCredential.indexOf(postBoundaryMarker) > UsageDetails.maximumStringLength)
        var bounded = UsageDetails.normalizeSections([
            { title: longAsciiCredential, rows: [] }
        ])
        compare(bounded.length, 1)
        verify(bounded[0].title.indexOf(postBoundaryMarker) === -1)
    }

    function test_redactsCredentialsCrossingTheAsciiDisplayBoundary() {
        var quotedCredential = "x".repeat(100)
            + " token=\"safe LEAK " + "a".repeat(100) + "\""
        var bareCredential = "x".repeat(109) + ":sk-1234567890-secret"

        var sections = UsageDetails.normalizeSections([
            { title: quotedCredential, rows: [] },
            { title: bareCredential, rows: [] }
        ])

        compare(sections.length, 2)
        verify(sections[0].title.indexOf("LEAK") === -1)
        verify(sections[0].title.indexOf("[redacted]") !== -1)
        verify(sections[1].title.indexOf("sk-123") === -1)
        verify(sections[1].title.indexOf("[redacted]") !== -1)
    }

    function test_rejectsMalformedOptionalDetailDataWithoutStringifyingIt() {
        var sections = UsageDetails.normalizeSections([
            null,
            {
                title: { unexpected: "object" },
                rows: [
                    { label: "", value: "hidden" },
                    { label: "Requests", value: "42", secondaryValue: { secret: "do not show" } },
                    { label: "Numeric value", value: 9 }
                ],
                chart: {
                    kind: "pie",
                    points: [{ label: "Ignored", value: 10 }]
                }
            },
            {
                title: "Trend",
                rows: [],
                chart: {
                    kind: "line",
                    points: [
                        { label: "Valid", value: -3 },
                        { label: "Zero", value: 0 },
                        { label: "Infinite", value: Infinity },
                        { label: "String", value: "4" },
                        { label: "", value: 2 }
                    ]
                }
            },
            { title: 5, rows: [] }
        ])

        compare(sections.length, 2)
        compare(sections[0].title, "")
        compare(sections[0].rows.length, 1)
        compare(sections[0].rows[0].secondaryValue, "")
        compare(sections[0].chart, null)
        compare(sections[1].chart.points.length, 2)
        compare(sections[1].chart.points[0].value, -3)
        compare(sections[1].chart.points[1].value, 0)
    }
}
