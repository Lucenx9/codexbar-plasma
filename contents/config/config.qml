import QtQuick
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
        name: i18n("Display")
        icon: "preferences-desktop-display"
        source: "configDisplay.qml"
    }
    ConfigCategory {
        name: i18n("Advanced")
        icon: "configure"
        source: "configAdvanced.qml"
    }
    ConfigCategory {
        name: i18n("Debug")
        icon: "tools-report-bug"
        source: "configDebug.qml"
    }
}
