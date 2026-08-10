import QtQuick
import QtTest
import "../contents/ui/SafeText.js" as SafeText

TestCase {
    name: "SafeText"

    function test_boundsAndFlattensDisplayMessages() {
        compare(SafeText.cliMessage("  first\nsecond\u0000  ", 12), "first second")
        compare(SafeText.cliMessage("x".repeat(40), 12), "x".repeat(12))
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

    function test_preservesDiagnosticLinesWhileBoundingAndRedacting() {
        var diagnostic = SafeText.cliDiagnostic("line one\nBearer secret-token\nline three", 32)

        verify(diagnostic.indexOf("\n") !== -1)
        verify(diagnostic.indexOf("secret-token") === -1)
        verify(diagnostic.length <= 32)
    }
}
