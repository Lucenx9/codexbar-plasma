import QtQuick
import QtTest
import "../contents/ui/NotificationPlanner.js" as NotificationPlanner

TestCase {
    name: "NotificationIncidentIdentity"

    function observation(incidentKey, active) {
        return {
            providerID: "codex",
            scopeID: "codex/account-a",
            pending: false,
            errorPresent: false,
            statusKnown: true,
            statusActive: active !== false,
            statusSeverity: active === false ? "" : "major",
            statusIncidentKey: incidentKey,
            rows: []
        }
    }

    function transition(mode, item, memo) {
        return NotificationPlanner.transition(item ? [item] : [], memo || ({}), {
            mode: mode,
            statusEnabled: true,
            quotaEnabled: false,
            paceEnabled: false,
            resetEnabled: false
        })
    }

    function test_partialIdentityDoesNotHideAReplacement_data() {
        return [
            { tag: "observe-same", reset: false, nextKey: "inc-1", expected: 0 },
            { tag: "observe-replacement", reset: false, nextKey: "inc-2", expected: 1 },
            { tag: "reprime-same", reset: true, nextKey: "inc-1", expected: 0 },
            { tag: "reprime-replacement", reset: true, nextKey: "inc-2", expected: 1 }
        ]
    }

    function test_partialIdentityDoesNotHideAReplacement(data) {
        var initial = transition("prime", observation("inc-1"))
        compare(initial.intents.length, 0)
        var memo = data.reset
            ? transition("reset", null, initial.nextMemo).nextMemo
            : initial.nextMemo
        // resetNotificationMemo primes against the current snapshot before
        // the next fresh pass; a temporarily absent id must survive that path.
        var unavailable = transition(data.reset ? "prime" : "observe",
            observation(""), memo)
        compare(unavailable.intents.length, 0)

        var identified = transition("observe", observation(data.nextKey), unavailable.nextMemo)
        compare(identified.intents.length, data.expected)
        if (data.expected > 0) {
            compare(identified.intents[0].kind, "status")
        }
        var repeated = transition("observe", observation(data.nextKey), identified.nextMemo)
        compare(repeated.intents.length, 0)

        var healthy = transition("observe", observation("", false), repeated.nextMemo)
        compare(healthy.intents.length, 0)
        var recurring = transition("observe", observation(data.nextKey), healthy.nextMemo)
        compare(recurring.intents.length, 1)
        compare(recurring.intents[0].kind, "status")
    }
}
