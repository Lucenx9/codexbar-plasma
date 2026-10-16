import QtQuick
import QtTest
import "../contents/ui/ProviderSnapshot.js" as Snapshot
import "../contents/ui/ProviderViewModel.js" as View

TestCase {
    name: "ProviderViewModel"
    property list<var> nativeDetails: [{title: "Synthetic details", rows: []}]
    property list<var> nativeDates: [{kind: "renews", date: "2026-11-01"}]
    function test_projectionBoundsDisplayFieldsAndKeepsSemanticMetadata() {
        var snapshot = Snapshot.normalize({provider: "codex", usage: {
            account: "synthetic@example.test", dataConfidence: "estimated",
            updatedAt: "2026-10-16T12:00:00Z", primary: {usedPercent: 0}}}, 1234)
        snapshot.providerDetails = nativeDetails
        snapshot.subscriptionDates = nativeDates
        snapshot.unexpectedSecret = "must-not-copy"
        var display = {title: "x".repeat(500), planText: "p".repeat(500), status: "s".repeat(900),
            rows: [{lane: "primary", label: "Localized quota"}], error: "", placeholder: "Localized empty",
            tokenCost: {total: 5}, providerCost: null, resetCredits: null, usageDashboard: null,
            dashboardUrl: "https://example.test", statusUrl: "", changelogUrl: ""}
        var before = JSON.stringify(snapshot)
        var result = View.presented(snapshot, display)
        compare(result.title.length, 120)
        compare(result.planText.length, 120)
        compare(result.status.length, 500)
        compare(result.usageReceivedAtMs, 1234)
        compare(result.dataConfidence, "estimated")
        compare(result.accountKey, snapshot.accountKey)
        compare(result.primaryRow, result.rows[0])
        verify(Array.isArray(result.providerDetails))
        verify(Array.isArray(result.subscriptionDates))
        compare(result.providerDetails[0].title, "Synthetic details")
        compare(result.tokenCost.total, 5)
        verify(result.unexpectedSecret === undefined)
        verify(result.statusRecord === undefined)
        compare(JSON.stringify(snapshot), before)
        result.rows.push({lane: "extra"})
        compare(display.rows.length, 1)
    }
    function test_primaryRowIsNotInventedForSecondaryOnlyUsage() {
        var snapshot = Snapshot.normalize({provider: "future", usage: {}}, 1000)
        var result = View.presented(snapshot, {rows: [{lane: "secondary"}], title: "Future", planText: "", status: ""})
        compare(result.primaryRow, null)
        verify(!result.statusKnown)
        verify(!result.hasIncident)
    }
}
