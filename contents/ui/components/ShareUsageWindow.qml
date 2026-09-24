import QtCore
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.kquickcontrolsaddons as KQuickControlsAddons
import "../ShareUsage.js" as ShareUsage
import "../CostPresentation.js" as Costs

Controls.ApplicationWindow {
    id: window

    required property var snapshot
    // Formatting is supplied by the applet; the snapshot contains only exported fields.
    required property var applet
    property bool capturing: false
    property int captureGeneration: 0
    property string feedback: ""
    readonly property string attribution: "github.com/Lucenx9/codexbar-plasma"
    readonly property string periodText: i18np("%1 day", "%1 days", snapshot.days)
    readonly property string noticeText: snapshot.partial ? i18n("Some data is missing, incomplete, or estimated. Unavailable amounts are not zero.") : ""
    readonly property string privacyText: i18n("Created locally. Only aggregate usage is included. Costs are usage estimates, not subscription fees.")
    readonly property var providerLines: snapshot.providers.map(function (row) {
        return applet.providerDisplayTitle(row.provider) + " · " + amountText(row);
    })
    readonly property var modelLines: snapshot.models.map(function (row) {
        return row.label + " · " + applet.providerDisplayTitle(row.provider) + " · " + amountText(row);
    })
    readonly property string tokensText: snapshot.tokens === null ? i18n("Tokens unavailable") : applet.usageCountText(snapshot.tokens, "tokens")
    readonly property string costText: snapshot.currencies.length === 0 ? i18n("Cost unavailable") : snapshot.currencies.map(function (row) {
        return applet.amountString(row.cost, row.currency);
    }).join(" · ")
    readonly property string createdText: i18n("Created %1", Qt.locale().toString(new Date(snapshot.createdAt), Locale.ShortFormat))
    readonly property string statisticsText: ["CodexBar", periodText, tokensText,
        i18n("Estimated usage cost"), costText, i18n("Providers"), providerLines.join("\n"),
        omittedProviderText(), i18n("Top models by tokens"), modelLines.join("\n"),
        omittedModelText(), noticeText, privacyText, createdText, attribution].filter(function (text) {
        return text.length > 0;
    }).join("\n")

    title: i18n("Share AI usage")
    width: Math.min(Screen.width, Kirigami.Units.gridUnit * 52)
    height: Math.min(Screen.height, Kirigami.Units.gridUnit * 43)
    minimumWidth: Kirigami.Units.gridUnit * 22
    minimumHeight: Kirigami.Units.gridUnit * 20
    color: Kirigami.Theme.backgroundColor
    // Do not transient-parent this window to the panel popup, which closes on focus loss.
    transientParent: null
    onSnapshotChanged: {
        feedback = ""
    }
    Connections {
        target: window.applet
        function onPrivacyModeChanged() { window.close() }
    }
    onClosing: {
        captureGeneration++;
        capturing = false;
        saveDialog.close();
    }

    function amountText(row) {
        var parts = [];
        if (row.tokens !== null)
            parts.push(applet.usageCountText(row.tokens, "tokens"));
        if (row.cost !== null)
            parts.push(applet.amountString(row.cost, row.currency));
        return parts.length > 0 ? parts.join(" · ") : i18n("Unavailable");
    }

    function omittedProviderText() {
        return snapshot.omittedProviders > 0 ? i18np("%1 more provider included in totals", "%1 more providers included in totals", snapshot.omittedProviders) : "";
    }

    function omittedModelText() {
        return snapshot.omittedModels > 0 ? i18np("%1 more model not shown", "%1 more models not shown", snapshot.omittedModels) : "";
    }

    function captureImage(save) {
        if (save) {
            saveDialog.open();
            return;
        }
        if (capturing || !visible || saveDialog.visible)
            return;
        capturing = true;
        feedback = "";
        var generation = ++captureGeneration;
        var accepted = card.grabToImage(function (result) {
            if (generation !== window.captureGeneration || !window.visible)
                return;
            window.capturing = false;
            clipboard.content = result.image;
            window.feedback = i18n("Image copied");
        }, Qt.size(Math.ceil(card.width * 2), Math.ceil(card.height * 2)));
        if (!accepted) {
            capturing = false;
            feedback = i18n("Could not create the image. Try again.");
        }
    }

    function saveImage(url) {
        if (!ShareUsage.localPngUrl(String(url))) {
            feedback = i18n("Choose a local PNG file.");
            return false;
        }
        if (capturing || !visible)
            return false;
        capturing = true;
        feedback = "";
        var generation = ++captureGeneration;
        var accepted = card.grabToImage(function (result) {
            if (generation !== window.captureGeneration || !window.visible)
                return;
            window.capturing = false;
            var saved = result.saveToFile(url);
            window.feedback = saved ? i18n("Image saved") : i18n("Could not save the image. Choose another location.");
        }, Qt.size(Math.ceil(card.width * 2), Math.ceil(card.height * 2)));
        if (!accepted) {
            capturing = false;
            feedback = i18n("Could not create the image. Try again.");
            return false;
        }
        return true;
    }

    KQuickControlsAddons.Clipboard {
        id: clipboard
    }

    FileDialog {
        id: saveDialog
        title: i18n("Save usage image")
        fileMode: FileDialog.SaveFile
        nameFilters: [i18n("PNG image (*.png)")]
        defaultSuffix: "png"
        currentFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        onAccepted: window.saveImage(selectedFile)
    }

    Shortcut {
        sequences: [StandardKey.Cancel]
        onActivated: window.close()
    }

    PlasmaComponents.ScrollView {
        id: shareScroll
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        contentWidth: availableWidth
        clip: true
        Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff

        ShareUsageCard {
            id: card
            width: shareScroll.availableWidth
            height: implicitHeight
            presentation: ({
                period: window.periodText,
                tokensTitle: i18n("Tracked tokens"),
                tokens: window.snapshot.tokens === null ? "-" : Costs.tokenCountString(window.snapshot.tokens),
                costTitle: i18n("Estimated usage cost"),
                cost: window.costText,
                sections: [
                    { title: i18n("Providers"), rows: window.snapshot.providers.map(function(row) {
                        return { title: window.applet.providerDisplayTitle(row.provider), detail: window.amountText(row),
                            color: window.applet.providerColor(row.provider) }
                    }), extra: window.omittedProviderText() },
                    { title: i18n("Top models by tokens"), rows: window.snapshot.models.map(function(row) {
                        return { title: row.label,
                            detail: window.applet.providerDisplayTitle(row.provider) + " · " + window.amountText(row),
                            color: window.applet.providerColor(row.provider) }
                    }), extra: window.snapshot.models.length === 0 ? i18n("Unavailable") : window.omittedModelText() }
                ],
                notice: window.noticeText, privacy: window.privacyText,
                attribution: window.attribution, created: window.createdText
            })
        }
    }

    footer: Controls.ToolBar {
        padding: Kirigami.Units.largeSpacing
        contentItem: ColumnLayout {
            PlainPlasmaLabel {
                text: window.feedback
                visible: text.length > 0
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Accessible.role: Accessible.AlertMessage
            }
            Flow {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Controls.Button {
                    text: i18n("Copy image")
                    icon.name: "edit-copy"
                    enabled: !window.capturing && !saveDialog.visible
                    onClicked: window.captureImage(false)
                }
                Controls.Button {
                    objectName: "shareCopyStatisticsButton"
                    enabled: !window.capturing && !saveDialog.visible
                    text: i18n("Copy statistics")
                    icon.name: "edit-copy"
                    onClicked: {
                        clipboard.content = window.statisticsText;
                        window.feedback = i18n("Copied");
                    }
                }
                Controls.Button {
                    text: i18n("Save PNG...")
                    icon.name: "document-save-as"
                    enabled: !window.capturing && !saveDialog.visible
                    onClicked: window.captureImage(true)
                }
                Controls.Button {
                    text: i18n("Close")
                    icon.name: "window-close"
                    onClicked: window.close()
                }
            }
        }
    }
}
