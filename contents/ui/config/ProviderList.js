.pragma library
.import "../ProviderIdentity.js" as ProviderIdentity
.import "../ProviderOrder.js" as ProviderOrder

// Search is a local projection of the normalized roster. Keep original records
// so filtering cannot change selection, pending commands, or CLI settings.
function filteredProviders(items, query, scope) {
    var source = Array.isArray(items) ? items : [];
    var needle = typeof query === "string" ? query.slice(0, 256).trim().toLowerCase() : "";
    var result = [];
    for (var i = 0; i < Math.min(source.length, ProviderOrder.maximumProviderItems); i++) {
        var item = source[i];
        if (!item || typeof item !== "object" || Array.isArray(item) || typeof item.provider !== "string" || ProviderIdentity.normalizedProviderID(item.provider).length === 0) {
            continue;
        }
        if ((scope === "enabled" && item.enabled !== true) || (scope === "disabled" && item.enabled === true)) {
            continue;
        }
        var name = typeof item.displayName === "string" ? item.displayName.slice(0, 256) : "";
        if (needle.length === 0 || name.toLowerCase().indexOf(needle) !== -1 || item.provider.toLowerCase().indexOf(needle) !== -1) {
            result.push(item);
        }
    }
    return result;
}
