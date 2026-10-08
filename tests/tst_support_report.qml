import QtQuick
import QtTest
import "../contents/ui/SupportReport.js" as SupportReport

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
        verify(text.indexOf("/home/[user]") >= 0)
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
}
