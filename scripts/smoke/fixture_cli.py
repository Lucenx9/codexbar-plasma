#!/usr/bin/env python3
"""Synthetic responses for the popup smoke test. Never invokes the real CLI."""

import copy
import json
import os
import sys
import time
from datetime import datetime, timedelta, timezone

SCENARIOS = ("normal", "tabs-overflow", "provider-settings", "provider-header", "provider-header-large", "loading", "partial-error", "long-text", "panel-rules", "panel-standard", "panel-minimal", "panel-minimal-single", "legacy-dashboard",
             "project-costs", "project-tokens", "project-range", "project-long-text",
             "localization-it", "localization-fr", "localization-de", "localization-es", "localization-pt_BR")
SCENARIOS += ("settings-general", "settings-panel", "settings-panel-information", "settings-panel-advanced", "settings-panel-narrow", "settings-popup", "settings-notifications", "settings-diagnostics")
SCENARIOS += ("settings-panel-scrolled",)
SCENARIOS += ("settings-providers", "settings-providers-narrow", "settings-providers-error",
              "settings-general-narrow", "settings-popup-narrow", "settings-notifications-narrow",
              "settings-diagnostics-narrow", "settings-diagnostics-error")
SCENARIOS += ("readme-overview", "readme-spend", "readme-sessions", "readme-codex")
SCENARIOS += ("readme-panel-standard", "readme-panel-minimal")
SCENARIOS += ("panel-information", "panel-information-minimal", "panel-information-single")
SCENARIOS += ("panel-default", "panel-default-single")
SCENARIOS += ("panel-vertical", "panel-vertical-minimal", "panel-small", "panel-dual-edge")
SCENARIOS += ("popup-cost-details", "popup-cost-tokens")
SCENARIOS += ("popup-cost-refresh-error", "cost-period")
SCENARIOS += ("share-usage", "share-usage-narrow")
SCENARIOS += ("popup-cost-missing-tokens", "popup-cost-partial-models")
SCENARIOS += ("popup-scroll", "popup-scroll-large")
SCENARIOS += ("popup-content", "popup-hidden-rows", "popup-hidden-sections", "refresh-on-open", "privacy-provider", "privacy-spend", "privacy-sessions")
SCENARIOS += ("privacy-cost-details",)
SCENARIOS += ("usage-retention", "usage-cache-restart")
SCENARIOS += ("estimated-usage", "estimated-panel", "unknown-panel")
SCENARIOS += ("percent-only-usage", "percent-only-panel")
SCENARIOS += ("percent-only-pace",)
SCENARIOS += ("subscription-dates",)
SCENARIOS += ("identified-local", "identified-partial", "identified-ssh-failure", "identified-only")

SCENARIOS += ("providers-0740",)
SCENARIOS += ("empty-providers", "usage-error", "usage-recovery", "cli-missing", "cli-setup")
SCENARIOS += ("ai-insights", "ai-insights-it", "ai-insights-mismatch", "ai-insights-error", "ai-insights-single",
              "settings-ai-insights", "settings-ai-insights-narrow")
MAX_SCENARIO_TIMEOUT_SECONDS = 120
MATRIX_SCENARIOS = ("panel-matrix-one", "panel-matrix-four")


