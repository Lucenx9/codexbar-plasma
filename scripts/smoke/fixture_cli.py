#!/usr/bin/env python3
"""Synthetic responses for the popup smoke test. Never invokes the real CLI."""

import copy
import json
import os
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

SCENARIOS = ("normal", "tabs-overflow", "provider-settings", "provider-header", "provider-header-large", "loading", "partial-error", "long-text", "panel-rules", "panel-standard", "panel-minimal", "panel-minimal-single", "legacy-dashboard",
             "project-costs", "project-tokens", "project-range", "project-long-text",
             "localization-it", "localization-fr", "localization-de", "localization-es", "localization-pt_BR")
SCENARIOS += ("settings-general", "settings-panel", "settings-panel-information", "settings-panel-advanced", "settings-panel-narrow", "settings-popup", "settings-notifications", "settings-diagnostics")
SCENARIOS += ("settings-general-updates", "settings-general-updates-narrow", "settings-providers-default",
              "settings-providers-wide")
SCENARIOS += ("settings-panel-scrolled",)
SCENARIOS += ("settings-providers", "settings-providers-narrow", "settings-providers-error",
              "settings-general-narrow", "settings-popup-narrow", "settings-notifications-narrow",
              "settings-diagnostics-narrow", "settings-diagnostics-error")
SCENARIOS += ("settings-providers-auth", "settings-providers-auth-legacy")
SCENARIOS += ("settings-providers-keys-soniox", "settings-providers-keys-chatbox")
SCENARIOS += ("readme-overview", "readme-spend", "readme-sessions", "readme-codex")
SCENARIOS += ("readme-panel-standard", "readme-panel-minimal")
SCENARIOS += ("tabs-icon-only",)
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
SCENARIOS += ("detail-severity",)
SCENARIOS += ("subscription-dates",)
SCENARIOS += ("identified-local", "identified-partial", "identified-ssh-failure", "identified-only")
SCENARIOS += ("identified-schema2", "identified-schema2-unpriced", "identified-schema-mismatch")
SCENARIOS += ("identified-schema2-subcent", "identified-schema2-zero")

SCENARIOS += ("providers-0740",)
SCENARIOS += ("empty-providers", "usage-error", "usage-recovery", "cli-missing", "cli-setup", "cli-setup-unusable")
SCENARIOS += ("ai-insights", "ai-insights-it", "ai-insights-mismatch", "ai-insights-error", "ai-insights-single",
              "settings-ai-insights", "settings-ai-insights-narrow", "settings-ai-insights-stored-narrow")
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
    if scenario == "detail-severity" and provider == "codex":
        snapshot["usage"]["details"] = [{"title": "API usage details", "rows": [
            {"label": "Completed batch", "value": "100 / 100", "severity": "normal", "progress": {"used": 100, "total": 100}},
            {"label": "Requests", "value": "1 / 100", "severity": "warning", "progress": {"used": 1, "total": 100}},
            {"label": "Account action", "value": "Check account settings", "severity": "critical"},
            {"label": "Imported rows", "value": "100 / 100", "progress": {"used": 100, "total": 100}},
            {"label": "Future metadata", "value": "100 / 100", "severity": "future", "progress": {"used": 100, "total": 100}}
        ]}]
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


def read_source_settings(scenario, now):
    """Project the fixture roster and persisted choices into a CLI config dump."""
    state_path = os.environ.get("CODEXBAR_SMOKE_SOURCE_STATE")
    saved = json.loads(Path(state_path).read_text()) if state_path and Path(state_path).exists() else {}
    rows = response(["config", "providers", "--format", "json", "--json-only"], scenario, now)
    return {"providers": [{"id": row["provider"], "source": saved.get(row["provider"], "auto")} for row in rows]}


def source_settings_response(args, scenario, now):
    """Read or update source settings in the isolated smoke scenario state."""
    if args == ["config", "dump", "--format", "json", "--json-only"]:
        return read_source_settings(scenario, now)
    if not scenario.startswith("settings-providers-auth") or args != [
            "config", "set-source", "--provider", "openrouter", "--source", "api", "--format", "json", "--json-only"]:
        raise ValueError("Unsupported synthetic CLI command: " + " ".join(args))
    state_path = os.environ.get("CODEXBAR_SMOKE_SOURCE_STATE")
    if state_path:
        Path(state_path).write_text(json.dumps({"openrouter": "api"}))
    return {"provider": "openrouter", "enabled": True, "source": "api"}


