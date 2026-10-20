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

function selectionText(providerIDs) {
    var selected = Array.isArray(providerIDs) ? providerIDs : [];
    return selected.length > 0 ? selected.join(",") : noneValue;
}
