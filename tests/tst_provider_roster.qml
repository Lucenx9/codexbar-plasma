import QtQuick
import QtTest
import "../contents/ui/ProviderRoster.js" as ProviderRoster
import "../contents/ui/SafeText.js" as SafeText

TestCase {
    name: "ProviderRoster"

    function test_projectsOnlyBoundedEnabledIdentities() {
        var result = ProviderRoster.response(JSON.stringify([
            null, [], {provider: "constructor", enabled: true},
            {provider: "codex", enabled: "true"},
            {provider: "claude", enabled: false},
            {provider: "future-provider", enabled: true},
            {provider: "codex", enabled: true, displayName: "Codex", apiKey: "private"}
        ]), "loader warning");
        compare(result.outcome, "success");
        compare(result.message, "");
        compare(JSON.stringify(result.providers), JSON.stringify([
            {provider: "future-provider", displayName: "Future Provider"},
            {provider: "codex", displayName: "Codex"}
        ]));
    }

    function test_boundsInputAndRecordCount() {
        compare(ProviderRoster.response("x".repeat(SafeText.maximumCliJsonLength + 1), "").outcome, "tooLarge");
        var records = [];
        for (var i = 0; i < 300; i++) {
            records.push({provider: "provider-" + i, enabled: true, displayName: "x".repeat(200)});
        }
        var result = ProviderRoster.response(JSON.stringify(records), "");
        compare(result.providers.length, 256);
        verify(result.providers.every(function (provider) { return provider.displayName.length <= 120; }));
    }

    function test_preservesRosterIDsAndDuplicates() {
        var result = ProviderRoster.response(JSON.stringify([
            {provider: " GROQCLOUD ", enabled: true},
            {provider: "groq", enabled: true},
            {provider: "groq", enabled: true}
        ]), "");
        compare(result.providers.map(function (provider) { return provider.provider; }).join(","), "GROQCLOUD,groq,groq");
    }

    function test_classifiesEmptyMalformedAndSingleRecordResponses() {
        compare(ProviderRoster.response(null, undefined).outcome, "empty");
        compare(ProviderRoster.response(" \n", "").outcome, "empty");
        compare(ProviderRoster.response("{", "").outcome, "invalidJson");
        var values = ["null", "[]", "false", "3", '"text"', "{}"];
        for (var i = 0; i < values.length; i++) {
            var result = ProviderRoster.response(values[i], "");
            compare(result.outcome, "success");
            compare(result.providers.length, 0);
        }
        var single = ProviderRoster.response('{"provider":"codex","enabled":true}', "");
        compare(single.providers.length, 1);
        compare(single.providers[0].displayName, "Codex");
    }

    function test_errorsAndDisplayNamesRedactCredentials() {
        var secret = "sk-abcdefghijklmnopqrstuvwxyz1234567890";
        var results = [
            ProviderRoster.response("", "api_key=" + secret),
            ProviderRoster.response(JSON.stringify({error: {message: "api_key=" + secret}}), ""),
            ProviderRoster.response('{"api_key":"' + secret, "")
        ];
        for (var i = 0; i < results.length; i++) {
            verify(results[i].outcome !== "success");
            compare(results[i].providers.length, 0);
            verify(results[i].message.indexOf(secret) < 0);
            verify(results[i].message.length <= SafeText.maximumCliMessageLength);
        }
        var result = ProviderRoster.response(JSON.stringify({
            provider: "codex", enabled: true, displayName: "api_key=" + secret
        }), "");
        verify(result.providers[0].displayName.indexOf(secret) < 0);
    }
}
