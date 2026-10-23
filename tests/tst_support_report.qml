import QtQuick
import QtTest
import "../contents/ui/SupportReport.js" as SupportReport
import "../contents/ui/SafeText.js" as SafeText

TestCase {
    name: "SupportReport"

    function payload() {
        return {environment: {plasma: "6.5.0", frameworks: "6.19.0", qt: "6.9.2"},
            selected: {status: "local", version: "0.73.0", path: "/home/private/.local/bin/codexbar", manager: "managed"},
            system: {status: "local", version: "0.67.0", path: "/usr/bin/codexbar", manager: "dpkg"},
            providers: {status: "checked", enabled: ["codex", "future-provider"]}, tools: {python3: true, timeout: false}}
    }

    function test_allowlistedFactsAndCompleteReport() {
        var value = payload()
        value.secret = "do-not-copy"
        value.environment.hostname = "private-host"
        var facts = SupportReport.response(JSON.stringify(value))
        var text = SupportReport.markdown({facts: facts, widgetVersion: "0.3.10", commandPath: "codexbar",
            timestamp: "2026-10-08T09:00:00Z", modules: {QtQuick: true, "QtQuick.Dialogs": false},
            lastError: "Failed account_id=acct_private email user@example.com Bearer token-secret /home/private/config"})
        verify(text.indexOf("0.73.0") >= 0)
        verify(text.indexOf("0.67.0") >= 0)
        verify(text.indexOf("managed") >= 0)
        verify(text.indexOf("dpkg") >= 0)
        verify(text.indexOf("codex, future-provider") >= 0)
        verify(text.indexOf("QtQuick.Dialogs: unavailable") >= 0)
        verify(text.indexOf("org.kde.kquickcontrolsaddons: not checked") >= 0)
        verify(text.indexOf("timeout: not found") >= 0)
        for (var secret of ["private-host", "do-not-copy", "acct_private", "user@example.com", "token-secret", "/home/private"])
            verify(text.indexOf(secret) === -1, secret)
        verify(text.indexOf("[path]") >= 0)
    }

    function test_malformedAndOversizedResults() {
        for (var text of ["", "null", "[]", "false", "x".repeat(32769)])
            verify(!SupportReport.response(text).valid)
        var value = payload()
        value.providers.enabled = ["codex\nsecret=leak"]
        verify(!SupportReport.response(JSON.stringify(value)).valid)
        value.providers.enabled = ["codex"]
        value.environment.plasma = "<img src=leak>"
        compare(SupportReport.response(JSON.stringify(value)).environment.plasma, "unknown")
    }

    function test_customFilesystemLayoutsNeverReachTheSharedReport() {
        for (var path of ["/srv/alice/bin/codexbar", "/data/private project/tool", "/var/home/alice/tool",
                          "/mnt/private-volume/cli", "/root/.local/bin/codexbar", "/Users/alice/tool"]) {
            var value = payload()
            value.selected.path = path
            value.system.path = "/usr/bin/codexbar"
            var facts = SupportReport.response(JSON.stringify(value))
            var report = SupportReport.markdown({facts: facts, lastError: "Could not read " + path + " (permission denied)"})
            verify(report.indexOf(path) < 0, report)
            for (var personal of ["alice", "private project", "private-volume", "/usr/bin", "/root"])
                verify(report.indexOf(personal) < 0, report)
            verify(report.indexOf("Resolved path:") < 0, report)
            verify(report.indexOf("Same resolved path as selected: no") >= 0)
            verify(report.indexOf("managed") >= 0 && report.indexOf("0.73.0") >= 0)
            compare(facts.selected.path, path, "sharing must not rewrite local probe facts")
            value.system.path = path
            verify(SupportReport.markdown({facts: SupportReport.response(JSON.stringify(value))})
                .indexOf("Same resolved path as selected: yes") >= 0)
        }
    }

    function test_diagnosticPathsWithSpacesQuotesAndFileUrlsAreOmitted() {
        for (var text of ['Could not open "/srv/private alice/tool" after failure',
                          "Could not open '/data/private alice/tool' after failure",
                          "Could not open file:///mnt/private%20alice/tool",
                          'Could not open {"file":"\\/srv\\/private alice\\/tool"}',
                          'Could not open {"file":"\\u002fsrv\\u002fprivate-alice\\u002ftool"}',
                          'Could not open {"file":"\\u002Fsrv\\u002Fprivate-alice\\u002Ftool"}',
                          "Could not open /data/private alice/tool after failure"]) {
            var shared = SupportReport.sharedText(text, 1024)
            verify(shared.indexOf("alice") < 0 && shared.indexOf("private") < 0, shared)
            compare(shared, "[path]")
        }
        var multiline = SupportReport.sharedText("Failed /srv/private alice/tool\nExit code 2", 1024)
        verify(multiline.indexOf("alice") < 0)
        verify(multiline.indexOf("Exit code 2") >= 0, multiline)
    }

    function test_executablePrefixedFailuresKeepTheirNonPersonalReason() {
        compare(SupportReport.sharedText("/srv/alice/codexbar: Permission denied"), "[path]: Permission denied")
        compare(SupportReport.sharedText("bash: line 1: /srv/alice/codexbar: No such file or directory"),
            "[path]: No such file or directory")
        compare(SupportReport.sharedText("/srv/alice/codexbar: Exec format error"), "[path]: Exec format error")
        var loader = SupportReport.sharedText("/srv/alice/codexbar: error while loading shared libraries: "
            + "/data/private-alice/libcustom.so: cannot open shared object file: No such file or directory")
        compare(loader, "[path]: error while loading shared libraries")
        verify(loader.indexOf("alice") < 0)
    }

    function test_relativeAndTildePathsOmitTheWholeDiagnosticLine() {
        for (var path of ["alice/project/config.json", "~alice/.config/tool", "~/private-alice/tool",
                          "./alice/tool", "../alice/tool", '"private alice/project/config.json"',
                          "'private alice/project/config.json'", "alice\\/project\\/config.json",
                          "~alice\\u002f.config\\u002ftool"]) {
            var error = "Could not open " + path + " after failure"
            compare(SupportReport.sharedText(error), "[path]", path)
            var report = SupportReport.markdown({checkError: error, lastError: error})
            verify(report.indexOf("alice") < 0 && report.indexOf("private") < 0, report)
        }
        compare(SupportReport.sharedText("Before\nCould not open private alice/project\nExit code 2"),
            "Before [path] Exit code 2")
        compare(SupportReport.sharedText("Connection timed out. Retry later."),
            "Connection timed out. Retry later.")
        compare(SupportReport.sharedText("~alice/bin/codexbar: Permission denied"), "[path]: Permission denied")
    }

    function test_credentialFilteringCannotHideThePathSeparator() {
        for (var path of ["alice-token=work/project/config.json", "~alice-password=work/.config/tool",
                          "alice-account_id=work/project/config.json", "alicehttps://work/project/config.json"]) {
            var error = "Could not open " + path + " after failure"
            for (var input of [error, SafeText.cliMessage(SafeText.stripLoaderDiagnostics(error),
                                                         SafeText.maximumCliMessageLength)]) {
                var shared = SupportReport.sharedText(input)
                verify(shared.indexOf("alice") < 0 && shared.indexOf("work") < 0, shared)
                var report = SupportReport.markdown({checkError: input, lastError: input})
                verify(report.indexOf("alice") < 0, report)
            }
        }
        compare(SupportReport.sharedText("Before\nBearer token-secret\nExit code 2"),
            "Before [redacted] Exit code 2")
    }

    function test_secretKeyAliasesNeverReachSharedReports() {
        for (var input of ["AWS_SECRET_ACCESS_KEY=SYNTHETIC_CREDENTIAL_VALUE",
                           "secret_key: SYNTHETIC_CREDENTIAL_VALUE",
                           '{"secretAccessKey":"SYNTHETIC_CREDENTIAL_VALUE"}']) {
            var shared = SupportReport.sharedText(input)
            verify(shared.indexOf("SYNTHETIC_CREDENTIAL_VALUE") === -1)
            verify(shared.indexOf("[redacted]") >= 0)
            var report = SupportReport.markdown({lastError: input, checkError: input})
            verify(report.indexOf("SYNTHETIC_CREDENTIAL_VALUE") === -1)
        }
    }

    function test_redactionBeforeBoundsAndMarkdownEscape() {
        var text = SupportReport.sharedText("Bearer \"" + "SECRET".repeat(200) + "\"\n<script>` /Users/alice/config", 128)
        verify(text.indexOf("SECRET") === -1)
        verify(text.indexOf("alice") === -1)
        verify(text.indexOf("<") === -1)
        verify(text.indexOf("`") === -1)
        verify(text.length <= 128)
    }

    function test_commandQuoteAndNoShellInterpolation() {
        var command = SupportReport.command("file:///tmp/a%20b/report.py", "/tmp/cli' $(evil)")
        verify(command.indexOf("'$(evil)'") === -1)
        verify(command.indexOf(" --command '") >= 0)
        compare(SupportReport.command("https://invalid/report.py", "codexbar"), "")
        compare(SupportReport.command("file:///tmp/report.py", "a\nb"), "")
    }

    function test_quotedIdentifiersUrlsAndJwtNeverReachSharedText() {
        var text = SupportReport.sharedText('{"accountId": "Private account label", "org_id": "org_PRIVATE", '
            + '"error": "https://user:private-password@example.test/private/path", '
            + '"value": "eyJheader.eyJpayload.privateSignature"}', 1024)
        for (var secret of ["Private account label", "org_PRIVATE", "private-password", "private/path", "privateSignature"])
            verify(text.indexOf(secret) === -1, secret)
    }

    function test_escapedAndUnterminatedQuotedIdentifiersStayRedacted() {
        var text = SupportReport.sharedText('{"account_id":"abc\\"PRIVATE_ESCAPED"} '
            + "workspace_id='a\\'PRIVATE_SINGLE' next project_id=\"PRIVATE_CUT tail", 1024)
        for (var secret of ["PRIVATE_ESCAPED", "PRIVATE_SINGLE", "PRIVATE_CUT"])
            verify(text.indexOf(secret) === -1, text)
        verify(text.indexOf("next") !== -1, text)
    }

    function test_unknownFieldsDoNotEnterCliNormalization() {
        var value = payload()
        value.selected.secret = {nested: {account: "PRIVATE_MARKER"}}
        var result = SupportReport.response(JSON.stringify(value))
        compare(result.selected.version, "0.73.0")
        verify(JSON.stringify(result).indexOf("PRIVATE_MARKER") === -1)
    }

    function test_uncheckedCliManagersAndProviderIdentities() {
        var text = SupportReport.markdown({facts: SupportReport.response(""), commandPath: "private-command"})
        verify(text.indexOf("Probe status: not checked") >= 0)
        verify(text.indexOf("private-command") === -1)
        var value = payload()
        value.selected.manager = "untrusted-manager"
        compare(SupportReport.response(JSON.stringify(value)).selected.manager, "external")
        for (var id of ["prototype", "constructor", "__proto__", "a".repeat(129)]) {
            value.providers.enabled = [id]
            verify(!SupportReport.response(JSON.stringify(value)).valid)
            verify(!SupportReport.providerID(id))
        }
    }

    function test_overridesMatchWidgetWhitespaceNormalization() {
        var text = SupportReport.markdown({providerOverride: "  codex  ", sourceOverride: " cli "})
        verify(text.indexOf("Provider override (Diagnostics form): codex") >= 0)
        verify(text.indexOf("Source override (Diagnostics form): cli") >= 0)
        verify(text.indexOf("invalid/omitted") === -1)
    }
    function test_truncationKeepsSurrogatePairsWhole() {
        var emoji = "\uD83D\uDE00"
        var text = SupportReport.sharedText("a".repeat(1023) + emoji, 1024)
        compare(text.charCodeAt(text.length - 1) >= 0xD800 && text.charCodeAt(text.length - 1) <= 0xDBFF, false)
        compare(text, "a".repeat(1023))
    }

}
