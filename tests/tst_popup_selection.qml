import QtQuick
import QtTest
import "../contents/ui/PopupSelection.js" as PopupSelection

TestCase {
    name: "PopupSelection"

    function state(providerID, globalView, initialized) {
        return {
            providerID: providerID,
            globalView: globalView,
            initialized: initialized
        }
    }

    function views(overview, spend, sessions) {
        return {
            overview: overview,
            spend: spend,
            sessions: sessions
        }
    }

    function options(autoSelect, currentProviderExists, firstProviderID,
            automaticProviderID, globalViews) {
        return {
            autoSelect: autoSelect,
            currentProviderExists: currentProviderExists,
            firstProviderID: firstProviderID,
            automaticProviderID: automaticProviderID,
            globalViews: globalViews
        }
    }

    function test_autoSelectionPreservesAnAvailableGlobalView() {
        var current = state("", "spend", true)
        var next = PopupSelection.reconcile(current,
            options(true, false, "codex", "claude", views(true, true, true)))

        compare(next.providerID, "")
        compare(next.globalView, "spend")
        compare(next.initialized, true)
    }

    function test_compactProviderKeepsAutomaticSelectionOnGlobalViews() {
        compare(PopupSelection.compactProviderIndex(true, -1, 1), 1)
    }

    function test_compactProviderKeepsTheSelectedProviderWhenAutoSelectionIsEnabled() {
        compare(PopupSelection.compactProviderIndex(true, 2, 1), 2)
    }

    function test_compactProviderKeepsTheFirstProviderWhenAutoSelectionIsDisabled() {
        compare(PopupSelection.compactProviderIndex(false, 2, 1), 0)
        compare(PopupSelection.compactProviderIndex(false, -1, 1), 0)
    }

    function test_autoSelectionRepairsAnUnavailableGlobalView() {
        var current = state("", "spend", true)
        var next = PopupSelection.reconcile(current,
            options(true, false, "codex", "claude", views(true, false, true)))

        compare(next.providerID, "claude")
        compare(next.globalView, "spend")
        compare(next.initialized, true)
    }

    function test_availabilityChangesDoNotMoveASelectedProvider() {
        var current = state("codex", "spend", true)
        verify(!PopupSelection.globalSelectionNeedsReconciliation(
            current, views(true, false, true)))
        verify(PopupSelection.globalSelectionNeedsReconciliation(
            state("", "spend", true), views(true, false, true)))
        verify(!PopupSelection.globalSelectionNeedsReconciliation(
            state("", "spend", true), views(true, true, true)))
    }

    function test_availabilityPredicatesReturnBooleansForMissingOrUnknownState() {
        compare(PopupSelection.globalSelectionNeedsReconciliation(
            null, views(true, true, true)), false)
        compare(PopupSelection.globalViewIsAvailable(
            "unknown", views(true, true, true)), false)
        compare(PopupSelection.globalViewIsAvailable("spend", null), false)
    }

    function test_zeroProvidersRevealTheEmptyStateForAnUnavailableGlobalView() {
        var next = PopupSelection.reconcile(state("", "overview", true),
            options(false, false, "", "", views(false, false, false)))

        compare(next.providerID, "")
        compare(next.globalView, "overview")
        compare(next.initialized, false)
    }

    function test_zeroProvidersPreserveAnAvailableSessionsView() {
        var next = PopupSelection.reconcile(state("", "sessions", true),
            options(false, false, "", "", views(false, false, true)))

        compare(next.providerID, "")
        compare(next.globalView, "sessions")
        compare(next.initialized, true)
    }

    function test_manualSelectionKeepsAStableProviderAndRepairsARemovedOne() {
        var available = views(true, true, true)
        var stable = PopupSelection.reconcile(state("codex", "overview", true),
            options(false, true, "claude", "", available))
        compare(stable.providerID, "codex")

        var removed = PopupSelection.reconcile(state("codex", "overview", true),
            options(false, false, "claude", "", available))
        compare(removed.providerID, "claude")
        compare(removed.initialized, true)
    }

    function test_manualInitializationRetainsTheOverviewRule() {
        var overview = PopupSelection.reconcile(state("", "spend", false),
            options(false, false, "codex", "", views(true, true, true)))
        compare(overview.providerID, "")
        compare(overview.globalView, "overview")
        compare(overview.initialized, true)

        var provider = PopupSelection.reconcile(state("", "spend", false),
            options(false, false, "codex", "", views(false, true, true)))
        compare(provider.providerID, "codex")
        compare(provider.initialized, true)
    }
}
