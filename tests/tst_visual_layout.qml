import QtQuick
import QtTest
import "../contents/ui/components" as Components
import "../contents/ui/CostPresentation.js" as CostPresentation
import "../contents/ui/SafeText.js" as SafeText
import "../contents/ui/ThemeContrast.js" as ThemeContrast
import "../contents/ui/UsageDetails.js" as UsageDetails
import "fixtures/ProviderUiStress.js" as ProviderUiStress

TestCase {
    id: testCase
    name: "VisualLayout"
    when: windowShown
    width: 620
    height: 240
    visible: true
    property var holders: []

    Components.UsageWindowText {
        id: usageLabels
        function i18n(source) {
            for (var i = 1; i < arguments.length; i++)
                source = source.replace("%" + i, String(arguments[i]));
            return source;
        }
    }

    QtObject {
        id: applet
        property bool verticalFormFactor: false
        property bool minimalPanel: false
        property bool quotaWarning: false
        property bool dualQuota: true
        property int meterCount: 2
        property real firstQuota: 57
        property bool secondaryWarning: false
        property color brandAccent: Qt.rgba(0.2, 0.6, 0.7, 1)
        property bool loading: false
        property bool expanded: false
        property bool privacyMode: false
        property bool costHistoryShowsTokens: false
        property string openedProvider: ""
        property real secondaryTextOpacity: 0.7
        property real valueTextOpacity: 0.85
        property var sessions: []
        readonly property var presentedSessions: sessions
        property bool sessionsLoading: false
        property string sessionsLastUpdatedText: ""
        property string sessionsErrorText: "Loading sessions timed out. Try again."
        property string selectedAccount: ""
        property string selectedProviderID: "codex"
        property var providerListFocus: null
        property int providerToggleCount: 0
        property bool providerEnabled: false
        property bool incidentOnMeter: true
        property bool metersHidden: false
        function isPending() {
            return false;
        }
        function visualEnabled() {
            return providerEnabled;
        }
        function setEnabled(providerID, enabled) {
            providerToggleCount++;
            providerEnabled = enabled;
        }
        property var accountItems: [
            {
                provider: "codex",
                account: "engineering-with-an-unusually-long-account-name@example.com",
                subtitle: "Workspace with a long display name for the example team"
            },
            {
                provider: "codex",
                account: "demo@example.com",
                subtitle: ""
            }
        ]
        function accountOptionsForProvider() {
            return accountItems;
        }
        function accountLoadingForProvider() {
            return false;
        }
        function accountErrorForProvider() {
            return "";
        }
        function accountNoticeForProvider() {
            return "named";
        }
        function selectedAccountForProvider() {
            return selectedAccount;
        }
        function accountLabel(item) {
            return item.account;
        }
        function accountKey(item) {
            return item.accountKey || item.account;
        }
        function accountDisplayLabel(item, index) {
            return accountLabel(item);
        }
        function providerPresentation(item) {
            return item;
        }
        function privateErrorText(text) {
            return text;
        }
        function amountString(value, currency) {
            return currency + " " + value;
        }
        function qualifiedCostValue(value) {
            return value;
        }
        function usageCountText(value) {
            return String(value);
        }
        function providerDisplayTitle(providerID) {
            return providerID;
        }
        function accountSubtitle(item) {
            return item.subtitle;
        }
        function accountIsSelected(item) {
            return item.account === selectedAccount;
        }
        function selectAccount(providerID, label) {
            selectedAccount = label;
        }
        function refreshSessions() {
        }
        property var panelOrder: ["identity", "status", "text", "meters"]
        function panelElementOrder() {
            return panelOrder;
        }
        property string providerNameText: "A long provider name"
        property string usageText: "57% remaining"
        property string creditsText: ""
        function compactTextSegments() {
            var segments = [];
            if (providerNameText.length > 0)
                segments.push({id: "name", text: providerNameText});
            if (usageText.length > 0)
                segments.push({id: "usage", text: usageText});
            if (creditsText.length > 0)
                segments.push({id: "credits", text: creditsText});
            return segments;
        }
        function compactText() {
            return compactTextSegments().map(segment => segment.text).join(" ");
        }
        function usageProviders() {
            return [
                {
                    provider: "codex",
                    title: "Codex",
                    value: firstQuota,
                    hasIncident: incidentOnMeter,
                    statusKnown: true,
                    statusSeverity: "minor",
                    status: "Degraded"
                },
                {
                    provider: "claude",
                    title: "Claude",
                    value: 0
                }
            ].concat(Array.from({length: Math.max(0, meterCount - 2)}, (_, index) => ({
                provider: "example-" + index, title: "Example " + index, value: 25
            })));
        }
        function compactProviders() {
            if (metersHidden) {
                return [];
            }
            return usageProviders();
        }
        function selectedCompactProvider() {
            var providers = usageProviders();
            for (var i = 0; i < providers.length; i++) {
                if (providers[i].provider === selectedProviderID) {
                    return providers[i];
                }
            }
            return null;
        }
        function primaryIncidentProvider() {
            // "gemini" never carries a meter, so it exercises the standalone
            // status element that must remain when no meter can badge it.
            return incidentOnMeter
                ? {provider: "codex", hasIncident: true, statusSeverity: "minor",
                   statusKnown: true, title: "Codex", status: "Degraded"}
                : {provider: "gemini", hasIncident: true, statusSeverity: "major",
                   statusKnown: true, title: "Gemini", status: "Degraded"};
        }
        function providerIconSource() {
            return "view-statistics";
        }
        function providerIconIsMask() {
            return true;
        }
        function providerReadableColor() {
            return brandAccent;
        }
        function statusBadgeColor() {
            return Qt.rgba(1, 0.5, 0, 1);
        }
        function switcherPercent(item) {
            return item.value;
        }
        function switcherMetricRow(item) {
            return item;
        }
        function panelDisplayRow(item, mode) {
            return item;
        }
        function panelMeterRows(item) {
            return dualQuota ? [item, {value: 70}] : [item];
        }
        function panelMeterDescription(item) {
            return "Primary: " + item.value + "% used. Secondary: 70% used";
        }
        function displayPercent(row) {
            return row.value;
        }
        property bool showPopupPace: true
        property real meterTrackHeight: 8
        property real compactMeterTrackHeight: 5
        function usageResetText(row) {
            return row.reset || "";
        }
        function resetLabel(value) {
            return value;
        }
        function usagePaceText(row) {
            return row.pace || "";
        }
        function paceMarkerPercent(row) {
            return row.pacePercent !== undefined ? row.pacePercent : -1;
        }
        function quotaWarningMarkers(row) {
            return row.warningMarkers || [];
        }
        property var hiddenUsageRowRequest: null
        function popupDetailSectionHideable(section) { return section.title.length > 0; }
        function hidePopupDetailSection(providerID, section) {}
        function popupUsageRowHideable(row) {
            return row.lane === "primary";
        }
        function hidePopupUsageRow(providerID, row) {
            hiddenUsageRowRequest = {provider: providerID, label: row.label};
        }
        function usagePercentText(row) { return usageLabels.percentText(row, false); }
        function usageConfidenceText(row) { return usageLabels.confidenceText(row); }
        function quotaMeterColor(item, accent) {
            return quotaWarning || (secondaryWarning && item.value === 70) ? Qt.rgba(1, 0.5, 0, 1) : accent;
        }
        function quotaSeverity(item) {
            return quotaWarning || (secondaryWarning && item.value === 70) ? "major" : "";
        }
        function withAlpha(c, a) {
            return Qt.rgba(c.r, c.g, c.b, a);
        }
        property real nestedSurfaceRadius: 4
        property bool sessionHostsVary: false
        function capitalize(value) {
            return value;
        }
        function elapsedText() {
            return "Just now";
        }
        function openProviderFromPanel(id) {
            openedProvider = id;
            expanded = true;
        }
        property string hoveredPanelProviderID: ""
        function setHoveredPanelProvider(providerID) {
            hoveredPanelProviderID = String(providerID || "");
        }
        function clearHoveredPanelProvider(providerID) {
            var id = String(providerID || "");
            if (hoveredPanelProviderID === id) {
                hoveredPanelProviderID = "";
            }
        }
        function panelProviderToolTipText(item) {
            if (!item) {
                return "";
            }
            return item.title + ": " + panelMeterDescription(item);
        }
        function canvasColor(c, a) {
            return Qt.rgba(c.r, c.g, c.b, a).toString();
        }
    }

    function createControl(type, properties, parent) {
        var holder;
        try {
            holder = Qt.createQmlObject('import QtQuick; import "../contents/ui/components" as Components; QtObject { property Component control: Component { Components.' + type
                + ' { function i18n(text) { for (var i = 1; i < arguments.length; i++) text = text.replace("%" + i, String(arguments[i])); return text }'
                + ' function i18np(one, many, count) { return count === 1 ? one : many } } } }', testCase, Qt.resolvedUrl("VisualLayoutTest.qml"));
        } catch (error) {
            if (/module "org\.kde\.(kirigami|plasma\.components)" is not installed/.test(String(error))) {
                skip("Visual layout checks need the optional KDE QML modules");
                return null;
            }
            throw error;
        }
        holders.push(holder);
        return createTemporaryObject(holder.control, parent || testCase, properties);
    }

    function cleanupTestCase() {
        for (var i = 0; i < holders.length; i++)
            holders[i].destroy();
    }

    function init() {
        applet.sessions = [];
        applet.privacyMode = false;
        applet.expanded = false;
        applet.openedProvider = "";
        applet.hoveredPanelProviderID = "";
        applet.dualQuota = true;
        applet.meterCount = 2;
        applet.firstQuota = 57;
        applet.secondaryWarning = false;
        applet.brandAccent = Qt.rgba(0.2, 0.6, 0.7, 1);
        applet.minimalPanel = false;
        applet.quotaWarning = false;
        applet.verticalFormFactor = false;
        applet.costHistoryShowsTokens = false;
        applet.selectedProviderID = "codex";
        applet.incidentOnMeter = true;
        applet.metersHidden = false;
        applet.loading = false;
        applet.panelOrder = ["identity", "status", "text", "meters"];
        applet.providerNameText = "A long provider name";
        applet.usageText = "57% remaining";
        applet.creditsText = "";
    }

    function test_minimalPanelAppearance_data() {
        return [
            {tag: "small", extent: 32},
            {tag: "normal", extent: 44},
            {tag: "large", extent: 60}
        ];
    }

    function test_minimalPanelAppearance(data) {
        var panel = createControl("CompactRepresentation", {applet: applet, height: data.extent});
        if (!panel)
            return;
        wait(0);
        var standardBarHeight = panel.meterBarHeight;
        var standardIconSize = panel.meterIconSize;
        var icon = findItem(panel, item => item.objectName === "panelProviderIcon");
        var track = findItem(panel, item => item.objectName === "panelMeterTrack");
        var fill = findItem(panel, item => item.objectName === "panelMeterFill");
        verify(icon !== null && track !== null && fill !== null);
        var brandColor = icon.color.toString();
        applet.minimalPanel = true;
        tryCompare(panel, "minimalStyle", true);
        compare(panel.meterBarHeight, standardBarHeight);
        verify(panel.meterIconSize <= 22);
        verify(panel.meterWidth >= 36);
        verify(icon.isMask);
        verify(icon.color.toString() !== brandColor);
        tryVerify(() => track.width <= panel.meterWidth);
        // Presentation must still defer to the same semantic warning color.
        applet.quotaWarning = true;
        tryCompare(fill, "color", Qt.rgba(1, 0.5, 0, 1));
        verify(icon.color.toString() !== fill.color.toString());
        // Minimal style promises capsules in the theme text color, so the
        // warning-hue muting never rewrites them: the capsule keeps the same
        // accent the minimal mode selected.
        applet.quotaWarning = false;
        applet.brandAccent = Qt.rgba(0.95, 0.45, 0.1, 1);
        wait(0);
        var meter = findItem(panel, item => item.modelData && item.modelData.provider === "codex");
        verify(meter !== null);
        compare(fill.color, meter.accent);
        applet.brandAccent = Qt.rgba(0.2, 0.6, 0.7, 1);
        wait(0);
        applet.minimalPanel = false;
        tryCompare(panel, "meterBarHeight", standardBarHeight);
        compare(panel.meterIconSize, standardIconSize);
        compare(icon.color.toString(), brandColor);
    }

    function findItem(item, predicate) {
        if (predicate(item))
            return item;
        var children = item.children || [];
        for (var i = 0; i < children.length; i++) {
            var found = findItem(children[i], predicate);
            if (found)
                return found;
        }
        return null;
    }

    // Non-visual children (tooltips live in resources/data, not children),
    // so tooltip hunts need the whole object tree. findItem is left on
    // children alone; existing first-match callers keep their order.
    function findAllItems(item, predicate, out) {
        if (item === null || item === undefined || out.indexOf(item) >= 0)
            return;
        if (predicate(item))
            out.push(item);
        var groups = [item.children, item.resources, item.data];
        for (var g = 0; g < groups.length; g++) {
            var kids = groups[g];
            if (kids === undefined || kids === null)
                continue;
            for (var i = 0; i < kids.length; i++)
                findAllItems(kids[i], predicate, out);
        }
    }

    function test_selectedTextStaysWithItsMeterAndFits_data() {
        return [
            {tag: "standard-small", minimal: false, extent: 24},
            {tag: "minimal-small", minimal: true, extent: 24},
            {tag: "standard", minimal: false, extent: 44},
            {tag: "minimal", minimal: true, extent: 44}
        ];
    }

    function test_selectedTextStaysWithItsMeterAndFits(data) {
        applet.minimalPanel = data.minimal;
        var panel = createControl("CompactRepresentation", {applet: applet, height: data.extent});
        if (!panel) return;
        verify(panel.inlinePrimaryText && !panel.showPrimaryIdentity);
        for (var id of ["codex", "claude"]) {
            applet.selectedProviderID = id;
            wait(0);
            var meter = findItem(panel, item => item.modelData && item.modelData.provider === id);
            var label = findItem(meter, item => item.objectName === "panelProviderText");
            var track = findItem(meter, item => item.objectName === "panelMeterTrack");
            verify(label.visible && label.width > 0);
            tryVerify(() => track.mapToItem(panel, track.width, 0).x < label.mapToItem(panel, 0, 0).x, 1000,
                JSON.stringify({id: id, track: track.mapToItem(panel, track.width, 0), text: label.mapToItem(panel, 0, 0), width: label.width}));
            verify(label.mapToItem(panel, label.width, 0).x <= panel.width);
            verify(label.mapToItem(panel, 0, 0).y >= 0);
            verify(label.mapToItem(panel, 0, label.height).y <= panel.height);
            verify(meter.Accessible.description.indexOf(applet.compactText()) >= 0);
            applet.openedProvider = "";
            mouseClick(label, label.width / 2, label.height / 2);
            compare(applet.openedProvider, id);
        }
        applet.verticalFormFactor = true;
        tryCompare(panel, "inlinePrimaryText", false);
        verify(!panel.showPrimaryIdentity);
    }

    function test_standaloneIdentityActivation_data() {
        var cases = [];
        for (var open of [false, true]) {
            for (var provider of ["codex", "missing"]) {
                for (var key of [0, Qt.Key_Space, Qt.Key_Return]) {
                    cases.push({tag: provider + "-" + open + "-" + key,
                        open: open, provider: provider, key: key});
                }
            }
        }
        return cases;
    }

    function test_standaloneIdentityActivation(data) {
        applet.metersHidden = true;
        applet.selectedProviderID = data.provider;
        applet.openedProvider = "claude";
        applet.expanded = data.open;
        var panel = createControl("CompactRepresentation", {applet: applet, height: 44});
        if (!panel) return;
        wait(0);
        var icon = findItem(panel, item => item.objectName === "panelIdentityIcon");
        verify(icon !== null && icon.visible);
        var focusBorder = findItem(panel, item => item.objectName === "panelIdentityFocusBorder");
        verify(focusBorder !== null);
        verify(!focusBorder.visible);
        if (data.key === 0) {
            mouseClick(icon, icon.width / 2, icon.height / 2);
            verify(!focusBorder.visible);
        } else {
            verify(icon.parent.activeFocusOnTab);
            icon.parent.forceActiveFocus(Qt.TabFocusReason);
            verify(focusBorder.visible);
            keyClick(data.key);
        }
        compare(applet.openedProvider, data.provider === "codex" ? "codex" : "claude");
        compare(applet.expanded, data.provider === "codex" ? true : !data.open);
    }

    function test_standaloneIdentityPreviewDoesNotActivate() {
        applet.metersHidden = true;
        applet.openedProvider = "claude";
        applet.expanded = false;
        var panel = createControl("CompactRepresentation", {applet: applet, height: 44, interactive: false});
        if (!panel) return;
        wait(0);
        var icon = findItem(panel, item => item.objectName === "panelIdentityIcon");
        verify(icon !== null && icon.visible);
        verify(!icon.parent.activeFocusOnTab);
        var focusBorder = findItem(panel, item => item.objectName === "panelIdentityFocusBorder");
        verify(focusBorder !== null);
        mouseClick(icon, icon.width / 2, icon.height / 2);
        icon.parent.forceActiveFocus();
        verify(!focusBorder.visible);
        keyClick(Qt.Key_Space);
        compare(applet.openedProvider, "claude");
        verify(!applet.expanded);
    }

    function test_crowdedMeterRowsRetainStandaloneText() {
        var panel = createControl("CompactRepresentation", {applet: applet, height: 44});
        if (!panel) return;
        verify(panel.inlinePrimaryText);
        // The live adapter caps meters at four. Stress the renderer's zero-width
        // boundary independently of that cap and the active theme's dimensions.
        applet.meterCount = Math.ceil(panel.maximumCompactWidth / panel.meterWidth) + 1;
        tryCompare(panel, "inlinePrimaryText", false);
        compare(panel.inlineTextWidth, 0);
        verify(panel.showPrimaryIdentity);
        var label = findItem(panel, item => item.objectName === "panelStandaloneText");
        tryVerify(() => label.visible && label.width > 0);
        // Nothing fits at this boundary, so the renderer keeps its last resort:
        // the most important single segment, elided, never an empty label.
        compare(label.text, panel.primaryText);
        compare(label.text, applet.usageText);
        // The surrendered segments stay available to assistive technology.
        compare(label.Accessible.name, applet.compactText());
        verify(label.mapToItem(panel, 0, 0).x >= 0);
        verify(label.mapToItem(panel, label.width, 0).x <= panel.width);
        applet.meterCount = 2;
        tryCompare(panel, "inlinePrimaryText", true);
        verify(!panel.showPrimaryIdentity);
        tryVerify(() => !label.visible);
    }

    // The panel budget is fixed, so enabling every content switch on a crowded
    // meter row asks for more width than the row has. Whole segments must be
    // surrendered by priority: a rendered label that elides turns a complete
    // value into a fragment that reads as a different one.
    function test_crowdedPanelTextDropsSegmentsInsteadOfEliding_data() {
        return [
            {tag: "inline", order: ["identity", "status", "text", "meters"]},
            {tag: "standalone", order: ["identity", "text", "status", "meters"]}
        ];
    }

    function test_crowdedPanelTextDropsSegmentsInsteadOfEliding(data) {
        applet.panelOrder = data.order;
        applet.creditsText = "1,250cr";
        var panel = createControl("CompactRepresentation", {applet: applet, height: 44});
        if (!panel) return;

        // Four meters is the cap the live adapter renders.
        for (var count = 1; count <= 4; count++) {
            applet.meterCount = count;
            wait(0);
            var label = findItem(panel, item => item.visible
                && (item.objectName === "panelProviderText" || item.objectName === "panelStandaloneText"));
            tryVerify(() => label && label.visible && label.width > 0, 1000, "count " + count);
            var message = JSON.stringify({count: count, text: label.text, width: label.width,
                compositions: panel.textCompositions, widths: panel.textCompositionWidths,
                budget: panel.inlineTextBudget, standalone: panel.standaloneTextBudget,
                panelWidth: panel.width, x0: label.mapToItem(panel, 0, 0).x,
                x1: label.mapToItem(panel, label.width, 0).x, inline: panel.inlinePrimaryText});
            // Eliding is the last resort, reached only when no composition fits.
            tryVerify(() => !label.truncated
                || panel.textCompositionIndex === panel.textCompositions.length - 1,
                1000, "elided: " + message);
            // Only whole segments are surrendered, and the usage figure is kept.
            verify(panel.textCompositions.indexOf(label.text) >= 0, "composition: " + message);
            verify(label.text.indexOf(applet.usageText) >= 0, "usage: " + message);
            compare(label.Accessible.name, applet.compactText());
            tryVerify(() => label.mapToItem(panel, label.width, 0).x <= panel.width,
                1000, "fits: " + message);
        }

        // The full composition survives once the row leaves room for it again.
        applet.providerNameText = "Codex";
        applet.meterCount = 1;
        tryCompare(panel, "primaryText", applet.compactText());
    }

    // Grows the usage segment until the full composition is as wide as the
    // budget allows, so the next character would no longer fit.
    function fillTextToBudget(panel, budget) {
        var filler = "";
        for (var i = 0; i < 200; i++) {
            applet.usageText = filler + "W";
            wait(0);
            if (panel.textCompositionWidths[0] > budget) {
                break;
            }
            filler = applet.usageText;
        }
        applet.usageText = filler;
        wait(0);
        return filler.length > 0;
    }

    // The budget stands in for the layout the panel has not built yet, so it
    // has to agree with that layout in both directions. Reserving too little
    // clips the row; reserving too much surrenders content while the space is
    // free, which is the defect this whole path exists to prevent. The layout
    // skips hidden elements, so each reserved gap must belong to a neighbour
    // that is actually rendered.
    function test_standaloneTextBudgetMatchesTheRenderedRow_data() {
        return [
            {tag: "meters hidden", metersHidden: true},
            {tag: "meters shown", metersHidden: false}
        ];
    }

    function test_standaloneTextBudgetMatchesTheRenderedRow(data) {
        applet.metersHidden = data.metersHidden;
        applet.panelOrder = ["identity", "text", "status", "meters"];
        // Short fixed segments leave the usage segment room to grow into the
        // budget; the point is the last pixel, not a long name.
        applet.providerNameText = "Codex";
        applet.creditsText = "9cr";
        applet.usageText = "43% used";
        var panel = createControl("CompactRepresentation", {applet: applet, height: 44});
        if (!panel) return;
        tryCompare(panel, "inlinePrimaryText", false);

        // What the row spends on everything except the text, measured from the
        // rendered layout rather than from the budget's own arithmetic. While
        // the row is below the cap its width is the layout's own request, so
        // the free space left for text follows without repeating the formula.
        // The comparison retries because the row settles over several frames.
        tryVerify(() => panel.desiredWidth < panel.maximumCompactWidth
            && panel.primaryTextWidth > 0
            && panel.primaryText === applet.compactText()
            && panel.standaloneTextBudget
                === panel.maximumCompactWidth - (panel.desiredWidth - panel.primaryTextWidth),
            2000, "the standalone budget must equal the row's free space");

        // The last pixel of that budget must also survive the real layout.
        verify(fillTextToBudget(panel, panel.standaloneTextBudget));
        var label = findItem(panel, item => item.visible && item.objectName === "panelStandaloneText");
        tryVerify(() => label && label.visible && label.width > 0);
        var message = JSON.stringify({text: label.text, width: label.width,
            widths: panel.textCompositionWidths, budget: panel.standaloneTextBudget,
            panelWidth: panel.width, maximum: panel.maximumCompactWidth});
        // Reserved too much: a composition inside the budget was surrendered.
        tryCompare(panel, "primaryText", applet.compactText(), 1000, "surrendered: " + message);
        // Reserved too little: the row outgrew the panel and is being cut.
        tryVerify(() => !label.truncated, 1000, "elided: " + message);
        tryVerify(() => label.mapToItem(panel, label.width, 0).x <= panel.width,
            1000, "clipped: " + message);
    }

    // The chosen composition index and the arrays it addresses are separate
    // bindings. A configuration change re-evaluates them in either order, so an
    // intermediate frame can index past a list that already shrank; the width
    // it produces must stay an int, not undefined.
    function test_staleCompositionIndexNeverYieldsUndefinedGeometry() {
        var panel = createControl("CompactRepresentation", {applet: applet, height: 44});
        if (!panel) return;
        for (var index of [-1, 1.5, 99, NaN, undefined]) {
            compare(panel.compositionText(index), "");
            compare(panel.compositionWidth(index), 0);
        }

        applet.providerNameText = "";
        applet.usageText = "";
        applet.creditsText = "";
        tryCompare(panel, "primaryText", "");
        compare(panel.primaryTextWidth, 0);
        compare(panel.inlineTextWidth, 0);
        compare(panel.inlinePrimaryText, false);

        applet.usageText = "57% remaining";
        tryCompare(panel, "primaryText", "57% remaining");
        verify(panel.primaryTextWidth > 0);
    }

    function test_emptyQuotaRetainsWarningColor_data() {
        return [{tag: "standard", minimal: false}, {tag: "minimal", minimal: true}];
    }

    function test_emptyQuotaRetainsWarningColor(data) {
        applet.minimalPanel = data.minimal;
        applet.quotaWarning = true;
        var panel = createControl("CompactRepresentation", {applet: applet, height: 44});
        if (!panel)
            return;
        wait(0);
        var meter = findItem(panel, item => item.modelData && item.modelData.provider === "claude");
        verify(meter !== null);
        var track = findItem(meter, item => item.objectName === "panelMeterTrack");
        var fill = findItem(meter, item => item.objectName === "panelMeterFill");
        verify(track !== null && fill !== null);
        tryCompare(fill, "width", 0);
        compare(track.color, Qt.rgba(1, 0.5, 0, 0.32));
    }

    function test_capsulesKeepGeometryAndAccurateSmallFills() {
        var panel = createControl("CompactRepresentation", {applet: applet, height: 32});
        if (!panel) return;
        wait(0);
        var meter = findItem(panel, item => item.modelData && item.modelData.provider === "codex");
        var icon = findItem(meter, item => item.objectName === "panelProviderIcon");
        var track = findItem(meter, item => item.objectName === "panelMeterTrack");
        var fill = findItem(track, item => item.objectName === "panelMeterFill");
        verify(icon.mapToItem(meter, icon.width, 0).x < track.mapToItem(meter, 0, 0).x);
        tryVerify(() => Math.abs(fill.width / track.width - 0.57) < 0.01);
        applet.firstQuota = 1;
        wait(0);
        meter = findItem(panel, item => item.modelData && item.modelData.provider === "codex");
        track = findItem(meter, item => item.objectName === "panelMeterTrack");
        fill = findItem(track, item => item.objectName === "panelMeterFill");
        // A small non-zero quota stays visible as a round dot.
        tryCompare(fill, "width", track.height);
        applet.secondaryWarning = true;
        wait(0);
        verify(fill.color.toString() !== "#ff8000");
        var warning = findItem(meter, item => item.objectName === "panelMeterFill" && item.color.toString() === "#ff8000");
        verify(warning !== null);
        var width = panel.width;
        applet.dualQuota = false;
        wait(0);
        compare(panel.width, width);
        track = findItem(meter, item => item.objectName === "panelMeterTrack");
        tryVerify(() => Math.abs(track.mapToItem(meter, 0, track.height / 2).y - meter.height / 2) < 1);
        verify(meter.Accessible.description.indexOf("Primary") >= 0);
    }

    // A brand hue close to the warning color would make a healthy capsule read
    // as an alert, so the capsule uses a muted brand color. The provider icon
    // keeps the brand color, and distinct brand hues stay unchanged.
    function test_capsulesMuteBrandColorsCloseToWarnings() {
        applet.brandAccent = Qt.rgba(0.95, 0.45, 0.1, 1);
        var panel = createControl("CompactRepresentation", {applet: applet, height: 32});
        if (!panel) return;
        wait(0);
        var meter = findItem(panel, item => item.modelData && item.modelData.provider === "codex");
        var icon = findItem(meter, item => item.objectName === "panelProviderIcon");
        var fill = findItem(meter, item => item.objectName === "panelMeterFill");
        compare(icon.color, applet.brandAccent);
        verify(!Qt.colorEqual(fill.color, applet.brandAccent));
        var muted = ThemeContrast.oklch(fill.color);
        verify(muted.chroma < ThemeContrast.minimumHueChroma);
        verify(ThemeContrast.hueDistance(muted.hue, ThemeContrast.oklch(applet.brandAccent).hue) < 10);
        // A fixed reduction is not enough for very saturated brands; the
        // panel asks ThemeContrast for the share its chroma needs.
        applet.brandAccent = Qt.rgba(1, 0.35, 0, 1);
        wait(0);
        verify(ThemeContrast.oklch(fill.color).chroma < ThemeContrast.minimumHueChroma);
        applet.brandAccent = Qt.rgba(0.2, 0.6, 0.7, 1);
        wait(0);
        fill = findItem(meter, item => item.objectName === "panelMeterFill");
        compare(fill.color, applet.brandAccent);
    }

    function test_sessionFeedbackKeepsHeadingAtTop_data() {
        return [
            {
                tag: "error",
                loading: false,
                errorText: "Loading sessions timed out. Try again."
            },
            {
                tag: "empty",
                loading: false,
                errorText: ""
            },
            {
                tag: "loading",
                loading: true,
                errorText: ""
            }
        ];
    }

    function test_sessionFeedbackKeepsHeadingAtTop(data) {
        applet.sessionsErrorText = data.errorText;
        applet.sessionsLoading = data.loading;
        var view = createControl("SessionsView", {
            applet: applet,
            width: 540,
            height: 300
        });
        if (!view)
            return;
        wait(0);
        var heading = findItem(view, function (item) {
            return item.text === "Sessions";
        });
        verify(heading !== null);
        verify(heading.mapToItem(view, 0, 0).y < 40);
        if (data.errorText.length > 0) {
            var error = findItem(view, function (item) {
                return item.visible && item.plainText === applet.sessionsErrorText;
            });
            verify(error !== null);
            verify(error.mapToItem(view, 0, 0).y < 100);
        } else if (!data.loading) {
            var placeholder = findItem(view, function (item) {
                return item.visible && item.plainText === "No local agent sessions found";
            });
            verify(placeholder !== null);
            compare(placeholder.height, placeholder.implicitHeight);
        }
    }

    // A session card offers one copy action, for its title, placed beside the
    // title text. Session state reads the same for every provider: a live one
    // uses the theme's positive color, never the provider accent.
    function test_sessionCardCopiesTheTitleAndColorsStateByMeaning_data() {
        return [
            {tag: "active", state: "active", label: "Active"},
            {tag: "running", state: "running", label: "Running"},
            {tag: "working", state: "working", label: "Working"}
        ];
    }

    function test_sessionCardCopiesTheTitleAndColorsStateByMeaning(data) {
        applet.sessionsErrorText = "";
        applet.sessionsLoading = false;
        applet.sessions = [
            {provider: "claude", projectName: "CodexBar Plasma", sessionName: "", host: "",
             state: data.state, source: "cli", activityMs: 1},
            {provider: "codex", projectName: "docs", sessionName: "", host: "",
             state: "idle", source: "cli", activityMs: 1}
        ];
        var view = createControl("SessionsView", {
            applet: applet,
            width: 540,
            height: 300
        });
        if (!view)
            return;
        wait(0);
        var buttons = [];
        findAllItems(view, function (item) {
            return item.visible && item.icon !== undefined && item.icon.name === "edit-copy";
        }, buttons);
        compare(buttons.length, 2);
        var title = findItem(view, function (item) {
            return item.visible && item.elide !== undefined && item.text === "CodexBar Plasma";
        });
        verify(title !== null);
        verify(!title.truncated, "a short title was elided: " + title.width + " < " + title.implicitWidth);
        var firstButton = buttons.filter(function (button) {
            return Math.abs(button.mapToItem(view, 0, 0).y - title.mapToItem(view, 0, 0).y) < title.height;
        })[0];
        verify(firstButton !== undefined);
        var gap = firstButton.mapToItem(view, 0, 0).x - title.mapToItem(view, title.width, 0).x;
        verify(gap >= 0 && gap < 16, "copy action drifted away from the title: " + gap);

        var theme = Qt.createQmlObject('import QtQuick; import org.kde.kirigami as Kirigami; Item { readonly property color positive: Kirigami.Theme.positiveTextColor }', view);
        var active = findItem(view, function (item) {
            return item.visible && item.text === data.label;
        });
        var idle = findItem(view, function (item) {
            return item.visible && item.text === "Idle";
        });
        verify(active !== null && idle !== null);
        compare(active.color, theme.positive);
        verify(active.color !== applet.brandAccent);
        compare(idle.opacity, applet.secondaryTextOpacity);
    }

    function test_sessionRowsReserveSpaceIndependently_data() {
        return [
            {tag: "narrow", width: 240, privacy: false},
            {tag: "small", width: 320, privacy: false},
            {tag: "normal", width: 540, privacy: false},
            {tag: "wide", width: 900, privacy: false},
            {tag: "private", width: 240, privacy: true}
        ];
    }

    function test_sessionRowsReserveSpaceIndependently(data) {
        failOnWarning(/Binding loop|recursive rearrange/);
        applet.sessionsErrorText = "";
        applet.privacyMode = data.privacy;
        applet.sessions = [{provider: "codex", projectName: Array(15).join("Workspace "),
            sessionName: "", host: "", state: "idle", source: "cli", activityMs: 1}];
        var view = createControl("SessionsView", {applet: applet, width: data.width, height: 300});
        if (!view) return;
        waitForRendering(view);
        var title = findItem(view, function(item) {
            return item.visible && item.elide !== undefined && item.text === (data.privacy ? "Session 1" : applet.sessions[0].projectName);
        });
        var state = findItem(view, function(item) { return item.visible && item.text === "Idle"; });
        var subtitle = findItem(view, function(item) {
            return item.visible && item.elide !== undefined && item.text === "codex · Command line";
        });
        var age = findItem(view, function(item) { return item.visible && item.text === "Just now"; });
        verify(title !== null && state !== null && subtitle !== null && age !== null);
        var titleRow = title.parent;
        verify(titleRow.width > subtitle.width,
            "the age still takes space from the title above it");
        verify(title.mapToItem(view, title.width, 0).x <= state.mapToItem(view, 0, 0).x);
        verify(subtitle.mapToItem(view, subtitle.width, 0).x <= age.mapToItem(view, 0, 0).x);
        verify(state.mapToItem(view, state.width, 0).x < data.width);
        verify(age.mapToItem(view, age.width, 0).x < data.width);
        var originalTitleWidth = titleRow.width;

        // Unknown CLI states stay literal and bounded. They must not push the
        // title or copy action out of the card at a narrow width.
        var unknownState = Array(16).join("<state> & ");
        applet.sessions = [{provider: "codex", projectName: applet.sessions[0].projectName,
            sessionName: "", host: "", state: unknownState, source: "cli", activityMs: 1}];
        wait(0);
        if (data.privacy) {
            compare(state.text, "Unknown");
            return;
        }
        compare(state.text, unknownState);
        verify(state.truncated);
        verify(titleRow.width > 0 && titleRow.width < originalTitleWidth);
        verify(titleRow.mapToItem(view, titleRow.width, 0).x <= state.mapToItem(view, 0, 0).x);
        var tips = [];
        findAllItems(state, function(item) { return item.plainText !== undefined; }, tips);
        compare(tips.length, 1);
        var tip = tips[0];
        compare(tip.text, SafeText.plainTextAsRichText(unknownState));
        if (data.width > testCase.width) return;
        tip.delay = 0;
        mouseMove(state, state.width / 2, state.height / 2);
        tryCompare(tip, "visible", true);
        mouseMove(testCase, testCase.width - 1, testCase.height - 1);
    }

    function test_truncatedSessionMetadataRevealsLiteralText_data() {
        return [
            {tag: "named-project", projectName: "Project"},
            {tag: "session-title", projectName: ""}
        ];
    }

    function test_truncatedSessionMetadataRevealsLiteralText(data) {
        var longName = Array(12).join("<session> & name ");
        applet.sessions = [
            {provider: "claude", projectName: data.projectName, sessionName: longName, host: "",
             state: "active", source: longName, activityMs: Date.now()}
        ];
        var view = createControl("SessionsView", {applet: applet, width: 240, height: 300});
        if (!view) return;
        waitForRendering(view);
        var labels = [];
        findAllItems(view, function(item) {
            return item.visible && item.elide !== undefined && typeof item.text === "string"
                && item.text.indexOf(longName) >= 0;
        }, labels);
        compare(labels.length, 2);
        for (var label of labels) {
            verify(label.truncated);
            var tips = [];
            findAllItems(label, function(item) {
                return item.plainText !== undefined;
            }, tips);
            compare(tips.length, 1);
            var tip = tips[0];
            compare(tip.text, SafeText.plainTextAsRichText(label.text));
            tip.delay = 0;
            mouseMove(label, label.width / 2, label.height / 2);
            tryCompare(tip, "visible", true);
            mouseMove(testCase, testCase.width - 1, testCase.height - 1);
            tryCompare(tip, "visible", false);
        }
    }

    // An open Sessions tab rescans every 30 seconds and each scan delivers a
    // new array. Same-size rescans must update cards in place so hover and
    // keyboard focus survive, and relative ages must use the scan's clock.
    function test_sessionRescanKeepsCardsAndResyncsAges() {
        applet.sessionsErrorText = "";
        applet.sessionsLoading = false;
        applet.sessions = [
            {provider: "claude", projectName: "CodexBar Plasma", sessionName: "", host: "",
             state: "active", source: "cli", activityMs: Date.now()}
        ];
        var view = createControl("SessionsView", {
            applet: applet,
            width: 540,
            height: 300
        });
        if (!view)
            return;
        wait(0);
        var titleBefore = findItem(view, function (item) {
            return item.visible && item.elide !== undefined && item.text === "CodexBar Plasma";
        });
        verify(titleBefore !== null);
        var copyButton = findItem(view, function (item) {
            return item.visible && item.icon !== undefined && item.icon.name === "edit-copy";
        });
        verify(copyButton !== null);
        copyButton.forceActiveFocus(Qt.TabFocusReason);
        verify(copyButton.activeFocus);
        mouseMove(copyButton, copyButton.width / 2, copyButton.height / 2);
        tryCompare(copyButton, "hovered", true);
        view.sessionClockMs = 1;

        var rescannedAtMs = Date.now();
        applet.sessions = [
            {provider: "claude", projectName: "CodexBar Plasma", sessionName: "", host: "",
             state: "idle", source: "cli", activityMs: rescannedAtMs}
        ];
        wait(0);
        var titleAfter = findItem(view, function (item) {
            return item.visible && item.elide !== undefined && item.text === "CodexBar Plasma";
        });
        verify(titleAfter === titleBefore, "a same-size rescan rebuilt the session card");
        verify(copyButton.activeFocus, "a same-size rescan lost copy keyboard focus");
        compare(copyButton.hovered, true);
        verify(findItem(view, function (item) {
            return item.visible && item.text === "Idle";
        }) !== null, "the kept card did not show the rescanned state");
        verify(view.sessionClockMs >= rescannedAtMs, "the age clock lagged the rescanned data");

        // Count changes recreate the cards without evaluating a departing
        // card against a missing entry.
        failOnWarning(/TypeError|undefined/);
        applet.sessions = [
            {provider: "codex", projectName: "docs", sessionName: "", host: "",
             state: "idle", source: "cli", activityMs: rescannedAtMs},
            applet.sessions[0]
        ];
        wait(0);
        applet.sessions = [applet.sessions[1]];
        wait(0);
        var titles = [];
        findAllItems(view, function (item) {
            return item.visible && item.elide !== undefined
                && (item.text === "CodexBar Plasma" || item.text === "docs");
        }, titles);
        compare(titles.length, 1);
        compare(titles[0].text, "CodexBar Plasma");
        mouseMove(testCase, testCase.width - 1, testCase.height - 1);
        testCase.forceActiveFocus();
    }

    // CopyableValue labels its copy action through tooltips anchored to the
    // copy button, so a hostile accessible name must arrive escaped there
    // and the transient confirmation must keep its own immediate tooltip.
    function test_copyableValueTooltipsEscapeAndAnchorToButton() {
        var hostile = "Copy <img src=\"http://127.0.0.1/probe\"> & <sessions>";
        var row = createControl("CopyableValue", {
            text: "session text",
            copyAccessibleName: hostile
        });
        if (!row)
            return;
        var tips = [];
        findAllItems(row, function (item) {
            return item.toString().indexOf("PlainToolTip") >= 0;
        }, tips);
        var hoverTips = tips.filter(function (tip) { return tip.plainText === hostile; });
        var copiedTips = tips.filter(function (tip) { return tip.plainText === "Copied"; });
        compare(hoverTips.length, 1);
        compare(copiedTips.length, 1);
        var hoverTip = hoverTips[0];
        var copiedTip = copiedTips[0];
        compare(hoverTip.text, SafeText.plainTextAsRichText(hostile));
        compare(copiedTip.text, SafeText.plainTextAsRichText("Copied"));
        var buttons = [];
        findAllItems(row, function (item) {
            return item.icon !== undefined && item.icon.name === "edit-copy";
        }, buttons);
        compare(buttons.length, 1);
        var button = buttons[0];
        compare(hoverTip.parent, button);
        compare(copiedTip.parent, button);
    }

    // The standalone status dot carries its incident label in a tooltip, so
    // provider-controlled titles must arrive escaped.
    function test_compactStatusTooltipEscapesIncidentText() {
        applet.incidentOnMeter = false;
        var panel = createControl("CompactRepresentation", {applet: applet, height: 44});
        if (!panel)
            return;
        var compactTips = [];
        findAllItems(panel, function (item) {
            return item.toString().indexOf("PlainToolTip") >= 0;
        }, compactTips);
        compare(compactTips.length, 1);
        var tip = compactTips[0];
        verify(tip.plainText.length > 0);
        compare(tip.text, SafeText.plainTextAsRichText(tip.plainText));
    }

    // The standalone status hover target must span the full badge slot so
    // the incident tooltip triggers anywhere in the slot, not only over
    // the small status dot.
    function test_compactStatusHoverTargetSpansTheBadgeSlot() {
        applet.incidentOnMeter = false;
        var panel = createControl("CompactRepresentation", {applet: applet, height: 44});
        if (!panel)
            return;
        wait(0);
        var dot = findItem(panel, function (item) {
            return item.visible && item.objectName === "panelStatusDot";
        });
        verify(dot !== null);
        var slot = dot.parent;
        verify(slot !== null);
        verify(slot.height > dot.height);
        var areas = [];
        findAllItems(slot, function (item) {
            return item.containsMouse !== undefined && item.hoverEnabled === true
                && item.acceptedButtons === 0;
        }, areas);
        compare(areas.length, 1);
        var area = areas[0];
        compare(area.width, slot.width);
        compare(area.height, slot.height);
        var tips = [];
        findAllItems(panel, function (item) {
            return item.toString().indexOf("PlainToolTip") >= 0;
        }, tips);
        compare(tips.length, 1);
        var tip = tips[0];
        var dotTop = dot.mapToItem(slot, 0, 0);
        var hoverInSlot = {x: slot.width / 2, y: Math.max(1, dotTop.y - 2)};
        verify(hoverInSlot.y < dotTop.y);
        mouseMove(testCase, testCase.width - 1, testCase.height - 1);
        wait(300);
        // The status slot can move while the panel's initial layout settles.
        var hoverInPanel = slot.mapToItem(panel, hoverInSlot.x, hoverInSlot.y);
        mouseMove(panel, hoverInPanel.x, hoverInPanel.y);
        tryCompare(tip, "visible", true);
        mouseMove(testCase, testCase.width - 1, testCase.height - 1);
        tryCompare(tip, "visible", false);
    }

    function test_incidentDotsStaySquareAndAttributed_data() {
        return [
            {
                tag: "badge on the incident provider meter",
                incidentOnMeter: true
            },
            {
                tag: "standalone fallback without a meter",
                incidentOnMeter: false
            },
            {
                tag: "badge persists during a refresh",
                incidentOnMeter: true,
                loading: true
            },
            {
                tag: "vertical identity badge carries its own provider",
                incidentOnMeter: true,
                vertical: true,
                metersHidden: true
            },
            {
                tag: "vertical standalone fallback for a foreign incident",
                incidentOnMeter: false,
                vertical: true,
                metersHidden: true
            }
        ];
    }

    function test_incidentDotsStaySquareAndAttributed(data) {
        applet.incidentOnMeter = data.incidentOnMeter;
        applet.loading = data.loading === true;
        applet.verticalFormFactor = data.vertical === true;
        applet.metersHidden = data.metersHidden === true;
        var panel = createControl("CompactRepresentation", data.vertical
            ? {applet: applet, width: 44}
            : {applet: applet, height: 32});
        if (!panel)
            return;
        wait(0);
        var badge = findItem(panel, function (item) {
            return item.visible && item.objectName === "panelIncidentBadge";
        });
        var dot = findItem(panel, function (item) {
            return item.visible && item.objectName === "panelStatusDot";
        });
        var identityBadge = findItem(panel, function (item) {
            return item.visible && item.objectName === "panelIdentityBadge";
        });
        if (data.vertical) {
            // Without meters the identity icon is the only anchor, and it may
            // badge only its own provider's incident: a foreign incident keeps
            // the standalone fallback so the outage never goes unmarked.
            verify(badge === null);
            if (data.incidentOnMeter) {
                verify(identityBadge !== null);
                verify(dot === null);
                compare(identityBadge.width, identityBadge.height);
                var identityIcon = findItem(panel, function (item) {
                    return item.visible && item.objectName === "panelIdentityIcon";
                });
                verify(identityIcon !== null);
                var badgeCenter = identityBadge.mapToItem(panel,
                    identityBadge.width / 2, identityBadge.height / 2);
                var iconTopLeft = identityIcon.mapToItem(panel, 0, 0);
                verify(badgeCenter.x >= iconTopLeft.x && badgeCenter.x <= iconTopLeft.x + identityIcon.width);
                verify(badgeCenter.y >= iconTopLeft.y && badgeCenter.y <= iconTopLeft.y + identityIcon.height);
            } else {
                verify(identityBadge === null);
                verify(dot !== null);
                compare(dot.width, dot.height);
            }
            return;
        }
        verify(identityBadge === null);
        if (data.incidentOnMeter) {
            verify(badge !== null);
            verify(dot === null);
            verify(badge.width > 0);
            compare(badge.width, badge.height);
            var icon = findItem(panel, function (item) {
                return item.visible && item.objectName === "panelProviderIcon";
            });
            verify(icon !== null);
            var badgeCenter = badge.mapToItem(panel, badge.width / 2, badge.height / 2);
            var iconTopLeft = icon.mapToItem(panel, 0, 0);
            verify(badgeCenter.x >= iconTopLeft.x && badgeCenter.x <= iconTopLeft.x + icon.width);
            verify(badgeCenter.y >= iconTopLeft.y && badgeCenter.y <= iconTopLeft.y + icon.height);
        } else {
            verify(badge === null);
            verify(dot !== null);
            verify(dot.width > 0);
            compare(dot.width, dot.height);
            var center = dot.mapToItem(panel, dot.width / 2, dot.height / 2);
            verify(Math.abs(center.y - panel.height / 2) < 1);
        }
    }

    function test_longAccountButtonsFitAndKeepFullAccessibleNames_data() {
        return [
            {
                tag: "narrow",
                width: 240
            },
            {
                tag: "popup",
                width: 540
            }
        ];
    }

    function test_longAccountButtonsFitAndKeepFullAccessibleNames(data) {
        applet.selectedAccount = "";
        var view = createControl("ProviderAccountsPanel", {
            applet: applet,
            providerData: {
                provider: "codex"
            },
            width: data.width
        });
        if (!view)
            return;
        wait(0);
        var button = findItem(view, function (item) {
            return item.checkable && item.Accessible.name.indexOf("engineering-") === 0;
        });
        verify(button !== null);
        verify(button.width > 0);
        verify(button.mapToItem(view, button.width, 0).x <= view.width);
        var fullLabel = applet.accountItems[0].account + " · " + applet.accountItems[0].subtitle;
        compare(button.Accessible.name, fullLabel);
        verify(button.plainText.length < fullLabel.length);
        button.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(applet.selectedAccount, applet.accountItems[0].account);
        compare(button.checked, true);
        applet.selectedAccount = applet.accountItems[1].account;
        tryCompare(button, "checked", false);
        testCase.forceActiveFocus();
    }

    function test_accountDelegatesStaySafeKeyboardButtons() {
        var savedItems = applet.accountItems;
        var savedSelected = applet.selectedAccount;
        var hostileAccount = "Status <img src=\"http://127.0.0.1/probe\"> & <test-org>";
        var hostileSubtitle = "Workspace <b>evil</b>";
        applet.accountItems = [{provider: "codex", account: hostileAccount, subtitle: hostileSubtitle}];
        applet.selectedAccount = "";
        try {
            var view = createControl("ProviderAccountsPanel", {
                applet: applet,
                providerData: { provider: "codex" },
                width: 540
            });
            // The accounts delegate must stay a real button: a swap that no
            // longer compiles must fail here instead of passing vacuously.
            verify(view !== null);
            wait(0);
            var button = findItem(view, function (item) {
                return item.checkable && item.Accessible.name.indexOf("Status <img") === 0;
            });
            verify(button !== null);
            // The safe-button interface carries the literal label; a delegate
            // without it cannot route untrusted text through SafeText.
            compare(button.plainText, hostileAccount + " · " + hostileSubtitle);
            compare(button.Accessible.name, hostileAccount + " · " + hostileSubtitle);
            button.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
            compare(applet.selectedAccount, hostileAccount);
            compare(button.checked, true);
            testCase.forceActiveFocus();
        } finally {
            applet.accountItems = savedItems;
            applet.selectedAccount = savedSelected;
        }
    }

    function test_providerRowRevealsTruncatedIdentity_data() {
        return [{tag: "hover", keyboard: false}, {tag: "keyboard", keyboard: true}];
    }

    function test_providerRowRevealsTruncatedIdentity(data) {
        var identity = {
            provider: "example-provider-with-an-unusually-long-identifier",
            displayName: "Example <provider> & an unusually long display name",
            enabled: false,
            defaultEnabled: false
        };
        var row = createControl("ProviderConfigRow", {
            configPage: applet,
            modelData: identity,
            width: 300
        });
        if (!row)
            return;
        var tips = [];
        findAllItems(row, item => item.toString().indexOf("PlainToolTip") >= 0, tips);
        compare(tips.length, 1);
        var tip = tips[0];
        var title = findItem(row, item => item.text === identity.displayName);
        verify(tip !== null && title !== null);
        tryCompare(title, "truncated", true);
        mouseMove(testCase, testCase.width - 1, testCase.height - 1);
        wait(300);
        if (data.keyboard)
            row.forceActiveFocus(Qt.TabFocusReason);
        else
            mouseMove(row, row.width / 2, row.height / 2);
        tryCompare(tip, "visible", true);
        compare(tip.plainText, identity.displayName + "\n" + identity.provider);
        compare(tip.text, SafeText.plainTextAsRichText(tip.plainText));
        compare(tip.parent, row);
        mouseMove(testCase, testCase.width - 1, testCase.height - 1);
        testCase.forceActiveFocus();
        tryCompare(tip, "visible", false);

        // The name fits but the ID does not; it must still be discoverable.
        row.modelData = Object.assign({}, identity, {displayName: "Example"});
        tryCompare(title, "truncated", false);
        if (data.keyboard)
            row.forceActiveFocus(Qt.TabFocusReason);
        else
            mouseMove(row, row.width / 2, row.height / 2);
        tryCompare(tip, "visible", true);

        row.modelData = Object.assign({}, identity, {provider: "example", displayName: "Example"});
        tryCompare(tip, "visible", false);
        wait(tip.delay + 100);
        verify(!tip.visible);
    }

    function test_providerRowKeyboardSelectionDoesNotToggleEnablement() {
        applet.selectedProviderID = "codex";
        applet.providerToggleCount = 0;
        applet.providerEnabled = false;
        var row = createControl("ProviderConfigRow", {
            configPage: applet,
            modelData: {
                provider: "gemini",
                displayName: "Gemini",
                enabled: false,
                defaultEnabled: false
            },
            width: 300
        });
        if (!row)
            return;
        verify(row.activeFocusOnTab);
        compare(row.Accessible.name, "Gemini");
        row.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(applet.selectedProviderID, "gemini");
        compare(applet.providerToggleCount, 0);
        var toggle = row.nextItemInFocusChain(true);
        verify(toggle !== row);
        toggle.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(applet.providerToggleCount, 1);
        compare(applet.providerEnabled, true);
    }

    function test_providerMetersSupportKeyboardAndPointer_data() {
        return [{tag: "standard", minimal: false}, {tag: "minimal", minimal: true}];
    }

    function test_minimalVerticalPanelKeepsMetersAndIncident_data() {
        return [{tag: "small", extent: 32}, {tag: "normal", extent: 44}, {tag: "wide", extent: 60}];
    }

    function test_minimalVerticalPanelKeepsMetersAndIncident(data) {
        applet.minimalPanel = true;
        applet.verticalFormFactor = true;
        var panel = createControl("CompactRepresentation", {applet: applet, width: data.extent});
        if (!panel)
            return;
        wait(0);
        verify(panel.height > 44);
        verify(!panel.showPrimaryIdentity);
        var dot = findItem(panel, item => item.visible && item.color !== undefined
            && item.color.toString() === "#ff8000");
        verify(dot !== null);
        compare(dot.width, dot.height);
        var meter = findItem(panel, item => item.activeFocusOnTab && typeof item.activate === "function");
        verify(meter !== null && meter.visible);
        var track = findItem(meter, item => item.objectName === "panelMeterTrack");
        verify(track.width > 0);
        verify(track.mapToItem(panel, track.width, 0).x <= panel.width);
    }

    function test_providerMetersSupportKeyboardAndPointer(data) {
        applet.minimalPanel = data.minimal;
        applet.openedProvider = "";
        applet.expanded = false;
        var panel = createControl("CompactRepresentation", {
            applet: applet,
            height: 32
        });
        if (!panel)
            return;
        wait(0);
        var meter = findItem(panel, function (item) {
            return item.activeFocusOnTab && typeof item.activate === "function";
        });
        verify(meter !== null);
        meter.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        compare(applet.openedProvider, "codex");
        applet.openedProvider = "";
        mouseClick(meter, meter.width / 2, meter.height / 2);
        compare(applet.openedProvider, "codex");
        compare(applet.expanded, true);
    }

    function test_panelMeterHoverTracksPerProviderTooltip() {
        applet.hoveredPanelProviderID = "";
        var panel = createControl("CompactRepresentation", {
            applet: applet,
            height: 44
        });
        if (!panel)
            return;
        wait(0);
        var codexMeter = findItem(panel, item => item.modelData && item.modelData.provider === "codex");
        var claudeMeter = findItem(panel, item => item.modelData && item.modelData.provider === "claude");
        verify(codexMeter !== null && claudeMeter !== null);
        mouseMove(codexMeter, codexMeter.width / 2, codexMeter.height / 2);
        tryCompare(applet, "hoveredPanelProviderID", "codex");
        var codexTip = applet.panelProviderToolTipText(codexMeter.modelData);
        verify(codexTip.indexOf("Codex") >= 0);
        verify(codexTip.indexOf("Claude") < 0);
        mouseMove(claudeMeter, claudeMeter.width / 2, claudeMeter.height / 2);
        tryCompare(applet, "hoveredPanelProviderID", "claude");
        var claudeTip = applet.panelProviderToolTipText(claudeMeter.modelData);
        verify(claudeTip.indexOf("Claude") >= 0);
        verify(claudeTip.indexOf("Codex") < 0);
        mouseMove(testCase, 600, 220);
        tryCompare(applet, "hoveredPanelProviderID", "");
        // A meter filtered out of the rendered set while hovered must not
        // keep the tooltip narrowed to it once its MouseArea is gone.
        mouseMove(codexMeter, codexMeter.width / 2, codexMeter.height / 2);
        tryCompare(applet, "hoveredPanelProviderID", "codex");
        applet.metersHidden = true;
        tryCompare(applet, "hoveredPanelProviderID", "");
        applet.metersHidden = false;
        tryCompare(applet, "hoveredPanelProviderID", "");
    }

    function test_longChartReadoutFitsAndKeysInspectPoints() {
        var chart = createControl("InteractiveChart", {
            applet: applet,
            width: 240,
            accent: "blue",
            points: [
                {
                    label: "First",
                    value: -1
                },
                {
                    label: "Final point with a long display label",
                    value: 1e300,
                    displayValue: "An unusually long value that must not push the chart beyond its assigned width"
                }
            ]
        });
        if (!chart)
            return;
        var plot = findItem(chart, function (item) {
            return typeof item.requestPaint === "function";
        });
        verify(plot !== null);
        plot.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_End);
        compare(chart.selectedIndex, 1);
        wait(0);
        var value = findItem(chart, function (item) {
            return item.text === chart.points[1].displayValue;
        });
        verify(value !== null);
        tryVerify(function () {
            return value.width > 0 && value.mapToItem(chart, value.width, 0).x <= chart.width && plot.width <= chart.width;
        });
        keyClick(Qt.Key_Left);
        compare(chart.selectedIndex, 0);
        mouseMove(plot, plot.width - 1, plot.height / 2);
        compare(chart.hoveredIndex, 1);
        mouseMove(testCase, 600, 220);
        tryCompare(chart, "hoveredIndex", -1);
        chart.points = [];
        tryCompare(chart, "selectedIndex", -1);
        keyClick(Qt.Key_End);
        compare(chart.selectedIndex, -1);
    }

    function test_chartReadoutRevealsTruncatedText_data() {
        return [
            {tag: "hover-label", keyboard: false, longLabel: true},
            {tag: "hover-value", keyboard: false, longLabel: false},
            {tag: "keyboard-label", keyboard: true, longLabel: true},
            {tag: "keyboard-value", keyboard: true, longLabel: false}
        ];
    }

    function test_chartReadoutRevealsTruncatedText(data) {
        var longText = "Platform infrastructure <model> & enterprise workspace allowance";
        var chart = createControl("InteractiveChart", {
            applet: applet, width: 240, accent: "blue",
            points: [{label: data.longLabel ? longText : "Day", value: 0,
                displayValue: data.longLabel ? "0" : longText}]
        });
        if (!chart)
            return;
        var plot = findItem(chart, item => typeof item.requestPaint === "function");
        verify(plot !== null);
        if (data.keyboard) {
            plot.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Home);
        } else {
            mouseMove(plot, plot.width / 2, plot.height / 2);
        }
        var label = findItem(chart, item => item.text === longText);
        verify(label !== null);
        tryCompare(label, "truncated", true);
        if (data.keyboard)
            compare(label.parent.opacity, 1, "Keyboard inspection must show its readout immediately");
        var tips = [];
        findAllItems(plot, item => typeof item.plainText === "string" && item.delay !== undefined, tips);
        compare(tips.length, 1);
        var tip = tips[0];
        tryCompare(tip, "visible", true, tip.delay + 1000);
        verify(tip.plainText.indexOf(longText) >= 0);
        verify(tip.text.indexOf("&lt;model&gt;") >= 0);

        // Both fields fit after a refresh, so inspection needs no tooltip.
        chart.points = [{label: "Day", value: 0, displayValue: "0"}];
        tryCompare(tip, "visible", false);
        // Reopening with an empty snapshot must not expose retained readout text.
        chart.points = [];
        compare(tip.plainText, "");
        mouseMove(testCase, 600, 220);
    }

    function test_providerDetailValuesStayWithinPopup_data() {
        return [
            { tag: "primary-narrow", field: "value", width: 240 },
            { tag: "primary-popup", field: "value", width: 540 },
            { tag: "secondary-narrow", field: "secondaryValue", width: 240 },
            { tag: "secondary-popup", field: "secondaryValue", width: 540 },
            { tag: "unit-narrow", field: "unit", width: 240 },
            { tag: "unit-popup", field: "unit", width: 540 },
            { tag: "short-values", field: "", width: 540 }
        ];
    }

    function test_providerDetailValuesStayWithinPopup(data) {
        failOnWarning(/Qt Quick Layouts: Detected recursive rearrange/);
        var longValue = "LongModelName".repeat(10).slice(0, 120);
        var rawSection = {
            title: "Details",
            rows: [{ label: "Model", value: "42", secondaryValue: "Included" }],
            chart: { kind: "line", title: "Daily usage", unit: "tokens", points: [] }
        };
        if (data.field === "unit")
            rawSection.chart.unit = longValue;
        else if (data.field.length > 0)
            rawSection.rows[0][data.field] = longValue;
        var section = UsageDetails.normalizeSections([rawSection])[0];
        var layout = createTemporaryQmlObject(
            'import QtQuick; import QtQuick.Layouts; ColumnLayout {}',
            testCase, String(Qt.resolvedUrl("ProviderDetailBoundsTest.qml")));
        layout.width = data.width;
        var view = createControl("ProviderDetailSection", {
            applet: applet,
            providerData: { provider: "codex" },
            modelData: section
        }, layout);
        if (!view)
            return;
        tryCompare(view, "width", data.width);
        var expectedTexts = [section.rows[0].label, section.rows[0].value,
            section.rows[0].secondaryValue, section.chart.title, section.chart.unit];
        for (var i = 0; i < expectedTexts.length; i++) {
            var expectedText = expectedTexts[i];
            var label = findItem(view, function (item) {
                return item.visible && item.text === expectedText;
            });
            verify(label !== null, "Missing detail text: " + expectedText);
            verify(label.width > 0, "Detail text has no available width");
            verify(label.mapToItem(view, 0, 0).x >= 0);
            verify(label.mapToItem(view, label.width, 0).x <= view.width + 1,
                "Detail text overflows the popup: " + expectedText);
            if (expectedText !== longValue)
                verify(label.width + 1 >= label.implicitWidth,
                    "A long value hides its short label");
        }
    }

    function test_providerDetailRevealsTruncatedText_data() {
        return [
            {tag: "title", field: "title"},
            {tag: "label", field: "label"},
            {tag: "value", field: "value"},
            {tag: "secondary", field: "secondaryValue"},
            {tag: "chart-title", field: "chartTitle"},
            {tag: "chart-unit", field: "chartUnit"}
        ];
    }

    function test_providerDetailRevealsTruncatedText(data) {
        var longText = "Platform infrastructure <model> & enterprise workspace allowance";
        var raw = {title: "Details", rows: [{label: "Model", value: "42", secondaryValue: "Included"}],
            chart: {kind: "line", title: "Daily usage", unit: "tokens", points: []}};
        if (data.field === "title")
            raw.title = longText;
        else if (data.field === "chartTitle")
            raw.chart.title = longText;
        else if (data.field === "chartUnit")
            raw.chart.unit = longText;
        else
            raw.rows[0][data.field] = longText;
        var view = createControl("ProviderDetailSection", {
            applet: applet, providerData: {provider: "codex"},
            modelData: UsageDetails.normalizeSections([raw])[0], width: 240
        });
        if (!view)
            return;
        var label = findItem(view, item => item.text === longText);
        verify(label !== null);
        tryCompare(label, "truncated", true);
        var tips = [];
        findAllItems(label, item => item.plainText === longText && item.delay !== undefined, tips);
        compare(tips.length, 1);
        var tip = tips[0];
        mouseMove(label, label.width / 2, label.height / 2);
        tryCompare(tip, "visible", true, tip.delay + 1000);
        verify(tip.text.indexOf("&lt;model&gt;") >= 0);
        mouseMove(testCase, testCase.width - 1, testCase.height - 1);
        tryCompare(tip, "visible", false);
        // Values which fit should not acquire an unnecessary tooltip.
        view.modelData = UsageDetails.normalizeSections([{
            title: "Details", rows: [{label: "Model", value: "42", secondaryValue: "Included"}],
            chart: {kind: "line", title: "Usage", unit: "tok", points: []}
        }])[0];
        var shortText = data.field === "title" ? "Details"
            : data.field === "chartTitle" ? "Usage" : data.field === "chartUnit" ? "tok"
            : data.field === "label" ? "Model" : data.field === "value" ? "42" : "Included";
        label = findItem(view, item => item.text === shortText);
        verify(label !== null);
        tryCompare(label, "truncated", false);
        tips = [];
        findAllItems(label, item => item.plainText === shortText && item.delay !== undefined, tips);
        compare(tips.length, 1);
        tip = tips[0];
        mouseMove(label, label.width / 2, label.height / 2);
        wait(tip.delay + 100);
        verify(!tip.visible);
    }

    function test_providerDetailWorstCases_data() {
        var cases = [];
        for (var width of [240, 320, 540, 900]) {
            for (var mode of ["demo", "worst", "empty", "one", "huge"])
                cases.push({tag: mode + "-" + width, mode: mode, width: width});
        }
        return cases;
    }

    function test_providerDetailWorstCases(data) {
        failOnWarning(/Qt Quick Layouts: Detected recursive rearrange|Binding loop detected/);
        var normalized = UsageDetails.normalizeSections([ProviderUiStress.section(data.mode)])[0];
        compare(normalized.rows.length, data.mode === "huge" ? 24
            : data.mode === "worst" ? 8 : data.mode === "empty" ? 0 : 1);
        var view = createControl("ProviderDetailSection", {
            applet: applet, providerData: {provider: "codex"}, modelData: normalized, width: data.width
        });
        if (!view)
            return;
        wait(30);
        for (var text of [normalized.title, normalized.chart.title, normalized.chart.unit]) {
            var label = findItem(view, item => item.text === text);
            verify(label !== null);
            verify(label.width > 0);
            verify(label.mapToItem(view, 0, 0).x >= -1);
            verify(label.mapToItem(view, label.width, 0).x <= view.width + 1);
        }
        var labels = [];
        findAllItems(view, item => item.textFormat !== undefined && item.truncated !== undefined, labels);
        for (var label of labels) {
            if (!label.visible || !label.text)
                continue;
            compare(label.textFormat, Text.PlainText);
            verify(label.mapToItem(view, 0, 0).x >= -1);
            verify(label.mapToItem(view, label.width, 0).x <= view.width + 1);
        }
        var meters = [];
        findAllItems(view, item => item.objectName === "detailProgressFill", meters);
        for (var meter of meters)
            verify(meter.width >= 0 && meter.width <= meter.parent.width + 1);
    }

    function test_providerDetailNestedLayoutDoesNotRearrangeRecursively() {
        failOnWarning(/Qt Quick Layouts: Detected recursive rearrange/);
        var layout = createTemporaryQmlObject(
            'import QtQuick; import QtQuick.Layouts; ColumnLayout { width: 540 }',
            testCase, String(Qt.resolvedUrl("ProviderDetailLayoutTest.qml")));
        var section = UsageDetails.normalizeSections([{
            title: "Details",
            rows: [{ label: "Model", value: "A long model value", secondaryValue: "Included" }],
            chart: { kind: "line", title: "Daily usage", unit: "tokens", points: [] }
        }])[0];
        var view = createControl("ProviderDetailSection", {
            applet: applet,
            providerData: { provider: "codex" },
            modelData: section
        }, layout);
        if (!view)
            return;
        tryCompare(view, "width", layout.width);
        layout.width = 240;
        tryCompare(view, "width", layout.width);
        layout.width = 540;
        tryCompare(view, "width", layout.width);
    }

    function test_providerDetailChartFollowsChartData() {
        var layout = createTemporaryQmlObject(
            'import QtQuick; import QtQuick.Layouts; ColumnLayout { width: 540 }',
            testCase, String(Qt.resolvedUrl("ProviderDetailChartTest.qml")));
        var withChart = UsageDetails.normalizeSections([{
            title: "Details",
            rows: [{ label: "Model", value: "42", secondaryValue: "" }],
            chart: { kind: "line", title: "Daily usage", unit: "tokens",
                points: [{ label: "Mon", value: 3 }, { label: "Tue", value: 7 }] }
        }])[0];
        var plotted = createControl("ProviderDetailSection", {
            applet: applet,
            providerData: { provider: "codex" },
            modelData: withChart
        }, layout);
        if (!plotted)
            return;
        // The section plots its chart through the shared interactive chart,
        // which appears only while the section carries chart data.
        var chart = findItem(plotted, function (item) {
            return typeof item.pointCount === "number" && typeof item.selectedIndex === "number";
        });
        verify(chart !== null);
        compare(chart.visible, true);
        compare(chart.pointCount, 2);
        var withoutChart = UsageDetails.normalizeSections([{
            title: "Details",
            rows: [{ label: "Model", value: "42", secondaryValue: "" }]
        }])[0];
        verify(withoutChart.chart === null);
        var plain = createControl("ProviderDetailSection", {
            applet: applet,
            providerData: { provider: "codex" },
            modelData: withoutChart
        }, layout);
        if (!plain)
            return;
        var hidden = findItem(plain, function (item) {
            return typeof item.pointCount === "number" && typeof item.selectedIndex === "number";
        });
        verify(hidden !== null);
        compare(hidden.visible, false);
    }

    function test_providerDetailProgressMeterFollowsRowProgress_data() {
        return [
            { tag: "narrow", width: 240 },
            { tag: "popup", width: 540 }
        ];
    }

    function test_providerDetailProgressMeterFollowsRowProgress(data) {
        failOnWarning(/Qt Quick Layouts: Detected recursive rearrange/);
        var layout = createTemporaryQmlObject(
            'import QtQuick; import QtQuick.Layouts; ColumnLayout {}',
            testCase, String(Qt.resolvedUrl("ProviderDetailProgressTest.qml")));
        layout.width = data.width;
        var section = UsageDetails.normalizeSections([{
            title: "Budget",
            rows: [
                { label: "Spend", value: "$2.50 / $10.00", progress: { used: 0.25, total: 1 } },
                { label: "Over budget", value: "$14.00 / $10.00", progress: { used: 1, total: 1 } },
                { label: "Model", value: "gpt-5", usageValue: 3 },
                { label: "Broken", value: "25%", progress: { used: 1, total: 0 } }
            ]
        }])[0];
        var view = createControl("ProviderDetailSection", {
            applet: applet,
            providerData: { provider: "codex" },
            modelData: section
        }, layout);
        if (!view)
            return;
        tryCompare(view, "width", data.width);
        var meters = [];
        findAllItems(view, function (item) {
            return item.objectName === "detailProgressMeter";
        }, meters);
        compare(meters.length, 4);
        var shown = meters.filter(function (meter) { return meter.visible; });
        compare(shown.length, 2);
        for (var i = 0; i < shown.length; i++) {
            verify(shown[i].width > 0);
            verify(shown[i].height > 0);
            verify(shown[i].mapToItem(view, 0, 0).x >= 0);
            verify(shown[i].mapToItem(view, shown[i].width, 0).x <= view.width + 1,
                "Detail meter overflows the popup");
        }
        var fills = shown.map(function (meter) {
            return findItem(meter, function (item) {
                return item.objectName === "detailProgressFill";
            });
        });
        fuzzyCompare(fills[0].width, shown[0].width * 0.25, 1);
        fuzzyCompare(fills[1].width, shown[1].width, 1);
        // Rows without valid progress keep their text and draw no meter.
        for (var t = 0; t < section.rows.length; t++) {
            var expectedText = section.rows[t].value;
            verify(findItem(view, function (item) {
                return item.visible && item.text === expectedText;
            }) !== null, "Missing detail value: " + expectedText);
        }
    }

    function usageRowData() {
        return {
            label: "Primary",
            value: 57,
            hasPercent: true,
            pace: "On pace",
            pacePercent: 40,
            paceOnTop: true,
            reset: "Resets 12:00",
            warningMarkers: [{ percent: 80, severity: "major" }]
        };
    }

    function test_providerUsageRevealsTruncatedText_data() {
        return [
            {tag: "window-title", field: "label"},
            {tag: "reset-description", field: "reset"}
        ];
    }

    function test_providerUsageRevealsTruncatedText(data) {
        var longText = data.field === "label"
            ? "Platform infrastructure <model> & enterprise workspace allowance"
            : "Resets after the next enterprise workspace billing cycle <UTC> & maintenance";
        var model = ProviderUiStress.quota("demo");
        model[data.field] = longText;
        var row = createControl("ProviderUsageRow", {
            applet: applet, providerData: {provider: "codex"}, modelData: model, width: 240
        });
        if (!row)
            return;
        var percent = findItem(row, item => item.objectName === "usagePercentLabel");
        compare(percent.text, "57% left");
        var label = findItem(row, item => item.text === longText);
        verify(label !== null);
        tryCompare(label, "truncated", true);
        var tips = [];
        findAllItems(label, item => item.plainText === longText && item.delay !== undefined, tips);
        compare(tips.length, 1, "Truncated quota text needs its full-value tooltip");
        var tip = tips[0];
        mouseMove(label, label.width / 2, label.height / 2);
        tryCompare(tip, "visible", true, tip.delay + 1000);
        verify(tip.text.indexOf("&lt;") >= 0);
        verify(tip.text.indexOf("&amp;") >= 0);
        mouseMove(testCase, testCase.width - 1, testCase.height - 1);
        tryCompare(tip, "visible", false);
        row.modelData = ProviderUiStress.quota("demo");
        tryCompare(label, "truncated", false);
        mouseMove(label, label.width / 2, label.height / 2);
        wait(tip.delay + 100);
        verify(!tip.visible);
    }

    function test_providerUsageRowResetTextComesFromRowData() {
        var row = createControl("ProviderUsageRow", {
            applet: applet,
            providerData: { provider: "codex" },
            modelData: usageRowData(),
            width: 540
        });
        if (!row)
            return;
        // The reset label renders the row's own reset text, not the
        // provider's, so each meter keeps its own window.
        var reset = findItem(row, function (item) {
            return item.text === "Resets 12:00";
        });
        verify(reset !== null);
        compare(reset.visible, true);
        var pace = findItem(row, function (item) {
            return item.text === "On pace";
        });
        verify(pace !== null);
    }

    function test_providerUsageMetadataAdaptsToAvailableWidth_data() {
        return [
            {tag: "ltr", mirrored: false, fontScale: 1},
            {tag: "rtl", mirrored: true, fontScale: 1},
            {tag: "large-text", mirrored: false, fontScale: 2}
        ];
    }

    function test_providerUsageMetadataAdaptsToAvailableWidth(data) {
        failOnWarning(/Qt Quick Layouts: Detected recursive rearrange|Binding loop detected/);
        var holder = createTemporaryQmlObject(
            'import QtQuick; Item { LayoutMirroring.childrenInherit: true }', testCase);
        holder.LayoutMirroring.enabled = data.mirrored;
        var model = usageRowData();
        model.pace = "37% in deficit · Expected 43% used · Runs out in 18 hours";
        var row = createControl("ProviderUsageRow", {
            applet: applet, providerData: {provider: "codex"}, modelData: model, width: 240
        }, holder);
        if (!row)
            return;
        var pace = findItem(row, item => item.objectName === "usagePaceLabel");
        var reset = findItem(row, item => item.text === model.reset);
        var originalFontSize = pace.font.pointSize;
        pace.font.pointSize = originalFontSize * data.fontScale;
        reset.font.pointSize = originalFontSize * data.fontScale;
        for (var width of [900 * data.fontScale, 540, 240, 900 * data.fontScale]) {
            row.width = width;
            verify(waitForPolish(row));
            if (width === 240 || (width === 540 && data.fontScale === 2)) {
                verify(reset.mapToItem(row, 0, 0).y >= pace.mapToItem(row, 0, pace.height).y,
                    "Long forecasts and reset times must use separate rows when space is limited");
            } else {
                fuzzyCompare(pace.mapToItem(row, 0, 0).y, reset.mapToItem(row, 0, 0).y, 1);
            }
            for (var label of [pace, reset]) {
                verify(label.width > 0);
                verify(label.mapToItem(row, 0, 0).x >= -1);
                verify(label.mapToItem(row, label.width, 0).x <= row.width + 1,
                    "Quota metadata must stay within the meter width");
            }
        }
        // An unbroken CLI fallback still wraps inside the popup.
        model = Object.assign({}, model, {pace: "VeryLongForecast".repeat(12)});
        row.modelData = model;
        row.width = 240;
        verify(waitForPolish(row));
        compare(pace.text, model.pace);
        verify(pace.contentWidth <= pace.width + 1);
        verify(reset.mapToItem(row, 0, 0).y >= pace.mapToItem(row, 0, pace.height).y);

        model = Object.assign({}, model, {
            pace: "", reset: "Resets after the next billing cycle ".repeat(4)
        });
        row.modelData = model;
        verify(waitForPolish(row));
        compare(pace.visible, false);
        verify(reset.truncated);
        verify(reset.width <= row.width);
    }

    // The hide action stays out of sight until the row is hovered or the
    // button takes focus, and asks the applet to hide this provider's row.
    function test_providerUsageRowOffersHideAction() {
        applet.hiddenUsageRowRequest = null;
        var data = usageRowData();
        data.lane = "primary";
        var row = createControl("ProviderUsageRow", {
            applet: applet,
            providerData: { provider: "codex" },
            modelData: data,
            width: 540
        });
        if (!row)
            return;
        var button = findItem(row, function (item) {
            return item.objectName === "hideUsageRowButton";
        });
        verify(button !== null);
        compare(button.visible, true);
        compare(button.opacity, 0);
        button.forceActiveFocus(Qt.TabFocusReason);
        compare(button.opacity, 1);
        mouseClick(button);
        compare(applet.hiddenUsageRowRequest, {provider: "codex", label: "Primary"});

        // The hidden action must not push the percentage away from the end
        // of its meter: both share the row's trailing edge.
        var percent = findItem(row, function (item) {
            return item.objectName === "usagePercentLabel";
        });
        var bar = findItem(row, function (item) {
            return item.objectName === "usageBar";
        });
        verify(percent !== null && bar !== null);
        fuzzyCompare(percent.mapToItem(row, percent.width, 0).x,
            bar.mapToItem(row, bar.width, 0).x, 0.5);

        var credit = createControl("ProviderUsageRow", {
            applet: applet,
            providerData: { provider: "codex" },
            modelData: usageRowData(),
            width: 540
        });
        compare(findItem(credit, function (item) {
            return item.objectName === "hideUsageRowButton";
        }).visible, false);
    }

    function test_providerUsageRowDrawsQuotaWarningMarkers() {
        var row = createControl("ProviderUsageRow", {
            applet: applet,
            providerData: { provider: "codex" },
            modelData: usageRowData(),
            width: 540
        });
        if (!row)
            return;
        // Every quota threshold the applet reports for the row draws one
        // marker on the meter from the same bounded source.
        var repeater = findItem(row, function (item) {
            return typeof item.count === "number" && typeof item.itemAt === "function";
        });
        verify(repeater !== null);
        compare(repeater.count, 1);
    }

    function test_projectCostsNestedLayoutDoesNotRearrangeRecursively_data() {
        return [{tag: "costs", tokens: false}, {tag: "tokens", tokens: true}];
    }

    function test_projectCostsNestedLayoutDoesNotRearrangeRecursively(data) {
        failOnWarning(/Qt Quick Layouts: Detected recursive rearrange/);
        applet.costHistoryShowsTokens = data.tokens;
        var layout = createTemporaryQmlObject(
            'import QtQuick; import QtQuick.Layouts; ColumnLayout { width: 540 }',
            testCase, String(Qt.resolvedUrl("ProjectCostLayoutTest.qml")));
        var view = createControl("ProjectCostSection", {
            applet: applet,
            providerCosts: []
        }, layout);
        if (!view)
            return;
        // Assign after creation to preserve JS arrays across the component boundary.
        var projectLabel = "A project with a long display name ".repeat(4).slice(0, 120);
        view.providerCosts = [{
            provider: "codex",
            projects: {
                rows: [{label: projectLabel, cost: 12.34, tokens: 5678, currency: "USD"}],
                truncated: false
            }
        }];
        compare(view.projectData.rows.length, 1);
        var label = findItem(view, item => item.text === projectLabel);
        var value = findItem(view, item => item.text === view.valueText(view.projectData.rows[0]));
        verify(label !== null && value !== null);
        for (var width of [540, 240, 540]) {
            layout.width = width;
            tryCompare(view, "width", width);
            verify(waitForPolish(layout));
            verify(label.width > 0 && value.width > 0);
            verify(label.mapToItem(view, label.width, 0).x <= value.mapToItem(view, 0, 0).x);
            verify(value.mapToItem(view, value.width, 0).x <= width + 1);
            verify(Math.abs(label.width / (label.width + value.width) - 0.55) < 0.01);
        }
    }
}
