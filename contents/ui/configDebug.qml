import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import "components" as Components
import "Guards.js" as Guards
import "SafeText.js" as SafeText

KCM.SimpleKCM {
    id: page

    property string cfg_commandPath
    property string cfg_commandPathDefault

    readonly property string commandPath: (cfg_commandPath || "codexbar").trim()
    property bool diagnosticRunning: false
    property string diagnosticOutput: ""
    property string diagnosticError: ""
    property string activeCommand: ""
    property int commandRunSerial: 0
    readonly property int diagnosticCommandTimeoutMs: 60000

    function shellQuote(value) {
        return Guards.shellQuote(value)
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
            finishDiagnosticCommand(activeCommand)
        }
        diagnosticRunning = true
        diagnosticOutput = ""
        diagnosticError = ""
        activeCommand = commandWithRunNonce(command)
        diagnosticSource.connectSource(activeCommand)
        diagnosticCommandTimeoutTimer.restart()
    }

    function commandWithRunNonce(command) {
        if (command.length === 0) {
            return ""
        }
        commandRunSerial += 1
        return "CODEXBAR_PLASMA_RUN=" + commandRunSerial + " " + command
    }

    function finishDiagnosticCommand(sourceName) {
        diagnosticCommandTimeoutTimer.stop()
        diagnosticSource.disconnectSource(sourceName)
        if (sourceName === activeCommand) {
            activeCommand = ""
        }
        diagnosticRunning = false
    }

    function handleDiagnosticTimeout() {
        if (activeCommand.length === 0) {
            return
        }
        finishDiagnosticCommand(activeCommand)
        diagnosticOutput = ""
        diagnosticError = i18n("Diagnostic command timed out. Try again.")
    }

    function handleDiagnosticData(sourceName, data) {
        if (sourceName !== activeCommand) {
            return
        }
        finishDiagnosticCommand(sourceName)

        var stdoutText = data && data["stdout"] ? data["stdout"] : ""
        var stderrText = data && data["stderr"] ? data["stderr"] : ""
        var exitCode = data && data["exit code"] !== undefined ? Number(data["exit code"]) : 0
        var safeOutput = SafeText.cliDiagnostic(stdoutText, SafeText.maximumDiagnosticLength)
        var safeError = SafeText.cliMessage(SafeText.stripLoaderDiagnostics(stderrText), SafeText.maximumCliMessageLength)
        diagnosticOutput = safeOutput.length > 0 ? safeOutput : i18n("No diagnostic output.")
        diagnosticError = exitCode !== 0 ? safeError : ""
    }

    Plasma5Support.DataSource {
        id: diagnosticSource

        engine: "executable"
        interval: 0

        onNewData: function(sourceName, data) {
            page.handleDiagnosticData(sourceName, data)
        }
    }

    Timer {
        id: diagnosticCommandTimeoutTimer

        interval: page.diagnosticCommandTimeoutMs
        repeat: false
        onTriggered: page.handleDiagnosticTimeout()
    }

    ColumnLayout {
        width: parent.width
        spacing: Kirigami.Units.smallSpacing

        Components.PlainControlsLabel {
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

        Components.PlainInlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Error
            plainText: page.diagnosticError
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
