import QtQuick
import QtTest
import "../contents/ui/general/ConfigValueSync.js" as ConfigValueSync

TestCase {
    name: "ConfigValueSync"

    function test_hiddenItemsKeepPageRestoresAndAdoptPopupChanges() {
        var a = { provider: "codex", row: "primary" }
        var b = { provider: "codex", row: "secondary" }
        var c = { provider: "claude", row: "primary" }
        // No pending restore: the page follows the popup exactly.
        compare(ConfigValueSync.hiddenItemsAfterPersistedChange([a], [a], [a, c]), [a, c])
        compare(ConfigValueSync.hiddenItemsAfterPersistedChange([a, b], [a, b], [b]), [b])
        // The page restored `a`; the popup hid `c` meanwhile. Apply keeps both.
        compare(ConfigValueSync.hiddenItemsAfterPersistedChange([b], [a, b], [a, b, c]), [b, c])
        // The popup restored `b` itself: nothing re-hides it.
        compare(ConfigValueSync.hiddenItemsAfterPersistedChange([b], [a, b], [a]), [])
        // Restoring everything, as the defaults do, clears only what the page saw.
        compare(ConfigValueSync.hiddenItemsAfterPersistedChange([], [a, b], [a, b, c]), [c])
        compare(ConfigValueSync.hiddenItemsAfterPersistedChange(null, undefined, [a]), [a])
    }

    function test_userEditBecomesPendingOnlyWhenItDiffersFromPersistedState() {
        var changed = ConfigValueSync.afterUserEdit(90, 30)
        compare(changed.pendingValue, 90)
        verify(changed.hasPendingEdit)

        var unchanged = ConfigValueSync.afterUserEdit("tokens", "tokens")
        compare(unchanged.pendingValue, "tokens")
        verify(!unchanged.hasPendingEdit)
    }

    function test_externalChangeReplacesAnUneditedSnapshot() {
        var result = ConfigValueSync.afterPersistedChange(30, false, 90)
        compare(result.pendingValue, 90)
        verify(!result.hasPendingEdit)
    }

    function test_externalChangePreservesADifferentPendingEdit() {
        var result = ConfigValueSync.afterPersistedChange("tokens", true, "cost")
        compare(result.pendingValue, "tokens")
        verify(result.hasPendingEdit)
    }

    function test_externalChangeClearsAPendingEditWhenValuesConverge() {
        var result = ConfigValueSync.afterPersistedChange(90, true, 90)
        compare(result.pendingValue, 90)
        verify(!result.hasPendingEdit)
    }

    function test_saveKeepsTheValueAndClearsPendingState() {
        var result = ConfigValueSync.afterSave(365)
        compare(result.pendingValue, 365)
        verify(!result.hasPendingEdit)
    }

    function test_dayEditKeepsDayModeAcrossExternalPeriodChanges() {
        var edited = ConfigValueSync.historyRangeAfterUserEdit(90, "", 30, "")
        verify(edited.hasPendingEdit)
        var external = ConfigValueSync.historyRangeAfterPersistedChange(
            edited.days, edited.period, edited.hasPendingEdit, 30, "month-to-date")
        compare(external.days, 90)
        compare(external.period, "")
        verify(external.hasPendingEdit)
        // Saving only the days must not release the calendar-mode edit.
        var partialSave = ConfigValueSync.historyRangeAfterPersistedChange(
            external.days, external.period, external.hasPendingEdit, 90, "month-to-date")
        verify(partialSave.hasPendingEdit)
        compare(partialSave.period, "")
        var saved = ConfigValueSync.historyRangeAfterPersistedChange(
            partialSave.days, partialSave.period, partialSave.hasPendingEdit, 90, "")
        verify(!saved.hasPendingEdit)
        var later = ConfigValueSync.historyRangeAfterPersistedChange(
            saved.days, saved.period, saved.hasPendingEdit, 90, "all")
        compare(later.period, "all")
        verify(!later.hasPendingEdit)
    }

    function test_dayEditProtectsDaysWhenOnlyModeChanges() {
        var edited = ConfigValueSync.historyRangeAfterUserEdit(30, "", 30, "all")
        verify(edited.hasPendingEdit)
        var external = ConfigValueSync.historyRangeAfterPersistedChange(
            edited.days, edited.period, edited.hasPendingEdit, 7, "all")
        compare(external.days, 30)
        compare(external.period, "")
        var unchanged = ConfigValueSync.historyRangeAfterUserEdit(30, "", 30, "")
        verify(!unchanged.hasPendingEdit)
    }

}
