.pragma library

.import "Guards.js" as Guards
.import "PanelDisplay.js" as PanelDisplay

var conditions = ["always", "usageAtLeast", "resetWithin", "runOut"];
var maximumResetMinutes = 10080;

function ownValue(record, key) {
    return record && typeof record === "object" && !Array.isArray(record)
        && Guards.hasOwnKey(record, key) ? record[key] : undefined;
}

function boundedInteger(value, fallback, minimum, maximum) {
    return typeof value === "number" && isFinite(value)
        ? Math.max(minimum, Math.min(maximum, Math.round(value))) : fallback;
}

function normalizedRule(value) {
    var condition = ownValue(value, "condition");
    return {
        condition: conditions.indexOf(condition) >= 0 ? condition : "always",
        usedPercent: boundedInteger(ownValue(value, "usedPercent"), 80, 0, 100),
        resetMinutes: boundedInteger(ownValue(value, "resetMinutes"), 60, 1, maximumResetMinutes)
    };
}

function normalizedRules(value) {
    var record = null;
    if (typeof value === "string" && value.length <= 2048) {
        try {
            record = JSON.parse(value);
        } catch (error) {
            record = null;
        }
    }
    return {
        text: normalizedRule(ownValue(record, "text")),
        meters: normalizedRule(ownValue(record, "meters"))
    };
}

function updatedRules(value, elementID, patch) {
    var rules = normalizedRules(value);
    if (elementID === "text" || elementID === "meters") {
        var fields = ["condition", "usedPercent", "resetMinutes"];
        for (var i = 0; i < fields.length; i++) {
            var field = fields[i];
            var replacement = ownValue(patch, field);
            if (replacement !== undefined) {
                rules[elementID][field] = replacement;
            }
        }
        rules[elementID] = normalizedRule(rules[elementID]);
    }
    return JSON.stringify(rules);
}

// Rules inspect the same quota as the element they gate. Relative reset labels
// are display text, not timestamps, so they cannot satisfy a timed condition.
function matches(value, row, nowMs) {
    var rule = normalizedRule(value);
    if (rule.condition === "always") {
        return true;
    }
    if (!row || typeof row !== "object" || Array.isArray(row)) {
        return false;
    }
    if (rule.condition === "usageAtLeast") {
        return row.hasPercent === true && typeof row.usedPercent === "number"
            && isFinite(row.usedPercent) && row.usedPercent >= rule.usedPercent;
    }
    if (rule.condition === "runOut") {
        return PanelDisplay.rowHasRunOut(row);
    }
    if (typeof row.resetsAt !== "string" || row.resetsAt.length > 128
            || typeof nowMs !== "number" || !isFinite(nowMs)) {
        return false;
    }
    var remainingMs = Date.parse(row.resetsAt) - nowMs;
    return isFinite(remainingMs) && remainingMs > 0 && remainingMs <= rule.resetMinutes * 60000;
}
