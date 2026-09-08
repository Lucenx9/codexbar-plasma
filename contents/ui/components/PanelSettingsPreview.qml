import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../PanelDisplay.js" as PanelDisplay
import "../PanelPreview.js" as PanelPreview
import "../ProviderIdentity.js" as ProviderIdentity
import "../QuotaThresholds.js" as QuotaThresholds
import "../ThemeContrast.js" as ThemeContrast

ColumnLayout {
    id: preview

    required property var configPage
    property bool usageBarsShowUsed: true
    property bool resetTimesShowAbsolute: false
    property bool showQuotaWarningMarkers: true
    property int quotaWarningPercent: QuotaThresholds.defaultWarningPercent
    property int quotaCriticalPercent: QuotaThresholds.defaultCriticalPercent
    property string providerOrder: ""
    property string scenario: "normal"
    readonly property real clockMs: Date.now()
    readonly property var previewModel: PanelPreview.model({
        panelStyle: configPage.cfg_panelStyle,
        elementOrder: configPage.cfg_panelElementOrder,
        quotaLane: configPage.cfg_panelQuotaLane,
        visibilityRules: configPage.cfg_panelVisibilityRules,
        displayMode: configPage.cfg_menuBarDisplayMode,
        showMeters: configPage.cfg_showMultiProviderInPanel,
        autoSelectProvider: configPage.cfg_autoSelectProvider,
        providerOrder: providerOrder
    }, scenario, clockMs)

    objectName: "panelSettingsPreview"
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    function metricText(row) {
        if (!row) {
            return "";
        }
        var suffix = usageBarsShowUsed ? i18n("used") : i18n("left");
        var percent = i18n("%1% %2", Math.round(previewApplet.displayPercent(row)), suffix);
        var pace = Math.round(usageBarsShowUsed ? row.pacePercent : Math.max(0, 100 - row.pacePercent));
        var paceText = row.paceOnTop ? i18n("%1% %2 at pace", pace, suffix) : i18n("%1% %2, behind pace", pace, suffix);
        switch (previewModel.mode) {
        case "pace":
            return paceText;
        case "both":
            return i18n("%1 - %2", percent, paceText);
        case "runOut":
            if (!PanelDisplay.rowHasRunOut(row)) {
                return "";
            }
            var minutes = Math.max(1, Math.round(row.paceEtaSeconds / 60));
            if (minutes < 60) {
                return i18np("%1 minute", "%1 minutes", minutes);
            }
            var hours = Math.max(1, Math.round(minutes / 60));
            return hours < 48 ? i18np("%1 hour", "%1 hours", hours)
                : i18np("%1 day", "%1 days", Math.max(1, Math.round(hours / 24)));
        case "resetTime":
            if (resetTimesShowAbsolute) {
                return i18n("Resets %1", Qt.formatDateTime(new Date(row.resetsAt), "ddd HH:mm"));
            }
            var resetMinutes = Math.max(1, Math.round(row.resetMinutes));
            if (resetMinutes < 60) {
                return i18n("Resets %1", i18np("%1 min", "%1 min", resetMinutes));
            }
            var resetHours = Math.floor(resetMinutes / 60);
            var restMinutes = resetMinutes % 60;
            if (resetHours < 24) {
                return i18n("Resets %1", restMinutes > 0 ? i18n("%1h %2m", resetHours, restMinutes)
                    : i18np("%1h", "%1h", resetHours));
            }
            var resetDays = Math.floor(resetHours / 24);
            var restHours = resetHours % 24;
            return i18n("Resets %1", restHours > 0 ? i18n("%1d %2h", resetDays, restHours)
                : i18np("%1d", "%1d", resetDays));
        default:
            return percent;
        }
    }

    function accessibleSummary() {
        var parts = [];
        var text = previewApplet.compactText();
        if (text.length > 0) {
            parts.push(text);
        }
        for (var i = 0; i < previewModel.meterProviders.length; i++) {
            var provider = previewModel.meterProviders[i];
            parts.push(provider.title + ": " + previewApplet.panelMeterDescription(provider));
        }
        if (previewModel.incidentProvider) {
            parts.push(i18n("Service incident"));
        }
        return parts.length > 0 ? parts.join(". ") : i18n("Provider icon");
    }

    function providerColor(value) {
        var channels = ProviderIdentity.providerBrandColorChannels(value);
        if (channels.length !== 3) {
            return Kirigami.Theme.highlightColor;
        }
        return Qt.rgba(channels[0], channels[1], channels[2], 1);
    }

    function withAlpha(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha);
    }

    QtObject {
        id: previewApplet

        readonly property bool verticalFormFactor: false
        readonly property bool minimalPanel: preview.previewModel.minimalStyle
        readonly property bool loading: false

        function providerPresentation(provider) {
            return provider;
        }
        function panelElementOrder() {
            return preview.previewModel.elementOrder;
        }
        function compactProviders() {
            return preview.previewModel.meterProviders;
        }
        function primaryIncidentProvider() {
            var provider = preview.previewModel.incidentProvider;
            return provider ? {
                provider: provider.provider,
                title: provider.title,
                hasIncident: true,
                statusSeverity: provider.statusSeverity,
                status: i18n("Service incident")
            } : null;
        }
        function selectedCompactProvider() {
            return preview.previewModel.selectedProvider;
        }
        function panelDisplayRow(provider, mode) {
            return PanelDisplay.rowForMode(provider ? provider.rows : [], mode, preview.previewModel.lane);
        }
        function panelMeterRows(provider) {
            return PanelDisplay.meterRows(provider ? provider.rows : [], preview.previewModel.lane);
        }
        function panelMeterDescription(provider) {
            return panelMeterRows(provider).map(function(row) {
                var label = row.lane === "primary" ? i18n("Primary")
                    : (row.lane === "secondary" ? i18n("Secondary") : i18n("Tertiary"));
                return i18n("%1: %2% %3", label, Math.round(displayPercent(row)),
                    preview.usageBarsShowUsed ? i18n("used") : i18n("left"));
            }).join(". ");
        }
        function compactText() {
            if (!preview.previewModel.textVisible) {
                return "";
            }
            var provider = selectedCompactProvider();
            var parts = [];
            if (preview.configPage.cfg_showProviderInPanel) {
                parts.push(provider.title);
            }
            var metric = preview.metricText(preview.previewModel.textRow);
            if (preview.configPage.cfg_showPercentInPanel && metric.length > 0) {
                parts.push(metric);
            }
            if (preview.configPage.cfg_showCreditsInPanel && provider.credits !== null) {
                parts.push(i18n("%1cr", provider.credits.toLocaleString(Qt.locale(), "f", 0)));
            }
            return parts.join(" ");
        }
        function displayPercent(row) {
            return preview.usageBarsShowUsed ? row.usedPercent : row.leftPercent;
        }
        function providerIconSource(providerID) {
            return Qt.resolvedUrl("../../icons/providers/" + ProviderIdentity.providerIconFileName(providerID));
        }
        function providerIconIsMask(providerID) {
            return true;
        }
        function providerReadableColor(providerID, background) {
            return ThemeContrast.readableAccentColor(preview.providerColor(providerID), background, Kirigami.Theme.textColor);
        }
        function quotaSeverity(row) {
            if (!preview.showQuotaWarningMarkers || !row) {
                return "";
            }
            var warning = QuotaThresholds.warningPercent(preview.quotaWarningPercent);
            return QuotaThresholds.level(row.usedPercent, warning, QuotaThresholds.criticalPercent(warning, preview.quotaCriticalPercent));
        }
        function statusBadgeColor(severity) {
            return severity === "major" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.neutralTextColor;
        }
        function quotaMeterColor(row, accent) {
            var severity = quotaSeverity(row);
            return severity.length > 0 ? statusBadgeColor(severity) : accent;
        }
        function withAlpha(color, alpha) {
            return preview.withAlpha(color, alpha);
        }
    }

    RowLayout {
        Layout.fillWidth: true

        PlainControlsLabel {
            Layout.fillWidth: true
            text: i18n("Panel preview")
            font.bold: true
        }

        PlainComboBox {
            id: scenarioCombo

            objectName: "panelPreviewScenario"
            model: [
                {
                    label: i18n("Normal"),
                    value: "normal"
                },
                {
                    label: i18n("Near limit"),
                    value: "nearLimit"
                },
                {
                    label: i18n("Service incident"),
                    value: "incident"
                },
                {
                    label: i18n("No data"),
                    value: "missing"
                }
            ]
            textRole: "label"
            valueRole: "value"
            currentIndex: Math.max(0, PanelPreview.scenarios.indexOf(preview.scenario))
            onActivated: preview.scenario = currentValue
            Accessible.name: i18n("Preview scenario")
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Kirigami.Units.gridUnit * 4
        radius: Kirigami.Units.smallSpacing
        color: Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: preview.withAlpha(Kirigami.Theme.textColor, 0.2)
        clip: true
        Accessible.role: Accessible.Graphic
        Accessible.name: i18n("Panel preview")
        Accessible.description: preview.accessibleSummary()

        CompactRepresentation {
            objectName: "panelPreviewRenderer"
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - Kirigami.Units.smallSpacing * 2)
            height: implicitHeight
            applet: previewApplet
            animationsEnabled: false
            interactive: false
            Accessible.ignored: true
        }
    }

    PlainControlsLabel {
        Layout.fillWidth: true
        text: i18n("Example data. Panel changes appear here before you apply them.")
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.disabledTextColor
    }
}
