#!/usr/bin/env python3
"""Synthetic AI Insights helper for smoke scenarios. Never contacts a network or wallet."""

import argparse
import json
import os
import time

PRIVATE = ("demo@example.com", "Example team", "business", "cli")


def main():
    parser = argparse.ArgumentParser()
    for name in ("--action", "--provider", "--model", "--endpoint", "--language", "--prompt", "--snapshot"):
        parser.add_argument(name, default="")
    parser.add_argument("--no-zdr", action="store_true")
    args = parser.parse_args()
    scenario = os.environ.get("CODEXBAR_SMOKE_SCENARIO", "")
    if args.action == "key-status":
        result = {"status": "present" if scenario == "settings-ai-insights" else "absent"}
    elif args.action == "models":
        # Enough models to exercise the bounded model list.
        result = {"status": "ok", "key": "none", "models": [{"id": "fixture-model"}, {"id": "llama3.2:3b"}]
                  + [{"id": "vendor/model-%03d" % index} for index in range(60)]}
    elif args.action != "generate":
        result = {"status": "error", "reason": "invalid_input"}
    elif scenario == "ai-insights-error":
        time.sleep(0.3)
        result = {"status": "error", "reason": "network"}
    else:
        snapshot = json.loads(args.snapshot)
        leaked = any(value in args.snapshot for value in PRIVATE)
        runs_out = any(signal.get("kind") == "quotaRunsOutBeforeReset" for signal in snapshot.get("signals", []))
        # The snapshot lists only providers with current measurements.
        current = {provider.get("id") for provider in snapshot.get("providers", [])}
        time.sleep(0.3)
        if current == {"codex"}:
            result = {"status": "ok",
                      "summary": ("Synthetic insight [" + args.language + "]: Codex is on pace to use its session "
                                  "window before the reset. "
                                  "Leak check " + ("FAILED" if leaked else "passed") + "."),
                      "highlights": ["Codex runs out in about 1 h" if runs_out else "No forecast"]}
        else:
            result = {"status": "ok",
                      "summary": ("Synthetic insight [" + args.language + "]: Codex is on pace to use its session "
                                  "window before the reset, while Claude still has most of its weekly allowance. "
                                  "Leak check " + ("FAILED" if leaked else "passed") + "."),
                      "highlights": ["Codex runs out in about 1 h" if runs_out else "No forecast",
                                     "Claude weekly window at 28%"]}
    print(json.dumps(result))


if __name__ == "__main__":
    main()
