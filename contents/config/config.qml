import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "configure"
        source: "configGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Providers")
        icon: "view-list-details"
        source: "configProviders.qml"
    }
    ConfigCategory {
        name: i18n("Panel")
        icon: "preferences-desktop-display"
        source: "configPanel.qml"
    }
    ConfigCategory {
        name: i18n("Popup")
        icon: "view-list-details"
        source: "configPopup.qml"
    }
    ConfigCategory {
        name: i18n("Notifications")
        icon: "preferences-desktop-notification"
        source: "configNotifications.qml"
    }
    ConfigCategory {
        name: i18n("Diagnostics")
        icon: "utilities-terminal"
        source: "configDiagnostics.qml"
    }
}
