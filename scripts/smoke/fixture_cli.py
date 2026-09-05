#!/usr/bin/env python3
"""Synthetic responses for the popup smoke test. Never invokes the real CLI."""

import copy
import json
import os
import sys
import time
from datetime import datetime, timedelta, timezone

SCENARIOS = ("normal", "loading", "partial-error", "long-text", "panel-rules",
             "project-costs", "project-tokens", "project-range", "project-long-text")


def usage(provider, scenario, now):
    if scenario == "partial-error" and provider == "claude":
        return {"provider": provider, "error": {"message": "Synthetic provider timeout. Try again."}}
    long_text = scenario == "long-text"
    return {
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


def response(args, scenario, now):
    """Only the read commands used by the applet are supported."""
    if args == ["--version"]:
        return "CodexBar 0.56.2 (synthetic smoke fixture)"
    if args == ["config", "providers", "--format", "json", "--json-only"]:
        return [{"provider": key, "enabled": True} for key in ("codex", "claude")]
    if args == ["sessions", "--json-v2"]:
        return {"sessions": [{"provider": "codex", "projectName": "Example project",
                              "state": "working", "lastActivityAt": now.isoformat()}]}
    if (args[:5] == ["cost", "--format", "json", "--json-only", "--days"]
            and len(args) == 6 and args[5] in ("7", "30", "90")):
        days = int(args[5])
        factor = 0.5 if days == 7 else 1
        snapshot = {"provider": "codex", "updatedAt": now.isoformat(), "historyDays": days,
                 "currencyCode": "USD", "sessionCostUSD": 1.25, "sessionTokens": 12000,
                 "totals": {"totalCost": 8.75 * factor, "totalTokens": 84000 * factor},
                 "daily": [{"date": (now - timedelta(days=6 - i)).date().isoformat(),
                            "totalCost": 1.25 * factor, "totalTokens": 12000 * factor}
                           for i in range(7)]}
        if scenario.startswith("project-"):
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
    for provider in ("codex", "claude"):
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
    if scenario == "loading":
        # The runner kills the whole preview process group after capture/timeout.
        time.sleep(300)
    print(result if isinstance(result, str) else json.dumps(result))


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