def response(args, scenario, now):
    """Synthetic reads and the source write used by authentication scenarios."""
    if args == ["config", "providers", "--descriptors", "--format", "json", "--json-only"]:
        raise ValueError("Unknown option --descriptors")
    if args[:2] in (["config", "dump"], ["config", "set-source"]):
        return source_settings_response(args, scenario, now)
    if args == ["--version"]:
        if scenario.startswith("settings-providers-keys"):
            return "CodexBar 0.83.0"
        if scenario.startswith("settings-providers-auth"):
            return "CodexBar " + ("0.82.0" if scenario.endswith("-legacy") else "0.83.0")
        if scenario.startswith("settings-providers"):
            return "CodexBar 0.73.0 (synthetic smoke fixture)"
        return "CodexBar 0.56.2 (synthetic smoke fixture)"
    if args == ["config", "providers", "--format", "json", "--json-only"]:
        if scenario.startswith("settings-providers-keys"):
            return [{"provider": key, "enabled": False, "authentication": {
                "sourceModes": ["api", "auto"], "supportsConfigAPIKey": True,
                "supportsConfigCookieHeader": False, "environmentVariables": []}}
                for key in ("soniox", "abliteration", "chatbox")]
        if scenario.startswith("settings-providers-auth"):
            rows = [{"provider": key, "enabled": key in ("codex", "copilot", "openrouter")}
                    for key in ("codex", "copilot", "openrouter", "moonshot", "flora", "helmcode", "future-provider")]
            if not scenario.endswith("-legacy"):
                for row in rows:
                    key = row["provider"]
                    row["authentication"] = dict(sourceModes=["api", "auto"], supportsConfigAPIKey=key != "moonshot",
                                                 supportsConfigCookieHeader=False, environmentVariables=[])
                rows[1]["authentication"].update(environmentVariables=["COPILOT_API_TOKEN"],
                    supportsConfigCookieHeader=True,
                    tokenAccounts=dict(title="GitHub accounts", setupHint="Sign in with multiple GitHub accounts via OAuth."),
                    loginCommand="codexbar config login --provider copilot")
                rows[2]["authentication"].update(environmentVariables=["OPENROUTER_API_KEY", "OPENROUTER_API_URL"],
                    tokenAccounts=dict(title="API keys", setupHint="Store multiple OpenRouter API keys."))
                rows[4]["authentication"]["environmentVariables"] = ["FLORA_API_KEY", "FLORA_WORKSPACE_ID"]
                rows[0]["authentication"].update(sourceModes=["api", "auto", "cli", "oauth", "web"],
                                                 supportsConfigAPIKey=False, supportsConfigCookieHeader=True)
                rows[5]["authentication"].update(sourceModes=["auto", "web"], supportsConfigAPIKey=False,
                                                 supportsConfigCookieHeader=True)
            return rows
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
        if scenario.startswith("identified-schema2"):
            ledger["schemaVersion"] = 2
            for record in ledger["records"]:
                record.update(model="gpt-5", pricingMode="standard", includedInPlan=False)
        if scenario == "identified-schema-mismatch":
            ledger["schemaVersion"] = 3
        if scenario == "identified-ssh-failure" or scenario.startswith("identified-schema2"):
            assert args[args.index("--remote") + 1] == "build@host"
            result = dict(reports=[dict(host="local", ledger=ledger), dict(host="build@host", error="synthetic SSH failure")],
                          subtotal=dict(kind="identified-request-subtotal", totalTokens=320, requestCount=2,
                                        conflictCount=0, excludedCount=0, partial=False, costUSD=None),
                          allSourcesAvailable=False, partial=True)
            if ledger["schemaVersion"] == 2:
                result["reports"][0].update(source="local", collectedAt=now.isoformat())
                result["reports"][1]["source"] = "ssh"
                price = {"identified-schema2": 0.0125, "identified-schema2-subcent": 0.004,
                         "identified-schema2-zero": 0}.get(scenario)
                result["subtotal"].update(costUSD=price, unpricedRequestCount=1 if price is None else 0)
            return result
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
    if (scenario == "identified-ssh-failure" or scenario.startswith("identified-schema2")) and "--identified-only" in sys.argv:
        sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
