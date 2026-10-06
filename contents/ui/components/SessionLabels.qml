import QtQuick
import "../PrivacyPresentation.js" as PrivacyPresentation

// Localized text for a local agent session card: title, details line, state
// and age. Privacy mode replaces CLI-supplied names with neutral labels.
QtObject {
    id: root

    required property var applet
    readonly property bool privacyMode: applet.privacyMode

    function sessionTitle(item, index) {
        if (root.privacyMode) {
            return i18n("Session %1", (index >= 0 ? index : 0) + 1)
        }
        if (!item) {
            return i18n("Untitled session")
        }
        return item.projectName.length > 0
            ? item.projectName
            : (item.sessionName.length > 0 ? item.sessionName : i18n("Untitled session"))
    }

    function sessionSubtitle(item, showHost) {
        item = PrivacyPresentation.session(item, root.privacyMode)
        if (!item) {
            return ""
        }
        var details = []
        var providerText = root.sessionProviderText(item)
        if (providerText.length > 0) {
            details.push(providerText)
        }
        if (showHost === true && item.host.length > 0) {
            details.push(item.host)
        }
        if (item.source.length > 0) {
            details.push(root.sessionSourceText(item.source))
        }
        return details.join(" \u00b7 ")
    }

    // Pi-family sessions share the `pi` provider; like the macOS menu, the
    // dialect names an OMP session instead of the provider.
    function sessionProviderText(item) {
        switch (item.dialect) {
        case "omp":
            return "OMP"
        case "":
        case "pi":
        case undefined:
            return item.provider.length > 0 ? root.applet.providerDisplayTitle(item.provider) : ""
        default:
            return root.privacyMode ? "" : item.dialect
        }
    }

    function sessionSourceText(source) {
        switch (source) {
        case "cli":
            return i18n("Command line")
        case "desktopApp":
            return i18n("Desktop app")
        case "ide":
            return i18n("IDE")
        case "unknown":
            return i18n("Unknown")
        default:
            return root.privacyMode ? i18n("Unknown") : source
        }
    }

    function sessionStateText(state) {
        switch (state) {
        case "active":
            return i18n("Active")
        case "idle":
            return i18n("Idle")
        case "running":
            return i18n("Running")
        case "working":
            return i18n("Working")
        case "":
        case "unknown":
            return i18n("Unknown")
        default:
            return root.privacyMode ? i18n("Unknown") : root.applet.capitalize(state)
        }
    }

    function sessionActivityText(item, nowMs) {
        if (!item || !isFinite(Number(item.activityMs)) || Number(item.activityMs) <= 0) {
            return ""
        }
        return root.applet.elapsedText(Number(item.activityMs), nowMs)
    }
}
