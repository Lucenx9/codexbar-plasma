import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: page

    property alias cfg_provider: providerField.text
    property string cfg_providerDefault
    property alias cfg_source: sourceField.text
    property string cfg_sourceDefault

    Kirigami.FormLayout {
        Controls.Label {
            Kirigami.FormData.label: i18n("Advanced provider override")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 18
            Layout.maximumWidth: Kirigami.Units.gridUnit * 18
            text: i18n("These options pin the widget to one provider or one source. Leave them blank to follow the providers enabled on the Providers page.")
            font: Kirigami.Theme.smallFont
            opacity: 0.72
            wrapMode: Text.WordWrap
        }

        Controls.TextField {
            id: providerField
            Kirigami.FormData.label: i18n("Provider:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 18
            placeholderText: i18n("Provider id (blank = all enabled)")
        }

        Controls.TextField {
            id: sourceField
            Kirigami.FormData.label: i18n("Source:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 18
            placeholderText: i18n("Provider default (blank)")
        }
    }
}
