import QtQuick
import QtTest
import "../contents/ui/PanelPreview.js" as PanelPreview

TestCase {
    name: "PanelPreview"

    readonly property real nowMs: Date.UTC(2026, 8, 8, 12)

    function test_scenariosKeepTheirSyntheticInputsIsolated() {
        var first = PanelPreview.model({}, "normal", nowMs);
        var second = PanelPreview.model({}, "normal", nowMs);
        compare(first.providers.length, 2);
        compare(first.selectedProvider.provider, "codex");
        compare(first.textRow.usedPercent, 42);
        compare(first.textRow.resetsAt, "2026-09-08T15:00:00.000Z");
        first.providers[0].rows[0].usedPercent = 1;
        compare(second.textRow.usedPercent, 42);
        compare(first.incidentProvider, null);
        var incident = PanelPreview.model({}, "incident", nowMs);
        compare(incident.incidentProvider.provider, "codex");
        compare(incident.incidentProvider.statusSeverity, "minor");
        var nearLimit = PanelPreview.model({}, "nearLimit", nowMs);
        compare(nearLimit.textRow.usedPercent, 98);
        compare(nearLimit.incidentProvider, null);
    }

    function test_missingLaneOmitsMetersAndMetricsWithoutFalseZero() {
        var tertiary = PanelPreview.model({
            quotaLane: "tertiary"
        }, "normal", nowMs);
        compare(tertiary.meterProviders.length, 1);
        compare(tertiary.meterProviders[0].provider, "codex");
        var missing = PanelPreview.model({
            displayMode: "both"
        }, "missing", nowMs);
        compare(missing.meterProviders.length, 0);
        compare(missing.textRow, null);
        compare(missing.selectedProvider.credits, null);
        verify(missing.textVisible);
    }

    function test_settingsUseSharedOrderLaneModeAndVisibilityRules() {
        var options = {
            elementOrder: "meters,text,status,identity",
            providerOrder: "claude,codex",
            quotaLane: "secondary",
            displayMode: "both",
            panelStyle: "minimal",
            visibilityRules: '{"text":{"condition":"usageAtLeast","usedPercent":80},"meters":{"condition":"usageAtLeast","usedPercent":50}}'
        };
        var normal = PanelPreview.model(options, "normal", nowMs);
        compare(normal.elementOrder, ["meters", "text", "status", "identity"]);
        compare(normal.selectedProvider.provider, "claude");
        compare(normal.textRow.lane, "secondary");
        compare(normal.mode, "both");
        verify(normal.minimalStyle);
        verify(!normal.textVisible);
        compare(normal.meterProviders.length, 1);
        compare(normal.meterProviders[0].provider, "claude");
        var nearLimit = PanelPreview.model(options, "nearLimit", nowMs);
        verify(nearLimit.textVisible);
        compare(nearLimit.meterProviders.length, 2);
        options.showMeters = false;
        compare(PanelPreview.model(options, "nearLimit", nowMs).meterProviders.length, 0);
    }

    function test_timedAndForecastRulesMatchTheSyntheticObservation() {
        var resetRule = {
            visibilityRules: '{"meters":{"condition":"resetWithin","resetMinutes":60}}'
        };
        compare(PanelPreview.model(resetRule, "normal", nowMs).meterProviders.length, 0);
        compare(PanelPreview.model(resetRule, "nearLimit", nowMs).meterProviders.length, 1);
        var forecastRule = {
            displayMode: "runOut",
            visibilityRules: '{"text":{"condition":"runOut"}}'
        };
        var normal = PanelPreview.model(forecastRule, "normal", nowMs);
        verify(!normal.textVisible);
        compare(normal.textRow, null);
        var nearLimit = PanelPreview.model(forecastRule, "nearLimit", nowMs);
        verify(nearLimit.textVisible);
        compare(nearLimit.textRow.paceEtaSeconds, 1200);
    }

    function test_automaticSelectionUsesHighestFixtureQuotaAndIgnoresRosterOrder() {
        compare(PanelPreview.model({
            autoSelectProvider: true
        }, "normal", nowMs).selectedProvider.provider, "claude");
        compare(PanelPreview.model({
            autoSelectProvider: true,
            providerOrder: "claude,codex"
        }, "nearLimit", nowMs).selectedProvider.provider, "codex");
        compare(PanelPreview.model({
            autoSelectProvider: true,
            providerOrder: "claude,codex"
        }, "missing", nowMs).selectedProvider.provider, "claude");
    }

    function test_panelProviderSelectionFiltersMetersTextAndSelection() {
        var claudeOnly = PanelPreview.model({
            panelProviderFilter: "claude"
        }, "normal", nowMs);
        compare(claudeOnly.providers.length, 2);
        compare(claudeOnly.meterProviders.length, 1);
        compare(claudeOnly.meterProviders[0].provider, "claude");
        compare(claudeOnly.selectedProvider.provider, "claude");

        // The automatic highest-usage pick follows the panel selection: with
        // claude filtered out, codex leads even though claude uses more.
        var codexOnly = PanelPreview.model({
            panelProviderFilter: "codex",
            autoSelectProvider: true
        }, "normal", nowMs);
        compare(codexOnly.meterProviders.length, 1);
        compare(codexOnly.selectedProvider.provider, "codex");

        // An explicit empty selection renders no meter and no text provider.
        var none = PanelPreview.model({
            panelProviderFilter: "__none__"
        }, "normal", nowMs);
        compare(none.meterProviders.length, 0);
        compare(none.selectedProvider, null);
        compare(none.textRow, null);

        // Unknown selections keep hiding meters instead of silently resetting
        // the stored choice; the settings reset button stays available.
        compare(PanelPreview.model({
            panelProviderFilter: "unknown"
        }, "normal", nowMs).meterProviders.length, 0);
        compare(PanelPreview.model({
            panelProviderFilter: 42
        }, "normal", nowMs).meterProviders.length, 0);
    }

    function test_invalidOptionsUseBoundedDefaults() {
        var preview = PanelPreview.model({
            quotaLane: "other",
            displayMode: "other",
            elementOrder: "text,text",
            visibilityRules: "malformed"
        }, "other", Infinity);
        compare(preview.scenario, "normal");
        compare(preview.lane, "auto");
        compare(preview.mode, "percent");
        compare(preview.elementOrder, ["text", "identity", "status", "meters"]);
        verify(isFinite(preview.clockMs));
        compare(preview.meterProviders.length, 2);
    }

    function test_enabledProviderMetadataUsesOnlySyntheticMeasurements() {
        var preview = PanelPreview.model({
            providerRoster: [{provider: "gemini", displayName: "Gemini", credits: 999,
                rows: [{usedPercent: 99}], account: "private@example.test", hasIncident: true}],
            panelProviderFilter: "gemini",
            autoSelectProvider: true
        }, "normal", nowMs);
        compare(preview.selectedProvider.provider, "gemini");
        compare(preview.selectedProvider.title, "Gemini");
        compare(preview.textRow.usedPercent, 42);
        compare(preview.selectedProvider.credits, null);
        compare(preview.selectedProvider.account, undefined);
        verify(!preview.selectedProvider.hasIncident);
        compare(preview.meterProviders.length, 1);
        compare(PanelPreview.model({providerRoster: [{provider: "gemini"}],
            panelProviderFilter: "__none__"}, "normal", nowMs).selectedProvider, null);
    }

    function test_rosterFallbackDoesNotInventUnknownSelections() {
        compare(PanelPreview.model({providerRoster: []}, "normal", nowMs).providers.length, 2);
        var missing = PanelPreview.model({providerRoster: [], panelProviderFilter: "unknown"}, "normal", nowMs);
        compare(missing.selectedProvider, null);
        compare(missing.meterProviders.length, 0);
        var available = PanelPreview.model({providerRoster: [{provider: "gemini"}],
            panelProviderFilter: "codex"}, "normal", nowMs);
        compare(available.selectedProvider, null);
        compare(available.meterProviders.length, 0);
    }

    function test_metadataIsBoundedOrderedAndCapsVisibleMeters() {
        var roster = [null, [], {provider: "constructor"}, {provider: "gemini", displayName: "x".repeat(200)},
            {provider: "GEMINI"}, {provider: "codex", displayName: "Codex"}, {provider: "claude", displayName: "Claude"},
            {provider: "cursor"}, {provider: "opencode"}];
        var options = {providerRoster: roster, providerOrder: "opencode,cursor,claude,codex,gemini"};
        var preview = PanelPreview.model(options, "normal", nowMs);
        compare(preview.providers.length, 5);
        compare(preview.selectedProvider.provider, "opencode");
        verify(preview.providers[4].title.length <= 120);
        compare(preview.meterProviders.map(function (provider) { return provider.provider; }),
            ["opencode", "cursor", "claude", "codex"]);
        options.autoSelectProvider = true;
        compare(PanelPreview.model(options, "normal", nowMs).selectedProvider.provider, "claude");
    }
}
