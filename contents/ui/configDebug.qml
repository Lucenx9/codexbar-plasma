import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

KCM.SimpleKCM {
    id: page

    property string cfg_commandPath
    property string cfg_commandPathDefault

    readonly property string commandPath: (cfg_commandPath || "codexbar").trim()
    property bool diagnosticRunning: false
    property string diagnosticOutput: ""
    property string diagnosticError: ""
    property string activeCommand: ""

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'"
    }

    function runDiagnostic() {
        var provider = diagnosticProviderField.text.trim()
        if (provider.length === 0) {
            provider = "all"
        }
        var command = shellQuote(commandPath) + " diagnose --provider " + shellQuote(provider) + " --format json --redact"
        runCommand(command)
    }

    function runProviderList() {
        var command = shellQuote(commandPath) + " config providers --format json --json-only"
        runCommand(command)
    }

    function runCommand(command) {
        if (commandPath.length === 0) {
            diagnosticError = i18n("Set the codexbar command path in the General page.")
            return
        }
        if (activeCommand.length > 0) {
            diagnosticSource.disconnectSource(activeCommand)
        }
        diagnosticRunning = true
        diagnosticOutput = ""
        diagnosticError = ""
        activeCommand = command
        diagnosticSource.connectSource(command)
    }

    function handleDiagnosticData(sourceName, data) {
        if (sourceName !== activeCommand) {
            return
        }
        diagnosticSource.disconnectSource(sourceName)
        activeCommand = ""
        diagnosticRunning = false

        var stdoutText = data && data["stdout"] ? data["stdout"].trim() : ""
        var stderrText = data && data["stderr"] ? data["stderr"].trim() : ""
        var exitCode = data && data["exit code"] !== undefined ? Number(data["exit code"]) : 0
        diagnosticOutput = stdoutText.length > 0 ? stdoutText : i18n("No diagnostic output.")
        diagnosticError = exitCode !== 0 && stderrText.length > 0 ? stderrText : ""
    }

    Plasma5Support.DataSource {
        id: diagnosticSource

        engine: "executable"
        interval: 0

        onNewData: function(sourceName, data) {
            page.handleDiagnosticData(sourceName, data)
        }
    }

    ColumnLayout {
        width: parent.width
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            Layout.fillWidth: true
            text: i18n("Run redacted CodexBar CLI diagnostics from Plasma. The diagnostic command omits raw tokens, cookies, auth headers, emails, account IDs, org IDs, raw responses, and billing-history records.")
            opacity: 0.72
            wrapMode: Text.WordWrap
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            Controls.TextField {
                id: diagnosticProviderField
                Kirigami.FormData.label: i18n("Provider:")
                Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                placeholderText: i18n("all")
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.Button {
                text: i18n("Run redacted diagnostics")
                icon.name: "tools-report-bug"
                enabled: !page.diagnosticRunning
                onClicked: page.runDiagnostic()
            }

            Controls.Button {
                text: i18n("List providers")
                icon.name: "view-list-details"
                enabled: !page.diagnosticRunning
                onClicked: page.runProviderList()
            }
        }

        Controls.BusyIndicator {
            running: page.diagnosticRunning
            visible: running
            Layout.alignment: Qt.AlignHCenter
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Error
            text: page.diagnosticError
            visible: page.diagnosticError.length > 0
            showCloseButton: true
            onVisibleChanged: if (!visible) page.diagnosticError = ""
        }

        Controls.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 16

            Controls.TextArea {
                id: diagnosticOutputArea
                readOnly: true
                wrapMode: TextEdit.NoWrap
                text: page.diagnosticOutput
                font.family: "monospace"
                placeholderText: i18n("Diagnostic output appears here.")
            }
        }
    }
}
