import QtQuick
import org.kde.kirigami as Kirigami

// Render the real KCM at a readable width, including its scrollable content.
Rectangle {
    id: preview

    required property var applet
    required property string pageSource
    property int viewportHeight: 0
    readonly property var page: pageLoader.item
    readonly property bool ready: page !== null && (typeof page.providerRosterLoading === "undefined" || !page.providerRosterLoading)

    width: 840
    height: viewportHeight > 0 ? viewportHeight : Math.max(600, Math.min(6000,
        page ? page.flickable.contentHeight + (page.header ? page.header.height : 0) + 40 : 600))
    color: Kirigami.Theme.backgroundColor

    Loader {
        id: pageLoader
        anchors.fill: parent

        Component.onCompleted: {
            var properties = preview.pageSource === "configPopup.qml" || preview.pageSource === "configDiagnostics.qml" ? {
                cfg_commandPath: preview.applet.commandPath
            } : {};
            setSource(Qt.resolvedUrl(preview.pageSource), properties);
        }
        onLoaded: {
            for (var key in item) {
                if (key.indexOf("cfg_") === 0 && key !== "cfg_commandPath" && !key.endsWith("Default") && typeof item[key + "Default"] !== "undefined")
                    item[key] = item[key + "Default"];
            }
            // General only edits a pending text field; other pages keep the
            // synthetic executable supplied before Component.onCompleted.
            if (preview.pageSource === "configDiagnostics.qml")
                item.cfg_commandPath = "codexbar";
        }
    }
}
