import QtQuick
import QtTest
import "../contents/ui/config/ProviderAuthentication.js" as Authentication
import "../contents/ui/config/ProviderConfigProtocol.js" as Protocol
import "../contents/ui/config/ProviderSource.js" as Source

TestCase {
    name: "ProviderAuthentication"

    function metadata() {
        return {sourceModes: ["api", "auto"], supportsConfigAPIKey: true,
            supportsConfigCookieHeader: false, environmentVariables: ["OPENROUTER_API_KEY"],
            tokenAccounts: {title: "API keys", setupHint: "Store multiple OpenRouter API keys."}};
    }
    function test_missingMetadataKeepsLegacySourceChoices() {
        compare(Authentication.normalize(undefined, "codex"), null);
        compare(Authentication.normalize(null, "codex"), null);
        compare(Source.availableModes(null), ["auto", "api", "cli", "oauth", "web"]);
        verify(Source.planWrite("codexbar", "codex", "web").ok);
    }
    function test_advertisedModesLimitWritesAndDoNotMutateInput() {
        var raw = metadata();
        raw.sourceModes = ["api", "auto", "api", "future", null, "web; bad"];
        var before = JSON.stringify(raw);
        var normalized = Authentication.normalize(raw, "openrouter");
        compare(Source.availableModes(normalized), ["api", "auto"]);
        verify(Source.planWrite("codexbar", "openrouter", "auto", normalized).ok);
        verify(!Source.planWrite("codexbar", "openrouter", "web", normalized).ok);
        compare(JSON.stringify(raw), before);
        normalized.sourceModes.push("cli");
        compare(raw.sourceModes.length, 6);
        var copy = Source.availableModes(null);
        copy.pop();
        compare(Source.availableModes(null).length, 5);
    }
    function test_malformedCapabilitiesKeepHealthyProviderRecords() {
        for (var raw of [false, "true", [], {}, {sourceModes: "api", supportsConfigAPIKey: "true"}]) {
            var result = Protocol.response(JSON.stringify([{provider: "future", enabled: true,
                authentication: raw}]), "", 0, "list");
            compare(result.outcome, "success");
            verify(result.value[0].enabled);
            var auth = result.value[0].authentication;
            compare(auth.sourceModes, []);
            verify(!auth.supportsConfigAPIKey && !auth.supportsConfigCookieHeader);
            verify(!Source.planWrite("codexbar", "future", "api", auth).ok);
        }
        var inherited = Object.create(metadata());
        compare(Authentication.normalize(inherited, "future").sourceModes, []);
        verify(!Authentication.normalize(inherited, "future").supportsConfigAPIKey);
        verify(!Source.planWrite("codexbar", "future", "api", inherited).ok);
        var empty = metadata();
        empty.sourceModes = [];
        compare(Source.availableModes(Authentication.normalize(empty, "future")), []);
    }
    function test_optionalHintsAreBoundedRedactedAndDiscardUnknownFields() {
        var secret = "sk-abcdefghijklmnopqrstuvwxyz1234567890";
        var raw = metadata();
        raw.apiKey = secret;
        raw.tokenAccounts = {title: "x".repeat(200), setupHint: "api_key=" + secret + " " + "y".repeat(700)};
        raw.environmentVariables = ["OPENROUTER_API_KEY", "OPENROUTER_API_KEY", null,
            "API_KEY=private", "lowercase", "BAD\nNAME", "A".repeat(129), "OTHER_API_URL"];
        var auth = Authentication.normalize(raw, "openrouter");
        compare(auth.environmentVariables, ["OPENROUTER_API_KEY", "OTHER_API_URL"]);
        verify(auth.tokenAccounts.title.length <= 120);
        verify(auth.tokenAccounts.setupHint.length <= 512);
        verify(JSON.stringify(auth).indexOf(secret) < 0);
        verify(JSON.stringify(auth).indexOf("private") < 0);
        raw.tokenAccounts = {title: {}, setupHint: false};
        compare(Authentication.normalize(raw, "openrouter").tokenAccounts, null);
        raw.tokenAccounts = {setupHint: "Valid hint"};
        compare(Authentication.normalize(raw, "future").tokenAccounts.setupHint, "Valid hint");
    }
    function test_listsAreBoundedBeforeInspectingElements() {
        var raw = metadata();
        raw.sourceModes = new Array(64).fill("future").concat(["api"]);
        raw.environmentVariables = [];
        for (var i = 0; i < 70; i++) raw.environmentVariables.push("ENV_" + i);
        var auth = Authentication.normalize(raw, "future");
        compare(auth.sourceModes, []);
        compare(auth.environmentVariables.length, 64);
        compare(auth.environmentVariables[63], "ENV_63");
    }
    function test_hintsRedactOpaqueTokensWithoutAssumingTheirLength() {
        var raw = metadata();
        for (var token of ["x", "or", "and", "a.b", "short-token"]) {
            raw.tokenAccounts.setupHint = "Use Bearer " + token + "; see the provider docs.";
            compare(Authentication.normalize(raw, "future").tokenAccounts.setupHint,
                "Use Bearer [redacted]; see the provider docs.");
        }
        raw.tokenAccounts.setupHint = "Paste a SuperGrok bearer or grok.com cookie. Open token file opens ~/.grok/auth.json.";
        compare(Authentication.normalize(raw, "grok").tokenAccounts.setupHint,
            "Paste a SuperGrok Bearer [redacted] grok.com cookie. Open token file opens ~/.grok/auth.json.");
    }
    function test_loginHintAllowsOnlyTheReleasedCopilotCommand() {
        var raw = metadata();
        raw.loginCommand = "codexbar config login --provider copilot";
        compare(Authentication.normalize(raw, "copilot").loginCommand, raw.loginCommand);
        compare(Authentication.normalize(raw, "future").loginCommand, "");
        for (var command of [null, [], "echo bad", raw.loginCommand + "; bad", raw.loginCommand + " --json"]) {
            raw.loginCommand = command;
            compare(Authentication.normalize(raw, "copilot").loginCommand, "");
        }
    }
}
