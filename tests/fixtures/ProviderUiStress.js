.pragma library

function section(mode) {
    var worst = mode === "worst" || mode === "huge";
    var rows = worst ? [
        {label: "Account", value: "bartholomew.fitzgerald@northwind-industries-holdings.example.com"},
        {label: "Workspace", value: "Aleksandra Wiśniewska-Kowalczyk", secondaryValue: "Platform infrastructure and enterprise engineering"},
        {label: "J", value: "1"},
        {label: "Đặng Thị Ngọc Hân", value: "王秀英", secondaryValue: "نور الهدى عبد الرحمن"},
        {label: "👩🏽‍💻 Priya", value: "<model> & enterprise", secondaryValue: "Included"},
        {label: "Budget", value: "$12,345,678.90 / $10,000,000.00", usageValue: 12345678.9,
            progress: {used: 12345678.9, total: 10000000}},
        {label: "Unused", value: "0", progress: {used: 0, total: 100}},
        {label: "Optional value", value: "Available", secondaryValue: null}
    ] : [{label: "Requests", value: "1", progress: {used: 1, total: 100}}];
    if (mode === "huge") {
        var examples = rows;
        rows = [];
        for (var i = 0; i < 1000; i++)
            rows.push(examples[i % examples.length]);
    }
    return {
        title: worst ? "Platform infrastructure <model> & enterprise workspace allowance" : "Usage details",
        rows: mode === "empty" ? [] : rows,
        chart: {
            kind: "bars",
            title: worst ? "Daily requests for the platform infrastructure and enterprise engineering workspace" : "Daily requests",
            unit: worst ? "requests per enterprise workspace billing period" : "requests",
            points: mode === "empty" ? [] : [
                {label: "Mon", value: 0}, {label: "Tue", value: 1},
                {label: "Wed", value: 1284}, {label: "Thu", value: 1000000}
            ].slice(0, mode === "one" ? 1 : 4)
        }
    };
}

function quota(mode) {
    var worst = mode === "worst" || mode === "huge";
    return {
        lane: "primary",
        label: worst ? "Platform infrastructure <model> & enterprise workspace allowance" : "Session",
        value: mode === "empty" ? 0 : mode === "one" ? 1 : 57,
        usedPercent: mode === "empty" ? 100 : mode === "one" ? 99 : 43,
        leftPercent: mode === "empty" ? 0 : mode === "one" ? 1 : 57,
        hasPercent: mode !== "empty",
        pace: "",
        pacePercent: -1,
        paceOnTop: true,
        reset: worst ? "Resets after the next enterprise workspace billing cycle <UTC> & maintenance" : "Resets in 2h"
    };
}
