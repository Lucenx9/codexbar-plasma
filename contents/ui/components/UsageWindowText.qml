import QtQuick
import "../ResetPresentation.js" as ResetPresentation
import "../PacePresentation.js" as PacePresentation

QtObject {
    id: root

    property TimeLabels dateLabels

    function resetText(window, nowMs, absolute) {
        var parts = ResetPresentation.parts(window, nowMs, absolute);
        switch (parts.kind) {
        case "absolute":
            return ResetPresentation.absoluteShowsDate(parts.timestampMs, nowMs) ? root.dateLabels.monthDayTime(parts.timestampMs) : root.dateLabels.weekdayTime(parts.timestampMs);
        case "now":
            return i18n("now");
        case "minutes":
            return i18np("%1 min", "%1 min", parts.minutes);
        case "hours":
            return parts.minutes > 0 ? i18n("%1h %2m", parts.hours, parts.minutes) : i18np("%1h", "%1h", parts.hours);
        case "days":
            return parts.hours > 0 ? i18n("%1d %2h", parts.days, parts.hours) : i18np("%1d", "%1d", parts.days);
        default:
            return parts.text;
        }
    }

    function paceSummaryPartsText(parts) {
        var labels = [];
        for (var i = 0; i < parts.length; i++) {
            var part = parts[i];
            switch (part.kind) {
            case "onTrack":
                labels.push(i18n("On pace"));
                break;
            case "deficit":
                labels.push(i18n("%1% in deficit", part.percent));
                break;
            case "reserve":
                labels.push(i18n("%1% in reserve", part.percent));
                break;
            case "expected":
                labels.push(i18n("Expected %1% used", part.percent));
                break;
            case "lasts":
                labels.push(i18n("Lasts until reset"));
                break;
            case "runsOut":
                labels.push(part.seconds === 0 ? i18n("Runs out now") : i18n("Runs out in %1", root.paceEtaText(part.seconds)));
                break;
            case "fallback":
                labels.push(part.text);
                break;
            }
        }
        return labels.join(" | ");
    }

    function paceEtaText(seconds) {
        var parts = PacePresentation.etaParts(seconds);
        switch (parts.kind) {
        case "minutes":
            return i18np("%1 minute", "%1 minutes", parts.count);
        case "hours":
            return i18np("%1 hour", "%1 hours", parts.count);
        case "days":
            return i18np("%1 day", "%1 days", parts.count);
        default:
            return i18n("now");
        }
    }

    function resetLabel(value) {
        var parts = ResetPresentation.labelParts(value);
        return parts.isTime ? i18n("Resets %1", parts.text) : parts.text;
    }
}
