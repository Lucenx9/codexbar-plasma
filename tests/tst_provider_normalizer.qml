import QtQuick
import QtTest
import "../contents/ui/ProviderNormalizer.js" as Normalizer

// The normalizer is the only place that turns untrusted `codexbar` JSON into the
// structures the popup renders, so these tests are written from the payload the
// CLI could plausibly emit while broken or hostile, not from the happy path.
TestCase {
    name: "ProviderNormalizer"

    function unsafeKeys() {
        return ["__proto__", "prototype", "constructor"]
    }

    // --- bounds -------------------------------------------------------------
    //
    // The numbers themselves are the contract: `scripts/test_security_regressions.sh`
    // asserts the call sites, and these pin the values those call sites read.

    function test_publishesTheDocumentedCollectionBounds() {
        compare(Normalizer.maximumProviderSnapshots, 256)
        compare(Normalizer.maximumAccountIdentityLength, 256)
        compare(Normalizer.maximumAccountSnapshots, 128)
        compare(Normalizer.maximumCostSnapshots, 256)
        compare(Normalizer.maximumExtraRateWindows, 24)
        compare(Normalizer.maximumSessions, 128)
        compare(Normalizer.maximumCostHistoryPoints, 365)
        compare(Normalizer.maximumModelBreakdownsPerDay, 128)
        compare(Normalizer.maximumCostModelRows, 6)
    }

    // --- object-key guards --------------------------------------------------

    function test_rejectsPrototypePollutingKeys() {
        var keys = unsafeKeys()
        for (var i = 0; i < keys.length; i++) {
            verify(Normalizer.isUnsafeObjectKey(keys[i]), keys[i] + " must be rejected")
        }
        verify(!Normalizer.isUnsafeObjectKey("codex"))
        verify(!Normalizer.isUnsafeObjectKey("toString"))
    }

    function test_hasOwnKeyIgnoresInheritedPrototypeMembers() {
        var item = { own: 1 }
        verify(Normalizer.hasOwnKey(item, "own"))
        verify(!Normalizer.hasOwnKey(item, "toString"))
        verify(!Normalizer.hasOwnKey(item, "hasOwnProperty"))
        // A payload that shadows hasOwnProperty must not be able to lie about
        // its own keys, which is why the guard calls through Object.prototype.
        verify(!Normalizer.hasOwnKey({ hasOwnProperty: function() { return true } }, "anything"))
        verify(!Normalizer.hasOwnKey(null, "own"))
    }

    function test_copyObjectStripsPollutingKeysAndInheritedMembers() {
        var payload = JSON.parse('{"provider":"codex","__proto__":{"polluted":true},"constructor":"x","prototype":"y"}')
        var copy = Normalizer.copyObject(payload)
        compare(copy.provider, "codex")
        var keys = unsafeKeys()
        for (var i = 0; i < keys.length; i++) {
            verify(!Normalizer.hasOwnKey(copy, keys[i]), keys[i] + " must not survive the copy")
        }
        compare(({}).polluted, undefined)
    }

    // --- provider identity --------------------------------------------------

    function test_resolvesCliAliasesToTheCanonicalProviderKey() {
        compare(Normalizer.normalizedProviderID("groqcloud"), "groq")
        compare(Normalizer.normalizedProviderID("alibaba-coding-plan"), "alibaba")
        compare(Normalizer.normalizedProviderID("  codex  "), "codex")
    }

    function test_rejectsProviderIDsThatAreNotUsableMapKeys() {
        compare(Normalizer.normalizedProviderID(""), "")
        compare(Normalizer.normalizedProviderID("   "), "")
        compare(Normalizer.normalizedProviderID(null), "")
        compare(Normalizer.normalizedProviderID(undefined), "")
        compare(Normalizer.normalizedProviderID(42), "")
        compare(Normalizer.normalizedProviderID({ provider: "codex" }), "")
        compare(Normalizer.normalizedProviderID("prototype"), "")
        compare(Normalizer.normalizedProviderID("__proto__"), "")
        compare(Normalizer.normalizedProviderID("constructor"), "")
        compare(Normalizer.normalizedProviderID("codex\nevil"), "")
    }

    function test_lowercasingMakesPrototypeMemberNamesSafeProviderKeys() {
        // The key is lowercased before the Object.prototype screen, so "toString"
        // becomes "tostring": a distinct key that cannot collide with a prototype
        // member. Rejecting it instead would lose a legitimate provider id.
        compare(Normalizer.normalizedProviderID("toString"), "tostring")
        compare(Normalizer.normalizedProviderID("hasOwnProperty"), "hasownproperty")
        verify(!Normalizer.hasOwnKey({}, "tostring"))
    }

    function test_rejectsOversizedProviderIDs() {
        var oversized = ""
        for (var i = 0; i < 200; i++) {
            oversized += "a"
        }
        compare(Normalizer.normalizedProviderID(oversized), "")
    }

    // --- provider config ----------------------------------------------------

    function test_keepsDisplayNamesForDisabledProvidersButOnlyEnabledIDs() {
        var entries = Normalizer.normalizeProviderConfigEntries([
            { provider: "codex", displayName: "Codex", enabled: true },
            { provider: "claude", displayName: "Claude", enabled: false },
            { provider: "groqcloud", displayName: "Groq", enabled: true }
        ])

        compare(entries.providerIDs.length, 2)
        compare(entries.providerIDs[0], "codex")
        compare(entries.providerIDs[1], "groq")
        compare(entries.displayNames["claude"], "Claude")
        compare(entries.displayNames["groq"], "Groq")
    }

    function test_providerConfigDistinguishesAnEmptyRosterFromAnUnsupportedEnvelope() {
        var emptyEntries = Normalizer.normalizeProviderConfigEntries([])
        compare(emptyEntries.providerIDs.length, 0)
        compare(Object.keys(emptyEntries.displayNames).length, 0)

        compare(Normalizer.normalizeProviderConfigEntries({
            provider: "cli",
            error: { message: "command failed" }
        }), null)
        compare(Normalizer.normalizeProviderConfigEntries([{
            provider: "cli",
            error: { message: "command failed" }
        }]), null)
    }

    function test_providerConfigAcceptsASingleDisabledProviderRecord() {
        var entries = Normalizer.normalizeProviderConfigEntries({
            provider: "claude",
            displayName: "Claude",
            enabled: false
        })

        compare(entries.providerIDs.length, 0)
        compare(entries.displayNames["claude"], "Claude")
    }

    function test_providerConfigDropsPollutingProviderIDsWithoutLosingTheOthers() {
        var entries = Normalizer.normalizeProviderConfigEntries(JSON.parse(
            '[{"provider":"__proto__","displayName":"Evil","enabled":true},'
            + '{"provider":"constructor","displayName":"Evil","enabled":true},'
            + '{"provider":"codex","displayName":"Codex","enabled":true}]'))

        compare(entries.providerIDs.length, 1)
        compare(entries.providerIDs[0], "codex")
        compare(entries.displayNames["codex"], "Codex")
        compare(({}).polluted, undefined)
    }

    function test_providerConfigDeduplicatesAliasesOfTheSameProvider() {
        var entries = Normalizer.normalizeProviderConfigEntries([
            { provider: "groqcloud", enabled: true },
            { provider: "groq", enabled: true },
            { provider: "groq-api", enabled: true }
        ])
        compare(entries.providerIDs.length, 1)
        compare(entries.providerIDs[0], "groq")
    }

    function test_providerConfigSurvivesMalformedEntries() {
        var entries = Normalizer.normalizeProviderConfigEntries([
            null,
            "codex",
            { enabled: true },
            { provider: "codex", displayName: { nested: "object" }, enabled: true },
            { provider: "claude", displayName: "Claude", enabled: true }
        ])
        compare(entries.providerIDs.length, 2)
        // A structured displayName is dropped, not stringified, and the other
        // providers survive the malformed entry.
        compare(entries.displayNames["codex"], undefined)
        compare(entries.displayNames["claude"], "Claude")
    }

    function test_providerSnapshotsDeduplicateAliasesAndPreferHealthyData() {
        var snapshots = Normalizer.dedupeProviderSnapshots([
            { provider: "groqcloud", error: "temporary failure", marker: "error" },
            { provider: "groq", error: "", marker: "healthy" },
            { provider: "claude", error: "", marker: "first" },
            { provider: "claude", error: "", marker: "later" },
            { provider: "alibaba-coding-plan", error: "", marker: "alias" }
        ])

        compare(snapshots.length, 3)
        compare(snapshots[0].marker, "healthy")
        compare(snapshots[1].marker, "first")
        compare(snapshots[2].provider, "alibaba")
    }

    // --- Codex monthly credit limit ---------------------------------------

    function test_normalizesCodexMonthlyCreditLimitForThePopup() {
        var limit = Normalizer.normalizeCodexCreditLimit("codex", {
            title: "  Monthly credit limit  ",
            used: 125.5,
            limit: 500,
            remaining: 374.5,
            remainingPercent: 74.9,
            resetsAt: "2026-09-30T23:59:59Z"
        })

        compare(limit.title, "Monthly credit limit")
        compare(limit.used, 125.5)
        compare(limit.limit, 500)
        compare(limit.remaining, 374.5)
        compare(limit.usedPercent, 25.1)
        compare(limit.leftPercent, 74.9)
        compare(limit.resetsAt, "2026-09-30T23:59:59Z")
    }

    function test_rejectsMalformedCodexMonthlyCreditLimitAmounts() {
        var fields = ["used", "limit", "remaining", "remainingPercent"]
        var invalidValues = [null, undefined, "", "   ", true, false, [], {}, "not-a-number"]
        for (var fieldIndex = 0; fieldIndex < fields.length; fieldIndex++) {
            for (var valueIndex = 0; valueIndex < invalidValues.length; valueIndex++) {
                var payload = {
                    used: 25,
                    limit: 100,
                    remaining: 75,
                    remainingPercent: 75
                }
                payload[fields[fieldIndex]] = invalidValues[valueIndex]
                compare(Normalizer.normalizeCodexCreditLimit("codex", payload), null,
                    fields[fieldIndex] + " must reject " + valueIndex)
            }
        }

        compare(Normalizer.normalizeCodexCreditLimit("codex", {
            used: -1, limit: 100, remaining: 101, remainingPercent: 101
        }), null)
        compare(Normalizer.normalizeCodexCreditLimit("codex", {
            used: 0, limit: 0, remaining: 0, remainingPercent: 100
        }), null)
        compare(Normalizer.normalizeCodexCreditLimit("claude", {
            used: 25, limit: 100, remaining: 75, remainingPercent: 75
        }), null)
    }

    function test_codexMonthlyCreditLimitRequiresOwnAmountFields() {
        function InheritedLimit() {}
        InheritedLimit.prototype.used = 25
        InheritedLimit.prototype.limit = 100
        InheritedLimit.prototype.remaining = 75
        InheritedLimit.prototype.remainingPercent = 75

        compare(Normalizer.normalizeCodexCreditLimit("codex", new InheritedLimit()), null)
    }

    function test_clampsCodexMonthlyCreditPercentagesAndBoundsItsText() {
        var oversizedTitle = ""
        for (var i = 0; i < 200; i++) {
            oversizedTitle += "x"
        }
        var over = Normalizer.normalizeCodexCreditLimit("codex", {
            title: oversizedTitle,
            used: 0,
            limit: 100,
            remaining: 100,
            remainingPercent: 130,
            resetsAt: { raw: "not display text" }
        })
        compare(over.title.length, 120)
        compare(over.usedPercent, 0)
        compare(over.leftPercent, 100)
        compare(over.resetsAt, "")

        var under = Normalizer.normalizeCodexCreditLimit("codex", {
            used: 100,
            limit: 100,
            remaining: 0,
            remainingPercent: -30
        })
        compare(under.usedPercent, 100)
        compare(under.leftPercent, 0)

        compare(Normalizer.normalizeCodexCreditLimit("codex", null), null)
        compare(Normalizer.normalizeCodexCreditLimit("codex", []), null)
    }

    // --- rate window percentages -------------------------------------------

    function test_clampsUsedPercentagesReportedOutsideTheMeterRange() {
        var over = Normalizer.rateWindowMetrics({ usedPercent: 137.5 }, null, true)
        compare(over.hasPercent, true)
        compare(over.usedPercent, 100)
        compare(over.leftPercent, 0)

        var under = Normalizer.rateWindowMetrics({ usedPercent: -42 }, null, true)
        compare(under.usedPercent, 0)
        compare(under.leftPercent, 100)
    }

    function test_clampsPaceProjectionsAndBoundsTheEta() {
        var metrics = Normalizer.rateWindowMetrics(
            { usedPercent: 50 },
            { expectedUsedPercent: 400, etaSeconds: 99999999999, willLastToReset: false },
            true)
        compare(metrics.pacePercent, 100)
        compare(metrics.paceOnTop, false)
        compare(metrics.paceEtaSeconds, Normalizer.maximumPaceEtaSeconds)

        var negative = Normalizer.rateWindowMetrics(
            { usedPercent: 50 },
            { expectedUsedPercent: -10, etaSeconds: -60 },
            true)
        compare(negative.pacePercent, 0)
        compare(negative.paceEtaSeconds, 0)
    }

    function test_keepsAnAbsentPaceDistinctFromAPaceOfZero() {
        // -1 is the "no projection" sentinel. A missing pace rendered as 0 would
        // draw a marker claiming the provider is comfortably ahead of schedule.
        compare(Normalizer.rateWindowMetrics({ usedPercent: 10 }, null, true).pacePercent, -1)
        compare(Normalizer.rateWindowMetrics({ usedPercent: 10 }, {}, true).pacePercent, -1)
        compare(Normalizer.rateWindowMetrics(
            { usedPercent: 10 }, { expectedUsedPercent: null }, true).pacePercent, -1)
        compare(Normalizer.rateWindowMetrics(
            { usedPercent: 10 }, { expectedUsedPercent: undefined }, true).pacePercent, -1)
        compare(Normalizer.rateWindowMetrics(
            { usedPercent: 10 }, { expectedUsedPercent: "soon" }, true).pacePercent, -1)
        compare(Normalizer.rateWindowMetrics(
            { usedPercent: 10 }, { expectedUsedPercent: 0 }, true).pacePercent, 0)
    }

    function test_rejectsEmptyBooleanAndStructuredPaceValues() {
        var invalidValues = [null, undefined, "", "   ", true, false, [], {}]
        for (var i = 0; i < invalidValues.length; i++) {
            var metrics = Normalizer.rateWindowMetrics(
                { usedPercent: 10 }, {
                    expectedUsedPercent: invalidValues[i],
                    etaSeconds: invalidValues[i]
                }, true)
            compare(metrics.pacePercent, -1)
            compare(metrics.paceEtaSeconds, 0)
        }
    }

    function test_strictFiniteNumberRejectsCoerciveValues() {
        var invalidValues = [null, undefined, "", "   ", true, false, [], {}]
        for (var i = 0; i < invalidValues.length; i++) {
            verify(isNaN(Normalizer.strictFiniteNumber(invalidValues[i])))
        }
        compare(Normalizer.strictFiniteNumber(0), 0)
        compare(Normalizer.strictFiniteNumber(" 2.5 "), 2.5)
        compare(Normalizer.firstStrictFiniteNumber({}, 0), 0)
        compare(Normalizer.firstStrictFiniteNumber("   ", " 3.5 "), 3.5)
    }

    function test_reportsAnUnknownPercentageInsteadOfGuessingZero() {
        var unknown = Normalizer.rateWindowMetrics({ usedPercent: 80 }, null, false)
        compare(unknown.hasPercent, false)
        compare(unknown.usedPercent, 0)
        compare(unknown.leftPercent, 0)
        compare(unknown.paceKnown, false)

        var malformed = Normalizer.rateWindowMetrics({ usedPercent: "quite a lot" }, null, true)
        compare(malformed.hasPercent, false)
        compare(malformed.usedPercent, 0)
    }

    function test_marksPaceAvailabilityIndependentlyFromUsage() {
        var recoveredPace = Normalizer.rateWindowMetrics(
            { usedPercent: 80 }, { willLastToReset: true }, false)
        compare(recoveredPace.hasPercent, false)
        compare(recoveredPace.paceKnown, true)

        var activePace = Normalizer.rateWindowMetrics(
            { usedPercent: 80 }, { willLastToReset: false, etaSeconds: 60 }, false)
        compare(activePace.paceKnown, true)

        var incompletePace = Normalizer.rateWindowMetrics(
            { usedPercent: 80 }, { willLastToReset: false }, false)
        compare(incompletePace.paceKnown, false)

        var invalidFlags = [null, undefined, "true", 1, [], {}]
        for (var i = 0; i < invalidFlags.length; i++) {
            var invalidPace = Normalizer.rateWindowMetrics(
                { usedPercent: 80 }, {
                    willLastToReset: invalidFlags[i],
                    etaSeconds: 60
                }, false)
            compare(invalidPace.paceKnown, false)
        }

        var inheritedRecovery = Normalizer.rateWindowMetrics(
            { usedPercent: 80 }, Object.create({ willLastToReset: true }), false)
        compare(inheritedRecovery.paceKnown, false)
    }

    function test_rejectsEmptyBooleanAndStructuredUsagePercentages() {
        var invalidValues = [null, undefined, "", "   ", true, false, [], {}]
        for (var i = 0; i < invalidValues.length; i++) {
            var metrics = Normalizer.rateWindowMetrics(
                { usedPercent: invalidValues[i] }, null, true)
            compare(metrics.hasPercent, false)
            compare(metrics.usedPercent, 0)
            compare(metrics.leftPercent, 0)
        }
    }

    function test_distinguishesAMissingWindowFromAnEmptyOne() {
        compare(Normalizer.rateWindowMetrics(null, null, true), null)
        compare(Normalizer.rateWindowMetrics(undefined, null, true), null)
        compare(Normalizer.rateWindowMetrics([], null, true), null)
        compare(Normalizer.rateWindowMetrics("primary", null, true), null)
        verify(Normalizer.rateWindowMetrics({}, null, true) !== null)
    }

    // --- status -------------------------------------------------------------

    function test_acceptsOnlyKnownStatusIndicators() {
        compare(Normalizer.statusSeverity({ indicator: "MAJOR" }), "major")
        compare(Normalizer.statusSeverity({ indicator: "maintenance" }), "maintenance")
        compare(Normalizer.statusSeverity({ indicator: "none" }), "")
        compare(Normalizer.statusSeverity({ indicator: "totally-made-up" }), "")
        compare(Normalizer.statusSeverity({}), "")
        compare(Normalizer.statusSeverity(null), "")
    }

    function test_statusSeverityRejectsStructuredIndicators() {
        // Coercing these values runs a missing or hostile toString, which used
        // to abort the whole usage refresh with a TypeError.
        compare(Normalizer.statusSeverity({ indicator: { toString: null } }), "")
        compare(Normalizer.statusSeverity({ indicator: ["major"] }), "")
        compare(Normalizer.statusSeverity({ indicator: 42 }), "")
        compare(Normalizer.statusSeverity({ indicator: null }), "")
    }

    function test_readsTheIncidentKeyFromEveryContractSpelling() {
        compare(Normalizer.statusIncidentKey({ incidentId: "a1" }), "a1")
        compare(Normalizer.statusIncidentKey({ incident_id: "a2" }), "a2")
        compare(Normalizer.statusIncidentKey({ incidentID: "a3" }), "a3")
        compare(Normalizer.statusIncidentKey({ id: "a4" }), "a4")
        compare(Normalizer.statusIncidentKey({ incident: { id: 55 } }), "55")
        compare(Normalizer.statusIncidentKey({ incident: {} }), "")
        compare(Normalizer.statusIncidentKey({}), "")
        compare(Normalizer.statusIncidentKey(null), "")
    }

    function test_statusIncidentKeyRejectsStructuredValues() {
        compare(Normalizer.statusIncidentKey({ incidentId: { toString: null } }), "")
        compare(Normalizer.statusIncidentKey({ incident: { id: { toString: null } } }), "")
        compare(Normalizer.statusIncidentKey({ incidentId: ["a1"] }), "")
        compare(Normalizer.statusIncidentKey({ incidentId: 0 }), "0")
    }

    function test_refusesToFollowAStatusUrlOffTheProviderHost() {
        var fallback = "https://status.openai.com/"
        compare(Normalizer.safeStatusUrl(fallback, "https://status.openai.com/incidents/42"),
                "https://status.openai.com/incidents/42")
        // Different host, lookalike host, and non-https schemes all fall back.
        compare(Normalizer.safeStatusUrl(fallback, "https://evil.example/steal"), fallback)
        compare(Normalizer.safeStatusUrl(fallback, "https://status.openai.com.evil.example/"), fallback)
        compare(Normalizer.safeStatusUrl(fallback, "http://status.openai.com/"), fallback)
        compare(Normalizer.safeStatusUrl(fallback, "javascript:alert(1)"), fallback)
        compare(Normalizer.safeStatusUrl(fallback, "file:///etc/passwd"), fallback)
        compare(Normalizer.safeStatusUrl(fallback, ""), fallback)
        compare(Normalizer.safeStatusUrl(fallback, null), fallback)
    }

    function test_offersNoStatusUrlWhenTheProviderShipsNoFallback() {
        compare(Normalizer.safeStatusUrl("", "https://evil.example/"), "")
        compare(Normalizer.safeStatusUrl(null, "https://evil.example/"), "")
    }

    // --- accounts -----------------------------------------------------------

    function test_accountLabelFallsBackThroughIdentityFields() {
        compare(Normalizer.accountLabel({ account: "a@example.com", organization: "Org" }), "a@example.com")
        compare(Normalizer.accountLabel({ account: "", organization: "Org" }), "Org")
        compare(Normalizer.accountLabel({ account: "", organization: "", loginMethod: "oauth" }), "oauth")
        compare(Normalizer.accountLabel({ account: "", organization: "", loginMethod: "" }), "")
        compare(Normalizer.accountLabel(null), "")
    }

    function test_accountLabelRejectsNonStringIdentityFields() {
        compare(Normalizer.accountLabel({ account: { length: 3 }, organization: "Org" }), "Org")
        compare(Normalizer.accountLabel({ account: 42, organization: 7, loginMethod: "oauth" }), "oauth")
        compare(Normalizer.accountLabel({ account: ["a@example.com"] }), "")
        var deduped = Normalizer.dedupeAccountOptions([{ account: { length: 3 } }, { account: "b@example.com" }])
        compare(deduped.length, 1)
        compare(deduped[0].account, "b@example.com")
    }

    function test_accountKeyValidatesWithoutRewritingTheIdentity() {
        // Display text collapses "Work  Team" to "Work Team"; the key must keep
        // the original spacing so selection still addresses the right account.
        compare(Normalizer.accountKey({ account: "Work  Team" }), "Work  Team")
        compare(Normalizer.accountKey({ account: "  padded@example.com  " }), "padded@example.com")
        compare(Normalizer.accountKey({ account: "", organization: "Org  Name" }), "Org  Name")
        compare(Normalizer.accountKey({ account: 42, organization: 7, loginMethod: "oauth" }), "oauth")
        compare(Normalizer.accountKey({ account: { length: 3 }, organization: "Org" }), "Org")
        compare(Normalizer.accountKey({ account: ["a@example.com"] }), "")
        compare(Normalizer.accountKey(null), "")
        var overlong = ""
        for (var i = 0; i < Normalizer.maximumAccountIdentityLength + 1; i++) {
            overlong += "a"
        }
        compare(Normalizer.accountKey({ account: overlong }), "")
    }

    function test_accountKeyPrefersTheValidatedSnapshotKey() {
        // A normalized snapshot's display fields are already collapsed, so the
        // stored key is the only copy of the original spacing.
        compare(Normalizer.accountKey({ account: "Work Team", accountKey: "Work  Team" }), "Work  Team")
    }

    function test_dedupeAccountOptionsKeepsSpacingVariantsSeparate() {
        var options = [
            { provider: "codex", account: "Work Team", accountKey: "Work  Team" },
            { provider: "codex", account: "Work Team", accountKey: "Work Team" },
            { provider: "codex", account: "Work Team", accountKey: "Work Team" }
        ]
        var deduped = Normalizer.dedupeAccountOptions(options)
        compare(deduped.length, 2)
        compare(deduped[0].accountKey, "Work  Team")
        compare(deduped[1].accountKey, "Work Team")
    }

    function test_dedupesAccountsWithoutLosingPrototypeNamedOnes() {
        // "constructor" and "toString" are legitimate account labels. A raw map
        // lookup would treat them as already seen and silently drop them.
        var options = [
            { account: "a@example.com" },
            { account: "a@example.com" },
            { account: "constructor" },
            { account: "toString" },
            { account: "__proto__" },
            { account: "" },
            { account: "b@example.com" }
        ]
        var deduped = Normalizer.dedupeAccountOptions(options)
        compare(deduped.length, 5)
        compare(deduped[0].account, "a@example.com")
        compare(deduped[1].account, "constructor")
        compare(deduped[2].account, "toString")
        compare(deduped[3].account, "__proto__")
        compare(deduped[4].account, "b@example.com")
    }

    function test_dedupeAccountOptionsRejectsNonArrayInputs() {
        compare(Normalizer.dedupeAccountOptions(null).length, 0)
        compare(Normalizer.dedupeAccountOptions(undefined).length, 0)
        compare(Normalizer.dedupeAccountOptions("invalid").length, 0)
        compare(Normalizer.dedupeAccountOptions({ account: "a" }).length, 0)
    }

    function test_dedupeAccountOptionsBoundsAtMaximumAccountSnapshots() {
        var oversized = []
        for (var i = 0; i < Normalizer.maximumAccountSnapshots + 20; i++) {
            oversized.push({ account: "acc" + i })
        }
        var inspectedPastBound = false
        Object.defineProperty(oversized[Normalizer.maximumAccountSnapshots], "account", {
            get: function() {
                inspectedPastBound = true
                return "outside-bound"
            }
        })
        var deduped = Normalizer.dedupeAccountOptions(oversized)
        compare(deduped.length, Normalizer.maximumAccountSnapshots)
        verify(!inspectedPastBound)
    }

    function test_treatsMissingTokenAccountsAsAnEmptyListNotAFailure() {
        verify(Normalizer.isMissingTokenAccountsError("No token accounts configured for codex."))
        verify(Normalizer.isMissingTokenAccountsError("NO TOKEN ACCOUNTS CONFIGURED"))
        verify(!Normalizer.isMissingTokenAccountsError("Request failed with status 500"))
        verify(!Normalizer.isMissingTokenAccountsError(""))
        // A malformed error value must not abort account parsing with a TypeError.
        verify(!Normalizer.isMissingTokenAccountsError(null))
        verify(!Normalizer.isMissingTokenAccountsError(undefined))
        verify(!Normalizer.isMissingTokenAccountsError({ message: "x" }))
    }

    // --- sessions -----------------------------------------------------------

    function test_normalizesASessionAndPrefersTheLastActivityTimestamp() {
        var session = Normalizer.normalizeSession({
            provider: "codex",
            projectName: "codexbar-plasma",
            sessionName: "refactor",
            host: "workstation",
            state: "RUNNING",
            source: "cli",
            startedAt: "2026-08-17T09:00:00Z",
            lastActivityAt: "2026-08-18T10:30:00Z"
        })
        compare(session.provider, "codex")
        compare(session.projectName, "codexbar-plasma")
        compare(session.state, "running")
        compare(session.activityAt, "2026-08-18T10:30:00Z")
        compare(session.activityMs, Date.parse("2026-08-18T10:30:00Z"))
    }

    function test_fallsBackToStartedAtWhenTheActivityStampIsUnusable() {
        var session = Normalizer.normalizeSession({
            provider: "codex",
            projectName: "p",
            lastActivityAt: "not a date",
            startedAt: "2026-08-17T09:00:00Z"
        })
        compare(session.activityAt, "2026-08-17T09:00:00Z")
        compare(session.activityMs, Date.parse("2026-08-17T09:00:00Z"))

        var undated = Normalizer.normalizeSession({ provider: "codex", projectName: "p" })
        compare(undated.activityAt, "")
        compare(undated.activityMs, 0)
    }

    function test_neverRetainsLocalSessionPaths() {
        var session = Normalizer.normalizeSession({
            provider: "codex",
            projectName: "p",
            cwd: "/home/user/secret-project",
            transcriptPath: "/home/user/.codexbar/transcript.jsonl",
            pid: 4242
        })
        compare(session.cwd, undefined)
        compare(session.transcriptPath, undefined)
        compare(session.pid, undefined)
    }

    function test_dropsSessionsThatCannotBeIdentified() {
        compare(Normalizer.normalizeSession(null), null)
        compare(Normalizer.normalizeSession("session"), null)
        compare(Normalizer.normalizeSession([]), null)
        compare(Normalizer.normalizeSession({ host: "workstation" }), null)
        // A session with only a host has nothing to title a row with; one with a
        // numeric project still does, so it is coerced rather than dropped.
        compare(Normalizer.normalizeSession({ provider: 42, projectName: 7 }).projectName, "7")
        compare(Normalizer.normalizeSession({ provider: 42, projectName: 7 }).provider, "")
    }

    function test_sortsSessionsByRecentActivityAndTruncatesAtTheBound() {
        var payload = []
        for (var i = 0; i < Normalizer.maximumSessions + 30; i++) {
            payload.push({
                provider: "codex",
                projectName: "project-" + i,
                lastActivityAt: new Date(1755000000000 + i * 1000).toISOString()
            })
        }
        var sessions = Normalizer.normalizeSessions(payload)
        compare(sessions.length, Normalizer.maximumSessions)
        // The bound applies before the sort, so it is the first 128 entries that
        // are kept and then ordered newest first.
        compare(sessions[0].projectName, "project-" + (Normalizer.maximumSessions - 1))
        compare(sessions[sessions.length - 1].projectName, "project-0")
    }

    function test_readsBothSupportedSessionsPayloadShapes() {
        var listed = Normalizer.normalizeSessions([{ provider: "codex", projectName: "p" }])
        compare(listed.length, 1)
        var wrapped = Normalizer.normalizeSessions({ sessions: [{ provider: "codex", projectName: "p" }] })
        compare(wrapped.length, 1)
        compare(Normalizer.normalizeSessions([]).length, 0)
    }

    function test_rejectsUnsupportedSessionsPayloadsInsteadOfEmptyingTheTab() {
        // null means "unsupported shape"; an empty array would read as a valid
        // snapshot and wipe the sessions the user was already looking at.
        compare(Normalizer.normalizeSessions({ items: [] }), null)
        compare(Normalizer.normalizeSessions({ sessions: "none" }), null)
        compare(Normalizer.normalizeSessions("no sessions"), null)
        compare(Normalizer.normalizeSessions(42), null)
        compare(Normalizer.normalizeSessions(null), null)
    }

    // --- cost ---------------------------------------------------------------

    function test_costProjectsKeepOnlyDisplayFieldsFromTheOfficialContract() {
        var result = Normalizer.normalizeCostProjects([{
            name: "Example project", path: "/private/example",
            totalCost: 12.5, totalTokens: 42000,
            daily: [{ path: "/private/daily" }],
            sources: [{ name: "source", path: "/private/source" }],
            modelBreakdowns: [{ modelName: "example" }]
        }], "EUR")

        compare(result.rows, [{
            label: "Example project", cost: 12.5, tokens: 42000, currency: "EUR"
        }])
        compare(result.truncated, false)
        verify(JSON.stringify(result).indexOf("/private") === -1)
    }

    function test_costProjectsPreserveUnknownAmountsAndExplicitZero() {
        var rows = Normalizer.normalizeCostProjects([
            { name: "Tokens only", totalTokens: 12 },
            { name: "Cost only", totalCost: "2.5", totalTokens: false },
            { name: "Empty", totalCost: 0, totalTokens: 0 },
            { name: "Negative", totalCost: -1, totalTokens: -2 },
            { name: "No amounts", totalCost: null, totalTokens: true },
            { name: "Nonfinite", totalCost: Infinity, totalTokens: NaN }
        ], "USD").rows
        compare(rows.length, 4)
        compare(rows[0].cost, null)
        compare(rows[0].tokens, 12)
        compare(rows[1].cost, 2.5)
        compare(rows[1].tokens, null)
        compare(rows[2].cost, 0)
        compare(rows[2].tokens, 0)
        compare(rows[3].cost, 0)
        compare(rows[3].tokens, 0)
    }

    function test_costProjectsRejectMalformedAndInheritedDisplayFields() {
        var inheritedName = Object.create({ name: "Inherited" })
        inheritedName.totalCost = 3
        var inheritedCost = Object.create({ totalCost: 8 })
        inheritedCost.name = "Inherited amount"
        inheritedCost.totalTokens = 2
        var result = Normalizer.normalizeCostProjects([
            null, false, [], "bad", { name: {}, totalCost: 1 },
            { name: 123, totalCost: 1 }, { name: "   ", totalCost: 1 },
            { path: "/private/no-name", totalCost: 1 }, inheritedName,
            inheritedCost, { name: "Healthy", totalCost: 4 }
        ], "USD")
        compare(result.rows.length, 2)
        compare(result.rows[0].cost, null)
        compare(result.rows[1].label, "Healthy")
        var malformed = [null, undefined, {}, "projects", 12]
        for (var i = 0; i < malformed.length; i++) {
            compare(Normalizer.normalizeCostProjects(malformed[i], "USD"),
                { rows: [], truncated: false })
        }
    }

    function test_costProjectNamesAreBoundedRedactedLabelsNotIdentities() {
        var rows = Normalizer.normalizeCostProjects([
            { name: "same", totalCost: 1, path: "/private/one" },
            { name: "same", totalCost: 2, path: "/private/two" },
            { name: "__proto__", totalCost: 3 },
            { name: "Example\nAuthorization: Bearer synthetic-secret", totalCost: 4 },
            { name: new Array(300).join("x"), totalCost: 5 },
            { name: "<b>Example</b>", totalCost: 6 }
        ], "USD").rows
        compare(rows.length, 6)
        compare(rows[0].label, rows[1].label)
        compare(rows[0].cost, 1)
        compare(rows[1].cost, 2)
        compare(rows[2].label, "__proto__")
        verify(rows[3].label.indexOf("synthetic-secret") === -1)
        verify(rows[3].label.indexOf("[redacted]") >= 0)
        verify(rows[4].label.length <= 120)
        compare(rows[5].label, "<b>Example</b>")
    }

    function test_costProjectsBoundInspectionBeforeFiltering() {
        var items = new Array(129)
        items[0] = { name: "First", totalCost: 1 }
        items[127] = { name: "Last inspected", totalCost: 2 }
        Object.defineProperty(items, "128", { get: function() {
            fail("Project inspection exceeded its bound")
        } })
        var result = Normalizer.normalizeCostProjects(items, "USD")
        compare(result.rows.length, 2)
        compare(result.rows[1].label, "Last inspected")
        compare(result.truncated, true)
    }

    function test_costEnvelopeAcceptsEmptyAndRecognizedSnapshots() {
        var empty = Normalizer.normalizeCostEnvelope([])
        verify(empty !== null)
        compare(empty.length, 0)

        var singleton = Normalizer.normalizeCostEnvelope({ provider: "groqcloud" })
        verify(singleton !== null)
        compare(singleton.length, 1)
        compare(singleton[0].provider, "groq")

        var mixed = Normalizer.normalizeCostEnvelope([
            null,
            { unexpected: true },
            { provider: "codex" },
            { provider: "claude", error: { message: "cost failed" } }
        ])
        verify(mixed !== null)
        compare(mixed.length, 2)
        compare(mixed[0].provider, "codex")
        compare(mixed[1].provider, "claude")
        verify(Normalizer.costRecordHasError(mixed[1]))
    }

    function test_costEnvelopeRejectsUnsupportedNonemptyPayloads() {
        compare(Normalizer.normalizeCostEnvelope({ unexpected: true }), null)
        compare(Normalizer.normalizeCostEnvelope([null, { unexpected: true }]), null)
        compare(Normalizer.normalizeCostEnvelope({ error: { message: "cost failed" } }), null)
        compare(Normalizer.normalizeCostEnvelope([
            { provider: "codex" },
            { error: { message: "cost failed" } }
        ]), null)
        compare(Normalizer.normalizeCostEnvelope("no cost data"), null)
        compare(Normalizer.normalizeCostEnvelope(42), null)
        compare(Normalizer.normalizeCostEnvelope(null), null)
    }

    function test_costEnvelopeAppliesTheSnapshotBoundBeforeFiltering() {
        var payload = []
        for (var i = 0; i < 256; i++) {
            payload.push({ provider: "provider-" + i })
        }
        payload.push({ provider: "outside-bound" })

        var snapshots = Normalizer.normalizeCostEnvelope(payload)
        verify(snapshots !== null)
        compare(snapshots.length, 256)
        compare(snapshots[255].provider, "provider-255")
    }

    function test_costTrustMetadataNormalizesTheOfficialContract() {
        var trust = Normalizer.normalizeCostTrustMetadata({
            coverage: {
                priced: 4,
                unpriced: 0,
                unmetered: 2,
                estimated: 1
            },
            provenance: "listPriceEstimate"
        })

        verify(trust !== null)
        compare(trust.coverage.priced, 4)
        compare(trust.coverage.unpriced, 0)
        compare(trust.coverage.unmetered, 2)
        compare(trust.coverage.estimated, 1)
        compare(trust.sourceKind, "listPrice")
    }

    function test_costTrustMetadataIsQuietWhenTheCliOmitsIt() {
        compare(Normalizer.normalizeCostTrustMetadata({ provider: "codex" }), null)
        compare(Normalizer.normalizeCostTrustMetadata(null), null)
        compare(Normalizer.normalizeCostTrustMetadata([]), null)
    }

    function test_costRecordErrorDetectionUsesTheOfficialEnvelope() {
        verify(Normalizer.costRecordHasError({
            provider: "codex",
            daily: [],
            error: { message: "scan failed" }
        }))
        verify(Normalizer.costRecordHasError({
            provider: "codex",
            totals: { totalCost: 0, totalTokens: 0 },
            error: { message: "scan failed" }
        }))
        verify(!Normalizer.costRecordHasError({ provider: "codex" }))
        verify(!Normalizer.costRecordHasError(null))
    }

    function test_partialCostMergeKeepsOnlyExplicitlyFailedProviders() {
        var previous = {
            codex: { marker: "old-codex" },
            claude: { marker: "old-claude" },
            groq: { marker: "old-groq" },
            removed: { marker: "stale-provider" }
        }
        var fresh = {
            codex: { marker: "new-codex" }
        }

        var merged = Normalizer.mergeCostSnapshotsAfterPartialFailure(
            previous, fresh, ["claude", "groqcloud"])

        compare(Object.keys(merged).sort().join(","), "claude,codex,groq")
        compare(merged.codex.marker, "new-codex")
        compare(merged.claude.marker, "old-claude")
        compare(merged.groq.marker, "old-groq")
        verify(merged.removed === undefined)
    }

    function test_costTrustMetadataKeepsEitherValidAxisWithoutLeakingTheOther() {
        var coverageOnly = Normalizer.normalizeCostTrustMetadata({
            coverage: { priced: 1, unpriced: 0, unmetered: 0, estimated: 0 },
            provenance: " future-wire-value "
        })
        compare(coverageOnly.sourceKind, "")
        compare(coverageOnly.coverage.priced, 1)

        var provenanceOnly = Normalizer.normalizeCostTrustMetadata({
            coverage: { priced: "1", unpriced: 0, unmetered: 0, estimated: 0 },
            provenance: "vendorMetered"
        })
        compare(provenanceOnly.coverage, null)
        compare(provenanceOnly.sourceKind, "vendor")

        var officialValues = [
            { wire: "listPriceEstimate", semantic: "listPrice" },
            { wire: "vendorMetered", semantic: "vendor" },
            { wire: "mixed", semantic: "mixed" },
            { wire: "unknown", semantic: "unknown" }
        ]
        for (var i = 0; i < officialValues.length; i++) {
            compare(Normalizer.normalizeCostTrustMetadata({
                provenance: officialValues[i].wire
            }).sourceKind, officialValues[i].semantic)
        }
    }

    function test_costTrustMetadataRejectsMalformedCoverageAsAWhole() {
        var valid = { priced: 1, unpriced: 0, unmetered: 0, estimated: 0 }
        var invalidValues = ["1", -1, 0.5, NaN, Infinity,
            Normalizer.maximumCostCoverageCount + 1]
        for (var i = 0; i < invalidValues.length; i++) {
            var coverage = {
                priced: invalidValues[i],
                unpriced: valid.unpriced,
                unmetered: valid.unmetered,
                estimated: valid.estimated
            }
            compare(Normalizer.normalizeCostTrustMetadata({ coverage: coverage }), null)
        }

        compare(Normalizer.normalizeCostTrustMetadata({ coverage: null }), null)
        compare(Normalizer.normalizeCostTrustMetadata({ coverage: [] }), null)
        compare(Normalizer.normalizeCostTrustMetadata({ coverage: "priced" }), null)
        compare(Normalizer.normalizeCostTrustMetadata({
            coverage: { priced: 1, unpriced: 0, unmetered: 0 }
        }), null)
    }

    function test_costTrustMetadataRequiresOwnMetadataAndCounterFields() {
        function InheritedRecord() {}
        InheritedRecord.prototype.coverage = {
            priced: 1, unpriced: 0, unmetered: 0, estimated: 0
        }
        InheritedRecord.prototype.provenance = "unknown"
        compare(Normalizer.normalizeCostTrustMetadata(new InheritedRecord()), null)

        function InheritedCoverage() {
            this.priced = 1
            this.unpriced = 0
            this.unmetered = 0
        }
        InheritedCoverage.prototype.estimated = 0
        compare(Normalizer.normalizeCostTrustMetadata({
            coverage: new InheritedCoverage()
        }), null)
    }

    function test_normalizesDailyCostAndKeepsTheRequestedRange() {
        var daily = []
        for (var i = 0; i < 40; i++) {
            daily.push({ date: "2026-07-" + i, totalCost: i, totalTokens: i * 10 })
        }
        var rows = Normalizer.normalizeCostDaily(daily, "USD", 7)
        compare(rows.length, 7)
        // The newest days are kept, restored to chronological order.
        compare(rows[rows.length - 1].cost, 39)
        compare(rows[0].cost, 33)
        compare(rows[0].currency, "USD")
    }

    function test_costHistoryFillsMissingCalendarDaysInTheReportedWindow() {
        var rows = Normalizer.normalizeCostDaily([
            { date: "2026-08-27", totalCost: 6, totalTokens: 60 }
        ], "USD", 3, "2026-08-29T12:00:00Z")

        compare(rows.length, 3)
        compare(rows[0].label, "2026-08-27")
        compare(rows[0].cost, 6)
        compare(rows[1].label, "2026-08-28")
        compare(rows[1].cost, 0)
        compare(rows[1].tokens, 0)
        compare(rows[2].label, "2026-08-29")
        compare(rows[2].cost, 0)
    }

    function test_costHistoryPreservesDateOnlyUpdatedAtAcrossTimeZones() {
        var rows = Normalizer.normalizeCostDaily([
            { date: "2026-08-28", totalCost: 6, totalTokens: 60 }
        ], "USD", 2, "2026-08-29")

        compare(rows.length, 2)
        compare(rows[0].label, "2026-08-28")
        compare(rows[0].cost, 6)
        compare(rows[1].label, "2026-08-29")
        compare(rows[1].cost, 0)
    }

    function test_costHistoryDoesNotReuseDatesOutsideAnEmptyWindow_data() {
        return [
            { tag: "older", date: "2026-08-20" },
            { tag: "future", date: "2026-08-31" }
        ]
    }

    function test_costHistoryDoesNotReuseDatesOutsideAnEmptyWindow(data) {
        var rows = Normalizer.normalizeCostDaily([
            { date: data.date, totalCost: 100, totalTokens: 1000 }
        ], "USD", 7, "2026-08-30")

        compare(rows.length, 0)
    }

    function test_costHistoryNeverExceedsTheHistoryPointBound() {
        var daily = []
        for (var i = 0; i < Normalizer.maximumCostHistoryPoints + 50; i++) {
            daily.push({ date: "d" + i, totalCost: 1 })
        }
        compare(Normalizer.normalizeCostDaily(daily, "USD", 100000).length,
                Normalizer.maximumCostHistoryPoints)
    }

    function test_costHistoryStopsScanningAfterTheInspectionBound() {
        // A payload padded with junk beyond the scan budget must terminate rather
        // than walk the whole array looking for one more usable day.
        var daily = []
        for (var i = 0; i < Normalizer.maximumCostHistoryScanItems + 500; i++) {
            daily.push(null)
        }
        daily.unshift({ date: "old", totalCost: 5 })
        var rows = Normalizer.normalizeCostDaily(daily, "USD", 30)
        compare(rows.length, 0)
    }

    function test_costHistorySkipsMalformedDaysWithoutStringifyingThem() {
        var rows = Normalizer.normalizeCostDaily([
            null,
            "2026-08-01",
            [],
            { date: "2026-08-02" },
            { date: { nested: "object" }, totalCost: 3 },
            { date: "2026-08-03", totalCost: 4 }
        ], "USD", 30)

        compare(rows.length, 2)
        // A structured date leaves the chart label empty rather than printing
        // "[object Object]" on the axis; the day's numbers are still usable.
        compare(rows[0].label, "")
        compare(rows[0].cost, 3)
        compare(rows[1].label, "2026-08-03")
        compare(rows[1].cost, 4)
    }

    function test_costHistoryClampsNegativeAmountsAndFallsBackToTokenParts() {
        var rows = Normalizer.normalizeCostDaily([
            { date: "2026-08-01", totalCost: -12, inputTokens: 10, outputTokens: 5, cacheReadTokens: 2 }
        ], "USD", 30)
        compare(rows.length, 1)
        compare(rows[0].cost, 0)
        compare(rows[0].tokens, 17)
        compare(rows[0].inputTokens, 10)
    }

    function test_costHistoryPreservesMissingCostForTokenOnlyRows() {
        var rows = Normalizer.normalizeCostDaily([
            { date: "2026-08-01", totalTokens: 250 }
        ], "USD", 30)

        compare(rows.length, 1)
        compare(rows[0].cost, null)
        compare(rows[0].tokens, 250)
    }

    function test_costHistoryPreservesUnknownTokensWithoutLosingMeasuredCost() {
        var rows = Normalizer.normalizeCostDaily([
            { date: "2026-08-27", totalCost: 2 },
            { date: "2026-08-28", totalCost: 3, totalTokens: 0 }
        ], "USD", 3, "2026-08-29")
        compare(rows[0].cost, 2)
        compare(rows[0].tokens, null)
        compare(rows[1].tokens, 0)
        compare(rows[2].tokens, 0)
        compare(rows[2].models, [])
    }

    function test_costHistoryRejectsMalformedTokenTotalsWithoutInventingZero() {
        var invalidTokens = [undefined, null, false, true, "", "unknown", {}, [], Infinity]
        for (var i = 0; i < invalidTokens.length; i++) {
            var rows = Normalizer.normalizeCostDaily([
                { totalCost: 2, totalTokens: invalidTokens[i], tokens: invalidTokens[i] }
            ], "USD", 1)
            compare(rows[0].cost, 2)
            compare(rows[0].tokens, null)
        }
        var overflow = Normalizer.normalizeCostDaily([
            { totalCost: 2, inputTokens: 1e308, outputTokens: 1e308 }
        ], "USD", 1)
        compare(overflow[0].cost, 2)
        compare(overflow[0].tokens, null)
    }

    function test_costHistoryPreservesZeroTokenParts_data() {
        return [
            { tag: "input", field: "inputTokens", value: 0 },
            { tag: "output", field: "outputTokens", value: 0 },
            { tag: "cache-read", field: "cacheReadTokens", value: 0 },
            { tag: "cache-creation", field: "cacheCreationTokens", value: 0 },
            { tag: "legacy-cache-write", field: "cacheWriteTokens", value: 0 },
            { tag: "numeric-string", field: "cacheReadTokens", value: "0" }
        ]
    }

    function test_costHistoryPreservesZeroTokenParts(data) {
        var day = { date: "2026-08-01" }
        day[data.field] = data.value
        var rows = Normalizer.normalizeCostDaily([day], "USD", 1, day.date)

        compare(rows.length, 1)
        compare(rows[0].label, day.date)
        compare(rows[0].tokens, 0)
        compare(rows[0].cost, null)
    }

    function test_zeroCacheDayDoesNotRevivePricedHistoryOutsideTheRange() {
        var rows = Normalizer.normalizeCostDaily([
            { date: "2026-07-31", totalCost: 9, totalTokens: 100 },
            { date: "2026-08-01", cacheReadTokens: 0 }
        ], "USD", 1, "2026-08-01")

        compare(rows.length, 1)
        compare(rows[0].label, "2026-08-01")
        compare(rows[0].tokens, 0)
        compare(rows[0].cost, null)
    }

    function test_costHistoryRejectsMissingOrInvalidCacheTokenParts_data() {
        return [
            { tag: "missing", value: undefined },
            { tag: "null", value: null },
            { tag: "boolean", value: false },
            { tag: "blank", value: "" },
            { tag: "text", value: "unknown" },
            { tag: "object", value: {} },
            { tag: "not-finite", value: Infinity }
        ]
    }

    function test_costHistoryRejectsMissingOrInvalidCacheTokenParts(data) {
        var rows = Normalizer.normalizeCostDaily([{
            date: "2026-08-01",
            cacheReadTokens: data.value,
            cacheCreationTokens: data.value,
            cacheWriteTokens: data.value
        }], "USD", 1, "2026-08-01")

        compare(rows.length, 0)
    }

    function test_costHistoryFillsTokenOnlyGapsWithoutInventingCost() {
        var rows = Normalizer.normalizeCostDaily([
            { date: "2026-08-01", totalTokens: 250 }
        ], "USD", 2, "2026-08-02")

        compare(rows.length, 2)
        compare(rows[0].cost, null)
        compare(rows[1].cost, null)
        compare(rows[1].tokens, 0)
    }

    function test_costHistoryIgnoresPricedRowsBeforeTheRenderedWindow() {
        var rows = Normalizer.normalizeCostDaily([
            { date: "2026-08-27", totalCost: 3, totalTokens: 30 },
            { date: "2026-08-29", totalTokens: 250 }
        ], "USD", 2, "2026-08-29")

        compare(rows.length, 2)
        compare(rows[0].label, "2026-08-28")
        compare(rows[0].cost, null)
        compare(rows[1].cost, null)
    }

    function test_costHistoryFillsGapsEvenWhenTheDayBoundIsAlreadyCollected() {
        // The CLI emits its default 30-day daily array while the user renders a
        // 7-day range: collecting historyDays rows must not skip the calendar
        // gap fill, or the chart compresses out a missing day and keeps a day
        // from before the rendered window.
        var rows = Normalizer.normalizeCostDaily([
            { date: "2026-08-22", totalCost: 1, totalTokens: 10 },
            { date: "2026-08-23", totalCost: 2, totalTokens: 20 },
            { date: "2026-08-24", totalCost: 3, totalTokens: 30 },
            { date: "2026-08-25", totalCost: 4, totalTokens: 40 },
            { date: "2026-08-26", totalCost: 5, totalTokens: 50 },
            { date: "2026-08-27", totalCost: 6, totalTokens: 60 },
            { date: "2026-08-29", totalCost: 8, totalTokens: 80 },
            { date: "2026-08-30", totalCost: 9, totalTokens: 90 }
        ], "USD", 7, "2026-08-30")

        compare(rows.length, 7)
        compare(rows.map(function (row) { return row.label }).join(","),
            "2026-08-24,2026-08-25,2026-08-26,2026-08-27,2026-08-28,2026-08-29,2026-08-30")
        compare(rows[0].cost, 3)
        compare(rows[4].label, "2026-08-28")
        compare(rows[4].cost, 0)
        compare(rows[4].tokens, 0)
        compare(rows[6].cost, 9)
    }

    function test_costHistoryAcceptsBothLegacyAndCurrentFieldNames() {
        var current = Normalizer.normalizeCostDaily(
            [{ date: "2026-08-01", totalCost: 2, totalTokens: 20, cacheCreationTokens: 3 }], "USD", 30)
        var legacy = Normalizer.normalizeCostDaily(
            [{ day: "2026-08-01", costUSD: 2, tokens: 20, cacheWriteTokens: 3 }], "USD", 30)
        compare(current[0].cost, legacy[0].cost)
        compare(current[0].tokens, legacy[0].tokens)
        compare(current[0].cacheCreationTokens, legacy[0].cacheCreationTokens)
        compare(current[0].label, legacy[0].label)
    }

    function test_costHistoryRejectsNullAndBooleanNumbersButUsesValidAliases() {
        var rows = Normalizer.normalizeCostDaily([
            { date: "2026-08-01", totalCost: null },
            { date: "2026-08-02", totalCost: false, totalTokens: true },
            { date: "2026-08-03", totalCost: null, costUSD: 3, totalTokens: false, tokens: 4 },
            { date: "2026-08-04", inputTokens: true }
        ], "USD", 30)

        compare(rows.length, 1)
        compare(rows[0].label, "2026-08-03")
        compare(rows[0].cost, 3)
        compare(rows[0].tokens, 4)
    }

    function test_costHistoryDoesNotFillAnExplicitlyMalformedDayWithZero() {
        var rows = Normalizer.normalizeCostDaily([
            { date: "2026-08-28", totalCost: 3, totalTokens: 30 },
            { date: "2026-08-29", totalCost: null }
        ], "USD", 2, "2026-08-29")

        compare(rows.length, 1)
        compare(rows[0].label, "2026-08-28")
        compare(rows[0].cost, 3)
    }

    function test_costHistoryDoesNotFillBeyondAnIncompleteInspection() {
        var daily = [{ date: "2026-08-29", totalCost: null }]
        for (var i = 0; i < Normalizer.maximumCostHistoryScanItems - 1; i++) {
            daily.push(null)
        }
        daily.push({ date: "2026-08-28", totalCost: 3, totalTokens: 30 })

        var rows = Normalizer.normalizeCostDaily(daily, "USD", 2, "2026-08-29")

        compare(rows.length, 1)
        compare(rows[0].label, "2026-08-28")
    }

    function test_costHistoryInspectsMalformedDaysBeyondTheResultBound() {
        var rows = Normalizer.normalizeCostDaily([
            { date: "2026-08-29", totalCost: null },
            { date: "2026-08-27", totalCost: 2 },
            { date: "2026-08-28", totalCost: 3 }
        ], "USD", 2, "2026-08-29")

        compare(rows.length, 2)
        compare(rows[0].label, "2026-08-27")
        compare(rows[1].label, "2026-08-28")
        compare(rows[1].cost, 3)
    }

    function test_costHistoryInspectsValidDaysBeyondTheResultBound() {
        var rows = Normalizer.normalizeCostDaily([
            { date: "2026-08-29", totalCost: 9 },
            { date: "2026-08-27", totalCost: 2 },
            { date: "2026-08-28", totalCost: 3 }
        ], "USD", 2, "2026-08-29")

        compare(rows.length, 2)
        compare(rows[0].label, "2026-08-28")
        compare(rows[1].label, "2026-08-29")
        compare(rows[1].cost, 9)
    }

    function test_costHistoryIgnoresMalformedLabelsBeforeTheRetainedRows() {
        var rows = Normalizer.normalizeCostDaily([
            { date: "bad-date", totalCost: 1 },
            { date: "2026-08-28", totalCost: 2 },
            { date: "2026-08-29", totalCost: 3 }
        ], "USD", 2, "2026-08-30")

        compare(rows.length, 2)
        compare(rows[0].label, "2026-08-29")
        compare(rows[0].cost, 3)
        compare(rows[1].label, "2026-08-30")
        compare(rows[1].cost, 0)
    }

    function test_costHistoryIgnoresDuplicateDatesOutsideTheWindow() {
        var rows = Normalizer.normalizeCostDaily([
            { date: "2026-08-20", totalCost: 1 },
            { date: "2026-08-20", totalCost: 2 },
            { date: "2026-08-29", totalCost: 3 }
        ], "USD", 2, "2026-08-30")

        compare(rows.length, 2)
        compare(rows[0].label, "2026-08-29")
        compare(rows[1].label, "2026-08-30")
        compare(rows[1].cost, 0)
    }

    function test_costDailyDegradesToAnEmptyRangeForNonArrays() {
        compare(Normalizer.normalizeCostDaily(null, "USD", 30).length, 0)
        compare(Normalizer.normalizeCostDaily({ "0": { totalCost: 1 }, length: 1 }, "USD", 30).length, 0)
        compare(Normalizer.normalizeCostDaily("2026-08-01", "USD", 30).length, 0)
    }

    function test_dailyCostModelsStayWithTheirOwnDayAndPreservePeriodTotals() {
        var items = [
            { date: "2026-08-28", totalCost: 4, totalTokens: 40, modelBreakdowns: [
                { modelName: "shared", cost: 1, totalTokens: 10 },
                { modelName: "shared", cost: 3, totalTokens: 30 }
            ] },
            { date: "2026-08-29", totalCost: 5, totalTokens: 50,
                modelBreakdowns: [{ modelName: "shared", cost: 5, totalTokens: 50 }] }
        ]
        var daily = Normalizer.normalizeCostDaily(items, "EUR", 2, "2026-08-29")
        compare(daily[0].models, [{ label: "shared", cost: 4, tokens: 40, currency: "EUR" }])
        compare(daily[1].models, [{ label: "shared", cost: 5, tokens: 50, currency: "EUR" }])
        compare(daily[0].modelsTruncated, false)
        compare(daily[1].modelsTruncated, false)
        compare(Normalizer.normalizeCostModels(items, "EUR", 2, "2026-08-29").rows,
            [{ label: "shared", cost: 9, tokens: 90, currency: "EUR" }])
        daily[0].models[0].cost = 99
        compare(daily[1].models[0].cost, 5)
        compare(items[0].modelBreakdowns[0].cost, 1)
    }

    function test_dailyCostModelsPreserveUnknownZeroAndLegacyAmounts() {
        var daily = Normalizer.normalizeCostDaily([{ totalTokens: 40, modelBreakdowns: [
            { modelName: "token-only", cost: null, totalTokens: 20 },
            { modelName: "zero", cost: 0, totalTokens: 0 },
            { model: "alias", cost: null, totalCost: "3", totalTokens: false, tokens: "4" },
            { modelName: "negative", cost: -2, totalTokens: -1 }
        ] }], "USD", 1)
        var models = daily[0].models
        compare(models.slice(0, 2), [
            { label: "alias", cost: 3, tokens: 4, currency: "USD" },
            { label: "token-only", cost: null, tokens: 20, currency: "USD" }
        ])
        var zeroModels = models.slice(2).sort(function(a, b) { return a.label.localeCompare(b.label) })
        compare(zeroModels, [
            { label: "negative", cost: 0, tokens: 0, currency: "USD" },
            { label: "zero", cost: 0, tokens: 0, currency: "USD" }
        ])
    }

    function test_dailyCostModelsRejectMalformedRecordsAndInheritedFields() {
        function InheritedModel() { this.cost = 1 }
        InheritedModel.prototype.modelName = "inherited-name"
        function InheritedAmount() { this.modelName = "inherited-cost" }
        InheritedAmount.prototype.cost = 2
        var arrayRecord = []
        arrayRecord.modelName = "array-record"
        arrayRecord.cost = 3
        var daily = Normalizer.normalizeCostDaily([{ totalCost: 1, modelBreakdowns: [
            null, "string-record", 3, true, arrayRecord, new InheritedModel(), new InheritedAmount(),
            { modelName: 7, cost: 2 },
            { modelName: true, cost: 2 },
            { modelName: { nested: "name" }, cost: 2 },
            { modelName: "coercive", cost: false, totalTokens: true },
            { modelName: "__proto__", cost: 2 },
            { modelName: "constructor", cost: 2 },
            { modelName: "prototype", cost: 2 },
            { modelName: "healthy", cost: 1 }
        ] }], "USD", 1)
        compare(daily[0].models, [{ label: "healthy", cost: 1, tokens: null, currency: "USD" }])
        compare(daily[0].modelsTruncated, false)
        compare(({}).polluted, undefined)
    }

    function test_dailyCostModelsRetainOnlyBoundedRedactedDisplayFields() {
        var daily = Normalizer.normalizeCostDaily([{ totalCost: 6, modelBreakdowns: [
            { modelName: "Authorization: Bearer synthetic-model-secret", cost: 3,
                source: { path: "/private/source", apiKey: "private-key" },
                path: "/private/model", standardCostUSD: 2, priorityCostUSD: 1 },
            { modelName: new Array(300).join("x"), cost: 2 },
            { modelName: "<b>literal model</b>", cost: 1 }
        ] }], "USD", 1)
        var models = daily[0].models
        compare(models[0].label, "Authorization: [redacted]")
        compare(models[1].label.length, 120)
        compare(models[2].label, "<b>literal model</b>")
        for (var i = 0; i < models.length; i++) {
            compare(Object.keys(models[i]).sort().join(","), "cost,currency,label,tokens")
        }
        var encoded = JSON.stringify(daily)
        verify(encoded.indexOf("synthetic-model-secret") === -1)
        verify(encoded.indexOf("/private/") === -1)
        verify(encoded.indexOf("private-key") === -1)
    }

    function test_dailyCostModelsReportInspectionTruncationBeforeFiltering() {
        var breakdowns = new Array(Normalizer.maximumModelBreakdownsPerDay + 1)
        breakdowns[0] = { modelName: "first", cost: 1 }
        breakdowns[Normalizer.maximumModelBreakdownsPerDay - 1] = { modelName: "last", cost: 2 }
        Object.defineProperty(breakdowns, String(Normalizer.maximumModelBreakdownsPerDay), {
            configurable: true,
            get: function() { fail("Model inspection exceeded its bound") }
        })
        var daily = Normalizer.normalizeCostDaily([{ totalCost: 3, modelBreakdowns: breakdowns }], "USD", 1)
        compare(daily[0].models.length, 2)
        compare(daily[0].models[0].label, "last")
        compare(daily[0].modelsTruncated, true)
        breakdowns.length = Normalizer.maximumModelBreakdownsPerDay
        daily = Normalizer.normalizeCostDaily([{ totalCost: 3, modelBreakdowns: breakdowns }], "USD", 1)
        compare(daily[0].modelsTruncated, false)
    }

    function test_dailyCostModelDisplayCapDoesNotTruncatePeriodAggregation() {
        var breakdowns = []
        for (var i = 0; i < 7; i++) {
            breakdowns.push({ modelName: "model-" + i, cost: 7 - i })
        }
        var items = [
            { date: "2026-08-28", totalCost: 28, modelBreakdowns: breakdowns },
            { date: "2026-08-29", totalCost: 100,
                modelBreakdowns: [{ modelName: "model-6", cost: 100 }] }
        ]
        var daily = Normalizer.normalizeCostDaily(items, "USD", 2, "2026-08-29")
        compare(daily[0].models.length, 6)
        compare(daily[0].models[5].label, "model-5")
        compare(daily[0].modelsTruncated, true)
        compare(daily[1].modelsTruncated, false)
        var period = Normalizer.normalizeCostModels(items, "USD", 2, "2026-08-29").rows
        compare(period.length, 6)
        compare(period[0].label, "model-6")
        compare(period[0].cost, 101)
    }

    function test_dailyCostModelsAggregateDuplicatesBeforeApplyingDisplayCap() {
        var breakdowns = []
        for (var i = 0; i < 10; i++) {
            breakdowns.push({ modelName: "same", cost: 1 })
        }
        var daily = Normalizer.normalizeCostDaily([{ totalCost: 10, modelBreakdowns: breakdowns }], "USD", 1)
        compare(daily[0].models.length, 1)
        compare(daily[0].models[0].cost, 10)
        compare(daily[0].modelsTruncated, false)
    }

    function test_dailyCostModelsPreserveAbsentTokensAndAggregateOnlyObservedCounts() {
        var items = [
            { totalCost: 3, modelBreakdowns: [
                { modelName: "cost-only", cost: 2 },
                { modelName: "mixed", cost: 1 }
            ] },
            { totalCost: 3, modelBreakdowns: [
                { modelName: "cost-only", cost: 2, totalTokens: null },
                { modelName: "mixed", cost: 1, totalTokens: 0 }
            ] }
        ]
        var daily = Normalizer.normalizeCostDaily(items, "USD", 2)
        compare(daily[0].models, [
            { label: "cost-only", cost: 2, tokens: null, currency: "USD" },
            { label: "mixed", cost: 1, tokens: null, currency: "USD" }
        ])
        compare(daily[1].models[1].tokens, 0)
        compare(Normalizer.normalizeCostModels(items, "USD", 2).rows, [
            { label: "cost-only", cost: 4, tokens: null, currency: "USD" },
            { label: "mixed", cost: 2, tokens: 0, currency: "USD" }
        ])
        items.push({ modelBreakdowns: [{ modelName: "mixed", cost: 1, totalTokens: 7 }] })
        var period = Normalizer.normalizeCostModels(items, "USD", 3).rows
        compare(period[1].label, "mixed")
        compare(period[1].tokens, 7)
    }

    function test_dailyCostModelOverflowKeepsTheCompanionMetricAndStaysUnknown() {
        var breakdowns = []
        for (var i = 0; i < 3; i++) {
            breakdowns.push({ modelName: "cost-overflow", cost: i < 2 ? 1e308 : 1, totalTokens: 2 })
            breakdowns.push({ modelName: "token-overflow", cost: 2, totalTokens: i < 2 ? 1e308 : 1 })
        }
        var item = { totalCost: 6, totalTokens: 6, modelBreakdowns: breakdowns }
        var dailyModels = Normalizer.normalizeCostDaily([item], "USD", 1)[0].models
        compare(dailyModels, [
            { label: "token-overflow", cost: 6, tokens: null, currency: "USD" },
            { label: "cost-overflow", cost: null, tokens: 6, currency: "USD" }
        ])
        compare(Normalizer.normalizeCostModels([item], "USD", 1).rows, dailyModels)
        var period = Normalizer.normalizeCostModels([
            { modelBreakdowns: [{ modelName: "same", cost: 1e308, totalTokens: 1 }] },
            { modelBreakdowns: [{ modelName: "same", cost: 1e308, totalTokens: 2 }] }
        ], "USD", 2).rows
        compare(period, [{ label: "same", cost: null, tokens: 3, currency: "USD" }])
    }

    function test_dailyCostModelsDoNotPopulateGapsOrReviveInvalidDays() {
        var daily = Normalizer.normalizeCostDaily([
            { date: "2026-08-20", totalCost: 9, modelBreakdowns: [{ modelName: "old", cost: 9 }] },
            { date: "2026-08-28", totalCost: 2, modelBreakdowns: [{ modelName: "current", cost: 2 }] }
        ], "USD", 2, "2026-08-29")
        compare(daily[0].models[0].label, "current")
        compare(daily[1].label, "2026-08-29")
        compare(daily[1].models, [])
        compare(daily[1].modelsTruncated, false)
        compare(Normalizer.normalizeCostDaily([
            { date: "2026-08-29", totalCost: null, modelBreakdowns: [{ modelName: "orphan", cost: 2 }] }
        ], "USD", 1, "2026-08-29"), [])
    }

    function test_dailyCostModelsIgnoreMalformedContainers() {
        var containers = [undefined, null, "models", {}, { "0": { modelName: "fake", cost: 2 }, length: 1 }]
        for (var i = 0; i < containers.length; i++) {
            var daily = Normalizer.normalizeCostDaily([{ totalCost: 1, modelBreakdowns: containers[i] }], "USD", 1)
            compare(daily[0].models, [])
            compare(daily[0].modelsTruncated, false)
        }
    }

    function test_costTotalsPreserveUnknownAndMeasuredTokenCounts_data() {
        return [
            { tag: "absent", totals: { totalCost: 2 }, expected: null },
            { tag: "null", totals: { totalCost: 2, totalTokens: null }, expected: null },
            { tag: "boolean", totals: { totalCost: 2, totalTokens: false }, expected: null },
            { tag: "invalid", totals: { totalCost: 2, totalTokens: "unknown" }, expected: null },
            { tag: "zero-total", totals: { totalCost: 2, totalTokens: 0 }, expected: 0 },
            { tag: "zero-part", totals: { totalCost: 2, inputTokens: 0 }, expected: 0 },
            { tag: "negative-only-parts", totals: { totalCost: 2, inputTokens: -3 }, expected: null },
            { tag: "overflowing-parts", totals: { totalCost: 2, inputTokens: 1e308, outputTokens: 1e308 }, expected: null }
        ]
    }

    function test_costTotalsPreserveUnknownAndMeasuredTokenCounts(data) {
        var totals = Normalizer.normalizeCostTotals(data.totals, undefined, undefined, "USD")
        compare(totals.tokens, data.expected)
        compare(totals.cost, 2)
    }

    function test_costDailyRejectsNegativeOnlyPartsAndKeepsMeasuredZero() {
        var rows = Normalizer.normalizeCostDaily([
            { date: "2026-09-01", inputTokens: -3 },
            { date: "2026-09-02", totalCost: 2, inputTokens: -3 },
            { date: "2026-09-03", inputTokens: 0 }
        ], "USD", 3)
        compare(rows.length, 2)
        compare(rows[0].tokens, null)
        compare(rows[1].tokens, 0)
    }

    function test_costDailyRetainsUnknownOverflowAndObservedParts() {
        var rows = Normalizer.normalizeCostDaily([
            { date: "2026-09-01", inputTokens: 1e308, outputTokens: 1e308 }
        ], "USD", 1)
        compare(rows.length, 1)
        compare(rows[0].cost, null)
        compare(rows[0].tokens, null)
        compare(rows[0].inputTokens, 1e308)
    }

    function test_costModelsRejectNonTextNames() {
        var summary = Normalizer.normalizeCostModels([{ modelBreakdowns: [
            { modelName: 123, cost: 1 },
            { model: 123, cost: 1 },
            { modelName: "123", cost: 2 }
        ] }], "USD", 1)
        compare(summary.rows, [{ label: "123", cost: 2, tokens: null, currency: "USD" }])
    }

    function test_costGapFillingRequiresAnObservedMetric() {
        var rows = Normalizer.normalizeCostDaily([
            { date: "2026-09-02", totalCost: 2 }
        ], "USD", 3, "2026-09-03")
        compare(rows.length, 3)
        for (var i = 0; i < rows.length; i++) {
            compare(rows[i].tokens, null)
        }
        compare(rows[0].cost, 0)
        var tokenRows = Normalizer.normalizeCostDaily([
            { date: "2026-09-02", totalTokens: 0 }
        ], "USD", 3, "2026-09-03")
        for (var j = 0; j < tokenRows.length; j++) {
            compare(tokenRows[j].tokens, 0)
            compare(tokenRows[j].cost, null)
        }
    }

    function test_periodCostModelsRetainDisplayAndInspectionTruncation() {
        var breakdowns = []
        for (var i = 0; i < 7; i++) {
            breakdowns.push({ modelName: "model-" + i, cost: 7 - i })
        }
        var summary = Normalizer.normalizeCostModels([{ modelBreakdowns: breakdowns }], "USD", 30)
        compare(summary.rows.length, 6)
        compare(summary.truncated, true)
        breakdowns.pop()
        compare(Normalizer.normalizeCostModels([{ modelBreakdowns: breakdowns }], "USD", 30).truncated, false)
        breakdowns.length = Normalizer.maximumModelBreakdownsPerDay + 1
        compare(Normalizer.normalizeCostModels([{ modelBreakdowns: breakdowns }], "USD", 30).truncated, true)
        compare(Normalizer.normalizeCostModels([], "USD", 30), { rows: [], truncated: false })
    }

    function test_costModelTiesHaveStableLabelOrder() {
        var items = [{ modelBreakdowns: [
            { modelName: "Zulu", cost: 2, totalTokens: 20 },
            { modelName: "Alpha", cost: 2, totalTokens: 20 }
        ] }]
        var first = Normalizer.normalizeCostModels(items, "USD", 30)
        items[0].modelBreakdowns.reverse()
        compare(Normalizer.normalizeCostModels(items, "USD", 30), first)
    }

    function test_costTotalsPreferEmittedTotalsAndFallBackToTheWindow() {
        var emitted = Normalizer.normalizeCostTotals(
            { totalCost: 12.5, totalTokens: 900 }, 99, 99, "EUR")
        compare(emitted.cost, 12.5)
        compare(emitted.tokens, 900)
        compare(emitted.currency, "EUR")

        var fallback = Normalizer.normalizeCostTotals(null, 7.25, 400, "")
        compare(fallback.cost, 7.25)
        compare(fallback.tokens, 400)
        compare(fallback.currency, "USD")
    }

    function test_costTotalsPreserveMissingCostForTokenOnlySnapshots() {
        var totals = Normalizer.normalizeCostTotals(
            { totalTokens: 900 }, undefined, undefined, "USD")

        compare(totals.cost, null)
        compare(totals.tokens, 900)
    }

    function test_costTotalsRejectNullAndBooleanNumbersBeforeUsingFallbacks() {
        var totals = Normalizer.normalizeCostTotals({
            totalCost: null,
            totalTokens: false,
            inputTokens: true,
            outputTokens: ""
        }, 7.25, 400, "USD")

        compare(totals.cost, 7.25)
        compare(totals.tokens, 400)
        compare(totals.inputTokens, 0)
        compare(totals.outputTokens, 0)
    }

    function test_costTotalsSumTokenPartsWhenNoTotalIsEmitted() {
        var totals = Normalizer.normalizeCostTotals(
            { inputTokens: 100, outputTokens: 50, cacheReadTokens: 25, cacheCreationTokens: 5 },
            0, undefined, "USD")
        compare(totals.tokens, 180)
    }

    function test_costTotalsNeverGoNegativeOrNaN() {
        var totals = Normalizer.normalizeCostTotals(
            { totalCost: -5, totalTokens: "lots", inputTokens: "x" }, undefined, undefined, "USD")
        compare(totals.cost, 0)
        compare(totals.tokens, null)
        compare(totals.inputTokens, 0)
    }

    function test_providerCostTotalsHideAntigravityCostButKeepOtherZeroes() {
        var antigravity = Normalizer.normalizeProviderCostTotals(
            "antigravity", { totalCost: 0, totalTokens: 0 }, 0, 0, "USD")
        var codex = Normalizer.normalizeProviderCostTotals(
            "codex", { totalCost: 0, totalTokens: 0 }, 0, 0, "USD")

        compare(antigravity.cost, null)
        compare(antigravity.tokens, 0)
        compare(codex.cost, 0)
    }

    function test_providerCostAmountsPreserveUnavailableAntigravityPricing_data() {
        return [
            { tag: "antigravity-idle-today", provider: "antigravity", amount: 0, expected: null },
            { tag: "antigravity-no-pricing", provider: "antigravity", amount: 1, expected: null },
            { tag: "antigravity-missing", provider: "antigravity", amount: undefined, expected: null },
            { tag: "codex-zero", provider: "codex", amount: 0, expected: 0 },
            { tag: "claude-zero", provider: "claude", amount: 0, expected: 0 },
            { tag: "codex-positive", provider: "codex", amount: 1.25, expected: 1.25 },
            { tag: "legacy-numeric-string", provider: "claude", amount: "2.5", expected: 2.5 },
            { tag: "missing", provider: "codex", amount: undefined, expected: null },
            { tag: "null", provider: "claude", amount: null, expected: null },
            { tag: "boolean", provider: "codex", amount: false, expected: null }
        ]
    }

    function test_providerCostAmountsPreserveUnavailableAntigravityPricing(data) {
        compare(Normalizer.normalizeProviderCostAmount(data.provider, data.amount), data.expected)
    }

    function test_sumTokenPartsReportsNaNWhenNothingIsUsable() {
        verify(isNaN(Normalizer.sumTokenParts(undefined, null, "x", NaN)))
        compare(Normalizer.sumTokenParts(0, 0, 0, 0), 0)
        verify(isNaN(Normalizer.sumTokenParts(-3, undefined, undefined, undefined)))
        compare(Normalizer.sumTokenParts(1, 2, 3, 4), 10)
    }

    function test_costModelsAggregateAcrossDaysAndRankByCost() {
        var rows = Normalizer.normalizeCostModels([
            { modelBreakdowns: [{ modelName: "gpt-5", cost: 1, totalTokens: 10 }] },
            { modelBreakdowns: [
                { modelName: "gpt-5", cost: 2, totalTokens: 20 },
                { model: "sonnet", totalCost: 5, tokens: 1 }
            ] }
        ], "USD", 30).rows

        compare(rows.length, 2)
        compare(rows[0].label, "sonnet")
        compare(rows[0].cost, 5)
        compare(rows[1].label, "gpt-5")
        compare(rows[1].cost, 3)
        compare(rows[1].tokens, 30)
    }

    function test_costModelsUseTheSameCalendarWindowAsDailyHistory_data() {
        return [
            { tag: "date-only", updatedAt: "2026-08-30" },
            { tag: "timestamp", updatedAt: new Date(2026, 7, 30, 12).toISOString() }
        ]
    }

    function test_costModelsUseTheSameCalendarWindowAsDailyHistory(data) {
        var items = [
            { date: "2026-08-20", totalCost: 100, totalTokens: 1000,
                modelBreakdowns: [{ modelName: "old", cost: 100, totalTokens: 1000 }] },
            { date: "2026-08-24", totalCost: 2, totalTokens: 20,
                modelBreakdowns: [{ modelName: "current", cost: 2, totalTokens: 20 }] },
            { date: "2026-08-29", totalCost: 1, totalTokens: 10,
                modelBreakdowns: [{ modelName: "current", cost: 1, totalTokens: 10 }] },
            { date: "2026-08-31", totalCost: 200, totalTokens: 2000,
                modelBreakdowns: [{ modelName: "future", cost: 200, totalTokens: 2000 }] }
        ]
        var daily = Normalizer.normalizeCostDaily(items, "USD", 7, data.updatedAt)
        var models = Normalizer.normalizeCostModels(items, "USD", 7, data.updatedAt).rows

        compare(daily.length, 7)
        compare(models.length, 1)
        compare(models[0].label, "current")
        compare(models[0].cost, 3)
        compare(models[0].tokens, 30)
        compare(daily.reduce(function(total, row) { return total + row.cost }, 0),
            models[0].cost)
    }

    function test_costModelsFindInRangeDatesBeyondTheRowCount() {
        var items = [
            { day: "2026-08-29", modelBreakdowns: [{ modelName: "current", cost: 2 }] },
            null,
            { dayKey: "2026-08-20", modelBreakdowns: [{ modelName: "old", cost: 100 }] },
            { date: "2026-08-30", modelBreakdowns: [{ modelName: "current", cost: 3 }] }
        ]
        var rows = Normalizer.normalizeCostModels(items, "USD", 2, "2026-08-30").rows

        compare(rows.length, 1)
        compare(rows[0].label, "current")
        compare(rows[0].cost, 5)
    }

    function test_costModelsDoNotReuseDatesOutsideAnEmptyWindow() {
        var rows = Normalizer.normalizeCostModels([
            { date: "2026-08-20", modelBreakdowns: [{ modelName: "old", cost: 100 }] }
        ], "USD", 7, "2026-08-30").rows

        compare(rows.length, 0)
    }

    function test_costModelsKeepLegacyTailWithoutUsableDates_data() {
        return [
            { tag: "missing-update", updatedAt: undefined, dated: true },
            { tag: "invalid-update", updatedAt: "not-a-date", dated: true },
            { tag: "missing-days", updatedAt: "2026-08-30", dated: false }
        ]
    }

    function test_costModelsKeepLegacyTailWithoutUsableDates(data) {
        var items = []
        for (var i = 0; i < 3; i++) {
            items.push({
                date: data.dated ? "2026-08-" + (20 + i) : "",
                modelBreakdowns: [{ modelName: "model-" + i, cost: i + 1 }]
            })
        }
        var rows = Normalizer.normalizeCostModels(items, "USD", 2, data.updatedAt).rows

        compare(rows.length, 2)
        compare(rows[0].label, "model-2")
        compare(rows[1].label, "model-1")
    }

    function test_costModelsStopAtTheCalendarInspectionBound() {
        var items = [{
            date: "2026-08-29",
            modelBreakdowns: [{ modelName: "uninspected", cost: 100 }]
        }]
        for (var i = 0; i < Normalizer.maximumCostHistoryScanItems - 1; i++) {
            items.push(null)
        }
        items.push({
            date: "2026-08-30",
            modelBreakdowns: [{ modelName: "inspected", cost: 1 }]
        })
        var rows = Normalizer.normalizeCostModels(items, "USD", 2, "2026-08-30").rows

        compare(rows.length, 1)
        compare(rows[0].label, "inspected")
    }

    function test_costModelsKeepTheDayBudgetWithDuplicateDates() {
        var items = []
        for (var i = 0; i < 5; i++) {
            items.push({
                date: "2026-08-30",
                modelBreakdowns: [{ modelName: "current", cost: 1 }]
            })
        }
        var rows = Normalizer.normalizeCostModels(items, "USD", 2, "2026-08-30").rows

        compare(rows.length, 1)
        compare(rows[0].cost, 2)
    }

    function test_costModelsPreserveMissingCostForTokenOnlyBreakdowns() {
        var rows = Normalizer.normalizeCostModels([{ modelBreakdowns: [{
            modelName: "gemini-2.5-pro",
            cost: null,
            totalTokens: 198
        }] }], "USD", 30).rows

        compare(rows.length, 1)
        compare(rows[0].cost, null)
        compare(rows[0].tokens, 198)
    }

    function test_costModelsRejectCoerciveNumbersAndUseValidAliases() {
        var rows = Normalizer.normalizeCostModels([{ modelBreakdowns: [
            { modelName: "null-cost", cost: null },
            { modelName: "boolean-tokens", cost: false, totalTokens: true },
            { modelName: "valid-aliases", cost: null, totalCost: 3,
                totalTokens: false, tokens: 4 }
        ] }], "USD", 30).rows

        compare(rows.length, 1)
        compare(rows[0].label, "valid-aliases")
        compare(rows[0].cost, 3)
        compare(rows[0].tokens, 4)
    }

    function test_costModelsDropPrototypePollutingModelNames() {
        var rows = Normalizer.normalizeCostModels([
            { modelBreakdowns: JSON.parse(
                '[{"modelName":"__proto__","cost":9},'
                + '{"modelName":"constructor","cost":9},'
                + '{"modelName":"prototype","cost":9},'
                + '{"modelName":"gpt-5","cost":1}]') }
        ], "USD", 30).rows

        compare(rows.length, 1)
        compare(rows[0].label, "gpt-5")
        compare(({}).polluted, undefined)
    }

    function test_costModelsKeepPrototypeMemberNamesThatAreNotDangerous() {
        // "toString" is a plausible model name and must survive the own-key check
        // that a bare `byName[name]` lookup would have swallowed.
        var rows = Normalizer.normalizeCostModels([
            { modelBreakdowns: [{ modelName: "toString", cost: 4 }] }
        ], "USD", 30).rows
        compare(rows.length, 1)
        compare(rows[0].label, "toString")
        compare(rows[0].cost, 4)
    }

    function test_costModelsCapBreakdownsPerDayAndRowsOverall() {
        var breakdowns = []
        for (var i = 0; i < Normalizer.maximumModelBreakdownsPerDay + 40; i++) {
            breakdowns.push({ modelName: "model-" + i, cost: i + 1 })
        }
        var rows = Normalizer.normalizeCostModels([{ modelBreakdowns: breakdowns }], "USD", 30).rows
        compare(rows.length, 6)
        // The most expensive surviving model is the last one inside the per-day
        // breakdown bound, not the most expensive one in the payload.
        compare(rows[0].label, "model-" + (Normalizer.maximumModelBreakdownsPerDay - 1))
    }

    function test_costModelsIgnoreMalformedBreakdownContainers() {
        compare(Normalizer.normalizeCostModels(null, "USD", 30).rows.length, 0)
        compare(Normalizer.normalizeCostModels("daily", "USD", 30).rows.length, 0)
        compare(Normalizer.normalizeCostModels([
            null,
            { modelBreakdowns: "gpt-5" },
            { modelBreakdowns: { "0": { modelName: "gpt-5", cost: 1 } } },
            { modelBreakdowns: [{ modelName: "gpt-5" }] }
        ], "USD", 30).rows.length, 0)
    }

    function test_costModelsFloorFractionalDayBounds() {
        // A fractional window must keep the last whole days like
        // normalizeCostDaily does: without the floor the loop index stays
        // fractional, every day lookup misses, and all model rows disappear.
        var items = [
            { modelBreakdowns: [{ modelName: "old", cost: 1 }] },
            { modelBreakdowns: [{ modelName: "mid", cost: 2 }] },
            { modelBreakdowns: [{ modelName: "new", cost: 3 }] }
        ]
        var rows = Normalizer.normalizeCostModels(items, "USD", 2.5).rows
        compare(rows.length, 2)
        compare(rows[0].label, "new")
        compare(rows[1].label, "mid")
        var singleDay = Normalizer.normalizeCostModels(items, "USD", 0.5).rows
        compare(singleDay.length, 1)
        compare(singleDay[0].label, "new")
    }

    // --- bounded display text ----------------------------------------------

    function test_boundedDisplayTextBlanksNullishValues() {
        compare(Normalizer.boundedDisplayText(null, 120), "")
        compare(Normalizer.boundedDisplayText(undefined, 120), "")
        compare(Normalizer.boundedDisplayText("", 120), "")
        compare(Normalizer.boundedDisplayText("   ", 120), "")
    }

    // Structured values are dropped; scalars still coerce, because a numeric or
    // boolean CLI field is a value the popup can legitimately print.
    function test_boundedDisplayTextDropsStructuredPayloadsButKeepsScalars() {
        compare(Normalizer.boundedDisplayText({ nested: "object" }, 120), "")
        compare(Normalizer.boundedDisplayText({}, 120), "")
        compare(Normalizer.boundedDisplayText([1, 2, 3], 120), "")
        compare(Normalizer.boundedDisplayText([], 120), "")
        compare(Normalizer.boundedDisplayText(7, 120), "7")
        compare(Normalizer.boundedDisplayText(true, 120), "true")
    }

    function test_boundedDisplayTextRedactsCredentialsAtTheCliBoundary() {
        compare(Normalizer.boundedDisplayText(
            "Authorization: Bearer provider-secret", 120),
            "Authorization: [redacted]")
    }

    function test_boundedDisplayTextKeepsFalsyScalars() {
        compare(Normalizer.boundedDisplayText(0, 120), "0")
        compare(Normalizer.boundedDisplayText(false, 120), "false")
    }

    function test_structuredSessionFieldsDegradeWithoutDroppingTheSession() {
        var session = Normalizer.normalizeSession({
            provider: "codex",
            projectName: "codexbar-plasma",
            host: { nested: "object" },
            sessionName: ["a", "b"]
        })
        compare(session.projectName, "codexbar-plasma")
        compare(session.host, "")
        compare(session.sessionName, "")
    }

    function test_boundedDisplayTextPreservesUnicodeWithoutSplittingGraphemes() {
        // Mirrors the contract exercised in tst_usage_details.qml: the CLI already
        // validates its own character budget, so re-slicing UTF-16 here would
        // corrupt combining marks and emoji sequences.
        var text = "família 👨‍👩‍👧‍👦 café ünïcödé"
        compare(Normalizer.boundedDisplayText(text, 120), text)

        var session = Normalizer.normalizeSession({ provider: "codex", projectName: text })
        compare(session.projectName, text)
    }

    function test_boundedDisplayTextFallsBackToASaneLimit() {
        var oversized = ""
        for (var i = 0; i < 900; i++) {
            oversized += "a"
        }
        compare(Normalizer.boundedDisplayText(oversized, 0).length, 500)
        compare(Normalizer.boundedDisplayText(oversized, NaN).length, 500)
        compare(Normalizer.boundedDisplayText(oversized, -1).length, 500)
        compare(Normalizer.boundedDisplayText(oversized, 120).length, 120)
    }

    // --- clamp --------------------------------------------------------------

    function test_clampStaysInsideTheRequestedRange() {
        compare(Normalizer.clamp(150, 0, 100), 100)
        compare(Normalizer.clamp(-1, 0, 100), 0)
        compare(Normalizer.clamp(42, 0, 100), 42)
    }
}
