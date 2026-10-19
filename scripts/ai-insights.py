#!/usr/bin/env python3
"""Run one optional AI Insights action and print a bounded JSON record."""
import argparse
import json
from lib.ai_insights import PROVIDERS, run, supervise_parent
from lib.ai_insights_input import consume, discard, prepare


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--action", choices=("key-status", "set-key", "clear-key", "models", "generate", "prepare", "discard"), required=True)
    parser.add_argument("--provider", choices=PROVIDERS, required=True)
    parser.add_argument("--model", default="")
    parser.add_argument("--endpoint", default="")
    parser.add_argument("--language", default="")
    parser.add_argument("--prompt", default="")
    parser.add_argument("--request", default="")
    parser.add_argument("--no-zdr", action="store_true")
    parser.add_argument("--supervised", action="store_true")
    args = parser.parse_args()
    if args.supervised and not supervise_parent():
        print(json.dumps({"status": "error", "reason": "unavailable"}))
        return
    try:
        if args.action == "prepare":
            result = prepare()
        elif args.action == "discard":
            discard(args.request)
            result = {"status": "discarded"}
        else:
            snapshot = consume(args.request) if args.action == "generate" else ""
            result = run(args.action, args.provider, args.model, args.endpoint, args.language,
                         snapshot, args.prompt, not args.no_zdr)
    except (OSError, ValueError, UnicodeError):
        result = {"status": "error", "reason": "invalid_input"}
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
