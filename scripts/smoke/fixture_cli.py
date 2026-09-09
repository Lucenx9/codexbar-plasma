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
SCENARIOS += ("settings-general", "settings-panel", "settings-popup", "settings-notifications", "settings-diagnostics")
SCENARIOS += ("readme-overview", "readme-spend", "readme-sessions", "readme-codex")
SCENARIOS += ("readme-panel-standard", "readme-panel-minimal")
SCENARIOS += ("panel-default", "panel-default-single")
SCENARIOS += ("panel-vertical", "panel-vertical-minimal", "panel-small", "panel-dual-edge")
SCENARIOS += ("popup-cost-details", "popup-cost-tokens")
SCENARIOS += ("popup-cost-missing-tokens", "popup-cost-partial-models")
SCENARIOS += ("popup-content", "refresh-on-open", "privacy-provider", "privacy-spend", "privacy-sessions")
SCENARIOS += ("privacy-cost-details",)
SCENARIOS += ("usage-retention", "usage-cache-restart")
MAX_SCENARIO_TIMEOUT_SECONDS = 120


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
            "topModels": [{"name": "Example model", "requests": 0}],
        }
        if provider == "claude":
            snapshot["usage"]["details"] = [{"title": "Generic details",
                                             "rows": [{"label": "Requests", "value": "7"}]}]
    if scenario == "popup-content":
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
        return "CodexBar 0.56.2 (synthetic smoke fixture)"
    if args == ["config", "providers", "--format", "json", "--json-only"]:
        providers = ("codex",) if scenario in ("panel-minimal-single", "panel-default-single") else ("codex", "claude")
        if scenario.startswith("readme-"):
            providers += ("gemini",)
        rows = [{"provider": key, "enabled": True} for key in providers]
        if scenario == "provider-settings":
            rows.extend({"provider": key, "enabled": False} for key in ("gemini", "cursor", "openrouter"))
        return rows
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
    if (args[:5] == ["cost", "--format", "json", "--json-only", "--days"]
            and len(args) == 6 and args[5] in ("7", "30", "90")):
        days = int(args[5])
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
        return [snapshot]
    for provider in (("codex", "claude", "gemini") if scenario.startswith("readme-") else ("codex", "claude")):
        prefix = ["usage", "--provider", provider]
        if args == prefix + ["--format", "json", "--json-only"]:
            return [usage(provider, scenario, now)]
        if args == prefix + ["--all-accounts", "--format", "json", "--json-only"]:
            first = usage(provider, scenario, now)
            second = copy.deepcopy(first)
            second["account"] = "second-demo@example.com"
            return [first, second]
    raise ValueError("SMOKE_FAILED: unsupported fixture CLI command")


def main():
    scenario = os.environ.get("CODEXBAR_SMOKE_SCENARIO")
    if scenario not in SCENARIOS:
        raise ValueError("SMOKE_FAILED: missing or unknown fixture scenario")
    result = response(sys.argv[1:], scenario, datetime.now(timezone.utc))
    if scenario == "loading" or (
        scenario == "usage-cache-restart" and os.environ.get("CODEXBAR_SMOKE_RESTART") == "1"
    ):
        # Keep responses blocked for every allowed preview duration; the runner
        # kills the process group after capturing the loading/restored state.
        time.sleep(MAX_SCENARIO_TIMEOUT_SECONDS + 1)
    print(result if isinstance(result, str) else json.dumps(result))


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
