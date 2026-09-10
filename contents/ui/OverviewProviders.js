.pragma library
.import "Guards.js" as Guards
.import "ProviderOrder.js" as ProviderOrder

// The persisted Overview selection: an empty value keeps the automatic
// behavior (the first three eligible providers, in display order), while any
// stored value means the Overview tab shows only the listed providers.
// noneValue stores an explicit empty selection so "no providers in Overview"
// survives a settings round trip.
var noneValue = "__none__";

// The Overview tab shows at most three providers, so a selection larger than
// that could never add visible rows.
var maximumOverviewProviders = 3;

function selectionActive(value) {
    return String(value || "").trim().length > 0;
}

function configuredProviderIDs(value) {
    var raw = String(value || "").trim();
    if (raw.length === 0 || raw === noneValue) {
        return [];
    }
    return ProviderOrder.configuredProviderIDs(raw).slice(0, maximumOverviewProviders);
}

// Resolves the stored value against roster IDs already in display order.
// Roster entries may use raw CLI spellings, so every ID is normalized here;
// the runtime resolves the same way, keeping the checkboxes and the applied
// selection from drifting apart.
function resolvedProviderIDs(orderedProviderIDs, value) {
    if (selectionActive(value)) {
        return configuredProviderIDs(value);
    }
    var roster = Array.isArray(orderedProviderIDs) ? orderedProviderIDs : [];
    var result = [];
    for (var i = 0; i < roster.length; i++) {
        var providerID = ProviderOrder.normalizedProviderID(roster[i]);
        if (providerID.length === 0 || result.indexOf(providerID) !== -1) {
            continue;
        }
        result.push(providerID);
        if (result.length >= maximumOverviewProviders) {
            break;
        }
    }
    return result;
}

function isSelected(resolvedProviderIDs, providerID) {
    var selected = Array.isArray(resolvedProviderIDs) ? resolvedProviderIDs : [];
    return selected.indexOf(ProviderOrder.normalizedProviderID(providerID)) !== -1;
}

// Returns the next selection after one toggle. Roster order wins so the
// stored value follows the saved provider order; selected providers missing
// from the current roster survive, so disabling a provider elsewhere does not
// silently drop it from the Overview selection on the next toggle. Adding
// beyond the visible limit keeps the current selection.
function toggledSelection(orderedProviderIDs, selectedProviderIDs, providerID, checked) {
    var selected = Array.isArray(selectedProviderIDs) ? selectedProviderIDs : [];
    var selectedSet = ({});
    for (var i = 0; i < selected.length; i++) {
        selectedSet[selected[i]] = true;
    }

    var key = ProviderOrder.normalizedProviderID(providerID);
    if (key.length === 0) {
        return selected.slice(0);
    }
    if (checked) {
        if (!Guards.hasOwnKey(selectedSet, key) && selected.length >= maximumOverviewProviders) {
            return selected.slice(0);
        }
        selectedSet[key] = true;
    } else if (Guards.hasOwnKey(selectedSet, key)) {
        delete selectedSet[key];
    }

    var result = [];
    var roster = Array.isArray(orderedProviderIDs) ? orderedProviderIDs : [];
    for (var j = 0; j < roster.length; j++) {
        var candidate = ProviderOrder.normalizedProviderID(roster[j]);
        if (candidate.length > 0 && Guards.hasOwnKey(selectedSet, candidate) && result.indexOf(candidate) === -1) {
            result.push(candidate);
            if (result.length >= maximumOverviewProviders) {
                break;
            }
        }
    }
    for (var k = 0; k < selected.length && result.length < maximumOverviewProviders; k++) {
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
