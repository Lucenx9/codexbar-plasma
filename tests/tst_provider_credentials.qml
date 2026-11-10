import QtQuick
import QtTest
import "../contents/ui/config/ProviderCredentials.js" as Credentials
import "../contents/ui/config/ProviderDescriptor.js" as Descriptor

TestCase {
    name: "ProviderCredentials"

    function test_versionGatesAndLinuxAllowlist() {
        for (var version of ["", "garbage", "CodexBar 0.79.0", "CodexBar 0.81.0", "CodexBar 0.82.0-beta.1"]) {
            verify(!Credentials.supportsCookie("claude", version, null));
            verify(!Credentials.supportsClear(version));
        }
        for (var provider of ["claude", "claudeplatform", "commandcode", "cursor", "mistral",
                              "ollama", "opencodego", "parallel", "raycast", "tinyapi",
                              "traecn", "typesafe", "xapi"]) {
            verify(Credentials.supportsCookie(provider, "CodexBar 0.82.0", null));
            verify(Credentials.supportsCookie(provider, "CodexBar 0.83.0", {supportsConfigCookieHeader: true}));
            verify(!Credentials.supportsCookie(provider, "CodexBar 0.83.0", {supportsConfigCookieHeader: "true"}));
        }
        verify(!Credentials.supportsCookie("opendesign", "CodexBar 0.82.0", null));
        verify(Credentials.supportsCookie("OPEN-DESIGN", "CodexBar 0.83.0", null));
        for (var refused of ["gemini", "helmcode", "abacus", "deepseek", "alibaba", "manus", "kimi", "copilot", "future", "__proto__"])
            verify(!Credentials.supportsCookie(refused, "CodexBar 0.83.0", {supportsConfigCookieHeader: true}));
        verify(Credentials.supportsClear("CodexBar 0.82.0"));
    }
    function test_loginIsCopilotOnlyAndHiddenBelowRelease() {
        verify(!Credentials.supportsLogin("copilot", "CodexBar 0.79.0"));
        verify(!Credentials.supportsLogin("copilot", "CodexBar 0.80.0-rc1"));
        verify(!Credentials.supportsLogin("claude", "CodexBar 0.83.0"));
        verify(Credentials.supportsLogin("COPILOT", "CodexBar 0.80.0"));
    }
    function test_sessionImportIsVersionGatedAndSecretOnly() {
        for (var version of ["", "0.83.0", "0.84.0-rc.1", "unknown"]) {
            verify(!Credentials.supportsSessionImport("claudeplatform", version, null));
            verify(!Credentials.supportsCookie("workbuddy", version, null));
        }
        verify(Credentials.supportsSessionImport("claudeplatform", "0.84.0", null));
        verify(Credentials.supportsCookie("workbuddy", "0.84.0", {supportsConfigCookieHeader: true}));
        verify(!Credentials.supportsCookie("workbuddy", "0.84.0", {supportsConfigCookieHeader: false}));
        verify(!Credentials.supportsSessionImport("claudeplatform", "0.84.0", {supportsConfigCookieHeader: false}));
        for (var id of ["claude", "copilot", "future", "__proto__"])
            verify(!Credentials.supportsSessionImport(id, "0.84.0", null));
        var field = {kind: "secret", writeCommand: ["codexbar", "config", "login", "--provider", "claudeplatform", "--stdin", "--json"]};
        verify(Descriptor.planSecretPrompt(field, "codexbar").ok);
        verify(!Descriptor.planFieldWrite(field, "private", "codexbar").ok);
        verify(!Descriptor.planAction({command: field.writeCommand}, "codexbar").ok);
        field.kind = "text";
        verify(!Descriptor.planSecretPrompt(field, "codexbar").ok);
        verify(!Descriptor.planFieldWrite(field, "private", "codexbar").ok);
        field.kind = "secret";
        for (var id of ["copilot", "claude", "future"]) {
            field.writeCommand[4] = id;
            verify(!Descriptor.planSecretPrompt(field, "codexbar").ok);
        }
        field.writeCommand[4] = "claudeplatform";
        field.writeCommand.push("{value}");
        verify(!Descriptor.planSecretPrompt(field, "codexbar").ok);
        compare(Credentials.helperCommand("file:///tmp/auth.py", "codexbar", "import-session", "copilot"), "");
        verify(Credentials.helperCommand("file:///tmp/auth.py", "codexbar", "import-session", "claudeplatform").length > 0);
    }
    function test_cookieWriterIsSecretOnly() {
        var field = {kind: "secret", writeCommand: ["codexbar", "config", "set-cookie", "--provider", "claude", "--stdin"]};
        verify(Descriptor.planSecretPrompt(field, "codexbar").ok);
        verify(!Descriptor.planFieldWrite(field, "synthetic-cookie", "codexbar").ok);
        field.kind = "text";
        field.writeCommand.push("{value}");
        verify(!Descriptor.planFieldWrite(field, "synthetic-cookie", "codexbar").ok);
        field.kind = "secret";
        verify(!Descriptor.planSecretPrompt(field, "codexbar").ok);
    }
    function test_helperCommandsQuoteAndRejectUnsafeInputs() {
        var command = Credentials.helperCommand("file:///tmp/a%20b/provider-auth.py", "/tmp/cli ' $test", "login", "copilot");
        verify(command.indexOf("'/tmp/a b/provider-auth.py'") >= 0);
        verify(command.indexOf("--action login --provider 'copilot'") >= 0);
        compare(Credentials.helperCommand("https://bad/helper.py", "codexbar", "login", "copilot"), "");
        compare(Credentials.helperCommand("file:///tmp/%zz", "codexbar", "login", "copilot"), "");
        compare(Credentials.helperCommand("file:///tmp/helper.py", "codexbar", "login", "claude"), "");
        compare(Credentials.helperCommand("file:///tmp/helper.py", "codexbar", "invented", "copilot"), "");
    }
    function test_responseDiscardsUntrustedDataAndRequiresMatchingProvider() {
        var raw = JSON.stringify({status: "ok", provider: "claude", enabled: true, cookie: "secret"});
        compare(Credentials.result(raw, 0, "claude", "set-cookie"), {status: "ok", enabled: true});
        compare(Credentials.result(raw, 1, "claude", "set-cookie").status, "failed");
        compare(Credentials.result("", 127, "copilot", "login").status, "unavailable");
        compare(Credentials.result(raw, 0, "cursor", "set-cookie").status, "failed");
        for (var bad of ["", "{", "[]", "null", "x".repeat(1025), '{"provider":"claude","status":"ok"}'])
            compare(Credentials.result(bad, 0, "claude", "set-cookie").status, "failed");
        compare(Credentials.result('{"cancelled":true}', 0, "claude", "set-cookie").status, "cancelled");
        for (var state of ["cancelled", "expired", "conflict", "unavailable"])
            compare(Credentials.result(JSON.stringify({provider:"copilot", status:state, error:"secret"}), 0, "copilot", "login"), {status:state});
    }
}
