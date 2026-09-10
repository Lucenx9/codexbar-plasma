.pragma library
.import "PanelDisplay.js" as PanelDisplay
.import "PanelElements.js" as PanelElements
.import "PanelProviders.js" as PanelProviders
.import "PanelRules.js" as PanelRules
.import "ProviderOrder.js" as ProviderOrder

var scenarios = ["normal", "nearLimit", "incident", "missing"];

function quota(lane, usedPercent, pacePercent, resetMinutes, nearLimit, nowMs) {
    return {
        lane: lane,
        hasPercent: true,
        usedPercent: usedPercent,
        leftPercent: 100 - usedPercent,
        pacePercent: pacePercent,
        paceOnTop: !nearLimit,
        paceEtaSeconds: nearLimit ? 1200 : 0,
        resetMinutes: resetMinutes,
        resetsAt: new Date(nowMs + resetMinutes * 60000).toISOString()
    };
}

// Deliberately fixed examples: this module never accepts account or CLI data.
function providersForScenario(value, nowMs) {
    var nearLimit = value === "nearLimit";
    var missing = value === "missing";
    return [
        {
            provider: "codex",
            title: "Codex",
            credits: missing ? null : 125,
            hasIncident: value === "incident",
            statusSeverity: value === "incident" ? "minor" : "",
            rows: missing ? [] : [quota("primary", nearLimit ? 98 : 42, 45, nearLimit ? 30 : 180, nearLimit, nowMs), quota("secondary", nearLimit ? 88 : 27, 35, 5760, nearLimit, nowMs), quota("tertiary", nearLimit ? 97 : 33, 40, 720, nearLimit, nowMs)]
        },
        {
            provider: "claude",
            title: "Claude",
            credits: null,
            hasIncident: false,
            statusSeverity: "",
            rows: missing ? [] : [quota("primary", nearLimit ? 84 : 58, 60, 120, nearLimit, nowMs), quota("secondary", nearLimit ? 91 : 61, 65, 7200, nearLimit, nowMs)]
        }
    ];
}

function model(options, scenarioValue, nowMs) {
    var settings = options || {};
    var scenario = scenarios.indexOf(scenarioValue) >= 0 ? scenarioValue : "normal";
    var clockMs = typeof nowMs === "number" && isFinite(nowMs) && Math.abs(nowMs) < 8000000000000000 ? nowMs : Date.UTC(2026, 0, 1, 12);
    var providers = ProviderOrder.orderedItems(providersForScenario(scenario, clockMs), settings.providerOrder);
    var panelProviders = PanelProviders.filteredItems(providers, settings.panelProviderFilter);
    var selected = panelProviders.length > 0 ? panelProviders[0] : null;
    if (settings.autoSelectProvider === true && scenario !== "missing") {
        // These fixture observations are ordered by their highest used quota.
        var highestProviderID = scenario === "nearLimit" ? "codex" : "claude";
        selected = panelProviders.filter(function (provider) {
            return provider.provider === highestProviderID;
        })[0] || selected;
    }
    var lane = PanelDisplay.safeLane(settings.quotaLane);
    var mode = PanelDisplay.safeMode(settings.displayMode);
    var rules = PanelRules.normalizedRules(settings.visibilityRules);
    var textRow = selected ? PanelDisplay.rowForMode(selected.rows, mode, lane) : null;
    return {
        scenario: scenario,
        clockMs: clockMs,
        minimalStyle: settings.panelStyle === "minimal",
        elementOrder: PanelElements.normalizedOrder(settings.elementOrder),
        lane: lane,
        mode: mode,
        providers: providers,
        selectedProvider: selected,
        textRow: textRow,
        textVisible: PanelRules.matches(rules.text, textRow, clockMs),
        meterProviders: settings.showMeters === false ? [] : panelProviders.filter(function (provider) {
            var rows = PanelDisplay.meterRows(provider.rows, lane);
            return PanelRules.matchesAny(rules.meters, rows, clockMs);
        }),
        incidentProvider: scenario === "incident" ? providers.filter(function (provider) {
            return provider.hasIncident;
        })[0] : null
    };
}
