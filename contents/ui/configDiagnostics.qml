import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import "components" as Components
import "Guards.js" as Guards
import "SafeText.js" as SafeText
import "controllers" as Controllers

KCM.SimpleKCM {
    id: page

    property alias cfg_commandPath: commandPathField.text
    property string cfg_commandPathDefault: "codexbar"

    property alias cfg_provider: providerField.text
    property string cfg_providerDefault: ""
    property alias cfg_source: sourceField.text
    property string cfg_sourceDefault: ""

    readonly property string commandPath: (cfg_commandPath || "codexbar").trim()
    property bool diagnosticRunning: false
    property string diagnosticOutput: ""
    property string diagnosticError: ""
    property string activeCommand: ""
    // Reported environment, filled by the versions probe. Empty until it runs.
    readonly property string resolvedCommandPath: versions.result.path
    readonly property string cliVersionText: versions.result.version
    readonly property bool environmentProbeFailed: versions.checked && versions.result.version.length === 0
    // `Plasmoid` is an attached name, so a bare reference throws wherever the
    // page is loaded outside an applet, such as the settings smoke capture.
    readonly property string widgetVersion: typeof Plasmoid !== "undefined" && Plasmoid.metaData
        ? String(Plasmoid.metaData.version || "") : ""
    property int commandRunSerial: 0
    readonly property int diagnosticCommandTimeoutMs: 60000
    // Shell-side bound for every diagnostics command. disconnectSource cannot
    // kill the child, so without this a hung `codexbar` outlives the page and
    // the dialog. The shell timeout plus kill grace (50s + 5s = 55s) stays
    // below diagnosticCommandTimeoutMs, keeping the QML timer the outer bound.
    readonly property int diagnosticCommandTimeoutSeconds: 50
    readonly property int diagnosticCommandKillAfterSeconds: 5

    onCommandPathChanged: {
        if (activeCommand.length > 0) {
            finishDiagnosticCommand(activeCommand)
        }
        diagnosticOutput = ""
        diagnosticError = ""
    }

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

    // Versions remains an offline probe, using the same selected executable and
    // bounded version/ownership contract as the release checker in General.
    Controllers.CliUpdateController {
        id: versions
        objectName: "cliVersionsController"
        commandPath: page.commandPath
        localOnly: true
    }

    // PATH-resolved copy (system or package-manager installation), probed
    // alongside the selected command so version drift between the two is
    // visible. Hidden when it resolves to the selected command itself.
    Controllers.CliUpdateController {
        id: systemVersions
        objectName: "systemCliVersionsController"
        commandPath: "codexbar"
        localOnly: true
    }
    readonly property bool systemCliDiffers: systemVersions.checked
        && systemVersions.result.path.length > 0
        && systemVersions.result.path !== versions.result.path

    function runEnvironmentProbe() {
        if (commandPath.length === 0)
            diagnosticError = i18n("Set the codexbar command path above.")
        versions.checkNow()
        // Without a selected command the page is already in an error state;
        // do not leave a second probe running past teardown.
        if (commandPath.length > 0) systemVersions.checkNow()
    }

    // Wrap the command so the shell kills a hung child on schedule, the way
    // the provider secret commands use `timeout --kill-after`. The probe
    // mirrors their guard: when GNU timeout is absent the raw command runs
    // instead, so diagnostics keep working without coreutils. `sh -c` carries
    // the conditional because the run-nonce prefix (`NAME=value` assignment)
    // is only valid before a simple command, not before `if`.
    function boundedDiagnosticCommand(command) {
        if (command.length === 0) {
            return ""
        }
        var bounded = "timeout --kill-after=" + shellQuote(diagnosticCommandKillAfterSeconds + "s")
            + " " + shellQuote(diagnosticCommandTimeoutSeconds + "s")
            + " " + command
        var script = "if command -v timeout >/dev/null 2>&1 && timeout --kill-after=1s 1s true >/dev/null 2>&1; then "
            + bounded + "; else " + command + "; fi"
        return "sh -c " + shellQuote(script)
    }

    function runCommand(command) {
        if (commandPath.length === 0) {
            diagnosticError = i18n("Set the codexbar command path above.")
            return
        }
        command = boundedDiagnosticCommand(command)
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

        var rawStdoutText = data && data["stdout"] ? data["stdout"] : ""
        var stdoutText = SafeText.cliJsonText(rawStdoutText)
        var stderrText = data && data["stderr"] ? data["stderr"] : ""
        var exitCode = data && data["exit code"] !== undefined ? Number(data["exit code"]) : 0
        if (stdoutText === null) {
            stdoutText = ""
            stderrText = i18n("codexbar response exceeded the supported size.")
            exitCode = 1
        }
        var safeOutput = SafeText.cliDiagnostic(stdoutText, SafeText.maximumDiagnosticLength)
        var safeError = SafeText.cliMessage(SafeText.stripLoaderDiagnostics(stderrText), SafeText.maximumCliMessageLength)
        // A command reaped by the shell bound above reports the same timeout
        // message as the QML timer. GNU timeout exits 124 when the time limit
        // is reached; when --kill-after escalates to SIGKILL for a child that
        // ignores SIGTERM, it exits 128+SIGKILL instead, so 137 is the
        // bound's other reap status. No wider signal range is mapped: any
        // other 128+signal death is the CLI's own crash, not our bound. The
        // CLI's own stderr still wins when present, so without GNU timeout a
        // genuine silent 124/137 from codexbar reads as a timeout -- accepted
        // because a CLI has no reason to exit silent with timeout's statuses.
        var shellTimeout = exitCode === 124 || exitCode === 137
        diagnosticOutput = safeOutput.length > 0 ? safeOutput : i18n("No diagnostic output.")
        diagnosticError = exitCode !== 0
            ? (safeError.length > 0
                ? safeError
                : (shellTimeout
                    ? i18n("Diagnostic command timed out. Try again.")
                    : i18n("codexbar exited with code %1", Number(exitCode))))
            : ""
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

        Kirigami.FormLayout {
            Layout.fillWidth: true

            Kirigami.Separator {
                Kirigami.FormData.label: i18n("Connection")
                Kirigami.FormData.isSection: true
            }
            RowLayout {
                id: commandPathRow

                Kirigami.FormData.label: i18n("Command path:")
                Layout.preferredWidth: Kirigami.Units.gridUnit * 24
                // FormLayout can stretch nested layouts as the KCM grows, so cap
                // this row to keep its trailing action inside the viewport.
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24

                Controls.TextField {
                    id: commandPathField
                    Layout.fillWidth: true
                    placeholderText: "codexbar"
                }

                Controls.Button {
                    id: usePathCommandButton
                    text: i18n("Use PATH")
                    enabled: page.cfg_commandPath.trim() !== (page.cfg_commandPathDefault || "codexbar")
                    onClicked: page.cfg_commandPath = page.cfg_commandPathDefault || "codexbar"
                }
            }

            Kirigami.Separator {
                Kirigami.FormData.label: i18n("Versions")
                Kirigami.FormData.isSection: true
            }

            Components.PlainControlsLabel {
                id: widgetVersionLabel
                objectName: "widgetVersionLabel"

                Kirigami.FormData.label: i18n("CodexBar Plasma:")
                text: page.widgetVersion.length > 0 ? page.widgetVersion : i18n("Unknown")
            }

            Components.PlainControlsLabel {
                id: cliVersionLabel
                objectName: "cliVersionLabel"

                Kirigami.FormData.label: i18n("CodexBar CLI:")
                text: page.cliVersionText.length > 0 ? page.cliVersionText
                    : (versions.checked ? versions.statusText : i18n("Not checked"))
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                wrapMode: Text.WordWrap
            }

            Components.PlainControlsLabel {
                id: resolvedCommandLabel
                objectName: "resolvedCommandLabel"

                Kirigami.FormData.label: i18n("Resolved command:")
                // The configured value can be a bare name; this is the absolute
                // path Plasma actually runs, which is what a bug report needs.
                text: page.resolvedCommandPath.length > 0 ? page.resolvedCommandPath
                    : (page.environmentProbeFailed ? i18n("Not found") : i18n("Not checked"))
                Layout.fillWidth: true
                Layout.preferredWidth: Kirigami.Units.gridUnit * 24
                elide: Text.ElideMiddle
            }

            Components.PlainControlsLabel {
                id: systemCliVersionLabel
                objectName: "systemCliVersionLabel"
                visible: page.systemCliDiffers

                Kirigami.FormData.label: i18n("System CLI (PATH):")
                text: systemVersions.result.version.length > 0
                    ? i18n("%1 (%2)", systemVersions.result.version, systemVersions.result.path)
                    : systemVersions.result.status === "unknown"
                        ? i18n("Could not identify the installed CLI version.")
                        : i18n("Not found")
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Controls.Button {
                    id: checkEnvironmentButton
                    objectName: "checkEnvironmentButton"

                    text: i18n("Check versions")
                    enabled: !versions.busy && !systemVersions.busy && !page.diagnosticRunning
                    onClicked: page.runEnvironmentProbe()
                }
                Controls.BusyIndicator {
                    running: versions.busy || systemVersions.busy
                    opacity: running ? 1 : 0
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }
            }

            Components.PlainControlsLabel {
                objectName: "cliInstallationLabel"
                text: versions.guidanceText
                visible: versions.checked && versions.result.path.length > 0
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                wrapMode: Text.WordWrap
            }

            Components.PlainControlsLabel {
                text: i18n("This checks installed versions only. Check upstream CLI releases in General / CLI updates.")
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                wrapMode: Text.WordWrap
            }

            Kirigami.Separator {
                Kirigami.FormData.label: i18n("Advanced provider override")
                Kirigami.FormData.isSection: true
            }

            Components.PlainControlsLabel {
                id: advancedOverrideExplanation

                Layout.fillWidth: true
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

        Components.PlainControlsLabel {
            Layout.fillWidth: true
            text: i18n("Run redacted CodexBar CLI diagnostics from Plasma. The diagnostic command omits raw tokens, cookies, auth headers, emails, account IDs, org IDs, raw responses, and billing-history records.")
            font: Kirigami.Theme.smallFont
            opacity: 0.72
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Components.PlainControlsLabel {
                id: diagnosticProviderLabel

                text: i18n("Diagnostic provider:")
            }

            Controls.TextField {
                id: diagnosticProviderField
                Accessible.name: diagnosticProviderLabel.text
                Layout.fillWidth: true
                Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                placeholderText: i18n("all")
                maximumLength: 256
            }

            Item {
                Layout.fillWidth: true
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.Button {
                text: i18n("Run redacted diagnostics")
                icon.name: "utilities-terminal"
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
            id: diagnosticErrorMessage

            Layout.fillWidth: true
            type: Kirigami.MessageType.Error
            plainText: page.diagnosticError
            visible: page.diagnosticError.length > 0
            showCloseButton: true
            onVisibleChanged: {
                if (visible || page.diagnosticError.length === 0) {
                    return
                }
                // Kirigami's close button hid the banner imperatively, severing
                // the visible binding; clear the text and reinstall the binding
                // so later failures still show up.
                page.diagnosticError = ""
                visible = Qt.binding(function() { return page.diagnosticError.length > 0 })
            }
        }

        Controls.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 16

            Controls.TextArea {
                id: diagnosticOutputArea
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.NoWrap
                text: page.diagnosticOutput
                font.family: "monospace"
                placeholderText: i18n("Diagnostic output appears here.")
            }
        }
    }
}