def usage(provider, scenario, now):
    if scenario == "partial-error" and provider == "claude":
        return {"provider": provider, "error": {"message": "Synthetic provider timeout. Try again."}}
    long_text = scenario == "long-text"
    snapshot = {
        "provider": provider,
        "account": "engineering-with-an-unusually-long-account-name@example.com" if long_text else "demo@example.com",
        "source": "cli",
        "usage": {
            "updatedAt": now.isoformat(),
            "identity": {
                "accountOrganization": "Workspace with a long display name for the example team" if long_text else "Example team",
                "loginMethod": "business",
            },
            "primary": {"usedPercent": 43 if provider == "codex" else 72, "windowMinutes": 300,
                        "resetsAt": (now + timedelta(hours=2)).isoformat()},
            "secondary": {"usedPercent": 28, "windowMinutes": 10080,
                          "resetsAt": (now + timedelta(days=4)).isoformat()},
        },
    }
    if scenario == "subscription-dates":
        snapshot["usage"].update(subscriptionRenewsAt="2026-11-01T08:30:00Z",
                                 subscriptionExpiresAt="2026-11-30T00:00:00Z",
                                 subscriptionExpiresAtIsDateOnly=True)
    if scenario.startswith("ai-insights") and provider == "codex":
        snapshot["pace"] = {"primary": {"stage": "ahead", "deltaPercent": 13,
            "expectedUsedPercent": 30, "willLastToReset": False, "etaSeconds": 3600}}
    if scenario in ("estimated-usage", "estimated-panel", "unknown-panel") and provider == "codex":
        snapshot["source"] = "local"
        snapshot["usage"]["dataConfidence"] = "unknown" if scenario == "unknown-panel" else "estimated"
        snapshot["usage"]["primary"]["usedPercent"] = 95
        snapshot["pace"] = {"primary": {"expectedUsedPercent": 30,
            "willLastToReset": False, "etaSeconds": 3600}}
    if scenario in ("percent-only-usage", "percent-only-panel", "percent-only-pace") and provider == "claude":
        snapshot["source"] = "claude"
        snapshot["usage"]["dataConfidence"] = "percentOnly"
        snapshot["usage"]["primary"].update(usedPercent=0, resetsAt=None)
        snapshot["usage"]["secondary"]["usedPercent"] = 100
        if scenario == "percent-only-pace":
            snapshot["usage"]["secondary"]["usedPercent"] = 80
            snapshot["pace"] = {"secondary": {"stage": "farAhead", "deltaPercent": 37,
                "expectedUsedPercent": 43, "willLastToReset": False, "etaSeconds": 64800}}
    if scenario in MATRIX_SCENARIOS:
        if provider == "codex":
            snapshot["credits"] = {"remaining": 125}
        snapshot["pace"] = {"primary": {"stage": "ahead", "deltaPercent": 13,
            "expectedUsedPercent": 30, "willLastToReset": False, "etaSeconds": 3600}}
    if scenario.startswith("readme-"):
        snapshot["account"] = "team@example.com"
        snapshot["usage"]["primary"]["usedPercent"] = {"codex": 43, "claude": 68, "gemini": 24}[provider]
        snapshot["usage"]["secondary"]["usedPercent"] = {"codex": 28, "claude": 36, "gemini": 12}[provider]
        snapshot["usage"]["primary"]["resetsAt"] = (now + timedelta(hours=2, minutes=35)).isoformat()
    if scenario == "panel-dual-edge":
        if provider == "codex":
            snapshot["usage"]["secondary"]["usedPercent"] = 100
        else:
            del snapshot["usage"]["secondary"]
    if scenario.startswith("provider-header"):
        snapshot["status"] = {"indicator": "minor", "description": "Synthetic service degradation"}
    if scenario == "legacy-dashboard":
        snapshot["openaiDashboard"] = {
            "creditsRemaining": 0,
            "currentDay": {"costUSD": 1.25, "totalTokens": 1200},
            "topModels": [{"name": ("Example model " * 8).strip(), "requests": 0}],
        }
        if provider == "codex":
            snapshot["usage"]["openAIAPIUsage"] = {
                "currentMonth": {"costUSD": 1234.56, "totalTokens": 987654321},
            }
        if provider == "claude":
            snapshot["usage"]["details"] = [{"title": "Generic details",
                                             "rows": [{"label": "Requests", "value": "7"}]}]
    if scenario in ("popup-content", "popup-hidden-sections"):
        snapshot["credits"] = {"remaining": 125}
        snapshot["usage"]["details"] = [{"title": "Generic details",
                                          "rows": [{"label": "Requests", "value": "7"}]}]
    if scenario.startswith("localization-") or scenario == "popup-content":
        snapshot["pace"] = {"primary": {"stage": "ahead", "deltaPercent": 13,
                                        "expectedUsedPercent": 30, "willLastToReset": False,
                                        "etaSeconds": 3600,
                                        "summary": "13% in deficit | Expected 30% used | Runs out in 1h"}}
    return snapshot


