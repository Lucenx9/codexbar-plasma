import QtQuick
import QtTest
import "../contents/ui/PanelDisplay.js" as PanelDisplay

TestCase {
    name: "PanelDisplay"

    function usageRow(overrides) {
        var row = {
            hasPercent: false,
            usedPercent: 0,
            leftPercent: 0,
            pacePercent: -1,
            paceOnTop: true,
            paceEtaSeconds: 0,
            resetsAt: "",
            resetDescription: "",
            reset: ""
        };
        for (var key in overrides) {
            row[key] = overrides[key];
        }
        return row;
    }

    function test_safeModeFallsBackToPercent() {
        compare(PanelDisplay.safeMode("pace"), "pace");
        compare(PanelDisplay.safeMode("unknown"), "percent");
        compare(PanelDisplay.safeMode(null), "percent");
    }

    function test_eachModeSelectsARowWithTheDataItNeeds() {
        var percent = usageRow({
            hasPercent: true,
            usedPercent: 25,
            leftPercent: 75
        });
        var pace = usageRow({
            pacePercent: 30
        });
        var reset = usageRow({
            resetsAt: "2026-09-04T12:00:00Z"
        });
        var runOut = usageRow({
            paceOnTop: false,
            paceEtaSeconds: 3600
        });
        var rows = [percent, pace, reset, runOut];

        compare(PanelDisplay.rowForMode(rows, "percent"), percent);
        compare(PanelDisplay.rowForMode(rows, "pace"), pace);
        compare(PanelDisplay.rowForMode(rows, "resetTime"), reset);
        compare(PanelDisplay.rowForMode(rows, "runOut"), runOut);
    }

    function test_bothCanFallBackToPaceWithoutAPercentage() {
        var pace = usageRow({
            pacePercent: 40
        });
        compare(PanelDisplay.rowForMode([pace], "both"), pace);
    }

    function test_resetAcceptsDescriptionsButRejectsStructuredText() {
        var description = usageRow({
            resetDescription: "Tomorrow"
        });
        compare(PanelDisplay.rowForMode([description], "resetTime"), description);
        compare(PanelDisplay.rowForMode([usageRow({
                resetDescription: {
                    text: "Tomorrow"
                }
            })], "resetTime"), null);
    }

    function test_runOutNeedsTheExplicitForecastAndPositiveEta() {
        compare(PanelDisplay.rowForMode([usageRow({
                paceOnTop: true,
                paceEtaSeconds: 60
            }), usageRow({
                paceOnTop: false,
                paceEtaSeconds: 0
            })], "runOut"), null);
    }

    function test_remainingSecondsUsesTheObservationTime() {
        compare(PanelDisplay.remainingSeconds(3600, 100000, 160000), 3540);
        compare(PanelDisplay.remainingSeconds(30, 100000, 160000), 0);
        compare(PanelDisplay.remainingSeconds(30, 160000, 100000), 30);
        compare(PanelDisplay.remainingSeconds("30", 100000, 110000), 0);
    }
}
