.pragma library
.import "ProviderIdentity.js" as ProviderIdentity

var maximumProviderItems = 256;
var maximumProviderOrderLength = maximumProviderItems * (ProviderIdentity.maximumProviderIDLength + 1);

function normalizedProviderID(value) {
    if (typeof value !== "string") {
        return "";
    }
    var candidate = value.trim();
    if (candidate.length === 0 || candidate.length > ProviderIdentity.maximumProviderIDLength) {
        return "";
    }
    return ProviderIdentity.providerMapKey(ProviderIdentity.resolveProviderKey(candidate));
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
        if (source[i] && source[i].enabled === true) {
            enabled.push(source[i]);
        } else {
            disabled.push(source[i]);
        }
    }

    disabled.sort(compareProviderDisplayNames);
    return {
        enabled: orderedItems(enabled, configuredValue),
        disabled: disabled
    };
}

function serializedOrder(items) {
    var result = [];
    var source = Array.isArray(items) ? items.slice(0, maximumProviderItems) : [];
    for (var i = 0; i < source.length; i++) {
        var providerID = itemProviderID(source[i]);
        if (providerID.length > 0 && result.indexOf(providerID) === -1) {
            result.push(providerID);
        }
    }
    return result.join(",");
}

function movedOrder(items, configuredValue, index, delta) {
    var ordered = orderedItems(items, configuredValue);
    var from = Math.floor(Number(index));
    var target = from + Math.floor(Number(delta));
    if (!isFinite(from) || !isFinite(target) || from < 0 || from >= ordered.length || target < 0 || target >= ordered.length) {
        return serializedOrder(ordered);
    }

    var item = ordered[from];
    ordered.splice(from, 1);
    ordered.splice(target, 0, item);
    return serializedOrder(ordered);
}
