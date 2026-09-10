import QtQuick
import QtTest
import "../contents/ui/CostPresentation.js" as CostPresentation
import "../contents/ui/UsageDetails.js" as UsageDetails

TestCase {
    id: testCase
    name: "VisualLayout"
    when: windowShown
    width: 620
    height: 240
    visible: true
    property var holders: []

    QtObject {
        id: applet
        property bool verticalFormFactor: false
        property bool minimalPanel: false
        property bool quotaWarning: false
        property bool dualQuota: true
        property int meterCount: 2
        property real firstQuota: 57
        property bool secondaryWarning: false
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
        function panelElementOrder() {
            return ["identity", "status", "text", "meters"];
        }
        function compactText() {
            return "A long provider name with 57% remaining";
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
            return Qt.rgba(0.2, 0.6, 0.7, 1);
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
        function quotaMeterColor(item, accent) {
            return quotaWarning || (secondaryWarning && item.value === 70) ? Qt.rgba(1, 0.5, 0, 1) : accent;
        }
        function quotaSeverity(item) {
            return quotaWarning || (secondaryWarning && item.value === 70) ? "major" : "";
        }
        function withAlpha(c, a) {
            return Qt.rgba(c.r, c.g, c.b, a);
        }
        function openProviderFromPanel(id) {
            openedProvider = id;
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
        function chartLineX(w, n, i, inset) {
            return CostPresentation.chartLineX(w, n, i, inset);
        }
        function chartLineIndexAt(w, n, x, inset) {
            return CostPresentation.chartLineIndexAt(w, n, x, inset);
        }
        function chartLineY(h, v, inset) {
            return CostPresentation.chartLineY(h, v, inset);
        }
        function chartBarGeometry(w, n) {
            return CostPresentation.chartBarGeometry(w, n);
        }
        function paintRoundedTopBar(ctx, x, y, w, h, r) {
            CostPresentation.paintRoundedTopBar(ctx, x, y, w, h, r);
        }
        function buildChartBarGradient(ctx, c, y, a, b) {
            var gradient = ctx.createLinearGradient(0, 0, 0, Math.max(1, y));
            gradient.addColorStop(0, canvasColor(c, a));
            gradient.addColorStop(1, canvasColor(c, b));
            return gradient;
        }
    }

    function createControl(type, properties, parent) {
        var holder;
        try {
            holder = Qt.createQmlObject('import QtQuick; import "../contents/ui/components" as Components; QtObject { property Component control: Component { Components.' + type + ' { function i18n(text) { return text } function i18np(one, many, count) { return count === 1 ? one : many } } } }', testCase, Qt.resolvedUrl("VisualLayoutTest.qml"));
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
        applet.hoveredPanelProviderID = "";
        applet.dualQuota = true;
        applet.meterCount = 2;
        applet.firstQuota = 57;
        applet.secondaryWarning = false;
        applet.minimalPanel = false;
        applet.quotaWarning = false;
        applet.verticalFormFactor = false;
        applet.costHistoryShowsTokens = false;
        applet.selectedProviderID = "codex";
        applet.incidentOnMeter = true;
        applet.metersHidden = false;
        applet.loading = false;
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
        compare(label.text, applet.compactText());
        verify(label.mapToItem(panel, 0, 0).x >= 0);
        verify(label.mapToItem(panel, label.width, 0).x <= panel.width);
        applet.meterCount = 2;
        tryCompare(panel, "inlinePrimaryText", true);
        verify(!panel.showPrimaryIdentity);
        tryVerify(() => !label.visible);
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
        tryVerify(() => Math.abs(fill.width / track.width - 0.01) < 0.001);
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
                return item.visible && item.plainText === "No local agent sessions found.";
            });
            verify(placeholder !== null);
            compare(placeholder.height, placeholder.implicitHeight);
        }
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
        compare(applet.expanded, false);
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
