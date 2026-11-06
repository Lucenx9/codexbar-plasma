import QtQuick
import QtQuick.Window
import QtTest
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
        height: capture.currentCase.vertical ? Math.max(240, panel.height + 32) : 100
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
                // Loader.item is typed QObject; the untyped property reaches
                // CompactRepresentation's own switches without a lint warning.
                capture.compactPanelItem.animationsEnabled = false;
                capture.compactPanelItem.interactive = false;
            }
        }
    }

    TestCase {
        id: input
        when: false
    }

    function namedItem(item, name) {
        if (item.objectName === name) return item;
        for (var i = 0; i < item.children.length; i++) {
            var found = namedItem(item.children[i], name);
            if (found) return found;
        }
        return null;
    }

    function nextCase() {
        if (currentCase.interaction === "press")
            input.mouseRelease(canvas, 0, 0);
        input.mouseMove(canvas, 0, 0);
        canvas.forceActiveFocus();
        caseIndex++;
        if (caseIndex >= cases.length) {
            console.log("SMOKE_CAPTURED:" + scenario);
            return;
        }
        currentCase = cases[caseIndex];
        compactPanelItem.interactive = !!currentCase.interaction;
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
        if (currentCase.edge === "tiny") {
            providers[0].rows[0].usedPercent = 1;
            providers[0].rows[0].leftPercent = 99;
            providers[0].rows[1].usedPercent = 15;
            providers[0].rows[1].leftPercent = 85;
        }
        if (currentCase.edge === "warning") {
            var warningProvider = providers.length > 1 ? providers[1] : providers[0];
            warningProvider.rows[0].usedPercent = 85;
            warningProvider.rows[0].leftPercent = 15;
        }
        if (currentCase.edge === "stale-confidence-incident") {
            providers[0].usageStale = true;
            providers[0].hasIncident = true;
            providers[0].statusKnown = true;
            providers[0].statusSeverity = "minor";
            providers[0].rows[0].dataConfidence = "estimated";
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
            var meter = capture.namedItem(panel.item, "panelProviderMeter");
            if (capture.currentCase.interaction === "focus")
                meter.forceActiveFocus(Qt.TabFocusReason);
            if (capture.currentCase.interaction === "hover" || capture.currentCase.interaction === "press")
                input.mouseMove(meter, meter.width / 2, meter.height / 2);
            if (capture.currentCase.interaction === "press")
                input.mousePress(meter, meter.width / 2, meter.height / 2);
            paint.restart();
        }
    }

    Timer {
        id: paint
        interval: 50
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
