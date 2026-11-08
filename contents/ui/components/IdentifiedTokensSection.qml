import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Rectangle {
    id: section
    objectName: "identifiedTokensSection"
    required property var applet
    readonly property var snapshot: applet.identifiedTokensSnapshot
    property bool detailsExpanded: false
    onSnapshotChanged: detailsExpanded = false
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

    implicitHeight: sectionContent.implicitHeight + Kirigami.Units.largeSpacing * 2
    radius: applet.roundedSurfaceRadius
    color: applet.withAlpha(Kirigami.Theme.textColor, 0.035)

    ColumnLayout {
        id: sectionContent
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlainHeading {
                text: i18n("Identified Codex tokens")
                level: 4
                type: Kirigami.Heading.Type.Primary
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            PlainPlasmaLabel {
                font: Kirigami.Theme.smallFont
                text: i18n("Identified requests only, not the whole account.")
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: section.applet.secondaryTextOpacity
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlainPlasmaLabel {
                objectName: "identifiedTokensValue"
                text: section.snapshot
                    ? i18n("%1 across %2", section.applet.usageCountText(section.snapshot.totalTokens, "tokens"),
                        section.applet.usageCountText(section.snapshot.requestCount, "requests"))
                    : i18n("No identified subtotal loaded.")
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * (section.snapshot ? 1.15 : 1)
                font.features: { "tnum": 1 }
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
                    ? i18n("API-price estimate: less than %1.", section.applet.amountString(0.01, "USD"))
                    : i18n("API-price estimate: %1.", section.applet.amountString(section.snapshot.apiEstimateUSD, "USD"))) : ""
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
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlainPlasmaLabel {
                objectName: "identifiedTokensRange"
                font: Kirigami.Theme.smallFont
                text: i18np("%1 UTC day", "%1 UTC days", section.snapshot
                    ? section.snapshot.historyDays : section.applet.identifiedTokensHistoryDays)
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: section.applet.secondaryTextOpacity
            }

            DisclosureButton {
                objectName: "identifiedDetailsButton"
                visible: section.snapshot !== null
                expanded: section.detailsExpanded
                plainText: section.detailsExpanded ? i18n("Hide details") : i18n("Show details")
                onClicked: section.detailsExpanded = !section.detailsExpanded
            }
        }

        ColumnLayout {
            objectName: "identifiedCollectionDetails"
            Layout.fillWidth: true
            visible: section.detailsExpanded && section.snapshot !== null
            spacing: Kirigami.Units.smallSpacing

            PlainPlasmaLabel {
                objectName: "identifiedTokensWindow"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                font.features: { "tnum": 1 }
                text: section.snapshot
                    ? i18n("UTC window: %1 to %2", new Date(section.snapshot.startUnixMs).toISOString().slice(0, 10),
                        new Date(section.snapshot.endUnixMs).toISOString().replace("T", " ").slice(0, 19))
                    : ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: section.applet.secondaryTextOpacity
            }

            PlainPlasmaLabel {
                font: Kirigami.Theme.smallFont
                visible: section.snapshot !== null
                text: section.snapshot && section.snapshot.remoteRequested
                    ? i18n("Sources requested: this computer + SSH") : i18n("Source requested: this computer")
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: section.applet.secondaryTextOpacity
            }

            PlainPlasmaLabel {
                visible: section.snapshot !== null && (section.snapshot.apiEstimateUSD !== null
                    || section.snapshot.unpricedRequestCount > 0)
                font: Kirigami.Theme.smallFont
                text: i18n("Separate from spend totals.")
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: section.applet.secondaryTextOpacity
            }

            PlainPlasmaLabel {
                visible: section.snapshot !== null && section.snapshot.remoteRequested
                    && !section.snapshot.remoteAvailable
                font: Kirigami.Theme.smallFont
                text: i18n("Check SSH and use the same supported codexbar version on both computers.")
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: section.applet.secondaryTextOpacity
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: (section.snapshot !== null && (!section.snapshot.allSourcesAvailable
                || section.snapshot.requestsPartial || section.snapshot.conflictCount > 0
                || section.snapshot.excludedCount > 0)) || section.failureText.length > 0
            spacing: Kirigami.Units.smallSpacing

            PlainNote {
                visible: section.snapshot !== null && !section.snapshot.allSourcesAvailable
                plainText: section.snapshot && !section.snapshot.localAvailable
                    ? i18n("Local data unavailable. Showing SSH data only.")
                    : i18n("SSH unavailable. Showing local data only.")
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
        }

        Flow {
            id: loadActions
            objectName: "identifiedLoadActions"
            Layout.fillWidth: true
            layoutDirection: Qt.application.layoutDirection
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Button {
                id: localButton
                objectName: "identifiedLocalButton"
                width: Math.min(implicitWidth, loadActions.width)
                text: i18n("Load local")
                Accessible.name: text
                icon.name: "view-refresh"
                enabled: !section.applet.identifiedTokensLoading
                onClicked: section.applet.loadIdentifiedTokens(false)

                PlainToolTip {
                    parent: localButton
                    visible: localButton.hovered || localButton.visualFocus
                    plainText: localButton.text
                }
            }
            PlasmaComponents.Button {
                id: sshButton
                objectName: "identifiedSshButton"
                width: Math.min(implicitWidth, loadActions.width)
                text: i18n("Load local + SSH")
                Accessible.name: text
                icon.name: "network-connect"
                visible: section.applet.identifiedTokensSshAvailable
                enabled: !section.applet.identifiedTokensLoading
                onClicked: section.applet.loadIdentifiedTokens(true)

                PlainToolTip {
                    parent: sshButton
                    visible: sshButton.hovered || sshButton.visualFocus
                    plainText: sshButton.text
                }
            }
            Controls.BusyIndicator {
                width: Kirigami.Units.iconSizes.smallMedium
                height: width
                running: section.applet.identifiedTokensLoading
                visible: running
            }
        }
    }
}
