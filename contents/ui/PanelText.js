.pragma library

// Inputs are already normalized/presented and text is localized by QML. Keep
// the fallback identity as a single usage segment, so fitting cannot drop it.
function segments(item, visible, selectionActive, options, text) {
    if (!visible) {
        return [];
    }
    if (!item) {
        return selectionActive ? [] : [{ id: "usage", text: text.fallback }];
    }
    var result = [];
    if (options.showProvider) {
        result.push({ id: "name", text: item.title,
            identifying: !options.iconIdentifies });
    }
    if (options.showPercent && text.display.length > 0) {
        result.push({ id: "usage", text: text.display });
    }
    if (options.showCredits && item.credits !== null) {
        result.push({ id: "credits", text: text.credits });
    }
    return result;
}

// Only current incidents accompany usage. A balance remains recoverable in
// the tooltip when the panel has surrendered its credit segment.
function providerTooltip(item, description, showCredits) {
    if (!item) {
        return null;
    }
    return {
        title: item.title,
        description: description,
        credits: showCredits && item.credits !== null && item.credits !== undefined
            ? item.credits : null,
        incident: item.hasIncident && item.statusKnown !== false && item.status.length > 0
            ? item.status : ""
    };
}
