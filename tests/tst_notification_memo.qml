import QtQuick
import QtTest
import "../contents/ui/NotificationMemo.js" as NotificationMemo

TestCase {
    name: "NotificationMemo"

    readonly property string provider: "codex"

    function primedMemo(value) {
        var memo = ({})
        memo[NotificationMemo.statusPrimedMemoKey(provider)] = "1"
        if (value && value.length > 0) {
            memo[NotificationMemo.statusMemoKey(provider)] = value
        }
        return memo
    }

    function incident(severity, incidentKey) {
        return NotificationMemo.statusMemoValue(severity, incidentKey)
    }

    // Applies one observation the way processNotifications does: the memo under
    // construction starts as a copy of the current one.
    function observe(memo, value, severity) {
        var next = ({})
        for (var key in memo) {
            next[key] = memo[key]
        }
        var decision = NotificationMemo.statusDecision(memo, provider, value, severity)
        NotificationMemo.applyStatusDecision(next, provider, decision)
        return { notify: decision.notify, memo: next }
    }

    function test_firstObservationPrimesSilently() {
        var result = observe(({}), incident("major", "inc-1"), "major")
        compare(result.notify, false)
        compare(result.memo[NotificationMemo.statusMemoKey(provider)], incident("major", "inc-1"))
        compare(result.memo[NotificationMemo.statusPrimedMemoKey(provider)], "1")
    }

    function test_incidentAppearingAfterAQuietBaselineNotifies() {
        var result = observe(primedMemo(""), incident("major", "inc-1"), "major")
        compare(result.notify, true)
    }

    function test_unchangedIncidentStaysQuiet() {
        var result = observe(primedMemo(incident("major", "inc-1")), incident("major", "inc-1"), "major")
        compare(result.notify, false)
    }

    function test_worsenedSeverityNotifies() {
        var result = observe(primedMemo(incident("minor", "inc-1")), incident("critical", "inc-1"), "critical")
        compare(result.notify, true)
    }

    function test_improvedSeverityStaysQuiet() {
        var result = observe(primedMemo(incident("critical", "inc-1")), incident("minor", "inc-1"), "minor")
        compare(result.notify, false)
    }

    function test_replacementIncidentAtSameSeverityNotifies() {
        var result = observe(primedMemo(incident("major", "inc-1")), incident("major", "inc-2"), "major")
        compare(result.notify, true)
    }

    function test_missingIncidentKeysDoNotCountAsReplacement() {
        var result = observe(primedMemo(incident("major", "")), incident("major", ""), "major")
        compare(result.notify, false)
    }

    function test_clearedIncidentDropsTheEntryWithoutNotifying() {
        var result = observe(primedMemo(incident("major", "inc-1")), "", "")
        compare(result.notify, false)
        compare(result.memo.hasOwnProperty(NotificationMemo.statusMemoKey(provider)), false)
        compare(result.memo[NotificationMemo.statusPrimedMemoKey(provider)], "1")
    }

    // A settings change rebuilds threshold-derived memo state. Status is not
    // threshold-derived, so its baseline must survive.
    function test_resetKeepsStatusStateAndDropsThresholdState() {
        var memo = primedMemo(incident("major", "inc-1"))
        memo["quota:[\"codex\",\"acct\"]:0"] = "warning"
        memo["reset:[\"codex\",\"acct\"]:weekly:Weekly:0"] = "1"
        memo["scope:[\"codex\",\"acct\"]"] = "1"
        var preserved = NotificationMemo.preservedMemoAfterReset(memo)
        compare(preserved[NotificationMemo.statusMemoKey(provider)], incident("major", "inc-1"))
        compare(preserved[NotificationMemo.statusPrimedMemoKey(provider)], "1")
        compare(preserved.hasOwnProperty("quota:[\"codex\",\"acct\"]:0"), false)
        compare(preserved.hasOwnProperty("reset:[\"codex\",\"acct\"]:weekly:Weekly:0"), false)
        compare(preserved.hasOwnProperty("scope:[\"codex\",\"acct\"]"), false)
    }

    function test_carryKeepsTheBaselineOfASkippedProvider() {
        var next = ({})
        NotificationMemo.carryStatusMemo(primedMemo(incident("major", "inc-1")), provider, next)
        compare(next[NotificationMemo.statusMemoKey(provider)], incident("major", "inc-1"))
        compare(next[NotificationMemo.statusPrimedMemoKey(provider)], "1")
    }

    function test_carryDoesNotInventABaseline() {
        var next = ({})
        NotificationMemo.carryStatusMemo(({}), provider, next)
        compare(next.hasOwnProperty(NotificationMemo.statusPrimedMemoKey(provider)), false)
    }

    // The three scenarios of a threshold change landing while the provider is
    // still refreshing, end to end: reset, prime-with-carry, then the first
    // fresh payload.
    function resetThenCarry(memo) {
        var preserved = NotificationMemo.preservedMemoAfterReset(memo)
        var primed = ({})
        NotificationMemo.carryStatusMemo(preserved, provider, primed)
        return primed
    }

    function test_ongoingIncidentSurvivesAResetDuringRefreshWithoutNotifying() {
        var primed = resetThenCarry(primedMemo(incident("major", "inc-1")))
        var result = observe(primed, incident("major", "inc-1"), "major")
        compare(result.notify, false)
    }

    function test_incidentStartingDuringAPendingRefreshStillNotifies() {
        var primed = resetThenCarry(primedMemo(""))
        var result = observe(primed, incident("major", "inc-1"), "major")
        compare(result.notify, true)
    }

    function test_incidentWorseningDuringAPendingRefreshStillNotifies() {
        var primed = resetThenCarry(primedMemo(incident("minor", "inc-1")))
        var result = observe(primed, incident("critical", "inc-1"), "critical")
        compare(result.notify, true)
    }

    function test_coldStartDuringAPendingRefreshPrimesSilently() {
        var primed = resetThenCarry(({}))
        var result = observe(primed, incident("major", "inc-1"), "major")
        compare(result.notify, false)
    }

    function test_severityRankOrdersKnownSeverities() {
        verify(NotificationMemo.severityRank("critical") > NotificationMemo.severityRank("major"))
        verify(NotificationMemo.severityRank("major") > NotificationMemo.severityRank("minor"))
        verify(NotificationMemo.severityRank("minor") > NotificationMemo.severityRank("maintenance"))
        verify(NotificationMemo.severityRank("maintenance") > NotificationMemo.severityRank("unknown"))
        compare(NotificationMemo.severityRank("nonsense"), 0)
        compare(NotificationMemo.severityRank(""), 0)
    }

    function test_statusKeysStayProviderScoped() {
        compare(NotificationMemo.statusMemoKey("claude"), "status:claude")
        compare(NotificationMemo.statusPrimedMemoKey("claude"), "statusPrimed:claude")
        verify(NotificationMemo.isStatusMemoKey("status:claude"))
        verify(NotificationMemo.isStatusMemoKey("statusPrimed:claude"))
        verify(!NotificationMemo.isStatusMemoKey("quota:[\"claude\",\"acct\"]:0"))
        verify(!NotificationMemo.isStatusMemoKey("scope:[\"claude\",\"acct\"]"))
    }
}
