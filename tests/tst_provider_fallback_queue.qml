import QtQuick
import QtTest
import "../contents/ui/ProviderFallbackQueue.js" as ProviderFallbackQueue

TestCase {
    name: "ProviderFallbackQueue"

    function request(sourceName, providerID) {
        return {
            sourceName: sourceName,
            providerID: providerID
        }
    }

    function test_beginStartsOnlyTheConcurrentBudget() {
        var transition = ProviderFallbackQueue.begin([
            request("source-codex", "codex"),
            request("source-claude", "claude"),
            request("source-gemini", "gemini")
        ], {
            maximumConcurrent: 2,
            maximumSnapshots: 10
        })

        compare(transition.sourcesToStart.length, 2)
        compare(transition.sourcesToStart[0].sourceName, "source-codex")
        compare(transition.sourcesToStart[1].sourceName, "source-claude")
        compare(transition.finished, false)
        compare(transition.orderedItems.length, 0)
    }

    function test_completeStartsTheNextQueuedRequest() {
        var transition = ProviderFallbackQueue.begin([
            request("source-codex", "codex"),
            request("source-claude", "claude"),
            request("source-gemini", "gemini")
        ], {
            maximumConcurrent: 2,
            maximumSnapshots: 10
        })

        transition = ProviderFallbackQueue.complete(transition.state, {
            sourceName: "source-codex",
            item: { provider: "codex" }
        })

        compare(transition.sourcesToStart.length, 1)
        compare(transition.sourcesToStart[0].sourceName, "source-gemini")
        compare(transition.finished, false)
        compare(transition.orderedItems.length, 0)
    }

    function test_finalItemsFollowProviderOrderWithOneSnapshotPerProvider() {
        var transition = ProviderFallbackQueue.begin([
            request("source-codex", "codex"),
            request("source-claude", "claude"),
            request("source-gemini", "gemini")
        ], {
            maximumConcurrent: 3,
            maximumSnapshots: 4
        })

        transition = ProviderFallbackQueue.complete(transition.state, {
            sourceName: "source-gemini",
            item: { account: "gemini-1" }
        })
        transition = ProviderFallbackQueue.complete(transition.state, {
            sourceName: "source-codex",
            item: { account: "codex-1" }
        })
        transition = ProviderFallbackQueue.complete(transition.state, {
            sourceName: "source-claude",
            item: { account: "claude-1" }
        })

        compare(transition.finished, true)
        compare(transition.sourcesToStart.length, 0)
        compare(transition.orderedItems.length, 3)
        compare(transition.orderedItems[0].account, "codex-1")
        compare(transition.orderedItems[1].account, "claude-1")
        compare(transition.orderedItems[2].account, "gemini-1")
    }

    function test_beginDropsMalformedAndDuplicateRequests() {
        var transition = ProviderFallbackQueue.begin([
            null,
            request("source-codex", "codex"),
            request("source-codex-copy", "codex"),
            request("source-codex", "claude"),
            request({ nested: "source" }, "gemini"),
            request("source-prototype", "__proto__"),
            request("source-gemini", "gemini")
        ], {
            maximumConcurrent: 8,
            maximumSnapshots: 10
        })

        compare(transition.sourcesToStart.length, 2)
        compare(transition.sourcesToStart[0].sourceName, "source-codex")
        compare(transition.sourcesToStart[0].providerID, "codex")
        compare(transition.sourcesToStart[1].sourceName, "source-gemini")
        compare(transition.sourcesToStart[1].providerID, "gemini")
    }

    function test_completeIgnoresMalformedAndStaleResults() {
        var transition = ProviderFallbackQueue.begin([
            request("source-codex", "codex"),
            request("source-claude", "claude")
        ], {
            maximumConcurrent: 1,
            maximumSnapshots: 10
        })

        transition = ProviderFallbackQueue.complete(transition.state, null)
        compare(transition.sourcesToStart.length, 0)
        compare(transition.finished, false)

        transition = ProviderFallbackQueue.complete(transition.state, {
            sourceName: "stale-source",
            items: []
        })
        compare(transition.sourcesToStart.length, 0)
        compare(transition.finished, false)

        transition = ProviderFallbackQueue.complete(transition.state, {
            sourceName: "source-codex",
            item: { provider: "codex" }
        })
        compare(transition.sourcesToStart.length, 1)
        compare(transition.sourcesToStart[0].sourceName, "source-claude")
    }

    function test_duplicateCompletionDoesNotAdvanceTheQueueTwice() {
        var transition = ProviderFallbackQueue.begin([
            request("source-codex", "codex"),
            request("source-claude", "claude"),
            request("source-gemini", "gemini")
        ], {
            maximumConcurrent: 1,
            maximumSnapshots: 10
        })

        transition = ProviderFallbackQueue.complete(transition.state, {
            sourceName: "source-codex",
            item: { provider: "codex" }
        })
        compare(transition.sourcesToStart[0].sourceName, "source-claude")

        transition = ProviderFallbackQueue.complete(transition.state, {
            sourceName: "source-codex",
            item: { provider: "codex" }
        })
        compare(transition.sourcesToStart.length, 0)

        transition = ProviderFallbackQueue.complete(transition.state, {
            sourceName: "source-claude",
            item: { provider: "claude" }
        })
        compare(transition.sourcesToStart.length, 1)
        compare(transition.sourcesToStart[0].sourceName, "source-gemini")
    }

    function test_beginDoesNotCoerceQueueBudgets() {
        var transition = ProviderFallbackQueue.begin([
            request("source-codex", "codex"),
            request("source-claude", "claude")
        ], {
            maximumConcurrent: "2",
            maximumSnapshots: "10"
        })

        compare(transition.sourcesToStart.length, 1)
        compare(transition.sourcesToStart[0].sourceName, "source-codex")
    }

    function test_completedStateRetainsAtMostOneItemPerProvider() {
        var transition = ProviderFallbackQueue.begin([
            request("source-codex", "codex"),
            request("source-claude", "claude")
        ], {
            maximumConcurrent: 2,
            maximumSnapshots: 10
        })

        transition = ProviderFallbackQueue.complete(transition.state, {
            sourceName: "source-claude",
            item: { provider: "claude" }
        })
        transition = ProviderFallbackQueue.complete(transition.state, {
            sourceName: "source-codex",
            item: { provider: "codex" }
        })

        compare(Object.keys(transition.state.resultsByProvider).length, 2)
        verify(!Array.isArray(transition.state.resultsByProvider.codex))
        verify(!Array.isArray(transition.state.resultsByProvider.claude))
    }

    function test_nullItemCompletesWithoutRetainingAResult() {
        var transition = ProviderFallbackQueue.begin([
            request("source-codex", "codex")
        ], {
            maximumConcurrent: 1,
            maximumSnapshots: 10
        })

        transition = ProviderFallbackQueue.complete(transition.state, {
            sourceName: "source-codex",
            item: null
        })

        compare(transition.finished, true)
        compare(transition.orderedItems.length, 0)
        compare(Object.keys(transition.state.resultsByProvider).length, 0)
    }
}
