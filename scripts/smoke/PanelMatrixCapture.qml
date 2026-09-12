import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

// Staged into the real applet by panel_matrix.py; never installed with it.
Item {
    id: capture

    required property var usageLifecycle
    required property var applet
    required property string scenario
    required property string imagePath
    property bool cacheRestart: false
    property var cases: []
    property int expectedProviders: 1
    property int caseIndex: -1
    property var snapshot: []
    property var currentCase: ({})
    property var compactPanelItem

    Rectangle {
        id: canvas
        parent: capture.applet.fullRepresentationItem
        z: 100
        width: capture.currentCase.vertical ? 100 : 440
        height: capture.currentCase.vertical ? 240 : 100
        color: Kirigami.Theme.backgroundColor

        Loader {
            id: panel

            readonly property Item compactItem: item as Item
            anchors.centerIn: parent
            sourceComponent: capture.applet.compactRepresentation
            width: capture.currentCase.vertical ? capture.currentCase.extent : (compactItem ? compactItem.implicitWidth : 0)
            height: capture.currentCase.vertical ? (compactItem ? compactItem.implicitHeight : 0) : (capture.currentCase.extent || 32)
            onLoaded: {
                capture.compactPanelItem = item;
                item.animationsEnabled = false;
                item.interactive = false;
            }
        }
    }

    function nextCase() {
        caseIndex++;
        if (caseIndex >= cases.length) {
            console.log("SMOKE_CAPTURED:" + scenario);
            return;
        }
        currentCase = cases[caseIndex];
        var config = applet.Plasmoid.configuration;
        for (var key in currentCase.config)
            config[key] = currentCase.config[key];
        var providers = JSON.parse(JSON.stringify(snapshot));
        if (currentCase.longName)
            providers[0].title = "Example provider with a very long display name";
        if (currentCase.edge === "missing-secondary")
            providers[0].rows = providers[0].rows.slice(0, 1);
        if (currentCase.edge === "no-quotas")
            providers[0].rows = [];
        if (currentCase.edge === "exhausted") {
            providers[0].rows[0].usedPercent = 100;
            providers[0].rows[0].leftPercent = 0;
            providers[0].rows[1].usedPercent = 0;
            providers[0].rows[1].leftPercent = 100;
        }
        applet.providers = providers;
        applet.selectedProviderID = currentCase.selected || "codex";
        settle.restart();
    }

    function visibleParts(item, result) {
        if (!item.visible)
            return;
        if (["panelProviderText", "panelStandaloneText", "panelProviderIcon", "panelIdentityIcon", "panelMeterTrack"].indexOf(item.objectName) >= 0) {
            var position = item.mapToItem(panel.item, 0, 0);
            result.push({
                name: item.objectName,
                text: item.text || "",
                truncated: item.truncated === true,
                x: position.x,
                y: position.y,
                width: item.width,
                height: item.height
            });
        }
        for (var i = 0; i < item.children.length; i++)
            visibleParts(item.children[i], result);
    }

    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            capture.applet.expanded = true;
            var popup = capture.applet.fullRepresentationItem;
            if (!popup || !panel.item || capture.usageLifecycle.loading || capture.applet.costLoading || capture.applet.providers.length !== capture.expectedProviders)
                return;
            popup.Window.window.width = 560;
            popup.Window.window.height = 360;
            capture.snapshot = JSON.parse(JSON.stringify(capture.applet.providers));
            stop();
            capture.nextCase();
        }
    }

    Timer {
        id: settle
        interval: 250
        onTriggered: {
            var parts = [];
            capture.visibleParts(panel.item, parts);
            var result = {
                id: capture.currentCase.id,
                width: panel.width,
                height: panel.height,
                text: capture.applet.compactText(),
                rendered: capture.compactPanelItem.primaryText,
                compositions: capture.compactPanelItem.textCompositions,
                provider: capture.applet.selectedCompactProvider().provider,
                inline: capture.compactPanelItem.inlinePrimaryText,
                identity: capture.compactPanelItem.showPrimaryIdentity,
                parts: parts
            };
            console.log("PANEL_MATRIX_RESULT:" + JSON.stringify(result));
            if (!canvas.grabToImage(function (image) {
                if (!image.saveToFile(capture.imagePath + "/" + capture.currentCase.id + ".png")) {
                    console.error("SMOKE_FAILED: could not save matrix screenshot");
                    return;
                }
                capture.nextCase();
            }))
                console.error("SMOKE_FAILED: could not capture matrix case");
        }
    }
}
