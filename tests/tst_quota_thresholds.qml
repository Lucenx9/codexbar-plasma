import QtQuick
import QtTest
import "../contents/ui/QuotaThresholds.js" as QuotaThresholds

TestCase {
    name: "QuotaThresholds"

    function test_defaultsMatchThePreviousHardcodedThresholds() {
        compare(QuotaThresholds.warningPercent(undefined), 80)
        compare(QuotaThresholds.criticalPercent(80, undefined), 95)
    }

    function test_rejectsNonNumericConfigurationWithoutDisablingWarnings() {
        compare(QuotaThresholds.warningPercent("abc"), 80)
        compare(QuotaThresholds.warningPercent(null), 80)
        compare(QuotaThresholds.criticalPercent(80, "abc"), 95)
    }

    function test_clampsOutOfRangePercentsIntoTheUsableBand() {
        compare(QuotaThresholds.warningPercent(0), 1)
        compare(QuotaThresholds.warningPercent(-40), 1)
        compare(QuotaThresholds.warningPercent(140), 99)
        compare(QuotaThresholds.criticalPercent(1, 140), 100)
        compare(QuotaThresholds.warningPercent(60.7), 60)
    }

    // A critical threshold below the warning threshold would make "major"
    // unreachable, so the invariant is enforced by raising critical.
    function test_criticalNeverFallsBelowWarning() {
        compare(QuotaThresholds.criticalPercent(90, 50), 90)
        compare(QuotaThresholds.criticalPercent(90, 90), 90)
        compare(QuotaThresholds.criticalPercent(99, 2), 99)
    }

    function test_levelUsesConfiguredBoundariesInclusively() {
        compare(QuotaThresholds.level(79, 80, 95), "")
        compare(QuotaThresholds.level(80, 80, 95), "minor")
        compare(QuotaThresholds.level(94, 80, 95), "minor")
        compare(QuotaThresholds.level(95, 80, 95), "major")
        compare(QuotaThresholds.level(100, 80, 95), "major")
    }

    function test_levelFollowsCustomThresholds() {
        compare(QuotaThresholds.level(55, 50, 70), "minor")
        compare(QuotaThresholds.level(70, 50, 70), "major")
        compare(QuotaThresholds.level(49, 50, 70), "")
    }

    function test_levelIgnoresUnusableUsageValues() {
        compare(QuotaThresholds.level(Number.NaN, 80, 95), "")
        compare(QuotaThresholds.level("abc", 80, 95), "")
        compare(QuotaThresholds.level(null, 80, 95), "")
    }

    // When the meter counts down, a threshold on "used" has to be mirrored so
    // the marker lands on the same physical point of the track.
    function test_markersMirrorWhenBarsShowRemaining() {
        var used = QuotaThresholds.markers(80, 95, true)
        compare(used.length, 2)
        compare(used[0].percent, 80)
        compare(used[0].severity, "minor")
        compare(used[1].percent, 95)
        compare(used[1].severity, "major")

        var left = QuotaThresholds.markers(80, 95, false)
        compare(left[0].percent, 20)
        compare(left[0].severity, "minor")
        compare(left[1].percent, 5)
        compare(left[1].severity, "major")
    }

    function test_markersApplyTheSameBoundsAsTheThresholdAccessors() {
        var markers = QuotaThresholds.markers(-10, 400, true)
        compare(markers[0].percent, 1)
        compare(markers[1].percent, 100)
    }
}
