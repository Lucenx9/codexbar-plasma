.pragma library
.import "ProviderNormalizer.js" as Normalizer

// The caller supplies its live clock. QML owns locale-specific date formatting
// and translations; a malformed optional reset must not discard a healthy quota.
function parts(window, nowMs, absolute) {
    if (!Normalizer.isCliRecord(window)) {
        return {
            kind: "text",
            text: ""
        };
    }
    var resetsAt = window.resetsAt;
    if (typeof resetsAt === "string") {
        resetsAt = Normalizer.boundedDisplayText(resetsAt, 500);
    } else if (typeof resetsAt !== "number") {
        resetsAt = "";
    }
    if (!resetsAt) {
        return {
            kind: "text",
            text: Normalizer.boundedDisplayText(window.resetDescription || "", 500)
        };
    }

    var timestampMs = new Date(resetsAt).getTime();
    if (!isFinite(timestampMs)) {
        return {
            kind: "text",
            text: Normalizer.boundedDisplayText(resetsAt, 500)
        };
    }
    if (absolute === true) {
        return {
            kind: "absolute",
            timestampMs: timestampMs
        };
    }
    if (typeof nowMs !== "number" || !isFinite(new Date(nowMs).getTime())) {
        return {
            kind: "text",
            text: Normalizer.boundedDisplayText(resetsAt, 500)
        };
    }

    var remainingMs = timestampMs - nowMs;
    if (remainingMs <= 0) {
        return {
            kind: "now"
        };
    }
    var minutes = Math.max(1, Math.round(remainingMs / 60000));
    if (minutes < 60) {
        return {
            kind: "minutes",
            minutes: minutes
        };
    }
    var hours = Math.floor(minutes / 60);
    if (hours < 24) {
        return {
            kind: "hours",
            hours: hours,
            minutes: minutes % 60
        };
    }
    return {
        kind: "days",
        days: Math.floor(hours / 24),
        hours: hours % 24
    };
}

// A weekday names one date only from today through the next six days. A reset
// further away, such as a monthly window or a weekly one that just reset and
// falls on today's weekday again, needs its date. Without a usable clock the
// date is the only unambiguous choice.
function absoluteShowsDate(timestampMs, nowMs) {
    var reset = new Date(typeof timestampMs === "number" ? timestampMs : NaN);
    var now = new Date(typeof nowMs === "number" ? nowMs : NaN);
    if (!isFinite(reset.getTime()) || !isFinite(now.getTime())) {
        return true;
    }
    // Calendar days in local time; UTC arithmetic keeps DST days whole.
    var days = Math.round((Date.UTC(reset.getFullYear(), reset.getMonth(), reset.getDate())
        - Date.UTC(now.getFullYear(), now.getMonth(), now.getDate())) / 86400000);
    return days < 0 || days > 6;
}

function labelParts(value) {
    var text = Normalizer.boundedDisplayText(value || "", 500);
    // Split joined units (5h30m), preserving compact durations (2h 30m).
    // Keep the existing prose compatibility rules; unknown text stays literal.
    text = text.replace(/([A-Za-z])(\d)/g, "$1 $2").replace(/\)([A-Za-z])/g, ") $1").replace(/(am|pm)\(/ig, "$1 (").replace(/\s+/g, " ");
    if (/^resets\b/i.test(text)) {
        text = text.replace(/^resets\s*/i, "");
    }
    return {
        text: text,
        isTime: looksLikeTime(text)
    };
}

function looksLikeTime(text) {
    if (/^(now|today|tomorrow)\b/i.test(text)) {
        return true;
    }
    if (/^\d{1,2}(:\d{2})?\s*(am|pm)(\s*\([^)]+\))?$/i.test(text)) {
        return true;
    }
    if (/^\d{1,2}:\d{2}(\s*\([^)]+\))?$/.test(text)) {
        return true;
    }
    if (/^\S+\s+\d{1,2}:\d{2}(\s*\([^)]+\))?$/.test(text)) {
        return true;
    }
    return /^\d+\s*(min|m|h|hr|hour|hours|d|day|days)(\s+\d+\s*(min|m|h|hr|hour|hours|d|day|days))*$/i.test(text);
}
