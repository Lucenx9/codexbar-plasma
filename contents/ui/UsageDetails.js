.pragma library
.import "SafeText.js" as SafeText

var maximumSectionsPerSnapshot = 8
var maximumRowsPerSection = 24
var maximumPointsPerChart = 120
var maximumStringLength = 120
var maximumStringCodeUnitsForSafety = maximumStringLength * 32

function optionalText(value) {
    if (typeof value !== "string") {
        return ""
    }
    var trimmed = value.trim()
    if (trimmed.length > maximumStringCodeUnitsForSafety) {
        return ""
    }

    // QML JavaScript has no grapheme segmenter. The official CLI already
    // validates the 120-character Swift String contract; re-counting UTF-16
    // here would corrupt valid combining and emoji sequences. Keep an exact
    // ASCII fast path plus a separate storage bound for untrusted payloads.
    var isAscii = /^[\x00-\x7F]*$/.test(trimmed)
    var redacted = isAscii
        ? SafeText.redactCredentialsWithinSourceLimit(trimmed, maximumStringLength)
        : SafeText.redactCredentials(trimmed, maximumStringCodeUnitsForSafety)
    if (redacted.length > maximumStringCodeUnitsForSafety) {
        return ""
    }
    return isAscii
        ? redacted.slice(0, maximumStringLength)
        : redacted
}

function optionalNumber(value) {
    return typeof value === "number" && isFinite(value) ? value : null
}

// The CLI caps progress.used at total while the display value stays uncapped,
// so the pair drives the meter and the display string is never parsed.
function optionalProgress(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
        return null
    }
    var used = optionalNumber(value.used)
    var total = optionalNumber(value.total)
    if (used === null || total === null || used < 0 || total <= 0) {
        return null
    }
    return {
        used: used,
        total: total,
        fraction: Math.min(1, used / total)
    }
}

function normalizeSections(rawSections) {
    if (!Array.isArray(rawSections)) {
        return []
    }

    var sections = []
    var sectionLimit = Math.min(rawSections.length, maximumSectionsPerSnapshot)
    for (var i = 0; i < sectionLimit; i++) {
        var rawSection = rawSections[i]
        if (!rawSection || typeof rawSection !== "object" || Array.isArray(rawSection)) {
            continue
        }

        var rows = []
        var rawRows = Array.isArray(rawSection.rows) ? rawSection.rows : []
        var rowLimit = Math.min(rawRows.length, maximumRowsPerSection)
        for (var rowIndex = 0; rowIndex < rowLimit; rowIndex++) {
            var rawRow = rawRows[rowIndex]
            if (!rawRow || typeof rawRow !== "object" || Array.isArray(rawRow)) {
                continue
            }
            var label = optionalText(rawRow.label)
            var value = optionalText(rawRow.value)
            if (label.length === 0 || value.length === 0) {
                continue
            }
            rows.push({
                label: label,
                value: value,
                secondaryValue: optionalText(rawRow.secondaryValue),
                usageValue: optionalNumber(rawRow.usageValue),
                progress: optionalProgress(rawRow.progress)
            })
        }

        var rawChart = rawSection.chart
        var chart = null
        if (rawChart
                && typeof rawChart === "object"
                && !Array.isArray(rawChart)
                && (rawChart.kind === "bars" || rawChart.kind === "line")) {
            var points = []
            var rawPoints = Array.isArray(rawChart.points) ? rawChart.points : []
            var pointLimit = Math.min(rawPoints.length, maximumPointsPerChart)
            for (var pointIndex = 0; pointIndex < pointLimit; pointIndex++) {
                var rawPoint = rawPoints[pointIndex]
                if (!rawPoint || typeof rawPoint !== "object" || Array.isArray(rawPoint)) {
                    continue
                }
                var pointLabel = optionalText(rawPoint.label)
                if (pointLabel.length === 0
                        || typeof rawPoint.value !== "number"
                        || !isFinite(rawPoint.value)) {
                    continue
                }
                points.push({
                    label: pointLabel,
                    value: rawPoint.value
                })
            }
            chart = {
                kind: rawChart.kind,
                title: optionalText(rawChart.title),
                unit: optionalText(rawChart.unit),
                points: points
            }
        }

        var title = optionalText(rawSection.title)
        if (title.length === 0 && rows.length === 0 && chart === null) {
            continue
        }
        sections.push({
            title: title,
            rows: rows,
            chart: chart
        })
    }
    return sections
}
