import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: section
    objectName: "identifiedTokensSection"
    required property var applet
    readonly property var snapshot: applet.identifiedTokensSnapshot
    readonly property string failureText: {
        switch (applet.identifiedTokensErrorKind) {
        case "": return "";
        case "timeout": return i18n("Loading identified tokens timed out. Try again.");
        case "tooLarge": return i18n("codexbar response exceeded the supported size.");
        case "commandUnavailable": return i18n("Could not start identified-token collection. Check codexbar and GNU timeout.");
        case "unavailable": return i18n("No selected source supplied identified Codex data. Check local history and SSH setup.");
        case "schemaMismatch": return i18n("Unsupported identified-token schema. Use compatible codexbar versions on each selected source; this widget supports schemas 1 and 2.");
        default: return i18n("Could not load identified Codex data. Check local history and use compatible codexbar versions on each selected source.");
        }
    }

    spacing: Kirigami.Units.smallSpacing

    PlainHeading {
        text: i18n("Identified Codex tokens")
        level: 4
        type: Kirigami.Heading.Type.Primary
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }

    PlainPlasmaLabel {
        text: i18n("Manual subtotal of identified requests only. This is not account-wide usage or spend.")
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: section.applet.secondaryTextOpacity
    }

    PlainPlasmaLabel {
        objectName: "identifiedTokensValue"
        text: section.snapshot
            ? i18n("%1 across %2", section.applet.usageCountText(section.snapshot.totalTokens, "tokens"),
                section.applet.usageCountText(section.snapshot.requestCount, "requests"))
            : i18n("No identified subtotal loaded.")
        font.weight: section.snapshot ? Font.DemiBold : Font.Normal
        opacity: section.snapshot ? 1 : section.applet.secondaryTextOpacity
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }

    PlainPlasmaLabel {
        objectName: "identifiedTokensEstimate"
        visible: section.snapshot !== null && section.snapshot.apiEstimateUSD !== null
        text: section.snapshot && section.snapshot.apiEstimateUSD !== null
            ? (section.snapshot.apiEstimateUSD > 0 && section.snapshot.apiEstimateUSD < 0.01
                ? i18n("API-price estimate: less than %1. Separate from spend totals.", section.applet.amountString(0.01, "USD"))
                : i18n("API-price estimate: %1. Separate from spend totals.", section.applet.amountString(section.snapshot.apiEstimateUSD, "USD"))) : ""
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: section.applet.secondaryTextOpacity
    }

    PlainPlasmaLabel {
        objectName: "identifiedTokensUnpriced"
        visible: section.snapshot !== null && section.snapshot.unpricedRequestCount > 0
        text: section.snapshot && section.snapshot.unpricedRequestCount > 0
            ? i18n("API-price estimate unavailable: %1 without a price.",
                section.applet.usageCountText(section.snapshot.unpricedRequestCount, "requests")) : ""
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: section.applet.secondaryTextOpacity
    }

    PlainPlasmaLabel {
        text: section.snapshot
            ? i18n("UTC window: %1 to %2", new Date(section.snapshot.startUnixMs).toISOString().slice(0, 10),
                new Date(section.snapshot.endUnixMs).toISOString().replace("T", " ").slice(0, 19))
            : i18np("Last %1 UTC day", "Last %1 UTC days", section.applet.identifiedTokensHistoryDays)
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: section.applet.secondaryTextOpacity
    }

    PlainPlasmaLabel {
        visible: section.snapshot !== null
        text: section.snapshot && section.snapshot.remoteRequested
            ? i18n("Sources requested: this computer + SSH") : i18n("Source requested: this computer")
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: section.applet.secondaryTextOpacity
    }

    PlainNote {
        visible: section.snapshot !== null && !section.snapshot.allSourcesAvailable
        plainText: section.snapshot && !section.snapshot.localAvailable
            ? i18n("Local data is unavailable. This subtotal contains the available SSH data only.")
            : i18n("SSH data is unavailable. This subtotal contains the available local data only. Check SSH and use the same supported codexbar version on both computers.")
        type: Kirigami.MessageType.Warning
        Layout.fillWidth: true
    }

    PlainNote {
        visible: section.snapshot !== null && section.snapshot.requestsPartial
        plainText: i18n("Some requests could not be included. This subtotal is partial.")
        type: Kirigami.MessageType.Warning
        Layout.fillWidth: true
    }

    PlainPlasmaLabel {
        visible: section.snapshot !== null && (section.snapshot.conflictCount > 0 || section.snapshot.excludedCount > 0)
        text: section.snapshot ? i18n("Conflicts: %1; excluded: %2",
            section.applet.usageCountText(section.snapshot.conflictCount, "requests"),
            section.applet.usageCountText(section.snapshot.excludedCount, "requests")) : ""
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: section.applet.secondaryTextOpacity
    }

    PlainNote {
        visible: section.failureText.length > 0
        plainText: section.failureText
        type: Kirigami.MessageType.Warning
        Layout.fillWidth: true
    }

    Flow {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlainButton {
            objectName: "identifiedLocalButton"
            plainText: i18n("Load local subtotal")
            icon.name: "view-refresh"
            enabled: !section.applet.identifiedTokensLoading
            onClicked: section.applet.loadIdentifiedTokens(false)
        }
        PlainButton {
            objectName: "identifiedSshButton"
            plainText: i18n("Load local + SSH subtotal")
            icon.name: "network-connect"
            visible: section.applet.identifiedTokensSshAvailable
            enabled: !section.applet.identifiedTokensLoading
            onClicked: section.applet.loadIdentifiedTokens(true)
        }
        Controls.BusyIndicator {
            width: Kirigami.Units.iconSizes.smallMedium
            height: width
            running: section.applet.identifiedTokensLoading
            visible: running
        }
    }
}
