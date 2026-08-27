import QtQuick
import QtTest
import "../contents/ui/general/ConfigValueSync.js" as ConfigValueSync

TestCase {
    name: "ConfigValueSync"

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
}
