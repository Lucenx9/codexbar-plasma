import QtQuick

// Localize planner intents against the applet's current normalized provider and
// row. The caller supplies reset/ETA labels and owns dispatch and privacy.
QtObject {
    function message(intent, item, row, resetLine, paceEta) {
        if (!intent || !item) return null
        if (intent.kind === "status") {
            return {
                title: i18n("%1 status issue", item.title),
                body: item.status,
                urgency: urgency(intent.severity)
            }
        }
        if (!row) return null
        if (intent.kind === "quota") {
            var body = i18n("%1 is %2% used", row.label, Math.round(row.usedPercent))
            if (resetLine.length > 0) body += ". " + resetLine
            return {
                title: intent.severity === "major"
                    ? i18n("%1 quota critical", item.title)
                    : i18n("%1 quota warning", item.title),
                body: body,
                urgency: urgency(intent.severity)
            }
        }
        if (intent.kind === "pace") {
            return {
                title: i18n("%1 pace warning", item.title),
                body: i18n("%1 may run out in %2", row.label, paceEta),
                urgency: "normal"
            }
        }
        if (intent.kind === "reset") {
            return {
                title: i18n("%1 limit reset", item.title),
                body: i18n("%1 is back to %2% used", row.label, Math.round(row.usedPercent)),
                urgency: "low"
            }
        }
        return null
    }

    function urgency(severity) {
        switch (String(severity || "")) {
        case "critical":
        case "major":
            return "critical"
        case "unknown":
            return "low"
        default:
            return "normal"
        }
    }
}
