import QtQuick
import "../PanelText.js" as PanelText
import "../PanelTextFit.js" as PanelTextFit
import "../CostPresentation.js" as CostPresentation
import "../ProviderNormalizer.js" as Normalizer

// Localized panel text only. The applet supplies privacy-filtered providers,
// row text, visibility and selection; this object never reaches its root.
QtObject {
    id: root

    property bool usageBarsShowUsed: true
    property bool loading: false
    property bool showProvider: false
    property bool showPercent: false
    property bool showCredits: false
    property var numberFormat: ({})

    function displayText(row, mode, resetText, runOutText) {
        if (mode === "pace") {
            return paceText(row)
        }
        if (mode === "both") {
            var percent = percentText(row)
            var pace = paceText(row)
            return percent.length > 0 && pace.length > 0
                ? i18n("%1 - %2", percent, pace) : (percent.length > 0 ? percent : pace)
        }
        if (mode === "resetTime") {
            return resetText
        }
        if (mode === "runOut") {
            return runOutText
        }
        return percentText(row)
    }

    function percentText(row) {
        if (!row || !row.hasPercent) {
            return ""
        }
        return i18n("%1% %2", Math.round(root.usageBarsShowUsed ? row.usedPercent : row.leftPercent),
            root.usageBarsShowUsed ? i18n("used") : i18n("left"))
    }

    function paceText(row) {
        if (!row || row.pacePercent < 0) {
            return ""
        }
        var shownPace = root.usageBarsShowUsed ? row.pacePercent
            : Normalizer.clamp(100 - row.pacePercent, 0, 100)
        if (shownPace < 0) {
            return ""
        }
        var suffix = root.usageBarsShowUsed ? i18n("used") : i18n("left")
        return row.paceOnTop
            ? i18n("%1% %2 at pace", Math.round(shownPace), suffix)
            : i18n("%1% %2, behind pace", Math.round(shownPace), suffix)
    }

    function segments(item, visible, selectionActive, display, iconIdentifies) {
        return PanelText.segments(item, visible, selectionActive, {
            showProvider: root.showProvider,
            showPercent: root.showPercent,
            showCredits: root.showCredits,
            iconIdentifies: iconIdentifies
        }, {
            fallback: root.loading ? i18n("Loading") : "CodexBar",
            display: display,
            credits: item && root.showCredits && item.credits !== null
                ? i18n("%1cr", CostPresentation.formatCount(root.numberFormat, item.credits)) : ""
        })
    }

    function fullText(segments) {
        return PanelTextFit.fullText(segments)
    }

    function providerToolTipText(item, description) {
        var parts = PanelText.providerTooltip(item, description, root.showCredits)
        if (!parts) {
            return ""
        }
        var details = []
        if (parts.description.length > 0) {
            details.push(parts.description)
        }
        if (parts.credits !== null) {
            details.push(i18n("%1cr", CostPresentation.formatCount(root.numberFormat, parts.credits)))
        }
        if (details.length > 0) {
            var line = i18n("%1: %2", parts.title, details.join(". "))
            return parts.incident.length > 0 ? i18n("%1 - %2", line, parts.incident) : line
        }
        return parts.incident.length > 0 ? i18n("%1: %2", parts.title, parts.incident) : ""
    }

    function toolTipText(providerLines, errorText) {
        var lines = providerLines.slice(0, 6)
        if (root.loading) {
            lines.push(i18n("Refreshing usage…"))
        }
        return lines.length === 0 && errorText.length > 0 ? errorText : lines.join("\n")
    }
}
