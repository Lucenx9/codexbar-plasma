import QtQuick
import QtTest
import "../contents/ui/ProviderSnapshot.js" as Snapshot
import "../contents/ui/ProviderAutoSelect.js" as AutoSelect
import "../contents/ui/PrivacyPresentation.js" as Privacy
import "../contents/ui/UsageCache.js" as Cache
import "../contents/ui/PanelDisplay.js" as PanelDisplay
import "../contents/ui/PanelRules.js" as PanelRules
import "../contents/ui/NotificationPlanner.js" as Notifications
import "../contents/ui/AiInsightsSnapshot.js" as Insights
import "../contents/ui/components" as Components

TestCase {
    name: "UsageConfidence"
    readonly property double nowMs: Date.parse("2026-10-14T12:00:00Z")
    readonly property string context: "0123456789abcdef0123456789abcdef"

    Components.UsageWindowText {
        id: text
    }
    Components.PanelText {
        id: panelText
    }

    function i18n(source) {
        for (var i = 1; i < arguments.length; i++)
            source = source.replace("%" + i, String(arguments[i]));
        return source;
    }

    function provider(confidence, percent) {
        var input = {
            provider: "opencodego",
            source: "local",
            usage: {
                dataConfidence: confidence,
                updatedAt: new Date(nowMs).toISOString(),
                primary: {
                    usedPercent: percent,
                    windowMinutes: 300,
                    resetsAt: "2026-10-14T14:00:00Z"
                }
            },
            pace: {
                primary: {
                    expectedUsedPercent: 30,
                    willLastToReset: false,
                    etaSeconds: 60
                }
            }
        };
        if (confidence === "" || confidence === undefined) {
            delete input.usage.dataConfidence;
        }
        var result = Snapshot.normalize(input, nowMs);
        result.error = "";
        result.primaryRow = result.rows[0];
        return result;
    }

    function test_textQualifiesEstimatesAndUnknownConfidence() {
        var row = provider("estimated", 95).rows[0];
        compare(text.percentText(row, true), "95% used (estimated)");
        compare(text.percentText(row, false), "5% left (estimated)");
        compare(panelText.displayText(row, "percent", "", ""), "95% used (estimated)");
        compare(panelText.displayText(row, "both", "", ""), "95% used (estimated)");
        compare(text.confidenceText(row), "Estimated usage; not a measured account quota.");
        row.dataConfidence = "unknown";
        compare(text.percentText(row, true), "95% used (confidence unknown)");
        verify(text.confidenceText(row).length > 0);
        for (var confidence of ["", "exact", undefined]) {
            row.dataConfidence = confidence;
            compare(text.percentText(row, true), "95% used");
            compare(text.confidenceText(row), "");
        }
        row.hasPercent = false;
        compare(text.percentText(row, true), "");
        compare(text.percentText(null, true), "");
    }

    function test_estimatesCannotWinAutomaticQuotaSelection() {
        var estimated = provider("estimated", 95);
        var measured = provider("exact", 50);
        measured.provider = "codex";
        var before = JSON.stringify(estimated);
        compare(AutoSelect.usedPercent(estimated), -1);
        compare(AutoSelect.bestIndex([estimated, measured]), 1);
        compare(AutoSelect.bestIndex([measured, estimated]), 0);
        estimated.providerCost = {
            percentUsed: 100
        };
        compare(AutoSelect.usedPercent(estimated), -1);
        estimated.providerCost = null;
        estimated.rows[0].dataConfidence = "unknown";
        compare(AutoSelect.usedPercent(estimated), -1);
        estimated.rows[0].dataConfidence = "estimated";
        // Provider status remains independent of usage confidence.
        estimated.statusSeverity = "critical";
        measured.rows[0].usedPercent = 0;
        compare(AutoSelect.bestIndex([measured, estimated]), 1);
        estimated.statusSeverity = "";
        compare(JSON.stringify(estimated), before);
        for (var confidence of ["exact", undefined]) {
            estimated.rows[0].dataConfidence = confidence;
            compare(AutoSelect.usedPercent(estimated), 95);
        }
    }

    function test_panelKeepsPercentagesWithoutQuotaTimingOrThresholds() {
        var row = provider("estimated", 95).rows[0];
        // Guards also protect adapters fed older in-memory rows.
        row.pacePercent = 30;
        row.paceOnTop = false;
        row.paceEtaSeconds = 60;
        row.resetsAt = "2026-10-14T14:00:00Z";
        row.resetDescription = "Synthetic reset";
        compare(PanelDisplay.rowForMode([row], "percent"), row);
        compare(PanelDisplay.meterRows([row], "auto"), [row]);
        for (var mode of ["pace", "resetTime", "runOut"])
            compare(PanelDisplay.rowForMode([row], mode), null);
        verify(PanelRules.matches({
            condition: "always"
        }, row, nowMs));
        for (var condition of ["usageAtLeast", "resetWithin", "runOut"])
            verify(!PanelRules.matches({
                condition: condition,
                resetMinutes: 180
            }, row, nowMs));
        row.dataConfidence = "exact";
        verify(PanelRules.matches({
            condition: "usageAtLeast"
        }, row, nowMs));
        verify(PanelRules.matches({
            condition: "resetWithin",
            resetMinutes: 180
        }, row, nowMs));
        verify(PanelRules.matches({
            condition: "runOut"
        }, row, nowMs));
    }

    function test_privacyRetentionAndRestartKeepConfidence_data() {
        return [
            {
                tag: "estimated",
                confidence: "estimated"
            },
            {
                tag: "unknown",
                confidence: "unknown"
            },
            {
                tag: "exact",
                confidence: "exact"
            },
            {
                tag: "legacy",
                confidence: ""
            }
        ];
    }
    function test_privacyRetentionAndRestartKeepConfidence(data) {
        var item = provider(data.confidence, 95);
        var before = JSON.stringify(item);
        var privateItem = Privacy.provider(item, true, {
            title: "Provider",
            usage: "Usage",
            rowLabels: []
        });
        compare(privateItem.dataConfidence, data.confidence);
        compare(privateItem.rows[0].dataConfidence, data.confidence);
        var fresh = Cache.reconcile([], [item], nowMs);
        var retained = Cache.reconcile(fresh, [
            {
                provider: item.provider,
                error: "Synthetic failure",
                rows: []
            }
        ], nowMs + 1);
        compare(retained[0].rows[0].dataConfidence, data.confidence);
        var encoded = Cache.encode(fresh, context, nowMs);
        verify(encoded.length > 0);
        var decoded = Cache.decode(encoded, context, nowMs);
        compare(decoded[0].usage.dataConfidence, data.confidence || undefined);
        compare(Snapshot.normalize(decoded[0], nowMs).rows[0].dataConfidence, data.confidence);
        var hostile = JSON.parse(encoded);
        hostile.snapshots[0].dataConfidence = {
            secret: "private-token"
        };
        var sanitized = Cache.decode(JSON.stringify(hostile), context, nowMs);
        compare(sanitized[0].usage.dataConfidence, "unknown");
        verify(JSON.stringify(sanitized).indexOf("private-token") < 0);
        hostile.snapshots[0].dataConfidence = "";
        var empty = Cache.decode(JSON.stringify(hostile), context, nowMs);
        compare(empty[0].usage.dataConfidence, "unknown");
        compare(Snapshot.normalize(empty[0], nowMs).rows[0].dataConfidence, "unknown");
        var saved = JSON.parse(encoded).snapshots[0];
        compare(Object.prototype.hasOwnProperty.call(saved, "dataConfidence"), data.confidence.length > 0);
        delete hostile.snapshots[0].dataConfidence;
        compare(Cache.decode(JSON.stringify(hostile), context, nowMs)[0].usage.dataConfidence, undefined);
        compare(JSON.stringify(item), before);
    }

    function observation(confidence, used, level, pace, severity) {
        return {
            providerID: "opencodego",
            scopeID: "account",
            statusActive: !!severity,
            statusSeverity: severity || "",
            statusIncidentKey: severity ? "incident" : "",
            rows: [
                {
                    lane: "primary",
                    dataConfidence: confidence,
                    hasPercent: true,
                    usedPercent: used,
                    quotaLevel: level,
                    paceKnown: true,
                    paceActive: pace
                }
            ]
        };
    }

    function test_estimatesNeitherNotifyNorArmOrConsumeQuotaTransitions_data() {
        return [
            {
                tag: "estimated",
                confidence: "estimated"
            },
            {
                tag: "unknown",
                confidence: "unknown"
            }
        ];
    }
    function test_estimatesNeitherNotifyNorArmOrConsumeQuotaTransitions(data) {
        var options = {
            mode: "prime",
            quotaEnabled: true,
            paceEnabled: true,
            resetEnabled: true,
            statusEnabled: true
        };
        var primed = Notifications.transition([observation(data.confidence, 95, "major", true)], {}, options);
        options.mode = "observe";
        var next = Notifications.transition([observation(data.confidence, 0, "", false)], primed.nextMemo, options);
        compare(next.intents.length, 0);
        next = Notifications.transition([observation(data.confidence, 95, "major", true)], next.nextMemo, options);
        compare(next.intents.length, 0);
        // Switching from a measured near-limit observation to an estimated zero
        // must not announce a reset or leave its measured reset armed.
        options.mode = "prime";
        primed = Notifications.transition([observation("exact", 95, "major", true)], {}, options);
        options.mode = "observe";
        next = Notifications.transition([observation(data.confidence, 0, "", false)], primed.nextMemo, options);
        compare(next.intents.length, 0);
        next = Notifications.transition([observation("exact", 0, "", false)], next.nextMemo, options);
        compare(next.intents.length, 0);
        next = Notifications.transition([observation(data.confidence, 95, "major", true, "minor")], next.nextMemo, options);
        compare(next.intents.length, 1);
        compare(next.intents[0].kind, "status");
        options.mode = "prime";
        primed = Notifications.transition([observation("exact", 95, "major", true)], {}, options);
        primed = Notifications.transition([observation(data.confidence, 0, "", false)], primed.nextMemo, options);
        options.mode = "observe";
        next = Notifications.transition([observation("exact", 0, "", false)], primed.nextMemo, options);
        compare(next.intents.length, 0);
        for (var confidence of ["exact", undefined]) {
            options.mode = "prime";
            primed = Notifications.transition([observation(confidence, 0, "", false)], {}, options);
            options.mode = "observe";
            next = Notifications.transition([observation(confidence, 95, "major", true)], primed.nextMemo, options);
            compare(next.intents.length, 2);
            compare(next.intents[0].kind, "quota");
            compare(next.intents[1].kind, "pace");
            next = Notifications.transition([observation(confidence, 0, "", false)], next.nextMemo, options);
            compare(next.intents.length, 1);
            compare(next.intents[0].kind, "reset");
        }
    }

    function test_insightsDoNotClaimEstimatedAccountHeadroom() {
        var estimated = provider("estimated", 95);
        var measured = provider("exact", 50);
        measured.provider = "codex";
        var snapshot = JSON.parse(Insights.build([estimated, measured], nowMs, 80).text);
        compare(snapshot.providers.filter(function (item) {
            return item.id === "opencodego";
        }).length, 0);
        compare(snapshot.providers[0].quotas[0].usedPercent, 50);
    }
}
