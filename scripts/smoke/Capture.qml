import QtQuick
import org.kde.kirigami as Kirigami

// Added only to a temporary copy of main.qml by smoke_popup.py.
Item {
    id: capture

    required property var applet
    required property string scenario
    required property string imagePath
    property bool prepared: false

    Component.onCompleted: {
        applet.expanded = true;
        console.log("SMOKE_LOADED:" + scenario);
    }

    // plasmawindowed owns the window background in a different QML engine;
    // grabToImage callbacks cannot cross that boundary. Supply the same theme
    // background inside the popup's engine so its capture is opaque.
    Rectangle {
        parent: capture.applet.fullRepresentationItem
        anchors.fill: parent
        z: -1
        color: Kirigami.Theme.backgroundColor
    }

    function scenarioReady() {
        if (scenario === "loading")
            return applet.loading && applet.providers.length === 0;
        if (applet.loading || applet.costLoading || applet.providers.length !== 2)
            return false;
        var codex = applet.providers[applet.providerIndexForID("codex")];
        var claude = applet.providers[applet.providerIndexForID("claude")];
        if (!codex || !claude || codex.rows.length !== 2 || codex.error.length > 0)
            return false;
        if (scenario === "partial-error")
            return applet.selectedProviderID === "claude" && claude.error.indexOf("Synthetic provider timeout") >= 0;
        if (claude.error.length > 0 || claude.rows.length !== 2)
            return false;
        if (scenario === "long-text")
            return applet.selectedProviderID === "codex" && !applet.accountLoadingForProvider("codex") && applet.accountOptionsForProvider("codex").length === 2 && codex.account.length > 50;
        return applet.overviewSelected;
    }

    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            var popup = capture.applet.fullRepresentationItem;
            if (!popup || popup.width <= 0 || popup.height <= 0)
                return;
            if (!capture.prepared) {
                capture.applet.expanded = true;
                if (capture.scenario !== "loading" && (capture.applet.loading || capture.applet.providers.length !== 2))
                    return;
                if (capture.scenario === "long-text") {
                    capture.applet.openProviderFromPanel("codex");
                    capture.applet.loadAccounts("codex");
                } else if (capture.scenario === "normal")
                    capture.applet.selectGlobalView("overview");
                else if (capture.scenario === "partial-error")
                    capture.applet.openProviderFromPanel("claude");
                capture.prepared = true;
            }
            if (capture.scenarioReady()) {
                console.log("SMOKE_READY:" + capture.scenario);
                stop();
                settle.start();
            }
        }
    }

    Timer {
        id: settle

        // Let layout and tab animations settle after the state is established.
        interval: 600
        onTriggered: {
            if (!capture.scenarioReady()) {
                console.error("SMOKE_FAILED: scenario changed before capture");
                return;
            }
            var popup = capture.applet.fullRepresentationItem;
            console.log("SMOKE_CAPTURE_START:" + capture.scenario);
            var accepted = popup.grabToImage(function (result) {
                if (result.saveToFile(capture.imagePath))
                    console.log("SMOKE_CAPTURED:" + capture.scenario);
                else
                    console.error("SMOKE_FAILED: could not save popup screenshot");
            });
            if (!accepted)
                console.error("SMOKE_FAILED: could not capture popup");
        }
    }
}
