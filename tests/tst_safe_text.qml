import QtQuick
import QtTest
import "../contents/ui/SafeText.js" as SafeText

TestCase {
    name: "SafeText"

    function test_boundsAndFlattensDisplayMessages() {
        compare(SafeText.cliMessage("  first\nsecond\u0000  ", 12), "first second")
        compare(SafeText.cliMessage("x".repeat(40), 12), "x".repeat(12))
    }

    function test_plainTextRichWrapperEscapesActiveMarkup() {
        var richText = SafeText.plainTextAsRichText(
            "Status <img src=\"http://127.0.0.1/probe\"> & <test-org>")

        compare(richText,
            "<span>Status &lt;img src=&quot;http://127.0.0.1/probe&quot;&gt; &amp; &lt;test-org&gt;</span>")
        verify(richText.indexOf("<img") === -1)
        verify(richText.indexOf("<test-org>") === -1)
    }

    function test_plainTextRichWrapperPreservesLineBreaksAndRejectsStructures() {
        compare(SafeText.plainTextAsRichText("first\nsecond"), "<span>first<br>second</span>")
        compare(SafeText.plainTextAsRichText({ text: "unsafe" }), "")
        compare(SafeText.plainTextAsRichText(["unsafe"]), "")
    }

    function test_plainTextRichWrapperRemovesNonDisplayControls() {
        compare(SafeText.plainTextAsRichText("first\u0000\u0007\tsecond"),
            "<span>first   second</span>")
    }

    function test_mnemonicRichWrapperPreservesEscapedEntities() {
        compare(SafeText.plainTextAsMnemonicRichText("<test> & \"quoted\""),
            "<span>&&lt;test&&gt; &&amp; &&quot;quoted&&quot;</span>")
    }

    function test_plainMnemonicLabelLeavesMarkupLiteralAndEscapesAmpersands() {
        compare(SafeText.plainTextAsMnemonicLabel("<test> & \"quoted\""),
            "<test> && \"quoted\"")
        compare(SafeText.plainTextAsMnemonicLabel({ text: "unsafe" }), "")
    }

    function test_plainButtonTextFollowsTheControlsStyleLabelPath() {
        compare(SafeText.plainButtonText("Docs & help", false), "Docs && help")
        compare(SafeText.plainButtonText("Docs & help", true),
            SafeText.plainTextAsMnemonicRichText("Docs & help"))
    }

    function test_emptyMessageStaysEmpty() {
        // QML's V4 engine returns -1 for "".indexOf(""), unlike ECMAScript's 0,
        // so the lookahead guard in redactCredentials must not use indexOf as a
        // startsWith test: with empty input that turned every no-error message
        // into "[redacted]".
        compare(SafeText.cliMessage("", 500), "")
        compare(SafeText.cliDiagnostic("", 500), "")
        compare(SafeText.cliMessage("   \n\t", 500), "")
    }

    function test_displayMessagesRejectStructuresAndKeepScalars() {
        compare(SafeText.cliMessage({ message: "quota exceeded" }, 500), "")
        compare(SafeText.cliMessage(["quota exceeded"], 500), "")
        compare(SafeText.cliMessage(42, 500), "42")
        compare(SafeText.cliMessage(0, 500), "0")
        compare(SafeText.cliMessage(false, 500), "false")
    }

    function test_skipsBoundedLeadingPaddingBeforeMessage() {
        compare(SafeText.boundedDisplayText(" ".repeat(5000) + "quota exceeded", 500), "quota exceeded")
        compare(SafeText.cliMessage(" ".repeat(5000) + "quota exceeded", 500), "quota exceeded")
    }

    function test_redactsCommonCredentialShapes() {
        var message = SafeText.cliMessage(
            "Authorization: Bearer header.payload.signature api_key=sk-secretvalue Cookie: session=abc; theme=dark",
            500)

        verify(message.indexOf("header.payload.signature") === -1)
        verify(message.indexOf("sk-secretvalue") === -1)
        verify(message.indexOf("session=abc") === -1)
        verify(message.indexOf("[redacted]") !== -1)
    }

    function test_redactsQuotedAndJsonCredentialShapes() {
        var message = SafeText.cliDiagnostic(
            "Authorization: \"Bearer header.payload.signature\"\n"
                + "Cookie: \"session=abc\"\n"
                + '{"apiKey":"sk-secretvalue","accessToken":"secret-token"}',
            500)

        verify(message.indexOf("header.payload.signature") === -1)
        verify(message.indexOf("session=abc") === -1)
        verify(message.indexOf("sk-secretvalue") === -1)
        verify(message.indexOf("secret-token") === -1)
        compare(message.match(/\[redacted\]/g).length, 4)
    }

    function test_redactsCompleteUnquotedAuthorizationValues() {
        var message = SafeText.cliDiagnostic(
            "Authorization: Basic dXNlcjpwYXNzd29yZA==\n"
                + "Proxy-Authorization: Digest username=user, response=secret-response",
            500)

        verify(message.indexOf("dXNlcjpwYXNzd29yZA==") === -1)
        verify(message.indexOf("username=user") === -1)
        verify(message.indexOf("secret-response") === -1)
        compare(message.match(/\[redacted\]/g).length, 2)
    }

    function test_preservesDiagnosticLinesWhileBoundingAndRedacting() {
        var diagnostic = SafeText.cliDiagnostic("line one\nBearer secret-token\nline three", 32)

        verify(diagnostic.indexOf("\n") !== -1)
        verify(diagnostic.indexOf("secret-token") === -1)
        verify(diagnostic.length <= 32)
    }

    function test_dropsNonFatalLoaderWarningsFromCliErrors() {
        var stderrText = "/usr/bin/codexbar: /lib64/libcurl.so.4: no version information available (required by /usr/bin/codexbar)\n"
            + "Error: Not logged in to Gemini."

        compare(SafeText.cliMessage(SafeText.stripLoaderDiagnostics(stderrText), 500),
            "Error: Not logged in to Gemini.")
    }

    function test_dropsLoaderWarningsWhenThePathContainsSpaces() {
        var stderrText = "/home/my user/bin/codexbar: /lib64/libcurl.so.4: no version information available (required by /home/my user/bin/codexbar)\n"
            + "Error: quota exceeded."

        compare(SafeText.cliMessage(SafeText.stripLoaderDiagnostics(stderrText), 500), "Error: quota exceeded.")
    }

    function test_keepsLoaderWarningWhenStderrCarriesNothingElse() {
        var stderrText = "/usr/bin/codexbar: /lib64/libcurl.so.4: no version information available (required by /usr/bin/codexbar)"

        verify(SafeText.stripLoaderDiagnostics(stderrText).indexOf("no version information available") !== -1)
    }

    function test_preservesFatalLoaderErrorsAndOrdinaryMessages() {
        var fatal = "codexbar: error while loading shared libraries: libcurl.so.4: cannot open shared object file"

        compare(SafeText.stripLoaderDiagnostics(fatal), fatal)
        compare(SafeText.stripLoaderDiagnostics("quota exceeded"), "quota exceeded")
    }

    function test_redactsCredentialCrossingDiagnosticBoundary() {
        var padding = "x".repeat(SafeText.maximumDiagnosticLength - 6)
        var diagnostic = SafeText.cliDiagnostic(
            padding + ":sk-1234567890-secret",
            SafeText.maximumDiagnosticLength)

        verify(diagnostic.indexOf("sk-123") === -1)
        verify(diagnostic.indexOf(":[reda") !== -1)
        verify(diagnostic.length <= SafeText.maximumDiagnosticLength)
    }

    function test_doesNotExposeDiagnosticLookaheadAfterRedactionShrinksText() {
        var authorization = "Authorization: Bearer " + "a".repeat(200) + "\n"
        var padding = "x".repeat(SafeText.maximumDiagnosticLength - authorization.length)
        var diagnostic = SafeText.cliDiagnostic(
            authorization + padding + "password=POST_BOUNDARY_SECRET",
            SafeText.maximumDiagnosticLength)

        verify(diagnostic.indexOf("POST_BOUNDARY_SECRET") === -1)
        verify(diagnostic.indexOf("password=") === -1)
        verify(diagnostic.length <= SafeText.maximumDiagnosticLength)
    }

    function test_rejectsOversizedCliJsonBeforeParsing() {
        compare(SafeText.cliJsonText("{}"), "{}")
        compare(SafeText.cliJsonText("x".repeat(SafeText.maximumCliJsonLength + 1)), null)
    }
}
