import QtQuick
import QtTest
import "../contents/ui/config/ProviderOperations.js" as Operations

TestCase {
    name: "ProviderOperations"

    function test_providerLocksKeepOptimisticFalseAndDoNotMutatePreviousState() {
        var initial = Operations.initialState()
        var a = Operations.providerPendingChanged(initial, "codex", true, false)
        var b = Operations.providerPendingChanged(a, "future", true, true)
        verify(!Operations.isProviderPending(initial, "codex"))
        verify(Operations.isProviderPending(b, "codex"))
        verify(!Operations.enabledValue(b, "codex", true))
        verify(Operations.enabledValue(b, "future", false))
        var done = Operations.providerPendingChanged(b, "codex", false)
        verify(!Operations.isProviderPending(done, "codex"))
        verify(Operations.enabledValue(done, "codex", true))
        verify(Operations.isProviderPending(done, "future"))
        verify(Operations.isProviderPending(a, "codex"))
        compare(Operations.providerPendingChanged(done, "codex", false), done)
    }

    function test_fieldAndDiagnosticLocksAreIndependent() {
        var state = Operations.initialState()
        state = Operations.fieldPendingChanged(state, "codex", "apiKey", true)
        state = Operations.fieldPendingChanged(state, "codex", "login", true)
        state = Operations.fieldPendingChanged(state, "future", "apiKey", true)
        state = Operations.diagnosticPendingChanged(state, "codex", true)
        verify(!Operations.isProviderPending(state, "codex"))
        verify(Operations.hasFieldOperations(state, "codex"))
        verify(!Operations.hasFieldOperations(state, "code"))
        verify(!Operations.hasFieldOperations(state, "codex-other"))
        var previous = state
        state = Operations.fieldPendingChanged(state, "codex", "apiKey", false)
        verify(!Operations.fieldPending(state, "codex", "apiKey"))
        verify(Operations.fieldPending(state, "codex", "login"))
        verify(Operations.fieldPending(state, "future", "apiKey"))
        verify(Operations.fieldPending(previous, "codex", "apiKey"))
        state = Operations.fieldPendingChanged(state, "codex", "login", false)
        verify(!Operations.hasFieldOperations(state, "codex"))
        verify(Operations.isDiagnosticPending(state, "codex"))
        state = Operations.diagnosticPendingChanged(state, "codex", false)
        verify(!Operations.isDiagnosticPending(state, "codex"))
        verify(Operations.isDiagnosticPending(previous, "codex"))
    }

    function test_invalidKeysCannotCreateLocks_data() {
        return ["", "__proto__", "constructor", "prototype", "toString", "bad\nkey", "x".repeat(129)]
            .map(function(key, i) { return {tag: String(i), key: key} })
    }

    function test_invalidKeysCannotCreateLocks(data) {
        var state = Operations.initialState()
        compare(Operations.providerPendingChanged(state, data.key, true, true), state)
        compare(Operations.fieldPendingChanged(state, data.key, "key", true), state)
        compare(Operations.diagnosticPendingChanged(state, data.key, true), state)
        verify(!Operations.isProviderPending(state, data.key))
        verify(!Operations.hasFieldOperations(state, data.key))
        verify(!Operations.isDiagnosticPending(state, data.key))
    }

    function test_fieldKeysAreBoundedAndQuoted() {
        var state = Operations.initialState()
        for (var field of ["", "   ", "x".repeat(129), null])
            compare(Operations.fieldPendingChanged(state, "codex", field, true), state)
        for (var field of ["__proto__", "constructor", "quoted\"::field", "x".repeat(128)]) {
            state = Operations.fieldPendingChanged(state, "codex", field, true)
            verify(Operations.fieldPending(state, "codex", field))
            verify(!Operations.fieldPending(state, "other", field))
        }
    }

    function test_reloadWaitsForLastSourceWriteAndKeepsLatestError() {
        var initial = Operations.initialState()
        var pending = Operations.reloadRequested(initial, true, false, "earlier error")
        verify(!pending.reload)
        verify(!initial.reloadDeferred)
        // Repeated requests coalesce; completing one of two writes still waits.
        pending = Operations.reloadRequested(pending.state, true, true, "other error")
        var waiting = Operations.deferredReload(pending.state, true, "first write failed")
        verify(!waiting.reload)
        var ready = Operations.deferredReload(waiting.state, false, "last write failed")
        verify(ready.reload)
        verify(ready.preserveMessages)
        compare(ready.retainedErrorText, "last write failed")
        verify(!ready.state.reloadDeferred)
        verify(!Operations.deferredReload(ready.state, false, "ignored").reload)
        // The retained error belongs to this refresh, not subsequent requests.
        var later = Operations.reloadRequested(ready.state, false, true)
        compare(later.retainedErrorText, "")
    }

    function test_reloadWithoutSourceWriteAndRetirement() {
        var state = Operations.providerPendingChanged(Operations.initialState(), "codex", true, true)
        var immediate = Operations.reloadRequested(state, false, false, "retained")
        verify(immediate.reload)
        verify(!immediate.preserveMessages)
        verify(Operations.isProviderPending(immediate.state, "codex"))
        compare(immediate.retainedErrorText, "retained")
        verify(!Operations.deferredReload(state, false, "").reload)
        var deferred = Operations.reloadRequested(state, true, true)
        var reset = Operations.initialState()
        verify(!Operations.deferredReload(reset, false, "old write error").reload)
        verify(!Operations.isProviderPending(reset, "codex"))
        verify(deferred.state.reloadDeferred)
    }
}
