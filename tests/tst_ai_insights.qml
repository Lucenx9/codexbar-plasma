import QtQuick
import QtTest
import "../contents/ui/AiInsights.js" as AiInsights

TestCase {
    name: "AiInsights"

    readonly property double hour: 3600000
    readonly property double now: Date.parse("2026-09-23T12:00:00Z")

    function contextFor(overrides) {
        var settings = {provider: "openrouter", model: "vendor/model", language: "it", endpoint: "", zdr: true}
        for (var key in overrides || ({}))
            settings[key] = overrides[key]
        return AiInsights.context(settings)
    }

    function observation(overrides) {
        var result = {enabled: true, configured: true, intervalHours: 6, busy: false, sufficient: true,
            nowMs: now, retryAtMs: 0, lastAttemptMs: NaN, lastSuccessMs: NaN,
            cacheMatchesContext: false, snapshotId: "aaaa", cachedSnapshotId: ""}
        for (var key in overrides || ({}))
            result[key] = overrides[key]
        return result
    }

    function entry(overrides) {
        var result = {summary: "Riepilogo", highlights: ["Uno"], generatedAtMs: now - hour,
            contextKey: AiInsights.contextKey(contextFor()), provider: "openrouter", model: "vendor/model",
            language: "it", snapshotId: "aaaa"}
        for (var key in overrides || ({}))
            result[key] = overrides[key]
        return result
    }

    function test_languageTagNormalizesCatalogMarkers_data() {
        return [
            {tag: "italian", value: "it", expected: "it"},
            {tag: "english", value: "en", expected: "en"},
            {tag: "german", value: " de ", expected: "de"},
            {tag: "brazilian", value: "pt_BR", expected: "pt-BR"},
            {tag: "case", value: "PT-br", expected: "pt-BR"},
            {tag: "untranslated marker falls back", value: "", expected: "en"},
            {tag: "prose is rejected", value: "Italiano", expected: "en"},
            {tag: "injection is rejected", value: "it; rm -rf ~", expected: "en"},
            {tag: "not a string", value: 7, expected: "en"}
        ]
    }

    function test_languageTagNormalizesCatalogMarkers(data) {
        compare(AiInsights.languageTag(data.value), data.expected)
    }

    function test_contextSeparatesLanguageProviderModelAndPrivacy() {
        var base = AiInsights.contextKey(contextFor())
        verify(base !== AiInsights.contextKey(contextFor({language: "en"})))
        verify(base !== AiInsights.contextKey(contextFor({language: "de"})))
        verify(base !== AiInsights.contextKey(contextFor({model: "vendor/other"})))
        verify(base !== AiInsights.contextKey(contextFor({provider: "openai"})))
        verify(base !== AiInsights.contextKey(contextFor({zdr: false})))
        // The endpoint is part of an Ollama context only.
        compare(AiInsights.contextKey(contextFor({endpoint: "http://elsewhere"})), base)
        verify(AiInsights.contextKey(contextFor({provider: "ollama", model: "llama3"}))
            !== AiInsights.contextKey(contextFor({provider: "ollama", model: "llama3", endpoint: "https://gpu.example"})))
    }

    function test_contextRequiresAUsableModel() {
        verify(contextFor().configured)
        verify(!contextFor({model: ""}).configured)
        verify(!contextFor({model: "openrouter/auto"}).configured)
        verify(!contextFor({model: "bad model"}).configured)
        verify(contextFor({provider: "ollama", model: "llama3.2:3b"}).configured)
        compare(contextFor({provider: "unknown"}).provider, "ollama")
    }

    function test_cacheRoundTripAndBounds() {
        var text = AiInsights.cacheText(entry({summary: "  Uno\u0000\ndue  ", highlights: ["a", "", 3, "b", "c", "d"]}))
        var parsed = AiInsights.parseCache(text)
        compare(parsed.summary, "Uno due")
        compare(parsed.highlights, ["a", "b", "c"])
        compare(parsed.language, "it")
        compare(parsed.snapshotId, "aaaa")
        var bounded = AiInsights.parseCache(AiInsights.cacheText(entry({summary: new Array(900).join("x")})))
        compare(bounded.summary.length, AiInsights.maximumSummaryLength)
    }

    function test_cacheRejectsMalformedRecords() {
        compare(AiInsights.parseCache(""), null)
        compare(AiInsights.parseCache("{"), null)
        compare(AiInsights.parseCache("[]"), null)
        compare(AiInsights.parseCache(JSON.stringify({version: 2, summary: "x", generatedAt: "2026-01-01T00:00:00Z", context: ""})), null)
        compare(AiInsights.parseCache(JSON.stringify({version: 1, summary: "", generatedAt: "2026-01-01T00:00:00Z", context: ""})), null)
        compare(AiInsights.parseCache(JSON.stringify({version: 1, summary: "x", generatedAt: "never", context: ""})), null)
        compare(AiInsights.parseCache(JSON.stringify({version: 1, summary: {}, generatedAt: "2026-01-01T00:00:00Z", context: ""})), null)
    }

    function test_cacheStateInvalidatesOtherLanguagesAndSettings() {
        var cached = AiInsights.parseCache(AiInsights.cacheText(entry()))
        var key = AiInsights.contextKey(contextFor())
        compare(AiInsights.cacheState(null, key, now, 6), "none")
        compare(AiInsights.cacheState(cached, key, now, 6), "current")
        compare(AiInsights.cacheState(cached, AiInsights.contextKey(contextFor({language: "en"})), now, 6), "otherContext")
        compare(AiInsights.cacheState(cached, AiInsights.contextKey(contextFor({model: "x/y"})), now, 6), "otherContext")
        compare(AiInsights.cacheState(cached, key, now + 6 * hour, 6), "stale")
        // Manual mode keeps an insight current for a day.
        compare(AiInsights.cacheState(cached, key, now + 20 * hour, 0), "current")
        compare(AiInsights.cacheState(cached, key, now + 26 * hour, 0), "stale")
        // A timestamp from the future is not trusted as current.
        compare(AiInsights.cacheState(cached, key, now - 3 * hour, 6), "stale")
    }

    function test_automaticGenerationFollowsOnlyTheInterval() {
        verify(AiInsights.automaticDue(observation()))
        verify(!AiInsights.automaticDue(observation({enabled: false})))
        verify(!AiInsights.automaticDue(observation({intervalHours: 0})))
        verify(!AiInsights.automaticDue(observation({configured: false})))
        verify(!AiInsights.automaticDue(observation({sufficient: false})))
        verify(!AiInsights.automaticDue(observation({busy: true})))
        verify(!AiInsights.automaticDue(observation({lastSuccessMs: now - 5 * hour})))
        verify(AiInsights.automaticDue(observation({lastSuccessMs: now - 6 * hour})))
        verify(AiInsights.automaticDue(observation({intervalHours: 24, lastSuccessMs: now - 25 * hour})))
        verify(!AiInsights.automaticDue(observation({intervalHours: 24, lastSuccessMs: now - 23 * hour})))
    }

    function test_restartAndFailuresDoNotRepeatRequests() {
        // A persisted attempt from a previous plasmashell blocks an immediate retry.
        verify(!AiInsights.automaticDue(observation({lastAttemptMs: now - 10 * 60000})))
        // A failed or timed-out attempt may have been billed, so the next
        // automatic one waits the whole interval, not a short retry delay.
        verify(!AiInsights.automaticDue(observation({lastAttemptMs: now - 31 * 60000})))
        verify(!AiInsights.automaticDue(observation({intervalHours: 24, lastAttemptMs: now - 23 * hour})))
        verify(AiInsights.automaticDue(observation({lastAttemptMs: now - 6 * hour})))
        verify(AiInsights.automaticDue(observation({intervalHours: 24, lastAttemptMs: now - 24 * hour})))
        verify(!AiInsights.automaticDue(observation({retryAtMs: now + 1})))
        // A language change leaves the schedule anchored at the last success.
        verify(!AiInsights.automaticDue(observation({lastSuccessMs: now - hour, cacheMatchesContext: false})))
        // Identical data would only repeat the same paid answer.
        verify(!AiInsights.automaticDue(observation({lastSuccessMs: now - 7 * hour, cacheMatchesContext: true,
            cachedSnapshotId: "aaaa"})))
        verify(AiInsights.automaticDue(observation({lastSuccessMs: now - 7 * hour, cacheMatchesContext: true,
            cachedSnapshotId: "bbbb"})))
    }

    function test_retryDelays() {
        compare(AiInsights.retryDelayMs("auth", 0, 6), 6 * hour)
        compare(AiInsights.retryDelayMs("credits", 0, 0), 24 * hour)
        compare(AiInsights.retryDelayMs("missing_key", 0, 12), 12 * hour)
        compare(AiInsights.retryDelayMs("format", 0, 6), 6 * hour)
        compare(AiInsights.retryDelayMs("truncated", 0, 6), 6 * hour)
        compare(AiInsights.retryDelayMs("rate_limited", 7200, 6), 2 * hour)
        compare(AiInsights.retryDelayMs("rate_limited", 1, 6), AiInsights.minimumRateLimitMs)
        compare(AiInsights.retryDelayMs("rate_limited", 1e12, 6), 24 * hour)
        // A timed-out request may still have been processed and billed.
        compare(AiInsights.retryDelayMs("timeout", 0, 6), 6 * hour)
        compare(AiInsights.retryDelayMs("network", 0, 12), 12 * hour)
        compare(AiInsights.retryDelayMs("unavailable", 0, 0), 24 * hour)
    }

    function test_rateLimitSurvivesRestartsOnlyForItsContext() {
        var key = AiInsights.contextKey(contextFor())
        var text = AiInsights.rateLimitText(now + 2 * hour, key)
        compare(AiInsights.rateLimitUntilMs(text, key, now), now + 2 * hour)
        compare(AiInsights.rateLimitUntilMs(text, key, now + 2 * hour), 0, "an expired deadline is void")
        compare(AiInsights.rateLimitUntilMs(text, AiInsights.contextKey(contextFor({provider: "openai"})), now), 0)
        compare(AiInsights.rateLimitText(0, key), "")
        compare(AiInsights.rateLimitText(NaN, key), "")
        // Persisted text is untrusted: no shape, date, or bound is assumed.
        compare(AiInsights.rateLimitUntilMs("", key, now), 0)
        compare(AiInsights.rateLimitUntilMs("{oops", key, now), 0)
        compare(AiInsights.rateLimitUntilMs("[]", key, now), 0)
        compare(AiInsights.rateLimitUntilMs(JSON.stringify({until: "soon", context: key}), key, now), 0)
        compare(AiInsights.rateLimitUntilMs(AiInsights.rateLimitText(now + 25 * hour, key), key, now), 0,
            "a deadline beyond the longest Retry-After cannot block generation")
    }

    function test_modelListedMatchesTheConfiguredModel() {
        verify(AiInsights.modelListed("openrouter", "vendor/model", ["a/b", "vendor/model"]))
        verify(AiInsights.modelListed("openai", " gpt-x ", ["gpt-x"]))
        verify(!AiInsights.modelListed("openrouter", "vendor/other", ["vendor/model"]))
        verify(!AiInsights.modelListed("openrouter", "", ["vendor/model"]))
        verify(!AiInsights.modelListed("openai", "gpt-x", null))
        // Ollama lists an untagged model under its default tag.
        verify(AiInsights.modelListed("ollama", "llama3", ["llama3:latest"]))
        verify(AiInsights.modelListed("ollama", "llama3:8b", ["llama3:8b"]))
        verify(!AiInsights.modelListed("ollama", "llama3", ["llama3:8b"]))
        verify(!AiInsights.modelListed("openai", "gpt-x", ["gpt-x:latest"]))
    }

    function test_generateCommandCarriesLanguageAndNoSecrets() {
        var command = AiInsights.command("file:///opt/pkg/scripts/ai-insights.py", "generate", {
            provider: "openrouter", model: "vendor/model", language: "it", zdr: true,
            snapshot: '{"providers":[{"id":"codex\'s"}]}'})
        verify(command.indexOf("timeout --kill-after=2s 90s python3 '/opt/pkg/scripts/ai-insights.py'") === 0, command)
        verify(command.indexOf("--language it ") >= 0, command)
        verify(command.indexOf("--model 'vendor/model'") >= 0, command)
        verify(command.indexOf("'{\"providers\":[{\"id\":\"codex'\\''s\"}]}'") >= 0, command)
        verify(command.indexOf("--no-zdr") < 0)
        verify(command.indexOf("--endpoint") < 0)
        verify(!/key|token|bearer|authorization/i.test(command.replace("ai-insights", "")), command)
        var english = AiInsights.command("file:///opt/pkg/scripts/ai-insights.py", "generate", {
            provider: "openrouter", model: "vendor/model", language: "english", zdr: false, snapshot: "{}"})
        verify(english.indexOf("--language en ") >= 0 && english.indexOf("--no-zdr") > 0, english)
    }

    function test_commandRejectsUnsafeInputs() {
        var script = "file:///opt/pkg/scripts/ai-insights.py"
        compare(AiInsights.command(script, "generate", {provider: "openrouter", model: "openrouter/auto", snapshot: "{}"}), "")
        compare(AiInsights.command(script, "generate", {provider: "openai", model: "$(id)", snapshot: "{}"}), "")
        compare(AiInsights.command(script, "generate", {provider: "openai", model: "gpt-x", snapshot: ""}), "")
        compare(AiInsights.command(script, "generate", {provider: "openai", model: "gpt-x",
            snapshot: new Array(AiInsights.maximumSnapshotLength + 2).join("x")}), "")
        compare(AiInsights.command(script, "shell", {provider: "openai"}), "")
        compare(AiInsights.command("https://example.com/x.py", "models", {provider: "openai"}), "")
        var ollama = AiInsights.command(script, "models", {provider: "ollama", endpoint: "http://x'; id; '"})
        verify(ollama.indexOf("--endpoint 'http://x'\\''; id; '\\'''") > 0, ollama)
        compare(AiInsights.command(script, "generate", {provider: "ollama", model: "llama3",
            endpoint: new Array(AiInsights.maximumEndpointLength + 2).join("x"), snapshot: "{}"}), "")
    }

    function test_generationReplyValidation_data() {
        return [
            {tag: "ok", text: JSON.stringify({status: "ok", summary: "<b>Uso</b>\n alto", highlights: ["a", 1, "<img src=x>"]}),
                outcome: "ok", summary: "<b>Uso</b> alto", highlights: ["a", "<img src=x>"]},
            {tag: "empty summary", text: JSON.stringify({status: "ok", summary: " "}), outcome: "error", reason: "format"},
            {tag: "malformed", text: "{not json", outcome: "error", reason: "format"},
            {tag: "array", text: "[]", outcome: "error", reason: "format"},
            {tag: "empty", text: "", outcome: "error", reason: "format"},
            {tag: "auth", text: JSON.stringify({status: "error", reason: "auth"}), outcome: "error", reason: "auth"},
            {tag: "unknown reason", text: JSON.stringify({status: "error", reason: "<script>"}), outcome: "error", reason: "unavailable"},
            {tag: "rate limit", text: JSON.stringify({status: "error", reason: "rate_limited", retryAfter: 120}),
                outcome: "error", reason: "rate_limited", retryAfterSeconds: 120}
        ]
    }

    function test_generationReplyValidation(data) {
        var reply = AiInsights.generationReply(data.text)
        compare(reply.outcome, data.outcome)
        if (data.outcome === "ok") {
            // Markup survives only as literal text; the card renders PlainText.
            compare(reply.summary, data.summary)
            compare(reply.highlights, data.highlights)
        } else {
            compare(reply.reason, data.reason)
            compare(reply.retryAfterSeconds, data.retryAfterSeconds || 0)
        }
    }

    function test_modelsReplyValidation() {
        var reply = AiInsights.modelsReply(JSON.stringify({status: "ok", key: "valid",
            models: [{id: "a/b"}, {id: "a/b"}, {id: "bad id"}, {id: 3}, null, {id: "llama3:8b"}]}))
        compare(reply.models, ["a/b", "llama3:8b"])
        compare(reply.key, "valid")
        compare(AiInsights.modelsReply(JSON.stringify({status: "error", reason: "auth"})).reason, "auth")
        compare(AiInsights.modelsReply("oops").outcome, "error")
        compare(AiInsights.statusReply(JSON.stringify({status: "present"}), ["present", "absent"]), "present")
        compare(AiInsights.statusReply(JSON.stringify({status: "sk-secret"}), ["present", "absent"]), "unavailable")
    }

    function test_safeReasonBoundsHelperReasons() {
        compare(AiInsights.safeReason("auth"), "auth")
        compare(AiInsights.safeReason("invalid_input"), "invalid_input")
        compare(AiInsights.safeReason("<script>"), "unavailable")
        compare(AiInsights.safeReason(""), "unavailable")
        compare(AiInsights.safeReason(7), "unavailable")
        compare(AiInsights.safeReason(null), "unavailable")
    }

    function test_localEndpointPresentation() {
        verify(AiInsights.isLocalEndpoint(""))
        verify(AiInsights.isLocalEndpoint("http://localhost:11434"))
        verify(AiInsights.isLocalEndpoint("http://127.0.0.1:11434/"))
        verify(AiInsights.isLocalEndpoint("http://[::1]:11434"))
        verify(!AiInsights.isLocalEndpoint("https://gpu.example:11434"))
        verify(!AiInsights.isLocalEndpoint("http://localhost.example.com"))
        verify(!AiInsights.isLocalEndpoint("http://user@localhost"))
    }
}
