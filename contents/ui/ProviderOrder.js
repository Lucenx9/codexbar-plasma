.pragma library
.import "ProviderIdentity.js" as ProviderIdentity

var maximumProviderItems = 256;
var maximumProviderOrderLength = maximumProviderItems * (ProviderIdentity.maximumProviderIDLength + 1);

function normalizedProviderID(value) {
    return ProviderIdentity.normalizedProviderID(value);
}

function configuredProviderIDs(value) {
    var tokens = String(value || "").slice(0, maximumProviderOrderLength).split(",");
    var result = [];
    for (var i = 0; i < tokens.length && result.length < maximumProviderItems; i++) {
        var providerID = normalizedProviderID(tokens[i]);
        if (providerID.length > 0 && result.indexOf(providerID) === -1) {
            result.push(providerID);
        }
    }
    return result;
}

function itemProviderID(item) {
    if (typeof item === "string") {
        return normalizedProviderID(item);
    }
    return item && typeof item === "object" ? normalizedProviderID(item.provider) : "";
}

function orderedItems(items, configuredValue) {
    var source = Array.isArray(items) ? items.slice(0, maximumProviderItems) : [];
    var configured = configuredProviderIDs(configuredValue);
    var result = [];
    var usedIndexes = [];

    for (var i = 0; i < configured.length; i++) {
        for (var j = 0; j < source.length; j++) {
            if (!usedIndexes[j] && itemProviderID(source[j]) === configured[i]) {
                usedIndexes[j] = true;
                result.push(source[j]);
                break;
            }
        }
    }

    for (var k = 0; k < source.length; k++) {
        if (!usedIndexes[k]) {
            result.push(source[k]);
        }
    }
    return result;
}

function providerDisplaySortKey(item) {
    var displayName = item && typeof item === "object"
        ? String(item.displayName || "").trim().toLowerCase()
        : "";
    return displayName.length > 0 ? displayName : itemProviderID(item);
}

function compareProviderDisplayNames(left, right) {
    var leftKey = providerDisplaySortKey(left);
    var rightKey = providerDisplaySortKey(right);
    if (leftKey !== rightKey) {
        return leftKey < rightKey ? -1 : 1;
    }

    var leftProviderID = itemProviderID(left);
    var rightProviderID = itemProviderID(right);
    return leftProviderID === rightProviderID ? 0 : (leftProviderID < rightProviderID ? -1 : 1);
}

function settingsGroups(items, configuredValue) {
    var source = Array.isArray(items) ? items.slice(0, maximumProviderItems) : [];
    var enabled = [];
    var disabled = [];

    for (var i = 0; i < source.length; i++) {
        var item = source[i];
        if (!item || typeof item !== "object" || Array.isArray(item)
                || itemProviderID(item).length === 0) {
            continue;
        }
        if (item.enabled === true) {
            enabled.push(item);
        } else {
            disabled.push(item);
        }
    }

    disabled.sort(compareProviderDisplayNames);
    return {
        enabled: orderedItems(enabled, configuredValue),
        disabled: disabled
    };
}

// The persisted order is a preference over every provider the user has ever
// ordered, not just the current roster: moves happen on the visible (enabled)
// subset, but configured tokens without a matching item must survive so a
// re-enabled provider returns to its configured position.
function providerOrderTokens(items, configuredValue) {
    var tokens = configuredProviderIDs(configuredValue);
    var ordered = orderedItems(items, configuredValue);
    for (var i = 0; i < ordered.length && tokens.length < maximumProviderItems; i++) {
        var providerID = itemProviderID(ordered[i]);
        if (providerID.length > 0 && tokens.indexOf(providerID) === -1) {
            tokens.push(providerID);
        }
    }
    return tokens;
}

function movedOrder(items, configuredValue, index, delta) {
    var ordered = orderedItems(items, configuredValue);
    var tokens = providerOrderTokens(items, configuredValue);
    var from = Math.floor(Number(index));
    var target = from + Math.floor(Number(delta));
    if (!isFinite(from) || !isFinite(target) || from < 0 || from >= ordered.length || target < 0 || target >= ordered.length) {
        return tokens.join(",");
    }

    // Rotate only visible slots; intervening disabled providers stay put.
    // Resolve every slot first so missing or duplicate tokens leave no partial move.
    var step = target < from ? -1 : 1;
    var slots = [];
    for (var i = from; ; i += step) {
        var slot = tokens.indexOf(itemProviderID(ordered[i]));
        if (slot < 0 || slots.indexOf(slot) !== -1) {
            return tokens.join(",");
        }
        slots.push(slot);
        if (i === target) {
            break;
        }
    }
    var movedProviderID = tokens[slots[0]];
    for (var j = 0; j < slots.length - 1; j++) {
        tokens[slots[j]] = tokens[slots[j + 1]];
    }
    tokens[slots[slots.length - 1]] = movedProviderID;
    return tokens.join(",");
}