def readme_cost(provider, days, now):
    """Varied synthetic history with totals derived from the displayed days."""
    cents = (96, 142, 185, 128, 164, 24, 8, 116, 172, 208, 154, 192, 36, 12,
             148, 186, 224, 178, 216, 48, 16, 168, 212, 246, 198, 232, 64, 24, 188, 218)
    daily = []
    for index in range(days):
        amount = cents[(len(cents) - days + index) % len(cents)]
        if provider == "claude":
            amount = amount * 3 // 4
        daily.append({"date": (now - timedelta(days=days - index - 1)).date().isoformat(),
                      "totalCost": amount / 100, "totalTokens": amount * 420})
    total_cost = round(sum(day["totalCost"] for day in daily), 2)
    total_tokens = sum(day["totalTokens"] for day in daily)
    return {"provider": provider, "updatedAt": now.isoformat(), "historyDays": days,
            "currencyCode": "USD", "sessionCostUSD": daily[-1]["totalCost"],
            "sessionTokens": daily[-1]["totalTokens"],
            "totals": {"totalCost": total_cost, "totalTokens": total_tokens}, "daily": daily}


def response(args, scenario, now):
    """Only the read commands used by the applet are supported."""
    if args == ["config", "providers", "--descriptors", "--format", "json", "--json-only"]:
        raise ValueError("Unknown option --descriptors")
    if args == ["--version"]:
        if scenario.startswith("settings-providers"):
            return "CodexBar 0.73.0 (synthetic smoke fixture)"
        return "CodexBar 0.56.2 (synthetic smoke fixture)"
    if args == ["config", "providers", "--format", "json", "--json-only"]:
        if scenario == "empty-providers":
            return []
        if scenario in ("usage-error", "settings-providers-error"):
            raise ValueError("Synthetic connection failure.")
        providers = ("codex",) if scenario in ("panel-minimal-single", "panel-default-single", "panel-information-single", "panel-matrix-one", "ai-insights-single") else ("codex", "claude")
        if scenario.startswith("readme-"):
            providers += ("gemini",)
        if scenario == "panel-matrix-four":
            providers += ("gemini", "cursor")
        rows = [{"provider": key, "enabled": True} for key in providers]
        if scenario == "providers-0740":
            rows.extend({"provider": key, "enabled": False} for key in (
                "tavily", "linkup", "tinyapi", "exa", "cosmic", "aerostack", "sailresearch", "sofya", "xapi"))
        if scenario == "provider-settings":
            rows.extend({"provider": key, "enabled": False} for key in ("gemini", "cursor", "openrouter"))
        if scenario.startswith("settings-providers"):
            # A long roster with the longest bundled title and an unknown ID.
            rows.append({"provider": "moonshot", "enabled": True, "defaultEnabled": False})
            rows.extend({"provider": key, "enabled": False} for key in (
                "gemini", "cursor", "openrouter", "alibabatokenplan", "huggingface", "azureopenai",
                "jetbrains", "perplexity", "example-provider-with-an-unusually-long-identifier"))
            rows[0]["defaultEnabled"] = True
        return rows
    if args == ["diagnose", "--provider", "codex", "--format", "json", "--redact"]:
        return {"provider": "codex", "displayName": "Codex", "source": "cli", "sourceMode": "auto",
                "auth": {"configured": True, "modes": ["oauth", "apiKey"]},
                "settings": {"source": "auto", "usageHistory": "enabled"}, "fetchAttempts": [{}, {}]}
    if args == ["sessions", "--json-v2"]:
        if scenario.startswith("readme-"):
            return {"sessions": [
                {"provider": provider, "projectName": project, "state": state,
                 "source": source, "lastActivityAt": (now - timedelta(minutes=age)).isoformat()}
                for provider, project, state, source, age in (
                    ("codex", "CodexBar Plasma", "active", "desktopApp", 0),
                    ("claude", "Design system", "active", "cli", 2),
                    ("codex", "Documentation", "idle", "ide", 18),
                    ("claude", "Release checks", "idle", "cli", 42))]}
        return {"sessions": [{"provider": "codex", "projectName": "Example project",
                              "state": "active", "source": "desktopApp", "lastActivityAt": now.isoformat()},
                             {"provider": "claude", "projectName": "Another project",
                              "state": "idle", "source": "cli", "lastActivityAt": now.isoformat()}]}
    if args[:3] == ["cost", "--provider", "codex"] and "--identified-only" in args:
        end = int(args[args.index("--identified-end") + 1])
        days = int(args[args.index("--days") + 1])
        partial = scenario == "identified-partial"
        ledger = dict(schemaVersion=1, provider="codex", startUnixMs=end - end % 86400000 - (days - 1) * 86400000,
                      endUnixMs=end, records=[dict(id=key * 64, timestampUnixMs=end, inputTokens=tokens,
                                                 outputTokens=10, cacheReadTokens=40, reasoningTokens=5)
                                              for key, tokens in (("a", 100), ("b", 200))],
                      conflictingIDs=["a" * 64] if partial else [], excludedCount=2 if partial else 0,
                      partial=partial)
        if scenario == "identified-ssh-failure":
            assert args[args.index("--remote") + 1] == "build@host"
            return dict(reports=[dict(host="local", ledger=ledger), dict(host="build@host", error="synthetic SSH failure")],
                        subtotal=dict(kind="identified-request-subtotal", totalTokens=320, requestCount=2,
                                      conflictCount=0, excludedCount=0, partial=False, costUSD=None),
                        allSourcesAvailable=False, partial=True)
        assert "--remote" not in args
        return ledger
    # CLI 0.67.0 calendar periods: an English label and, for all history, the
    # days since year 1, as the official CLI reports them.
    if (args[:5] == ["cost", "--format", "json", "--json-only", "--period"]
            and len(args) == 6 and args[5] in ("month-to-date", "all")):
        days = now.day if args[5] == "month-to-date" else 60
        snapshots = [readme_cost(provider, days, now) for provider in ("codex", "claude")]
        for snapshot in snapshots:
            snapshot["reportingPeriod"] = args[5]
            snapshot["historyLabel"] = "Month to date" if args[5] == "month-to-date" else "All"
            if args[5] == "all":
                snapshot["historyDays"] = 739887
        return snapshots
    if (args[:5] == ["cost", "--format", "json", "--json-only", "--days"]
            and len(args) == 6 and args[5] in ("7", "30", "90")):
        days = int(args[5])
        if scenario.startswith("share-usage"):
            snapshots = [readme_cost(provider, days, now) for provider in ("codex", "claude")]
            for snapshot in snapshots:
                snapshot["provenance"] = "listPriceEstimate"
                for day in snapshot["daily"]:
                    day["modelBreakdowns"] = [{
                        "modelName": "Example coding model" if snapshot["provider"] == "codex" else "Example reasoning model",
                        "cost": day["totalCost"], "totalTokens": day["totalTokens"]}]
            return snapshots
        if scenario.startswith("readme-"):
            return [readme_cost(provider, days, now) for provider in ("codex", "claude")]
        if scenario.startswith("popup-cost-") or scenario == "privacy-cost-details":
            snapshot = readme_cost("codex", days, now)
            if scenario == "privacy-cost-details":
                snapshot["provenance"] = "listPriceEstimate"
            daily = snapshot["daily"]
            daily[0]["modelBreakdowns"] = [{"modelName": "Earlier model", "cost": daily[0]["totalCost"],
                                             "totalTokens": daily[0]["totalTokens"]}]
            daily[-1]["modelBreakdowns"] = [
                {"modelName": "Example reasoning model", "cost": 1.4, "totalTokens": 50000},
                {"modelName": "Example coding model", "cost": 0.78, "totalTokens": 41560},
            ]
            if scenario == "popup-cost-tokens":
                for day in daily:
                    day.pop("totalCost")
                    for model in day.get("modelBreakdowns", []):
                        model.pop("cost")
                snapshot.pop("sessionCostUSD")
                snapshot["totals"].pop("totalCost")
            elif scenario == "popup-cost-missing-tokens":
                for day in daily:
                    day.pop("totalTokens")
                    day.pop("modelBreakdowns", None)
                snapshot.pop("sessionTokens")
                snapshot["totals"].pop("totalTokens")
                snapshot["daily"] = [daily[-1]]
                snapshot["totals"]["totalCost"] = daily[-1]["totalCost"]
            elif scenario in ("popup-cost-partial-models", "privacy-cost-details"):
                daily[-1]["modelBreakdowns"] = [
                    {"modelName": f"Example model {index}", "cost": 0.01, "totalTokens": 1000}
                    for index in range(7)
                ]
            return [snapshot]
        factor = 0.5 if days == 7 else 1
        snapshot = {"provider": "codex", "updatedAt": now.isoformat(), "historyDays": days,
                 "currencyCode": "USD", "sessionCostUSD": 1.25, "sessionTokens": 12000,
                 "totals": {"totalCost": 8.75 * factor, "totalTokens": 84000 * factor},
                 "daily": [{"date": (now - timedelta(days=6 - i)).date().isoformat(),
                            "totalCost": 1.25 * factor, "totalTokens": 12000 * factor}
                           for i in range(7)]}
        if scenario.startswith("project-") or scenario.startswith("privacy-"):
            snapshot["projects"] = [
                {"name": "CodexBar Plasma", "totalCost": 5.5 * factor, "totalTokens": 24000 * factor},
                {"name": "Documentation site", "totalCost": 3.25 * factor, "totalTokens": 55000 * factor},
                {"name": "Unpriced experiment", "totalTokens": 5000 * factor},
                {"name": "Empty project", "totalCost": 0, "totalTokens": 0},
            ]
            for project in snapshot["projects"]:
                project["path"] = "/private/synthetic-project-path"
                project["sources"] = [{"path": "/private/synthetic-source-path"}]
            if scenario == "project-long-text":
                snapshot["projects"][0]["name"] = "Example project with a long display name for the engineering and documentation team"
        if scenario == "usage-retention":
            return [snapshot, {**snapshot, "provider": "claude"}]
        return [snapshot]
    matrix_providers = ("codex", "claude", "gemini", "cursor")
    for provider in (("codex", "claude", "gemini") if scenario.startswith("readme-")
                     else matrix_providers if scenario == "panel-matrix-four"
                     else ("codex", "claude")):
        prefix = ["usage", "--provider", provider]
        if args == prefix + ["--format", "json", "--json-only"]:
            return [usage(provider, scenario, now)]
        if args == prefix + ["--all-accounts", "--format", "json", "--json-only"]:
            first = usage(provider, scenario, now)
            if scenario in ("popup-scroll", "popup-scroll-large"):
                accounts = []
                for index in range(20):
                    account = copy.deepcopy(first)
                    account["account"] = f"synthetic-engineering-account-with-a-long-label-{index}@example.com"
                    accounts.append(account)
                return accounts
            second = copy.deepcopy(first)
            second["account"] = "second-demo@example.com"
            return [first, second]
    raise ValueError("SMOKE_FAILED: unsupported fixture CLI command")


