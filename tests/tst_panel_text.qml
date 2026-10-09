import QtQuick
import QtTest
import "../contents/ui/PanelText.js" as PanelTextPlan
import "../contents/ui/PanelTextFit.js" as PanelTextFit
import "../contents/ui/CostPresentation.js" as CostPresentation
import "../contents/ui/components" as Components

TestCase {
    id: testCase
    name: "PanelText"

    property var currentItem: null
    readonly property string liveText: presentation.fullText(
        presentation.segments(currentItem, true, false, "43% used", false))
    readonly property string liveTooltip: presentation.toolTipText([], "Error")

    Components.PanelText {
        id: presentation
        numberFormat: CostPresentation.numberFormat(",", ".")
        function i18n(source) {
            var text = source;
            for (var i = 1; i < arguments.length; i++) {
                text = text.replace("%" + i, String(arguments[i]));
            }
            return text;
        }
    }

    function init() {
        failOnWarning(/.*/);
        presentation.loading = false;
        presentation.usageBarsShowUsed = true;
        presentation.showProvider = true;
        presentation.showPercent = true;
        presentation.showCredits = true;
        currentItem = null;
    }

    function item(credits) {
        return {provider: "unknown-provider", title: "Example", credits: credits,
            hasIncident: false, statusKnown: true, status: ""};
    }

    function test_segmentsKeepDisplayOrderAndRecoverableIdentity() {
        var provider = item(1234);
        var before = JSON.stringify(provider);
        var segments = presentation.segments(provider, true, false, "43% used", false);
        compare(segments.length, 3);
        compare(segments[0].id, "name");
        compare(segments[0].identifying, true);
        compare(segments[1].id, "usage");
        compare(segments[2].id, "credits");
        compare(presentation.fullText(segments), "Example 43% used 1,234cr");
        compare(PanelTextFit.segmentTexts(segments)[1], "Example 43% used");
        compare(JSON.stringify(provider), before);
        segments = presentation.segments(provider, true, false, "43% used", true);
        compare(segments[0].identifying, false);
        compare(PanelTextFit.segmentTexts(segments)[1], "43% used 1,234cr");
    }

    function test_displayModesKeepTheirSelectedRowAndFallbacks() {
        var row = {hasPercent: true, usedPercent: 43, leftPercent: 57,
            pacePercent: 60, paceOnTop: true};
        compare(presentation.displayText(row, "percent", "Reset", "ETA"), "43% used");
        compare(presentation.displayText(row, "pace", "Reset", "ETA"), "60% used at pace");
        compare(presentation.displayText(row, "both", "Reset", "ETA"), "43% used - 60% used at pace");
        compare(presentation.displayText(row, "resetTime", "Reset", "ETA"), "Reset");
        compare(presentation.displayText(row, "runOut", "Reset", "ETA"), "ETA");
        compare(presentation.displayText(row, "unknown", "", ""), "43% used");
        presentation.usageBarsShowUsed = false;
        compare(presentation.displayText(row, "both", "", ""), "57% left - 40% left at pace");
        row.paceOnTop = false;
        compare(presentation.displayText(row, "pace", "", ""), "40% left, behind pace");
        row.hasPercent = false;
        compare(presentation.displayText(row, "both", "", ""), "40% left, behind pace");
        row.pacePercent = -1;
        compare(presentation.displayText(row, "both", "", ""), "");
        compare(presentation.displayText(null, "percent", "", ""), "");
        compare(presentation.displayText(null, "pace", "", ""), "");
    }

    function test_bindingsFollowSettingsAndLoadingWithoutRecreatingTheComponent() {
        compare(liveText, "CodexBar");
        compare(liveTooltip, "Error");
        presentation.loading = true;
        compare(liveText, "Loading");
        compare(liveTooltip, "Refreshing usage…");
        currentItem = item(125);
        compare(liveText, "Example 43% used 125cr");
        presentation.showCredits = false;
        compare(liveText, "Example 43% used");
        presentation.showProvider = false;
        compare(liveText, "43% used");
        presentation.showPercent = false;
        compare(liveText, "");
    }

    function test_emptyRosterFallback_data() {
        return [
            {tag: "automatic", loading: false, selection: false, visible: true, expected: "CodexBar"},
            {tag: "loading", loading: true, selection: false, visible: true, expected: "Loading"},
            {tag: "explicit-empty", loading: false, selection: true, visible: true, expected: ""},
            {tag: "explicit-loading", loading: true, selection: true, visible: true, expected: ""},
            {tag: "hidden", loading: false, selection: false, visible: false, expected: ""},
            {tag: "hidden-loading", loading: true, selection: false, visible: false, expected: ""}
        ];
    }

    function test_emptyRosterFallback(data) {
        presentation.loading = data.loading;
        compare(presentation.fullText(presentation.segments(null, data.visible,
            data.selection, "", false)), data.expected);
    }

    function test_settingsAndMissingFieldsKeepTheirExistingMeaning() {
        compare(presentation.segments(item(0), false, false, "43% used", false).length, 0);
        compare(presentation.fullText(presentation.segments(item(0), true, false, "", false)),
            "Example 0cr");
        compare(presentation.fullText(presentation.segments(item(null), true, false, "", false)),
            "Example");
        presentation.showProvider = false;
        presentation.showPercent = false;
        presentation.showCredits = false;
        compare(presentation.segments(item(1234), true, false, "43% used", false).length, 0);
        // Fallback identity remains one indivisible usage segment even with
        // every optional content setting disabled.
        var fallback = presentation.segments(null, true, false, "", false);
        compare(fallback.length, 1);
        compare(fallback[0].id, "usage");
        compare(fallback[0].text, "CodexBar");
    }

    function test_tooltipKeepsBalanceAndOnlyCurrentIncidents() {
        var provider = item(0);
        compare(presentation.providerToolTipText(null, ""), "");
        compare(presentation.providerToolTipText(provider, "Primary: 43% used"),
            "Example: Primary: 43% used. 0cr");
        provider.hasIncident = true;
        provider.status = "Provider <status> & text";
        compare(presentation.providerToolTipText(provider, "Last known usage"),
            "Example: Last known usage. 0cr - Provider <status> & text");
        provider.statusKnown = false;
        compare(presentation.providerToolTipText(provider, ""), "Example: 0cr");
        provider.statusKnown = true;
        presentation.showCredits = false;
        compare(presentation.providerToolTipText(provider, ""), "Example: Provider <status> & text");
        provider.hasIncident = false;
        compare(presentation.providerToolTipText(provider, ""), "");
        provider.credits = undefined;
        presentation.showCredits = true;
        compare(presentation.providerToolTipText(provider, ""), "");
    }

    function test_tooltipBoundsLinesAndDoesNotMutateItsInputs() {
        var lines = ["One", "Two", "Three", "Four", "Five", "Six", "Seven"];
        var before = JSON.stringify(lines);
        compare(presentation.toolTipText(lines, "Error"), "One\nTwo\nThree\nFour\nFive\nSix");
        presentation.loading = true;
        compare(presentation.toolTipText(lines, "Error"),
            "One\nTwo\nThree\nFour\nFive\nSix\nRefreshing usage…");
        compare(presentation.toolTipText([], "Error"), "Refreshing usage…");
        presentation.loading = false;
        compare(presentation.toolTipText([], "Error"), "Error");
        compare(presentation.toolTipText([], ""), "");
        compare(JSON.stringify(lines), before);
    }

    function test_purePlansDoNotMutateNormalizedProviders() {
        var provider = item(125);
        provider.hasIncident = true;
        provider.status = "Incident";
        var before = JSON.stringify(provider);
        var plan = PanelTextPlan.providerTooltip(provider, "Description", true);
        compare(plan.incident, "Incident");
        compare(plan.credits, 125);
        compare(PanelTextPlan.providerTooltip(provider, "Description", false).credits, null);
        compare(JSON.stringify(provider), before);
        compare(PanelTextPlan.providerTooltip(null, "Description", true), null);
    }
}
