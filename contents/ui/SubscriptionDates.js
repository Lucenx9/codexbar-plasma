.pragma library
.import "Guards.js" as Guards

// Official usage dates are ISO-8601 strings. Check calendar components before
// Date.parse, which otherwise rolls impossible dates into the following month.
function date(value, dateOnly, kind) {
    if (typeof value !== "string" || value.length > 35) {
        return null;
    }
    var parts = /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|[+-]\d{2}:\d{2}))?$/.exec(value);
    if (!parts) {
        return null;
    }
    var year = Number(parts[1]);
    var month = Number(parts[2]);
    var day = Number(parts[3]);
    var leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
    var days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (year < 1 || month < 1 || month > 12 || day < 1 || day > days[month - 1]) {
        return null;
    }
    if (parts[4] !== undefined) {
        var zone = parts[7];
        if (Number(parts[4]) > 23 || Number(parts[5]) > 59 || Number(parts[6]) > 59
                || (zone !== "Z" && (Number(zone.slice(1, 3)) > 23 || Number(zone.slice(4)) > 59))) {
            return null;
        }
    } else if (!dateOnly) {
        return null;
    }
    var timestampMs = Date.parse(value);
    if (!isFinite(timestampMs)) {
        return null;
    }
    // The CLI serializes a calendar value as a timestamp plus a true flag.
    // Preserve that serialized day, rather than converting it to local time.
    return {kind: kind, timestampMs: dateOnly ? null : timestampMs,
        calendarDay: dateOnly ? value.slice(0, 10) : ""};
}

function normalize(usage) {
    var result = [];
    for (var entry of [{field: "subscriptionRenewsAt", kind: "renews"},
            {field: "subscriptionExpiresAt", kind: "expires"}]) {
        if (!Guards.hasOwnKey(usage, entry.field)) {
            continue;
        }
        var flag = entry.field + "IsDateOnly";
        var normalized = date(usage[entry.field], Guards.hasOwnKey(usage, flag) && usage[flag] === true, entry.kind);
        if (normalized) {
            result.push(normalized);
        }
    }
    return result;
}