def main():
    scenario = os.environ.get("CODEXBAR_SMOKE_SCENARIO")
    if scenario not in SCENARIOS + MATRIX_SCENARIOS:
        raise ValueError("SMOKE_FAILED: missing or unknown fixture scenario")
    result = response(sys.argv[1:], scenario, datetime.now(timezone.utc))
    if sys.argv[1:2] == ["cost"]:
        run = int(os.environ.get("CODEXBAR_PLASMA_RUN", "0"))
        if scenario == "popup-cost-refresh-error":
            if run in (2, 6, 11, 14):
                print("Synthetic cost refresh failed.", file=sys.stderr)
                return
            if run in (3, 7):
                result = "{"
            elif run in (4, 8):
                result = "null"
            elif run in (5, 9):
                result = [{"provider": "codex", "error": {"message": "Synthetic cost scan failed."}}]
            elif run == 10:
                result = []
            elif run == 12:
                result = [{"provider": "codex", "totals": {"totalCost": 4, "totalTokens": 100}}]
        elif scenario == "privacy-cost-details" and run == 2:
            print("demo@example.com private cost error", file=sys.stderr)
            return
        elif scenario == "usage-retention" and run == 2:
            result = "{"
    if scenario == "loading" or (
        scenario == "usage-cache-restart" and os.environ.get("CODEXBAR_SMOKE_RESTART") == "1"
    ):
        # Keep responses blocked for every allowed preview duration; the runner
        # kills the process group after capturing the loading/restored state.
        time.sleep(MAX_SCENARIO_TIMEOUT_SECONDS + 1)
    print(result if isinstance(result, str) else json.dumps(result))
    if scenario == "identified-ssh-failure" and "--identified-only" in sys.argv:
        sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
