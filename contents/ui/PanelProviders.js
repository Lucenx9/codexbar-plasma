.pragma library
.import "Guards.js" as Guards
.import "ProviderOrder.js" as ProviderOrder

// The persisted panel selection: an empty value keeps the automatic behavior
// (every enabled provider, in display order), while any stored value means the
// panel shows only the listed providers. noneValue stores an explicit empty
// selection so "no providers in the panel" survives a settings round trip.
var noneValue = "__none__";

// The compact renderer draws at most four provider meters, so a selection
// larger than that could never add visible rows.
var maximumSelectableProviders = 4;

function selectionActive(value) {
    return String(value || "").trim().length > 0;
}

function configuredProviderIDs(value) {
    if (!selectionActive(value)) {
        return [];
    }
    var raw = String(value).trim();
    if (raw === noneValue) {
        return [];
    }
    return ProviderOrder.configuredProviderIDs(raw);
}

// Filters roster items to the configured panel selection. The popup and every
// other surface keep the unfiltered roster; only panel surfaces call this.
function filteredItems(items, value) {
    var source = Array.isArray(items) ? items : [];
    if (!selectionActive(value)) {
        return source;
    }
    var selected = configuredProviderIDs(value);
    if (selected.length === 0) {
        return [];
    }
    var wanted = ({});
    for (var i = 0; i < selected.length; i++) {
        wanted[selected[i]] = true;
    }
    var result = [];
    for (var j = 0; j < source.length; j++) {
        var providerID = ProviderOrder.itemProviderID(source[j]);
        if (providerID.length > 0 && Guards.hasOwnKey(wanted, providerID)) {
            result.push(source[j]);
            if (result.length >= maximumSelectableProviders) {
                break;
            }
        }
    }
    return result;
}

// Returns the next selection after one toggle. Roster order wins so the stored
// value follows the saved provider order; selected providers missing from the
// current roster survive, so disabling a provider elsewhere does not silently
// drop it from the panel selection on the next toggle.
function toggledSelection(orderedProviderIDs, selectedProviderIDs, providerID, checked) {
    var selected = Array.isArray(selectedProviderIDs) ? selectedProviderIDs : [];
    var selectedSet = ({});
    for (var i = 0; i < selected.length; i++) {
        selectedSet[selected[i]] = true;
    }

    var key = ProviderOrder.normalizedProviderID(providerID);
    if (key.length > 0) {
        if (checked) {
            selectedSet[key] = true;
        } else if (Guards.hasOwnKey(selectedSet, key)) {
            delete selectedSet[key];
        }
    }

    var result = [];
    var roster = Array.isArray(orderedProviderIDs) ? orderedProviderIDs : [];
    for (var j = 0; j < roster.length; j++) {
        var candidate = ProviderOrder.normalizedProviderID(roster[j]);
        if (candidate.length > 0 && Guards.hasOwnKey(selectedSet, candidate)
                && result.indexOf(candidate) === -1) {
            result.push(candidate);
        }
    }
    for (var k = 0; k < selected.length; k++) {
        var prior = selected[k];
        if (Guards.hasOwnKey(selectedSet, prior) && result.indexOf(prior) === -1) {
            result.push(prior);
        }
    }
    return result;
}

function selectionText(providerIDs) {
    var selected = Array.isArray(providerIDs) ? providerIDs : [];
    return selected.length > 0 ? selected.join(",") : noneValue;
}
