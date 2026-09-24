#!/usr/bin/env python3
"""Run one optional AI Insights action and print a bounded JSON record."""
import argparse
import json
from lib.ai_insights import PROVIDERS, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--action", choices=("key-status", "set-key", "clear-key", "models", "generate"), required=True)
    parser.add_argument("--provider", choices=PROVIDERS, required=True)
    parser.add_argument("--model", default="")
    parser.add_argument("--endpoint", default="")
    parser.add_argument("--language", default="")
    parser.add_argument("--prompt", default="")
    parser.add_argument("--snapshot", default="")
    parser.add_argument("--no-zdr", action="store_true")
    args = parser.parse_args()
    print(json.dumps(run(args.action, args.provider, args.model, args.endpoint, args.language,
                         args.snapshot, args.prompt, not args.no_zdr), ensure_ascii=False))


if __name__ == "__main__":
    main()
