import QtQuick
import QtTest

TestCase {
    name: "ConfigModel"

    // The settings dialog pages are registered here: every supported page
    // must resolve to its QML source, and the retired About page must stay
    // out of the dialog.
    function test_settingsDialogRegistersItsPages() {
        var component = Qt.createComponent("../contents/config/config.qml");
        if (component.status === Component.Error
                && /module "org\.kde\.[^"]+" is not installed/.test(component.errorString())) {
            skip("Config model checks need the optional KDE QML modules");
            return;
        }
        compare(component.status, Component.Ready, component.errorString());
        var model = component.createObject(this);
        verify(model !== null);
        var sources = [];
        for (var i = 0; i < model.count; i++)
            sources.push(model.get(i).source);
        compare(sources.sort(), [
            "configDiagnostics.qml",
            "configGeneral.qml",
            "configNotifications.qml",
            "configPanel.qml",
            "configPopup.qml",
            "configProviders.qml"
        ]);
        verify(sources.indexOf("configAbout.qml") < 0);
    }
}
