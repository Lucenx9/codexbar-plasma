import QtQuick
import QtTest
import "../contents/ui/PrivacyPresentation.js" as Privacy

TestCase {
    name: "PrivacyPresentation"

    function labels() {
        return { title: "Codex", account: "Account hidden", status: "Issue",
            error: "Details hidden", placeholder: "No usage", usage: "Usage",
            rowLabels: ["Session", "Usage"] }
    }

    function quota() {
        return { lane: "primary", label: "confidential deployment", hasPercent: true,
            usedPercent: 42, leftPercent: 58, paceKnown: true, pacePercent: 20,
            paceOnTop: false, paceEtaSeconds: 7200, resetsAt: "2026-09-08T17:00:00Z",
            paceObservedAtMs: 1788868800000,
            resetDescription: "confidential reset owner", reset: "confidential fallback",
            pace: "confidential organization" }
    }

    function cost() {
        return { provider: "codex", historyDays: 7, historyCoverageEstablished: false,
            sessionLine: "confidential history", monthLine: "confidential period",
            today: { cost: 2, tokens: 50, currency: "USD" },
            totals: { cost: 0, tokens: 100, inputTokens: 90, outputTokens: 10, currency: "USD" },
            trust: { sourceKind: "listPrice", coverage: { priced: 1, estimated: 2, unpriced: 3, unmetered: 4 }, note: "confidential" },
            daily: [{ label: "2026-09-08", cost: null, tokens: 100, currency: "USD" }],
            models: [{ label: "confidential custom model", cost: 0, tokens: 100, currency: "USD" }],
            projects: { rows: [{ label: "confidential project", cost: 0, tokens: 100, currency: "USD" }], truncated: true }
        }
    }

    function test_providerHidesIdentityAndFreeFormDetailsWithoutMutatingSource() {
        var row = quota()
        var source = { provider: "codex", title: "confidential alias",
            account: "private@example.test", organization: "confidential", loginMethod: "confidential",
            source: "confidential file", version: "confidential", planText: "confidential team",
            rows: [row], primaryRow: row, providerDetails: [{ value: "confidential detail" }],
            usageDashboard: { summaryRows: [{ value: "confidential dashboard" }] },
            providerCost: { spendLine: "confidential billing period", percentUsed: 40 },
            tokenCost: cost(), credits: 14, status: "confidential incident", statusKnown: true,
            statusSeverity: "minor", hasIncident: true, error: "private@example.test failed",
            placeholder: "confidential placeholder", updatedAt: "2026-09-08T12:00:00Z",
            futureDisplayField: "confidential" }
        var before = JSON.stringify(source)
        var result = Privacy.provider(source, true, labels())
        verify(JSON.stringify(result).indexOf("confidential") === -1)
        verify(JSON.stringify(result).indexOf("private@example.test") === -1)
        compare(result.title, "Codex")
        compare(result.account, "Account hidden")
        compare(result.statusSeverity, "minor")
        compare(result.error, "Details hidden")
        compare(result.providerDetails, [])
        compare(result.usageDashboard, null)
        compare(result.providerCost, { percentUsed: 40 })
        compare(result.primaryRow, result.rows[0])
        compare(result.rows[0].usedPercent, 42)
        compare(result.rows[0].paceEtaSeconds, 7200)
        compare(result.rows[0].paceObservedAtMs, 1788868800000)
        compare(result.rows[0].resetsAt, "2026-09-08T17:00:00.000Z")
        compare(result.credits, 14)
        compare(JSON.stringify(source), before)
        compare(Privacy.provider(source, false, labels()), source)
    }

    function test_costKeepsMissingAndZeroAmountsWhileRemovingNames() {
        var source = cost()
        var before = JSON.stringify(source)
        var result = Privacy.cost(source, true)
        verify(JSON.stringify(result).indexOf("confidential") === -1)
        compare(result.totals.cost, 0)
        compare(result.daily[0].cost, null)
        compare(result.daily[0].label, "2026-09-08")
        compare(result.models[0].tokens, 100)
        compare(result.projects.rows[0].label, "")
        compare(result.projects.truncated, true)
        compare(result.trust.sourceKind, "listPrice")
        compare(result.trust.coverage.unpriced, 3)
        compare(result.historyCoverageEstablished, false)
        compare(JSON.stringify(source), before)
        compare(Privacy.cost(source, false), source)
    }

    function test_sessionHidesHostNamesAndUnknownStatesAndSources() {
        var source = { provider: "claude", projectName: "confidential project",
            sessionName: "confidential session", host: "private@example.test",
            state: "confidential state", source: "confidential source", activityMs: 1234 }
        var before = JSON.stringify(source)
        var result = Privacy.session(source, true)
        compare(result, { provider: "claude", projectName: "", sessionName: "", host: "",
            state: "unknown", source: "unknown", activityMs: 1234 })
        compare(JSON.stringify(source), before)
        compare(Privacy.session(source, false), source)
        source.state = "active"
        source.source = "cli"
        compare(Privacy.session(source, true).state, "active")
        compare(Privacy.session(source, true).source, "cli")
    }

    function test_quotaDropsInvalidDatesAndProseFallbacks() {
        var row = quota()
        row.resetsAt = "private@example.test"
        var result = Privacy.quota(row, true, "Usage")
        compare(result.resetsAt, "")
        compare(result.resetDescription, "")
        compare(result.reset, "")
        compare(result.pace, "")
        compare(Privacy.quota(row, false, "Usage"), row)
    }

    function test_projectionIgnoresInheritedFieldsAndMalformedNumbers() {
        var inherited = Object.create({ account: "confidential", error: "confidential", rows: [quota()] })
        inherited.provider = "codex"
        inherited.credits = Infinity
        var result = Privacy.provider(inherited, true, labels())
        compare(result.account, "")
        compare(result.error, "")
        compare(result.rows, [])
        compare(result.credits, null)
        var day = { label: "confidential", cost: "5", tokens: NaN, currency: "private@example.test" }
        var privateCost = Privacy.cost({ daily: [day], totals: day }, true)
        compare(privateCost.daily[0].label, "")
        compare(privateCost.totals.cost, null)
        compare(privateCost.totals.tokens, null)
        compare(privateCost.totals.currency, "")
        compare(Privacy.provider(null, true, labels()), null)
        compare(Privacy.cost(null, true), null)
        compare(Privacy.session(null, true), null)
        compare(Privacy.errorText({ message: "confidential" }, true, "Hidden"), "")
    }

    function test_projectionBoundsCollections() {
        var source = cost()
        while (source.daily.length < 400) source.daily.push(source.daily[0])
        while (source.models.length < 10) source.models.push(source.models[0])
        while (source.projects.rows.length < 140) source.projects.rows.push(source.projects.rows[0])
        var result = Privacy.cost(source, true)
        compare(result.daily.length, 365)
        compare(result.models.length, 6)
        compare(result.projects.rows.length, 128)
    }

    function test_missingTrustStaysAbsentAndMalformedCoverageStaysUnknown() {
        compare(Privacy.cost({}, true).trust, null)
        compare(Privacy.cost({ trust: {} }, true).trust, null)
        var source = { trust: { sourceKind: "vendor", coverage: { priced: 4 } } }
        compare(Privacy.cost(source, true).trust, { sourceKind: "vendor", coverage: null })
        source.trust.coverage = { priced: 1, estimated: 0, unpriced: -1, unmetered: 0 }
        compare(Privacy.cost(source, true).trust.coverage, null)
        source.trust.sourceKind = "confidential"
        compare(Privacy.cost(source, true).trust, null)
    }

    function test_invalidQuotaRowsCannotCreateFalseZeroMeters() {
        var source = { rows: [null, "confidential", [], { hasPercent: true }] }
        var result = Privacy.provider(source, true, labels())
        compare(result.rows.length, 1)
        compare(result.rows[0].hasPercent, false)
        compare(Privacy.quota(null, true, "Usage"), null)
        compare(Privacy.quota([], true, "Usage"), null)
    }

    function test_localResetCreditLabelsAreCopiedWithoutUnknownFields() {
        var source = { resetCredits: { title: "Reset credits", line: "2 available", extra: "confidential" } }
        var result = Privacy.provider(source, true, labels())
        compare(result.resetCredits, { title: "Reset credits", line: "2 available" })
        result.resetCredits.line = "different"
        compare(source.resetCredits.line, "2 available")
        source.resetCredits = Object.create({ title: "confidential", line: "confidential" })
        compare(Privacy.provider(source, true, labels()).resetCredits, null)
    }

    function test_invalidCurrencyDoesNotTurnIntoAnInventedDollarAmount() {
        var result = Privacy.cost({ totals: { cost: 100, tokens: 20, currency: "confidential" } }, true)
        compare(result.totals.cost, null)
        compare(result.totals.tokens, 20)
        compare(result.totals.currency, "")
    }

    function test_errorsAreHiddenOnlyWhileModeIsEnabled() {
        compare(Privacy.errorText("private@example.test failed", true, "Details hidden"), "Details hidden")
        compare(Privacy.errorText("", true, "Details hidden"), "")
        compare(Privacy.errorText("private@example.test failed", false, "Details hidden"), "private@example.test failed")
    }

    function test_providerCostKeepsOnlyTheBoundedQuotaFallback() {
        var values = [null, undefined, "40", -1, NaN, Infinity, false]
        for (var i = 0; i < values.length; i++) {
            compare(Privacy.provider({ providerCost: { percentUsed: values[i] } }, true, labels()).providerCost, null)
        }
        var inherited = Object.create({ percentUsed: 40 })
        compare(Privacy.provider({ providerCost: inherited }, true, labels()).providerCost, null)
        for (var percent of [0, 40, 100, 120]) {
            var source = { providerCost: { percentUsed: percent, title: "confidential", spendLine: "confidential" } }
            compare(Privacy.provider(source, true, labels()).providerCost, { percentUsed: Math.min(100, percent) })
            compare(source.providerCost.percentUsed, percent)
        }
    }

    function test_dailyAndPeriodModelsKeepAmountsAndIndependentCoverage() {
        var source = cost()
        source.modelsTruncated = true
        source.daily[0].models = source.models
        var before = JSON.stringify(source)
        var result = Privacy.cost(source, true)
        compare(result.modelsTruncated, true)
        compare(result.daily[0].modelsTruncated, false)
        compare(result.daily[0].models[0].tokens, 100)
        compare(result.daily[0].models[0].cost, 0)
        verify(JSON.stringify(result).indexOf("confidential") === -1)
        compare(JSON.stringify(source), before)
        source.daily[0].modelsTruncated = true
        compare(Privacy.cost(source, true).daily[0].modelsTruncated, true)
        while (source.daily[0].models.length < 9) source.daily[0].models.push(source.models[0])
        result = Privacy.cost(source, true)
        compare(result.daily[0].models.length, 6)
        verify(result.daily[0].modelsTruncated)
        result = Privacy.cost({ daily: [{ models: [] }, {}] }, true)
        compare(result.daily[0].models, [])
        compare(result.daily[0].modelsTruncated, false)
        compare(result.daily[1].models, [])
        compare(result.totals.tokens, null)
        compare(result.totals.inputTokens, null)
    }
}
