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
        compare(Normalizer.maximumAccountSnapshots, 128)
        compare(Normalizer.maximumCostSnapshots, 256)
        compare(Normalizer.maximumExtraRateWindows, 24)
        compare(Normalizer.maximumSessions, 128)
        compare(Normalizer.maximumCostHistoryPoints, 365)
        compare(Normalizer.maximumModelBreakdownsPerDay, 128)
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

    function test_reportsAnUnknownPercentageInsteadOfGuessingZero() {
        var unknown = Normalizer.rateWindowMetrics({ usedPercent: 80 }, null, false)
        compare(unknown.hasPercent, false)
        compare(unknown.usedPercent, 0)
        compare(unknown.leftPercent, 0)

        var malformed = Normalizer.rateWindowMetrics({ usedPercent: "quite a lot" }, null, true)
        compare(malformed.hasPercent, false)
        compare(malformed.usedPercent, 0)
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

    function test_costDailyDegradesToAnEmptyRangeForNonArrays() {
        compare(Normalizer.normalizeCostDaily(null, "USD", 30).length, 0)
        compare(Normalizer.normalizeCostDaily({ "0": { totalCost: 1 }, length: 1 }, "USD", 30).length, 0)
        compare(Normalizer.normalizeCostDaily("2026-08-01", "USD", 30).length, 0)
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
        compare(totals.tokens, 0)
        compare(totals.inputTokens, 0)
    }

    function test_sumTokenPartsReportsNaNWhenNothingIsUsable() {
        verify(isNaN(Normalizer.sumTokenParts(undefined, null, "x", NaN)))
        verify(isNaN(Normalizer.sumTokenParts(0, 0, 0, 0)))
        compare(Normalizer.sumTokenParts(1, 2, 3, 4), 10)
    }

    function test_costModelsAggregateAcrossDaysAndRankByCost() {
        var rows = Normalizer.normalizeCostModels([
            { modelBreakdowns: [{ modelName: "gpt-5", cost: 1, totalTokens: 10 }] },
            { modelBreakdowns: [
                { modelName: "gpt-5", cost: 2, totalTokens: 20 },
                { model: "sonnet", totalCost: 5, tokens: 1 }
            ] }
        ], "USD", 30)

        compare(rows.length, 2)
        compare(rows[0].label, "sonnet")
        compare(rows[0].cost, 5)
        compare(rows[1].label, "gpt-5")
        compare(rows[1].cost, 3)
        compare(rows[1].tokens, 30)
    }

    function test_costModelsDropPrototypePollutingModelNames() {
        var rows = Normalizer.normalizeCostModels([
            { modelBreakdowns: JSON.parse(
                '[{"modelName":"__proto__","cost":9},'
                + '{"modelName":"constructor","cost":9},'
                + '{"modelName":"prototype","cost":9},'
                + '{"modelName":"gpt-5","cost":1}]') }
        ], "USD", 30)

        compare(rows.length, 1)
        compare(rows[0].label, "gpt-5")
        compare(({}).polluted, undefined)
    }

    function test_costModelsKeepPrototypeMemberNamesThatAreNotDangerous() {
        // "toString" is a plausible model name and must survive the own-key check
        // that a bare `byName[name]` lookup would have swallowed.
        var rows = Normalizer.normalizeCostModels([
            { modelBreakdowns: [{ modelName: "toString", cost: 4 }] }
        ], "USD", 30)
        compare(rows.length, 1)
        compare(rows[0].label, "toString")
        compare(rows[0].cost, 4)
    }

    function test_costModelsCapBreakdownsPerDayAndRowsOverall() {
        var breakdowns = []
        for (var i = 0; i < Normalizer.maximumModelBreakdownsPerDay + 40; i++) {
            breakdowns.push({ modelName: "model-" + i, cost: i + 1 })
        }
        var rows = Normalizer.normalizeCostModels([{ modelBreakdowns: breakdowns }], "USD", 30)
        compare(rows.length, 6)
        // The most expensive surviving model is the last one inside the per-day
        // breakdown bound, not the most expensive one in the payload.
        compare(rows[0].label, "model-" + (Normalizer.maximumModelBreakdownsPerDay - 1))
    }

    function test_costModelsIgnoreMalformedBreakdownContainers() {
        compare(Normalizer.normalizeCostModels(null, "USD", 30).length, 0)
        compare(Normalizer.normalizeCostModels("daily", "USD", 30).length, 0)
        compare(Normalizer.normalizeCostModels([
            null,
            { modelBreakdowns: "gpt-5" },
            { modelBreakdowns: { "0": { modelName: "gpt-5", cost: 1 } } },
            { modelBreakdowns: [{ modelName: "gpt-5" }] }
        ], "USD", 30).length, 0)
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

    // SEPARATE KNOWN GAP, pinned deliberately: `String(value || "")` inside
    // SafeText.boundedInspectionText swallows numeric zero and `false`. That
    // helper also feeds credential redaction and the diagnostic paths, so
    // changing it is its own commit with its own security review, not a rider on
    // the structured-value fix. ProviderDescriptor.js already works around this
    // class of bug with nullish-only descriptor value conversion.
    function test_boundedDisplayTextStillSwallowsFalsyScalars() {
        compare(Normalizer.boundedDisplayText(0, 120), "")
        compare(Normalizer.boundedDisplayText(false, 120), "")
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
