.pragma library
.import "Guards.js" as Guards
.import "ProviderOrder.js" as ProviderOrder

// The persisted Overview selection: an empty value keeps the automatic
// behavior (the first three eligible providers, in display order), while any
// stored value means the Overview tab shows only the listed providers.
// noneValue stores an explicit empty selection so "no providers in Overview"
// survives a settings round trip.
var noneValue = "__none__";

var automaticProviderCount = 3;

function selectionActive(value) {
    return String(value || "").trim().length > 0;
}

function configuredProviderIDs(value) {
    var raw = String(value || "").trim();
    if (raw.length === 0 || raw === noneValue) {
        return [];
    }
    return ProviderOrder.configuredProviderIDs(raw);
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
        if (result.length >= automaticProviderCount) {
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
// silently drop it from the Overview selection on the next toggle.
function toggledSelection(orderedProviderIDs, selectedProviderIDs, providerID, checked) {
    var selected = Array.isArray(selectedProviderIDs) ? selectedProviderIDs : [];
    var key = ProviderOrder.normalizedProviderID(providerID);
    if (key.length === 0) {
        return selected.slice(0);
    }
    return ProviderOrder.toggledSelection(orderedProviderIDs, selected, key, checked);
}

function selectionText(providerIDs) {
    var selected = Array.isArray(providerIDs) ? providerIDs : [];
    return selected.length > 0 ? selected.join(",") : noneValue;
}

// The placeholder line a provider shows instead of quota rows. Codex spends
// its placeholder slot on the token cost summary, which the popup already
// renders, so an empty string keeps that line from being shown twice.
function placeholderText(item) {
    if (!item || !item.placeholder || item.placeholder.length === 0) {
        return "";
    }
    if (item.provider === "codex" && item.tokenCost) {
        return "";
    }
    return item.placeholder;
}

// The line under a provider's Overview title: its account identity, or what
// stands in for it when the CLI reports none.
function detailText(item) {
    if (!item) {
        return "";
    }
    if (item.account && item.account.length > 0) {
        return item.account;
    }
    // Only an active incident may stand in for a missing account: an
    // operational status is service state, not identity information.
    if (item.hasIncident === true && item.statusKnown !== false
            && item.status && item.status.length > 0) {
        return item.status;
    }
    var placeholder = placeholderText(item);
    if (placeholder.length > 0) {
        return placeholder;
    }
    if (item.source && item.source.length > 0) {
        var source = String(item.source).trim().toLowerCase();
        var providerID = String(item.provider || "").trim().toLowerCase();
        var title = String(item.title || "").trim().toLowerCase();
        // Repeating the provider's own name adds nothing under its title.
        if (source !== providerID && source !== title) {
            return item.source;
        }
    }
    return "";
}

// Normalized sections can retain an empty chart container. Only its visible
// labels or points, a section title, or detail rows provide usable content.
function hasDetailContent(sections) {
    return Array.isArray(sections) && sections.some(function(section) {
        return section.title.length > 0 || section.rows.length > 0
            || (section.chart && (section.chart.title.length > 0
                || section.chart.unit.length > 0 || section.chart.points.length > 0));
    });
}

// A snapshot that carries an error and nothing else. Any surviving quota row,
// credit balance, subscription date, Codex monthly limit, cost figure, detail
// section, dashboard summary, or placeholder keeps the provider eligible, so a
// failed enrichment never hides healthy data.
function isErrorOnly(item) {
    return !!(item
        && item.error
        && item.error.length > 0
        && (!item.rows || item.rows.length === 0)
        && placeholderText(item).length === 0
        && item.credits === null
        && item.codexCreditLimit === null
        && (!item.subscriptionDates || item.subscriptionDates.length === 0)
        && !hasDetailContent(item.providerDetails)
        && !item.usageDashboard
        && !item.resetCredits
        && !item.providerCost
        && !item.tokenCost);
}

// An empty stored value shows the first eligible providers in roster order.
// An explicit selection shows its eligible providers in that same order.
function visibleItems(items, value) {
    var roster = Array.isArray(items) ? items : [];
    var eligible = [];
    for (var i = 0; i < roster.length && eligible.length < ProviderOrder.maximumProviderItems; i++) {
        var item = roster[i];
        if (item && typeof item === "object" && !Array.isArray(item) && !isErrorOnly(item)) {
            eligible.push(item);
        }
    }

    if (!selectionActive(value)) {
        return eligible.slice(0, automaticProviderCount);
    }
    var configured = configuredProviderIDs(value);
    if (configured.length === 0) {
        return [];
    }

    var selected = ({});
    for (var j = 0; j < configured.length; j++) {
        selected[configured[j]] = true;
    }
    var result = [];
    for (var k = 0; k < eligible.length; k++) {
        if (Guards.hasOwnKey(selected, ProviderOrder.normalizedProviderID(eligible[k].provider))) {
            result.push(eligible[k]);
        }
    }
    return result;
}
