import QtQuick
import QtTest
import "../contents/ui/CostResponse.js" as CostResponse

TestCase {
    name: "CostResponsePerformance"
    // One warm-up, then nine batch averages. Fixture construction/serialization
    // are outside timing; run separately from the parallel correctness suite.
    function fixture(days, models, period) {
        var daily = [];
        for (var d = 0; d < days; ++d) {
            var breakdowns = [];
            for (var m = 0; m < models; ++m)
                breakdowns.push({
                    modelName: "synthetic-model-" + m,
                    cost: 1,
                    totalTokens: 1000
                });
            daily.push({
                date: new Date(Date.UTC(2026, 10, 13) - (days - 1 - d) * 86400000).toISOString().slice(0, 10),
                totalCost: models,
                totalTokens: models * 1000,
                modelBreakdowns: breakdowns
            });
        }
        return {
            provider: "codex",
            updatedAt: "2026-11-13T12:00:00Z",
            historyDays: days,
            reportingPeriod: period,
            daily: daily,
            totals: {
                totalCost: days * models,
                totalTokens: days * models * 1000
            }
        };
    }
    function test_cost_data() {
        return [
            {
                tag: "rolling-30-4models",
                days: 30,
                models: 4,
                period: "rolling:30",
                iterations: 20,
                budgetMs: 100
            },
            {
                tag: "rolling-365-16models",
                days: 365,
                models: 16,
                period: "rolling:365",
                iterations: 2,
                budgetMs: 1000
            },
            {
                tag: "all-2048-16models",
                days: 2048,
                models: 16,
                period: "all",
                iterations: 1,
                budgetMs: 2000
            }
        ];
    }
    function test_cost(data) {
        var input = fixture(data.days, data.models, data.period);
        var text = JSON.stringify([input]);
        verify(text.length < 4 * 1024 * 1024);
        var result = CostResponse.response(text, "", data.days, 0);
        compare(result.outcome, "success");
        compare(result.costs.codex.daily.length, Math.min(data.days, 365));
        compare(result.costs.codex.models.length, Math.min(data.models, 6));
        compare(result.costs.codex.models[0].cost, data.days);
        if (data.period === "all") {
            compare(result.costs.codex.averageDaily.cost.value, 16);
            compare(result.costs.codex.averageDaily.tokens.value, 16000);
        }
        var samples = [];
        for (var s = 0; s < 9; s++) {
            var started = Date.now();
            for (var i = 0; i < data.iterations; i++)
                result = CostResponse.response(text, "", data.days, 0);
            samples.push((Date.now() - started) / data.iterations);
        }
        var ordered = samples.slice().sort(function (a, b) {
            return a - b;
        });
        var median = ordered[Math.floor(ordered.length / 2)];
        console.log("PERF " + JSON.stringify({
            name: data.tag,
            bytes: text.length,
            samplesMs: samples,
            medianMs: median,
            budgetMs: data.budgetMs
        }));
        verify(median < data.budgetMs, data.tag + ": median " + median + " ms exceeds " + data.budgetMs + " ms budget");
    }
}
