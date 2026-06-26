import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: page

    readonly property string projectUrl: "https://github.com/Lucenx9/codexbar-plasma"
    readonly property string upstreamUrl: "https://github.com/steipete/CodexBar"

    ColumnLayout {
        width: parent.width
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                source: Qt.resolvedUrl("../icons/codex.svg")
                Layout.preferredWidth: Kirigami.Units.iconSizes.large
                Layout.preferredHeight: Kirigami.Units.iconSizes.large
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing / 2

                Kirigami.Heading {
                    text: i18n("CodexBar Plasma")
                    level: 2
                    Layout.fillWidth: true
                }

                Controls.Label {
                    text: i18n("KDE Plasma widget for CodexBar provider usage.")
                    opacity: 0.7
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.Button {
                text: i18n("Project")
                icon.name: "globe"
                onClicked: Qt.openUrlExternally(page.projectUrl)
            }

            Controls.Button {
                text: i18n("Upstream CodexBar")
                icon.name: "view-list-details"
                onClicked: Qt.openUrlExternally(page.upstreamUrl)
            }

            Controls.Button {
                text: i18n("CLI documentation")
                icon.name: "help-contents"
                onClicked: Qt.openUrlExternally(page.upstreamUrl + "/blob/main/docs/cli.md")
            }

            Controls.Button {
                text: i18n("License")
                icon.name: "license"
                onClicked: Qt.openUrlExternally(page.projectUrl + "/blob/main/LICENSE")
            }
        }

        Controls.Label {
            Layout.fillWidth: true
            text: i18n("Provider logic, authentication, quota parsing, and JSON output come from the CodexBar CLI. This widget keeps the Plasma frontend small and focused.")
            opacity: 0.72
            wrapMode: Text.WordWrap
        }
    }
}
